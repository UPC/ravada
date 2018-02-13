use warnings;
use strict;

package Ravada::VM;

=head1 NAME

Ravada::VM - Virtual Managers library for Ravada

=cut

use Carp qw( carp croak cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use JSON::XS;
use Socket qw( inet_aton inet_ntoa );
use Moose::Role;
use Net::DNS;
use Net::Ping;
use IO::Socket;
use IO::Interface;
use Net::Domain qw(hostfqdn);

our $REX_ERROR;

no warnings "experimental::signatures";
use feature qw(signatures);

requires 'connect';

# global DB Connection

our $CONNECTOR = \$Ravada::CONNECTOR;
our $CONFIG = \$Ravada::CONFIG;

our $MIN_MEMORY_MB = 128 * 1024;

our %REX_CONNECTION;
# domain
requires 'create_domain';
requires 'search_domain';

requires 'list_domains';

# storage volume
requires 'create_volume';
requires 'list_storage_pools';

requires 'connect';
requires 'disconnect';
requires 'import_domain';

############################################################

has 'host' => (
          isa => 'Str'
         , is => 'ro',
    , default => 'localhost'
);

has 'public_ip' => (
        isa => 'Str'
        , is => 'rw'
);

has 'default_dir_img' => (
      isa => 'String'
     , is => 'ro'
);

has 'readonly' => (
    isa => 'Str'
    , is => 'ro'
    ,default => 0
);

############################################################
#
# Method Modifiers definition
# 
#
around 'create_domain' => \&_around_create_domain;

before 'search_domain' => \&_pre_search_domain;
before 'list_domains' => \&_pre_list_domains;

before 'create_volume' => \&_connect;

around 'import_domain' => \&_around_import_domain;

after 'disconnect' => \&_post_disconnect;

#############################################################
#
# method modifiers
#

sub _init_connector {
    return if $CONNECTOR && $$CONNECTOR;
    $CONNECTOR = \$Ravada::CONNECTOR if $Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR if !defined $$CONNECTOR
                                                && defined $Ravada::Front::CONNECTOR;
}

=head1 Constructors

=head2 open

Opens a Virtual Machine Manager (VM)

Arguments: id of the VM

=cut

sub open {
    my $proto = shift;
    my %args;
    if (!scalar @_ % 2) {
        %args = @_;
        confess "ERROR: Don't set the id and the type "
            if $args{id} && $args{type};
        return _open_type($proto,@_) if $args{type};
    } else {
        $args{id} = shift;
    }
    my $class=ref($proto) || $proto;

    my $self = {};
    bless($self, $class);
    my $row = $self->_do_select_vm_db( id => $args{id});
    lock_hash(%$row);
    confess "ERROR: I can't find VM id=$args{id}" if !$row || !keys %$row;

    my $type = $row->{vm_type};
    $type = 'KVM'   if $type eq 'qemu';
    $class .= "::$type";
    bless ($self,$class);

    $args{host} = $row->{hostname};
    $args{security} = decode_json($row->{security}) if $row->{security};

    return $self->new(%args);

}

sub BUILD {
    my $self = shift;

    my $args = $_[0];

    $self->_load_rex()  if !$self->is_local;

    my $id = delete $args->{id};
    my $host = delete $args->{host};
    my $name = delete $args->{name};
    delete $args->{readonly};
    delete $args->{security};
    delete $args->{public_ip};

    # TODO check if this is needed
    delete $args->{connector};

    lock_hash(%$args);

    confess "ERROR: Unknown args ".join (",", keys (%$args)) if keys %$args;

    if ($id) {
        $self->_select_vm_db(id => $id)
    } else {
        my %query = (
            hostname => ($host or 'localhost')
            ,vm_type => $self->type
        );
        $query{name} = $name  if $name;
        $self->_select_vm_db(%query);
    }
    $self->id;

    $self->public_ip($self->_data('public_ip'))
        if defined $self->_data('public_ip')
            && (!defined $self->public_ip
                || $self->public_ip ne $self->_data('public_ip')
            );

}

sub _load_rex {
    return if defined $REX_ERROR;
    eval {
        require Rex;
        Rex->import();
    
        require Rex::Commands;
        Rex::Commands->import;
    
        require Rex::Commands::File;
        Rex::Commands::File->import();

        require Rex::Commands::Run;
        Rex::Commands::Run->import();
    
        require Rex::Group::Entry::Server;
        Rex::Group::Entry::Server->import();
    
        require Rex::Commands::Iptables;
        Rex::Commands::Iptables->import();
    };
    $REX_ERROR = $@;
    $REX_ERROR .= "\nInstall from http://www.rexify.org/get.html\n\n" if $REX_ERROR;
    warn $REX_ERROR if $REX_ERROR;

};

sub _open_type {
    my $self = shift;
    my %args = @_;

    my $type = delete $args{type} or confess "ERROR: Missing VM type";
    my $class = "Ravada::VM::$type";

    my $proto = {};
    bless $proto,$class;

    my $vm = $proto->new(%args);
    eval { $vm->vm };
    warn $@ if $@;
    return if $@;

    return $vm;

}

sub _check_readonly {
    my $self = shift;
    confess "ERROR: You can't create domains in read-only mode "
        if $self->readonly 

}

sub _connect {
    my $self = shift;
    $self->connect();
}

sub _pre_create_domain {
    _check_create_domain(@_);
    _connect(@_);
}

sub _pre_search_domain($self,@) {
    $self->_connect();
    die "ERROR: VM ".$self->name." unavailable" if !$self->ping();
}

sub _pre_list_domains($self,@) {
    $self->_connect();
    die "ERROR: VM ".$self->name." unavailable" if !$self->ping();
}

sub _connect_rex($self) {
    confess "Don't connect to local rex"
        if $self->is_local;

    if ( $self->readonly ) {
        warn $self->name." readonly, don't do rex";
        return;
    }
    return if !$self->ping();

    my @pwd = getpwuid($>);
    my $home = $pwd[7];

    return $self->{_rex_connection} if exists $self->{_rex_connection}
        && $self->{_rex_connection}->{conn}->server eq $self->host
        && $self->{_rex_connection}->{conn}->{connected};

    if ($REX_CONNECTION{$self->host}) {
        $self->{_rex_connection} = $REX_CONNECTION{$self->host};
        return $self->{_rex_connection}
            if $self->{_rex_connection}->{conn}->{connected}
    }
    my $connection;
    eval {
        Rex::Commands::timeout(60);
        Rex::Commands::max_connect_retries(3);
        $connection = Rex::connect(
            server    => $self->host,
            user      => "root",
            private_key => "$home/.ssh/id_rsa",
            public_key => "$home/.ssh/id_rsa.pub"
        );
    };
    warn $@ if $@;
    return if !$connection;
    $self->{_rex_connection} = $connection;
    $REX_CONNECTION{$self->host} = $connection;
    return $connection;
}

sub _post_disconnect($self) {
    return if $self->is_local;

    $self->_load_rex();
    my $sth = $$CONNECTOR->dbh->prepare(
        "UPDATE domains set status='down' WHERE id_vm=? AND status='active'"
    );
    $sth->execute($self->id);
    $sth->finish;

    if ( my $con = Rex::Commands::connection() ) {
        $con->disconnect();
    }
    if ($self->{_rex_connection} ) {
        $self->{_rex_connection}->{conn}->disconnect;
#        $self->{_rex_connection}->{conn}->disconnect();
        delete $self->{_rex_connection};
    }
    if ( $REX_CONNECTION{$self->host} ) {
        $REX_CONNECTION{$self->host}->{conn}->disconnect;
        delete $REX_CONNECTION{$self->host};
    }
}

sub _around_create_domain {
    my $orig = shift;
    my $self = shift;
    my %args = @_;

    my $id_owner = delete $args{id_owner} or confess "ERROR: Missing id_owner";

    $self->_pre_create_domain(@_);

    my $domain = $self->$orig(@_);

    $domain->add_volume_swap( size => $args{swap})  if $args{swap};

    if ($args{id_base}) {
        my $base = $self->search_domain_by_id($args{id_base});
        $domain->run_timeout($base->run_timeout)
            if defined $base->run_timeout();
    }
    my $user = Ravada::Auth::SQL->search_by_id($id_owner);
    $domain->is_volatile(1)    if $user->is_temporary();

    $domain->get_info();

    return $domain;
}

sub _around_import_domain {
    my $orig = shift;
    my $self = shift;
    my ($name, $user, $spinoff) = @_;

    my $domain = $self->$orig($name, $user);

    $domain->_insert_db(name => $name, id_owner => $user->id);

    if ($spinoff) {
        warn "Spinning volumes off their backing files ...\n"
            if $ENV{TERM} && $0 !~ /\.t$/;
        $domain->spinoff_volumes();
    }
    return $domain;
}

############################################################
#

sub _domain_remove_db {
    my $self = shift;
    my $name = shift;
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM domains WHERE name=?");
    $sth->execute($name);
    $sth->finish;
}

=head2 domain_remove

Remove the domain. Returns nothing.

=cut


sub domain_remove {
    my $self = shift;
    $self->domain_remove_vm();
    $self->_domain_remove_bd();
}

=head2 name

Returns the name of this Virtual Machine Manager

    my $name = $vm->name();

=cut

sub name {
    my $self = shift;

    return $self->_data('name') if defined $self->{_data}->{name};

    my ($ref) = ref($self) =~ /.*::(.*)/;
    return ($ref or ref($self))."_".$self->host;
}

=head2 search_domain_by_id

Returns a domain searching by its id

    $domain = $vm->search_domain_by_id($id);

=cut

sub search_domain_by_id {
    my $self = shift;
      my $id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM domains "
        ." WHERE id=?");
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    return if !$name;

    return $self->search_domain($name);
}

