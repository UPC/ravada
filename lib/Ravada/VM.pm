use warnings;
use strict;

package Ravada::VM;

=head1 NAME

Ravada::VM - Virtual Managers library for Ravada

=cut

use Carp qw( carp croak cluck);
use Data::Dumper;
use File::Path qw(make_path);
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use JSON::XS;
use Socket qw( inet_aton inet_ntoa );
use Moose::Role;
use Net::DNS;
use Net::Ping;
use Net::SSH2 qw(LIBSSH2_FLAG_SIGPIPE);
use IO::Socket;
use IO::Interface;
use Net::Domain qw(hostfqdn);

use Ravada::Utils;

no warnings "experimental::signatures";
use feature qw(signatures);

requires 'connect';

# global DB Connection

our $CONNECTOR = \$Ravada::CONNECTOR;
our $CONFIG = \$Ravada::CONFIG;

our $MIN_MEMORY_MB = 128 * 1024;

our $SSH_TIMEOUT = 20 * 1000;
our $CACHE_TIMEOUT = 60;
our $FIELD_TIMEOUT = '_data_timeout';

our %VM; # cache Virtual Manager Connection
our %SSH;

our $ARP = `which arp`;
chomp $ARP;

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

requires 'is_alive';

requires 'free_memory';
requires 'free_disk';

requires '_fetch_dir_cert';

############################################################