=head2 ip

Returns the external IP this for this VM

=cut

sub ip {
    my $self = shift;

    my $name = ($self->public_ip or $self->host())
        or confess "this vm has no host name";
    my $ip = inet_ntoa(inet_aton($name)) ;

    return $ip if $ip && $ip !~ /^127\./;

    $name = Ravada::display_ip();

    if ($name) {
        if ($name =~ /^\d+\.\d+\.\d+\.\d+$/) {
            $ip = $name;
        } else {
            $ip = inet_ntoa(inet_aton($name));
        }
    }
    return $ip if $ip && $ip !~ /^127\./;

    $ip = $self->_interface_ip();
    return $ip if $ip && $ip !~ /^127/ && $ip =~ /^\d+\.\d+\.\d+\.\d+$/;

    warn "WARNING: I can't find the IP of host ".$self->host.", using localhost."
        ." This virtual machine won't be available from the network.";

    return '127.0.0.1';
}

sub _interface_ip {
    my $s = IO::Socket::INET->new(Proto => 'tcp');

    for my $if ( $s->if_list) {
        next if $if =~ /^virbr/;
        my $addr = $s->if_addr($if);
        return $addr if $addr && $addr !~ /^127\./;
    }
    return;
}

sub _check_memory {
    my $self = shift;
    my %args = @_;
    return if !exists $args{memory};

    die "ERROR: Low memory '$args{memory}' required ".int($MIN_MEMORY_MB/1024)." MB " if $args{memory} < $MIN_MEMORY_MB;
}

sub _check_disk {
    my $self = shift;
    my %args = @_;
    return if !exists $args{disk};

    die "ERROR: Low Disk '$args{disk}' required 1 Gb " if $args{disk} < 1024*1024;
}


sub _check_create_domain {
    my $self = shift;

    my %args = @_;

    confess "ERROR: Domains can only be created at localhost got ".$self->host
        unless     $self->host eq 'localhost'
                || $self->host eq '127.0.0.1';

    $self->_check_readonly(@_);

    $self->_check_require_base(@_);
    $self->_check_memory(@_);
    $self->_check_disk(@_);

}

sub _check_require_base {
    my $self = shift;

    my %args = @_;

    my $id_base = delete $args{id_base} or return;
    my $request = delete $args{request};
    my $id_owner = delete $args{id_owner}
        or confess "ERROR: id_owner required ";

    delete @args{'_vm','name','vm', 'memory','description'};

    confess "ERROR: Unknown arguments ".join(",",keys %args)
        if keys %args;

    my $base = Ravada::Domain->open($id_base);
    if (my @requests = $base->list_requests) {
        confess "ERROR: Domain ".$base->name." has ".$base->list_requests
                            ." requests.\n"
            unless scalar @requests == 1 && $request
                && $requests[0]->id eq $request->id;
    }


    die "ERROR: Domain ".$self->name." is not base"
            if !$base->is_base();

    my $user = Ravada::Auth::SQL->search_by_id($id_owner);

    die "ERROR: Base ".$base->name." is not public\n"
        unless $user->is_admin || $base->is_public;
}

=head2 id

Returns the id value of the domain. This id is used in the database
tables and is not related to the virtual machine engine.

=cut

sub id {
    return $_[0]->_data('id');
}

sub _data {
    my $self = shift;
    my $field = shift or confess "Missing field name";
    my $value = shift;
    if (defined $value) {
        $self->{_data}->{$field} = $value;
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE vms set $field=?"
            ." WHERE id=?"
        );
        $sth->execute($value, $self->id);
        $sth->finish;
        return $value;
    }

#    _init_connector();

    return $self->{_data}->{$field} if exists $self->{_data}->{$field};
    $self->{_data} = $self->_select_vm_db( name => $self->name);

    confess "No DB info for VM ".$self->name    if !$self->{_data};
    confess "No field $field in vms"            if !exists$self->{_data}->{$field};

    return $self->{_data}->{$field};
}