has 'host' => (
          isa => 'Str'
         , is => 'ro',
    , default => 'localhost'
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

has 'tls_host_subject' => (
    isa => 'Str'
    , is => 'ro'
    , builder => '_fetch_tls_host_subject'
    , lazy => 1
);

has 'tls_ca' => (
    isa => 'Str'
    , is => 'ro'
    , builder => '_fetch_tls_ca'
    , lazy => 1
);

has dir_cert => (
    isa => 'Str'
    ,is => 'ro'
    ,lazy => 1
    ,builder => '_fetch_dir_cert'
);

has 'store' => (
    isa => 'Bool'
    , is => 'rw'
    , default => 1
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

around 'ping' => \&_around_ping;
around 'connect' => \&_around_connect;

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

sub _dbh($self) {
    return $$CONNECTOR->dbh();
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

    if ( $VM{$args{id}} && $VM{$args{id}}->name eq $row->{name} ) {
        my $vm = $VM{$args{id}};
        return _clean($vm);
    }

    my $type = $row->{vm_type};
    $type = 'KVM'   if $type eq 'qemu';
    $class .= "::$type";
    bless ($self,$class);

    $args{host} = $row->{hostname};
    $args{security} = decode_json($row->{security}) if $row->{security};

    my $vm = $self->new(%args);
    $VM{$args{id}} = $vm;
    return $vm;

}

sub _clean_cache {
    %VM = ();
}

sub BUILD {
    my $self = shift;

    my $args = $_[0];

    my $id = delete $args->{id};
    my $host = delete $args->{host};
    my $name = delete $args->{name};
    my $store = delete $args->{store};
    $store = 1 if !defined $store;
    my $public_ip = delete $args->{public_ip};

    delete $args->{readonly};
    delete $args->{security};

    # TODO check if this is needed
    delete $args->{connector};

    lock_hash(%$args);

    confess "ERROR: Unknown args ".join (",", keys (%$args)) if keys %$args;
    return if !$store;
    if ($id) {
        $self->_select_vm_db(id => $id)
    } else {
        my %query = (
            hostname => ($host or 'localhost')
            ,vm_type => $self->type
        );
        $query{name} = $name  if $name;
        $query{public_ip} = $public_ip if defined $public_ip;
        $self->_select_vm_db(%query);
    }
    $self->id;

}

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

    return $vm;

}

sub _check_readonly {
    my $self = shift;
    confess "ERROR: You can't create domains in read-only mode "
        if $self->readonly 

}

sub _connect {
    my $self = shift;
    my $result = $self->connect();
    if ($result) {
        $self->is_active(1);
    } else {
        $self->is_active(0);
    }
    return $result;
}

sub _around_connect($orig, $self) {
    my $result = $self->$orig();
    if ($result) {
        $self->is_active(1);
    } else {
        $self->is_active(0);
    }
    return $result;
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

sub _connect_ssh($self, $disconnect=0) {
    confess "Don't connect to local ssh"
        if $self->is_local;

    if ( $self->readonly ) {
        warn $self->name." readonly, don't do ssh";
        return;
    }
    return if !$self->ping();

    my @pwd = getpwuid($>);
    my $home = $pwd[7];

    my $ssh= $self->{_ssh};
    $ssh = $SSH{$self->host}    if exists $SSH{$self->host};

    if (! $ssh || $disconnect ) {
        $ssh->disconnect if $ssh && $disconnect;
        $ssh = Net::SSH2->new( timeout => $SSH_TIMEOUT );
        my $connect;
        for ( 1 .. 3 ) {
            eval { $connect = $ssh->connect($self->host) };
            last if $connect;
            warn "RETRYING ssh ".$self->host." ".join(" ",$ssh->error);
            sleep 1;
        }
        if ( !$connect) {
            eval { $connect = $ssh->connect($self->host) };
            if (!$connect) {
                $self->_cached_active(0);
                confess $ssh->error();
            }
        }
        $ssh->auth_publickey( 'root'
            , "$home/.ssh/id_rsa.pub"
            , "$home/.ssh/id_rsa"
        ) or $ssh->die_with_error();
        $self->{_ssh} = $ssh;
        $SSH{$self->host} = $ssh;
    }
    return $ssh;
}

sub _ssh_channel($self) {
    my $ssh = $self->_connect_ssh() or confess "ERROR: I can't connect to SSH in ".$self->host;
    my $ssh_channel;
    for ( 1 .. 5 ) {
        $ssh_channel = $ssh->channel();
        last if $ssh_channel;
        sleep 1;
    }
    if (!$ssh_channel) {
        $ssh = $self->_connect_ssh(1);
        $ssh_channel = $ssh->channel();
    }
    die $ssh->die_with_error    if !$ssh_channel;
    $ssh->blocking(1);
    return $ssh_channel;
}

sub _around_create_domain {
    my $orig = shift;
    my $self = shift;
    my %args = @_;
    my $remote_ip = delete $args{remote_ip};
    my $add_to_pool = delete $args{add_to_pool};
    my %args_create = %args;

    my $id_owner = delete $args{id_owner} or confess "ERROR: Missing id_owner";
    my $owner = Ravada::Auth::SQL->search_by_id($id_owner) or confess "Unknown user id: $id_owner";

    my $base;
    my $volatile = delete $args{volatile};
    my $id_base = delete $args{id_base};
     my $id_iso = delete $args{id_iso};
     my $active = delete $args{active};
       my $name = delete $args{name};
       my $swap = delete $args{swap};

     # args get deleted but kept on %args_create so when we call $self->$orig below are passed
     delete $args{disk};
     delete $args{memory};
     delete $args{request};
     delete $args{iso_file};
     delete $args{id_template};
     delete @args{'description','remove_cpu','vm','start'};

    confess "ERROR: Unknown args ".Dumper(\%args) if keys %args;

    $self->_check_duplicate_name($name);
    if ($id_base) {
        $base = $self->search_domain_by_id($id_base)
            or confess "Error: I can't find domain $id_base on ".$self->name;
        $volatile = 1 if $base->volatile_clones;
    }

    confess "ERROR: User ".$owner->name." is not allowed to create machines"
        unless $owner->is_admin
            || $owner->can_create_machine()
            || ($base && $owner->can_clone);

    confess "ERROR: Base ".$base->name." is private"
        if !$owner->is_admin && $base && !$base->is_public();

    if ($add_to_pool) {
        confess "Error: This machine can only be added to a pool if it is a clone"
            if !$base;
        confess("Error: Requested to add a clone for the pool but this base has no pools")
            if !$base->pools;
    }
    $args_create{listen_ip} = $self->listen_ip($remote_ip);
    $args_create{spice_password} = $self->_define_spice_password($remote_ip);
    $self->_pre_create_domain(%args_create);

    my $domain = $self->$orig(%args_create, volatile => $volatile);
    $domain->add_volume_swap( size => $swap )   if $swap;

    if ($id_base) {
        $domain->run_timeout($base->run_timeout)
            if defined $base->run_timeout();

        for my $port ( $base->list_ports ) {
            my %port = %$port;
            delete @port{'id','id_domain','public_port'};
            $domain->expose(%port);
        }
    }
    my $user = Ravada::Auth::SQL->search_by_id($id_owner);
    $domain->is_volatile(1)     if $user->is_temporary() ||($base && $base->volatile_clones());

    my @start_args = ( user => $owner );
    push @start_args, (remote_ip => $remote_ip) if $remote_ip;

    $domain->_post_start(@start_args) if $domain->is_active;
    eval {
           $domain->start(@start_args)      if $active || ($domain->is_volatile && ! $domain->is_active);
    };
    die $@ if $@ && $@ !~ /code: 55,/;

    $domain->info($owner);
    $domain->display($owner)    if $domain->is_active;

    $domain->is_pool(1) if $add_to_pool;
    return $domain;
}

sub _define_spice_password($self, $remote_ip) {
    my $spice_password = Ravada::Utils::random_name(4);
    if ($remote_ip) {
        my $network = Ravada::Network->new(address => $remote_ip);
        $spice_password = undef if !$network->requires_password;
    }
    return $spice_password;
}

sub _check_duplicate_name($self, $name) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id,name,vm FROM domains where name=?");
    $sth->execute($name);
    my $row = $sth->fetchrow_hashref;
    confess "Error: machine with name '$name' already exists ".Dumper($row)
        if $row->{id};
    return 1;
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

sub _domain_in_db($self, $name) {

    my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM domains WHERE name=?");
    $sth->execute($name);
    my ($id) =$sth->fetchrow;
    return $id;
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
        ." This virtual machine won't be available from the network." if $0 !~ /\.t$/;

    return '127.0.0.1';
}

=head2 nat_ip

Returns the IP of the VM when it is in a NAT environment

=cut

sub nat_ip($self) {
    return Ravada::nat_ip();
}

sub _interface_ip($self, $remote_ip=undef) {
    return '127.0.0.1' if $remote_ip && $remote_ip =~ /^127\./;
    my ($out, $err) = $self->run_command("/sbin/ip","route");
    my %route;
    my ($default_gw , $default_ip);

    my $remote_ip_addr = NetAddr::IP->new($remote_ip);

    for my $line ( split( /\n/, $out ) ) {
        if ( $line =~ m{^default via ([\d\.]+)} ) {
            $default_gw = NetAddr::IP->new($1);
        }
        if ( $line =~ m{^([\d\.\/]+).*src ([\d\.\/]+)} ) {
            my ($network, $ip) = ($1, $2);
            $route{$network} = $ip;

            my $netaddr = NetAddr::IP->new($network);
            return $ip if $remote_ip_addr->within($netaddr);

            $default_ip = $ip if !defined $default_ip && $ip !~ /^127\./;
            $default_ip = $ip if defined $default_gw && $default_gw->within($netaddr);
        }
    }
    return $default_ip;
}

sub listen_ip($self, $remote_ip=undef) {
    return Ravada::display_ip() if Ravada::display_ip();
    return $self->public_ip     if $self->public_ip;

    return $self->_interface_ip($remote_ip) if $remote_ip;

    return (
            $self->ip()
    );
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

    delete $args{start};
    delete $args{remote_ip};

    delete @args{'_vm','name','vm', 'memory','description','id_iso','listen_ip','spice_password'};

    confess "ERROR: Unknown arguments ".join(",",keys %args)
        if keys %args;

    my $base = Ravada::Domain->open($id_base);
    my %ignore_requests = map { $_ => 1 } qw(clone refresh_machine set_base_vm start_clones);
    my @requests;
    for my $req ( $base->list_requests ) {
        push @requests,($req) if !$ignore_requests{$req->command};
    }
    if (@requests) {
        confess "ERROR: Domain ".$base->name." has ".$base->list_requests
                            ." requests.\n"
                            .Dumper([$base->list_requests])
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

sub _data($self, $field, $value=undef) {
    if (defined $value && $self->store ) {
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

    $self->_timed_data_cache()  if $self->{_data}->{$field} && $field ne 'name';
    return $self->{_data}->{$field} if exists $self->{_data}->{$field};
    return if !$self->store();

    $self->{_data} = $self->_select_vm_db( name => $self->name);

    confess "No DB info for VM ".$self->name    if !$self->{_data};
    confess "No field $field in vms"            if !exists$self->{_data}->{$field};

    return $self->{_data}->{$field};
}

sub _timed_data_cache($self) {
    return if !$self->{$FIELD_TIMEOUT} || time - $self->{$FIELD_TIMEOUT} < $CACHE_TIMEOUT;
    return _clean($self);
}

sub _clean($self) {
    my $name = $self->{_data}->{name};
    my $id = $self->{_data}->{id};
    delete $self->{_data};
    delete $self->{$FIELD_TIMEOUT};
    $self->{_data}->{name} = $name  if $name;
    $self->{_data}->{id} = $id      if $id;
    return $self;
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

    confess Dumper(\%args) if !keys %args;
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
    $self->{$FIELD_TIMEOUT} = time if $row->{id};
    return $row if $row->{id};
}

sub _insert_vm_db {
    my $self = shift;
    return if !$self->store();

    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO vms (name, vm_type, hostname, public_ip)"
        ." VALUES(?, ?, ?, ?)"
    );
    my %args = @_;
    my $name = ( delete $args{name} or $self->name);
    my $host = ( delete $args{hostname} or $self->host );
    my $public_ip = ( delete $args{public_ip} or '' );
    delete $args{vm_type};

    confess "Unknown args ".Dumper(\%args)  if keys %args;

    eval { $sth->execute($name,$self->type,$host, $public_ip) };
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
    $self->_select_vm_db() if $self->store();
    return $self->_data('default_storage');
}

=head2 base_storage_pool

Set the storage pool for bases in this Virtual Machine Manager

    $vm->base_storage_pool('pool2');

=cut

sub base_storage_pool {
    my $self = shift;
    my $value = shift;

    #TODO check pool exists
    if (defined $value) {
        my $id = $self->id();
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE vms SET base_storage=?"
            ." WHERE id=?"
        );
        $sth->execute($value,$id);
        $self->{_data}->{base_storage} = $value;
    }
    $self->_select_vm_db();
    return $self->_data('base_storage');
}

=head2 clone_storage_pool

Set the storage pool for clones in this Virtual Machine Manager

    $vm->clone_storage_pool('pool3');

=cut

sub clone_storage_pool {
    my $self = shift;
    my $value = shift;

    #TODO check pool exists
    if (defined $value) {
        my $id = $self->id();
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE vms SET clone_storage=?"
            ." WHERE id=?"
        );
        $sth->execute($value,$id);
        $self->{_data}->{clone_storage} = $value;
    }
    $self->_select_vm_db();
    return $self->_data('clone_storage');
}

=head2 min_free_memory

Returns the minimun free memory necessary to start a new virtual machine

=cut

sub min_free_memory {
    my $self = shift;
    return $self->_data('min_free_memory');
}

=head2 max_load 

Returns the maximum cpu load that the host can handle.

=cut

sub max_load {
    my $self = shift;
    return $self->_data('max_load');
}

=head2 active_limit

Returns the value of 'active_limit' in the BBDD

=cut

sub active_limit {
    my $self = shift;
    return $self->_data('active_limit');
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
    return @{$self->{_nodes}} if $self->{_nodes};

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id FROM vms WHERE vm_type=?"
    );
    my @nodes;
    $sth->execute($self->type);

    while (my ($id) = $sth->fetchrow) {
        push @nodes,(Ravada::VM->open($id))
    }

    $self->{_nodes} = \@nodes;
    return @nodes;
}

=head2 ping

Returns if the virtual manager connection is available

=cut

sub ping($self, $option=undef) {
    confess "ERROR: option unknown" if defined $option && $option ne 'debug';

    return 1 if $self->is_local();
    my $debug = 0;
    $debug = 1 if defined $option && $option eq 'debug';

    return $self->_do_ping($self->host, $debug);
}

sub _do_ping($self, $host, $debug=0) {

    my $p = Net::Ping->new('tcp',2);
    my $ping_ok;
    eval { $ping_ok = $p->ping($host) };
    confess $@ if $@;
    warn "$@ pinging host $host" if $@;

    $self->_store_mac_address() if $ping_ok && $self;
    return 1 if $ping_ok;
    $p->close();

    return if $>; # icmp ping requires root privilege
    warn "trying icmp"   if $debug;
    $p= Net::Ping->new('icmp',2);
    eval { $ping_ok = $p->ping($host) };
    warn $@ if $@;
    $self->_store_mac_address() if $ping_ok && $self;
    return 1 if $ping_ok;

    return 0;
}

sub _around_ping($orig, $self, $option=undef) {

    my $ping = $self->$orig($option);
    $self->_cached_active($ping);
    $self->_cached_active_time(time);

    return $ping;
}

=head2 is_active

Returns if the domain is active. The active state is cached for some seconds.
Pass an optional true value to perform a real check.

Arguments: optional force mode

    if ($node->is_active) {
    }


    if ($node->is_active(1)) {
    }

=cut

sub is_active($self, $force=0) {
    return $self->_do_is_active() if $self->is_local || $force;

    return $self->_cached_active if time - $self->_cached_active_time < 60;
    return $self->_do_is_active();
}

sub _do_is_active($self) {
    my $ret = 0;
    if ( $self->is_local ) {
        $ret = 1 if $self->vm;
    } else {
        if ( !$self->ping() ) {
            $ret = 0;
        } else {
            if ( $self->is_alive ) {
                $ret = 1;
            }
        }
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

=head2 enabled

Returns if the domain is enabled.

=cut

sub enabled($self, $value=undef) {
    return $self->_data('enabled', $value);
}

sub is_enabled($self, $value=undef) {
    return $self->enabled($value);
}

sub public_ip($self, $value=undef) {
    return $self->_data('public_ip', $value);
}

=head2 remove

Remove the virtual machine manager.

=cut

sub remove($self) {
    #TODO stop the active domains
    #
    delete $VM{$self->id};

    $self->disconnect();
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM vms WHERE id=?");
    $sth->execute($self->id);
}

=head2 run_command

Run a command on the node

    my @ls = $self->run_command("ls");

=cut

sub run_command($self, @command) {

    return $self->_run_command_local(@command) if $self->is_local();

    my $chan = $self->_ssh_channel() or die "ERROR: No SSH channel to host ".$self->host;

    my $command = join(" ",@command);
    $chan->exec($command);# or $self->{_ssh}->die_with_error;

    $chan->send_eof();

    my ($out, $err) = ('', '');
    while (!$chan->eof) {
        if (my ($o, $e) = $chan->read2) {
            $out .= $o;
            $err .= $e;
        }
    }
    return ($out, $err);
}

sub run_command_nowait($self, @command) {

    return $self->_run_command_local(@command) if $self->is_local();

    my $chan = $self->_ssh_channel() or die "ERROR: No SSH channel to host ".$self->host;

    my $command = join(" ",@command);
    $chan->exec($command);# or $self->{_ssh}->die_with_error;

    $chan->send_eof();

    return;
}


sub _run_command_local($self, @command) {
    my ( $in, $out, $err);
    my ($exec) = $command[0];
    confess "ERROR: Missing command $exec"  if ! -e $exec;
    run3(\@command, \$in, \$out, \$err);
    return ($out, $err);
}

=head2 write_file

Writes a file to the node

    $self->write_file("filename.extension", $contents);

=cut

sub write_file( $self, $file, $contents ) {
    return $self->_write_file_local($file, $contents )  if $self->is_local;

    my $chan = $self->_ssh_channel();
    $chan->exec("cat > $file");
    my $bytes = $chan->write($contents);
    $chan->send_eof();
}

sub _write_file_local( $self, $file, $contents ) {
    my ($path) = $file =~ m{(.*)/};
    make_path($path) or die "$! $path"
        if ! -e $path;
    CORE::open(my $out,">",$file) or confess "$! $file";
    print $out $contents;
    close $out or die "$! $file";
}

sub read_file( $self, $file ) {
    return $self->_read_file_local($file) if $self->is_local;

    my ($content, $err) = $self->run_command("cat $file");
    confess $err if $err;
    return $content;
}

sub _read_file_local( $self, $file ) {
    CORE::open my $in,'<',$file or die "$! $file";
    return join('',<$in>);
}

sub file_exists( $self, $file ) {
    return -e $file if $self->is_local;

    # why should we force disconnect before ?
    $self->_connect_ssh();
    my ( $out, $err) = $self->run_command("/usr/bin/test",
        "-e $file ; echo \$?");

    chomp $out;
    chomp $err;

    warn $self->name." ".$err if $err;

    return 1 if $out =~ /^0$/;
    return 0;
}

sub remove_file( $self, $file ) {
    unlink $file if $self->is_local;
    return $self->run_command("/bin/rm", $file);
}

sub create_iptables_chain($self,$chain) {
    my ($out, $err) = $self->run_command("/sbin/iptables","-n","-L",$chain);

    $self->run_command("/sbin/iptables", '-N' => $chain)
        if $out !~ /^Chain $chain/;

    ($out, $err) = $self->run_command("/sbin/iptables","-n","-L",'INPUT');
    return if grep(/^RAVADA /, split(/\n/,$out));

    $self->run_command("/sbin/iptables", '-A','INPUT', '-j' => $chain);

}

sub iptables($self, @args) {
    my @cmd = ('/sbin/iptables');
    for ( ;; ) {
        my $key = shift @args or last;
        my $field = "-$key";
        $field = "-$field" if length($key)>1;
        push @cmd,($field);
        push @cmd,(shift @args);

    }
    my ($out, $err) = $self->run_command(@cmd);
    warn $err if $err;
}

sub iptables_list($self) {
#   Extracted from Rex::Commands::Iptables
#   (c) Jan Gehring <jan.gehring@gmail.com>
    my ($out,$err) = $self->run_command("/sbin/iptables-save");
    my ( %tables, $ret );

    my ($current_table);
    for my $line (split /\n/, $out) {
        chomp $line;

        next if ( $line eq "COMMIT" );
        next if ( $line =~ m/^#/ );
        next if ( $line =~ m/^:/ );

        if ( $line =~ m/^\*([a-z]+)$/ ) {
            $current_table = $1;
            $tables{$current_table} = [];
            next;
        }

        #my @parts = grep { ! /^\s+$/ && ! /^$/ } split (/(\-\-?[^\s]+\s[^\s]+)/i, $line);
        my @parts = grep { !/^\s+$/ && !/^$/ } split( /^\-\-?|\s+\-\-?/i, $line );

        my @option = ();
        for my $part (@parts) {
            my ( $key, $value ) = split( /\s/, $part, 2 );
            push( @option, $key => $value );
        }

        push( @{ $ret->{$current_table} }, \@option );

    }
    return $ret;
}

sub _random_list(@list) {
    return @list if rand(5) < 2;
    return reverse @list if rand(5) < 2;
    return (sort { $a cmp $b } @list);
}

sub balance_vm($self, $base=undef) {

    my $min_memory = $Ravada::Domain::MIN_FREE_MEMORY;
    $min_memory = $base->get_info->{memory} if $base;

    my %vm_list;
    my @status;

    my @vms;
    if ($base) {
        @vms = $base->list_vms();
    } else {
        @vms = $self->list_nodes();
    }
#    warn Dumper([ map { $_->name } @vms]);
    return $self if !@vms;
    for my $vm (_random_list( @vms )) {
        next if !$vm->enabled();
        my $active = 0;
        eval { $active = $vm->is_active() };
        my $error = $@;
        if ($error && !$vm->is_local) {
            warn "[balance] disabling ".$vm->name." ".$vm->enabled()." $error";
            $vm->enabled(0);
        }

        next if !$vm->enabled();
        next if !$active;
        next if $base && !$vm->is_local && !$base->base_in_vm($vm->id);

        my $free_memory;
        eval { $free_memory = $vm->free_memory };
        if ($@) {
            warn $@;
            $vm->enabled(0) if !$vm->is_local();
            next;
        }

        my $n_active = $vm->count_domains(status => 'active')
                        + $vm->count_domains(status => 'starting');

        my $key = $n_active.".".$free_memory;
        $vm_list{$key} = $vm;
        last if $key =~ /^[01]+\./; # don't look for other nodes when this one is empty !
    }
    my @sorted_vm = map { $vm_list{$_} } sort { $a <=> $b } keys %vm_list;
#    warn Dumper([ map {  [$_ , $vm_list{$_}->name ] } keys %vm_list]);
#    warn "sorted ".Dumper([ map { $_->name } @sorted_vm ]);
    for my $vm (@sorted_vm) {
        return $vm;
    }
    return $self;
}

sub count_domains($self, %args) {
    my $query = "SELECT count(*) FROM domains WHERE id_vm = ? AND ";
    $query .= join(" AND ",map { "$_ = ?" } sort keys %args );
    my $sth = $$CONNECTOR->dbh->prepare($query);
    $sth->execute( $self->id, map { $args{$_} } sort keys %args );
    my ($count) = $sth->fetchrow;
    return $count;
}

sub shutdown_domains($self) {
    my $sth_inactive
        = $$CONNECTOR->dbh->prepare("UPDATE domains set status='down' WHERE id=?");
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id FROM domains "
        ." where status='active'"
        ."  AND id_vm = ".$self->id
    );
    $sth->execute();
    while ( my ($id_domain) = $sth->fetchrow) {
        $sth_inactive->execute($id_domain);
        Ravada::Request->shutdown_domain(
            id_domain => $id_domain
                , uid => Ravada::Utils::user_daemon->id
        );
    }
    $sth->finish;
}

sub shared_storage($self, $node, $dir) {
    return if !$node->is_active || !$self->is_active;
    my $cached_st_key = "_cached_shared_storage_".$self->name.$node->name.$dir;
    $cached_st_key =~ s{/}{_}g;
    return $self->{$cached_st_key} if exists $self->{$cached_st_key};

    $dir .= '/' if $dir !~ m{/$};
    my $file;
    for ( ;; ) {
        $file = $dir.Ravada::Utils::random_name(4).".tmp";
        eval {
            next if $self->file_exists($file);
            next if $node->file_exists($file);
        };
        return if $@ && $@ =~ /onnect to SSH/i;
        last;
    }
    $file = "$dir$cached_st_key";
    $self->write_file($file,''.localtime(time));
    confess if !$self->file_exists($file);
    my $shared;
    for (1 .. 5 ) {
        $shared = $node->file_exists($file);
        last if $shared;
        sleep 1;
    }
    $self->remove_file($file);

    $self->{$cached_st_key} = $shared;
    return $shared;
}
sub _fetch_tls_host_subject($self) {
    return '' if !$self->dir_cert();

    my @cmd= qw(/usr/bin/openssl x509 -noout -text -in );
    push @cmd, ( $self->dir_cert."/server-cert.pem" );

    my ($out, $err) = $self->run_command(@cmd);
    die $err if $err;

    for my $line (split /\n/,$out) {
        chomp $line;
        next if $line !~ /^\s+Subject:\s+(.*)/;
        my $subject = $1;
        $subject =~ s/ = /=/g;
        $subject =~ s/, /,/g;
        return $subject;
    }
}

sub _fetch_tls_ca($self) {
    my ($out, $err) = $self->run_command("/bin/cat", $self->dir_cert."/ca-cert.pem");

    return join('\n', (split /\n/,$out) );
}

sub _store_mac_address($self, $force=0 ) {
    return if !$force && $self->_data('mac');
    die "Error: I can't find arp" if !$ARP;

    my %done;
    for my $ip ($self->host,$self->ip, $self->public_ip) {
        next if !$ip || $done{$ip}++;
        CORE::open (my $arp,'-|',"$ARP -n ".$ip) or die "$! $ARP";
        while (my $line = <$arp>) {
            chomp $line;
            my ($mac) = $line =~ /(..:..:..:..:..:..)/ or next;

            $self->_data(mac => $mac);
            return;
        }
        close $arp;
    }
}

sub _wake_on_lan( $self ) {
    return if $self->is_local;

    die "Error: I don't know the MAC address for node ".$self->name
        if !$self->_data('mac');

    my $sock = new IO::Socket::INET(Proto=>'udp', Timeout => 60)
        or die "Error: I can't create an UDP socket";
    my $host = '255.255.255.255';
    my $port = 9;
    my $mac_addr = $self->_data('mac');

    my $ip_addr = inet_aton($host);
    my $sock_addr = sockaddr_in($port, $ip_addr);
    $mac_addr =~ s/://g;
    my $packet = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

    setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1);
    send($sock, $packet, MSG_DONTWAIT , $sock_addr);
    close ($sock);

}

sub start($self) {
    $self->_wake_on_lan();
}

sub shutdown($self) {
    die "Error: local VM can't be shut down\n" if $self->is_local;
    $self->is_active(0);
    $self->run_command_nowait('/sbin/poweroff');
}

sub _check_free_disk($self, $size, $storage_pool=undef) {

    my $size_out = int($size / 1024 / 1024 / 1024 ) * 1024 *1024 *1024;

    my $free = $self->free_disk($storage_pool);
    my $free_out = int($free / 1024 / 1024 / 1024 ) * 1024 *1024 *1024;

    die "Error creating volume, out of space."
    ." Requested: ".Ravada::Utils::number_to_size($size_out)
    ." , Disk free: ".Ravada::Utils::number_to_size($free_out)
    ."\n"
    if $size > $free;

}
sub _list_used_ports_sql($self, $used_port) {

    my $sth = $$CONNECTOR->dbh->prepare("SELECT public_port FROM domain_ports ");
    $sth->execute();
    my $port;
    $sth->bind_columns(\$port);

    while ($sth->fetch ) { $used_port->{$port}++ if defined $port };

}

sub _list_used_ports_ss($self, $used_port) {
    my @cmd = ("/bin/ss","-tln");
    my ($out, $err) = $self->run_command(@cmd);
    for my $line ( split /\n/,$out ) {
        my ($port) = $line=~ m{^LISTEN.*?\d.\d\:(\d+)};
        $used_port->{$port}++ if $port;
    }
}

sub _list_used_ports_iptables($self, $used_port) {
    my $iptables = $self->iptables_list();
    for my $rule ( @{$iptables->{nat}} ) {
        my %rule = @{$rule};
        next if !exists $rule{A} || $rule{A} ne 'PREROUTING';
        $used_port->{dport}++;
    }
}

sub _new_free_port($self) {
    my $used_port = {};
    $self->_list_used_ports_sql($used_port);
    $self->_list_used_ports_ss($used_port);
    $self->_list_used_ports_iptables($used_port);

    my $free_port = 5950;
    for (;;) {
        last if !$used_port->{$free_port};
        $free_port++ ;
    }
    return $free_port;
}

1;