sub _do_select_vm_db {
    my $self = shift;
    my %args = @_;

    _init_connector();

    if (!keys %args) {
        my $id;
        eval { $id = $self->id  };
        if ($id) {
            %args =( id => $id );
        }
    }

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM vms WHERE ".join(" AND ",map { "$_=?" } sort keys %args )
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    return if !$row;

    return $row;
}

sub _select_vm_db {
    my $self = shift;

    my ($row) = ($self->_do_select_vm_db(@_) or $self->_insert_vm_db(@_));

    $self->{_data} = $row;
    return $row if $row->{id};
}

sub _insert_vm_db {
    my $self = shift;
    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO vms (name, vm_type, hostname, public_ip)"
        ." VALUES(?, ?, ?, ?)"
    );
    my %args = @_;
    my $name = ( delete $args{name} or $self->name);
    my $host = ( delete $args{hostname} or $self->host );
    delete $args{vm_type};

    confess "Unknown args ".Dumper(\%args)  if keys %args;

    eval { $sth->execute($name,$self->type,$host, $self->public_ip)  };
    confess $@ if $@;
    $sth->finish;

    return $self->_do_select_vm_db( name => $name);
}

=head2 default_storage_pool_name

Set the default storage pool name for this Virtual Machine Manager

    $vm->default_storage_pool_name('default');

=cut

sub default_storage_pool_name {
    my $self = shift;
    my $value = shift;

    #TODO check pool exists
    if (defined $value) {
        my $id = $self->id();
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE vms SET default_storage=?"
            ." WHERE id=?"
        );
        $sth->execute($value,$id);
        $self->{_data}->{default_storage} = $value;
    }
    return $self->_data('default_storage');
}

=head2 list_drivers

Lists the drivers available for this Virtual Machine Manager

Arguments: Optional driver type

Returns a list of strings with the nams of the drivers.

    my @drivers = $vm->list_drivers();
    my @drivers = $vm->list_drivers('image');

=cut

sub list_drivers($self, $name=undef) {
    return Ravada::Domain::drivers(undef,$name,$self->type);
}

=head2 is_local

Returns wether this virtual manager is in the local host

=cut

sub is_local($self) {
    return 1 if $self->host eq 'localhost'
        || $self->host eq '127.0.0,1'
        || !$self->host;
    return 0;
}


=head2 list_nodes

Returns a list of virtual machine manager nodes of the same type as this.

    my @nodes = $self->list_nodes();

=cut

sub list_nodes($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id FROM vms WHERE vm_type=?"
    );
    my @nodes;
    $sth->execute($self->type);

    while (my ($id) = $sth->fetchrow) {
        push @nodes,(Ravada::VM->open($id))
    }

    return @nodes;
}

=head2 ping

Returns if the virtual manager connection is available

=cut

sub ping($self) {
    return 1 if $self->is_local();

    my $p = Net::Ping->new('tcp',2);
    return 1 if $p->ping($self->host);
    $p->close();

    return if $>; # icmp ping requires root privilege
    $p= Net::Ping->new('icmp',2);
    return 1 if $p->ping($self->host);

    return 0;
}

=head2 is_active

Returns if the domain is active.

=cut

sub is_active($self) {
    if ($self->is_local) {
        my $active = 0;
        $active=1 if $self->vm;

        # store it anyway for the frontend
        $self->_cached_active($active);
        $self->_cached_active_time(time);
        return $active;
    }

    return $self->_cached_active if time - $self->_cached_active_time < 5;
    my $ret = 0;
    if ( !$self->ping() ) {
        $ret = 0;
    } elsif ( $self->_connect_rex ) {
        $ret = 1;
    }
    $self->_cached_active($ret);
    $self->_cached_active_time(time);
    return $ret;
}

sub _cached_active($self, $value=undef) {
    return $self->_data('is_active', $value);
}

sub _cached_active_time($self, $value=undef) {
    return $self->_data('cached_active_time', $value);
}

=head2 remove

Remove the virtual machine manager.

=cut

sub remove($self) {
    #TODO stop the active domains
    #
    $self->disconnect();
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM vms WHERE id=?");
    $sth->execute($self->id);
}

=head2 run_command

Run a command on the node

    my @ls = $self->run_command("ls");

=cut

sub run_command($self, $command) {
    # TODO local VMs what ?
    $self->_connect_rex()
        && return run($command);
}

=head2 write_file

Writes a file to the node

    $self->write_file("filename.extension", $contents);

=cut

sub write_file( $self, $file, $contents ) {
    $self->_load_rex();
    # TODO local VMs what ?
    if ($self->_connect_rex) {
        my $fh = file_write($file);
        $fh->write($contents);
        $fh->close;
    }
}
1;

