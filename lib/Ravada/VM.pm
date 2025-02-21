use warnings;
use strict;

package Ravada::VM;

=head1 NAME

Ravada::VM - Virtual Managers library for Ravada

=cut

use utf8;
use Carp qw( carp confess croak cluck);
use Data::Dumper;
use File::Copy qw(copy);
use File::Path qw(make_path);
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use JSON::XS;
use Socket qw( inet_aton inet_ntoa );
use Moose::Role;
use Net::DNS;
use Net::Ping;
use Net::OpenSSH;
use IO::Socket;
use IO::Interface;
use Net::Domain qw(hostfqdn);
use Storable qw(dclone);

use Ravada::HostDevice;
use Ravada::Utils;

no warnings "experimental::signatures";
use feature qw(signatures);

requires 'connect';

# global DB Connection

our $CONNECTOR = \$Ravada::CONNECTOR;
our $CONFIG = \$Ravada::CONFIG;

our $MIN_MEMORY_MB = 128 * 1024;
our $MIN_DISK_MB = 1024 * 1024;

our $CACHE_TIMEOUT = 60;
our $FIELD_TIMEOUT = '_data_timeout';

our $TIMEOUT_DOWN_CACHE = 300;

our %VM; # cache Virtual Manager Connection
our %SSH;

our $ARP = `which arp`;
chomp $ARP;

our $FREE_PORT = 5950;

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

requires 'remove_file';

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

has 'netssh' => (
    isa => 'Any'
    ,is => 'ro'
    , builder => '_connect_ssh'
    , lazy => 1
    , clearer => 'clear_netssh'
);

has 'has_networking' => (
    isa => 'Bool'
    , is => 'ro'
    , default => 0
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
after 'disconnect' => \&_post_disconnect;

around 'new_network' => \&_around_new_network;
around 'create_network' => \&_around_create_network;
around 'remove_network' => \&_around_remove_network;
around 'list_virtual_networks' => \&_around_list_networks;
around 'change_network' => \&_around_change_network;

around 'copy_file_storage' => \&_around_copy_file_storage;

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

        $args{id} = _search_id($args{name}) if $args{name};

        confess "I don't know how to open ".Dumper(\%args)
        if !$args{id};
    } else {
        $args{id} = shift;
    }
    my $force = delete $args{force};

    confess "Error: undefind id in ".Dumper(\%args) if !$args{id};

    my $class=ref($proto) || $proto;

    my $self = {};
    bless($self, $class);

    if ($force) {
        _set_by_id($args{id}, 'cached_down' => 0 );
    }

    my $row = $self->_do_select_vm_db( id => $args{id});
    lock_hash(%$row);
    confess "ERROR: I can't find VM id=$args{id}" if !$row || !keys %$row;

    if (!$args{readonly} && $VM{$args{id}} && $VM{$args{id}}->name eq $row->{name} ) {
        my $internal_vm;
        eval { $internal_vm = $VM{$args{id}}->vm };
        warn $@ if $@;
        if ($internal_vm) {
            my $vm = $VM{$args{id}};
            return _clean($vm);
        }
    }

    my $type = $row->{vm_type};
    $type = 'KVM'   if $type eq 'qemu';
    $class .= "::$type";
    bless ($self,$class);

    $args{host} = $row->{hostname};
    $args{security} = decode_json($row->{security}) if $row->{security};

    my $vm = $self->new(%args);

    my $internal_vm;
    eval {
        $internal_vm = $vm->vm;
    };
    $VM{$args{id}} = $vm unless $args{readonly} || !$internal_vm;
    return if $vm->is_local && !$internal_vm;
    return $vm;

}

sub _search_id($name) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id FROM vms WHERE name=?"
    );
    $sth->execute($name);
    my ($id) = $sth->fetchrow;
    return $id;
}

sub _search_name($id) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT name FROM vms WHERE id=?"
    );
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    return $name;
}
sub _refresh_version($self) {
    my $version = $self->get_library_version();
    return if defined $self->_data('version')
    && $self->_data('version') eq $version;

    $self->_data('version' => $version);
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

=head1 Methods

=cut

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

=head2 timeout_down_cache

  Returns time in seconds for nodes to be kept cached down.

=cut

sub timeout_down_cache($self) {
    return $TIMEOUT_DOWN_CACHE;
}

sub _around_connect($orig, $self) {

    if ($self->_data('cached_down') && time-$self->_data('cached_down')< $self->timeout_down_cache()) {
            return;
    }
    my $result = $self->$orig();
    if ($result) {
        $self->is_active(1);
        $self->_fetch_tls();
        $self->_refresh_version();
    } else {
        $self->is_active(0);
    }
    return $result;
}

sub _post_disconnect($self) {
    if (!$self->is_local) {
        if ($self->netssh) {
            $self->netssh->disconnect();
	    }
        $self->clear_netssh();
        delete $SSH{$self->host};
    }
    delete $VM{$self->id};
}

sub _pre_create_domain {
    _check_create_domain(@_);
    _connect(@_);
}

sub _pre_search_domain($self,@) {
    $self->_connect();
    die "ERROR: VM ".$self->name." unavailable\n" if !$self->ping();
}

sub _pre_list_domains($self,@) {
    $self->_connect();
    die "ERROR: VM ".$self->name." unavailable\n" if !$self->ping();
}

sub _connect_ssh($self) {
    confess "Don't connect to local ssh"
        if $self->is_local;

    if ( $self->readonly ) {
        confess $self->name." readonly, don't do ssh";
        return;
    }

    my $ssh;
    $ssh = $SSH{$self->host}    if exists $SSH{$self->host};

    if (!$ssh || !$ssh->check_master) {

        if ($self->_data('cached_down') && time-$self->_data('cached_down')< $self->timeout_down_cache()) {
            return;
        }

        delete $SSH{$self->host};
        if ($self->_data('cached_down')
                && time-$self->_data('cached_down')< $self->timeout_down_cache()) {
            return;
        }

        for ( 1 .. 3 ) {
            $ssh = Net::OpenSSH->new($self->host
                    ,timeout => 2
                 ,batch_mode => 1
                ,forward_X11 => 0
              ,forward_agent => 0
        ,kill_ssh_on_timeout => 1
            );
            last if !$ssh->error;
            # warn "RETRYING ssh ".$self->host." ".join(" ",$ssh->error);
            sleep 1;
        }
        if ( $ssh->error ) {
            $self->_cached_active(0);
            $self->_data('cached_down' => time);
            # warn "Error connecting to ".$self->host." : ".$ssh->error();
            return;
        }
    }
    $SSH{$self->host} = $ssh;
    return $ssh;
}

sub _ssh($self) {
    my $ssh = $self->netssh;
    return if !$ssh;
    return $ssh if $ssh->check_master;
    warn "WARNING: ssh error '".$ssh->error."'" if $ssh->error;
    $self->netssh->disconnect;
    $self->clear_netssh();
    return $self->netssh;
}

sub _around_create_domain {
    my $orig = shift;
    my $self = shift;
    my %args = @_;
    my $remote_ip = delete $args{remote_ip};
    my $add_to_pool = delete $args{add_to_pool};
    my $hardware = delete $args{options}->{hardware};
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
       my $from_pool = delete $args{from_pool};
       my $alias = delete $args{alias};

    my $config = delete $args{config};

    if ($name !~ /^[a-zA-Z0-9_\-]+$/) {
        $alias = $self->_set_alias_unique($alias or $name);
        $name = $self->_set_ascii_name($name);
        $args_create{name} = $name;
    }

     # args get deleted but kept on %args_create so when we call $self->$orig below are passed
     delete $args{disk};
     delete $args{memory};
     my $request = delete $args{request};
     delete $args{iso_file};
     delete $args{id_template};
     delete @args{'description','remove_cpu','vm','start','options','id', 'alias','storage'
                    ,'enable_host_devices'};

    confess "ERROR: Unknown args ".Dumper(\%args) if keys %args;

    $self->_check_duplicate_name($name, $volatile);
    if ($id_base) {
        my $vm_local = $self;
        $vm_local = $self->new( host => 'localhost') if !$vm_local->is_local;
        $base = $vm_local->search_domain_by_id($id_base)
            or confess "Error: I can't find domain $id_base on ".$self->name;

        die "Error: user ".$owner->name." can not clone from ".$base->name
        unless $owner->allowed_access($base->id);

        if ( $base->list_host_devices() ) {
            $args_create{volatile}=0;
        } elsif (!defined $args_create{volatile}) {
            $args_create{volatile} = $base->volatile_clones;
        }
        if ($add_to_pool) {
            confess "Error: you can't add to pool and also pick from pool" if $from_pool;
            $from_pool = 0;
        }
        $from_pool = 1 if !defined $from_pool && $base->pools();
    }

    confess "ERROR: User ".$owner->name." is not allowed to create machines"
        unless $owner->is_admin
            || $owner->can_create_machine()
            || ($base && $owner->can_clone);

#   Do not check if base is public to allow not public machines to be copied
#    confess "ERROR: Base ".$base->name." is private"
#        if !$owner->is_admin && $base && !$base->is_public();

    if ($add_to_pool) {
        confess "Error: This machine can only be added to a pool if it is a clone"
            if !$base;
        confess("Error: Requested to add a clone for the pool but this base has no pools")
            if !$base->pools;
    }
    $args_create{spice_password} = $self->_define_spice_password($remote_ip);
    $self->_pre_create_domain(%args_create);
    $args_create{listen_ip} = $self->listen_ip($remote_ip);

    return $base->_search_pool_clone($owner) if $from_pool;

    if ($self->is_local && $base && $base->is_base && $args_create{volatile} && !$base->list_host_devices) {
        $request->status("balancing")                       if $request;
        my $vm = $self->balance_vm($owner->id, $base);

        if (!$vm) {
            die "Error: No free nodes available.\n";
        }
        $request->status("creating machine on ".$vm->name)  if $request;
        $self = $vm;
        $args_create{listen_ip} = $self->listen_ip($remote_ip);
    }

    my $domain = $self->$orig(%args_create);
    $domain->_data('date_status_change'=>Ravada::Utils::now());
    $self->_add_instance_db($domain->id);
    $domain->add_volume_swap( size => $swap )   if $swap;
    $domain->_data('is_compacted' => 1);
    $domain->_data('alias' => $alias) if $alias;
    $domain->_data('date_status_change', Ravada::Utils::now());
    $self->_change_hardware_install($domain,$hardware) if $hardware;

    if ($id_base) {
        $domain->run_timeout($base->run_timeout)
            if defined $base->run_timeout();
        $domain->_data(shutdown_disconnected => $base->_data('shutdown_disconnected'));
        $domain->_data(shutdown_grace_time => $base->_data('shutdown_grace_time'));
        for my $port ( $base->list_ports ) {
            my %port = %$port;
            delete @port{'id','id_domain','public_port','id_vm', 'is_secondary'};
            $domain->expose(%port);
        }
        $base->_copy_host_devices($domain);
        $domain->_clone_filesystems();
        my @displays = $base->_get_controller_display();
        for my $display (@displays) {
            delete $display->{id};
            delete $display->{id_domain};
            $display->{is_active} = 0;
            my $port = $domain->exposed_port($display->{driver});
            $display->{id_domain_port} = $port->{id};
            delete $display->{port};
            $domain->_store_display($display);
        }
        $domain->_chroot_filesystems();
    }
    my $user = Ravada::Auth::SQL->search_by_id($id_owner);

    $volatile = $volatile || $user->is_temporary || $args_create{volatile};

    my @start_args = ( user => $owner );
    push @start_args, (remote_ip => $remote_ip) if $remote_ip;

    $domain->_post_start(@start_args) if $domain->is_active;

    if ( $active || ($volatile && ! $domain->is_active) ) {
        $domain->_data('date_status_change'=>Ravada::Utils::now());
        $domain->status('starting');

        eval {
           $domain->start(@start_args, is_volatile => $volatile);
        };
        my $err = $@;

        $domain->_data('date_status_change'=>Ravada::Utils::now());
        if ( $err && $err !~ /code: 55,/ ) {
            $domain->is_volatile($volatile) if defined $volatile;
            die $err;
        }
    }
    $domain->is_volatile($volatile) if defined $volatile;

    $domain->info($owner);
    $domain->display($owner)    if $domain->is_active;

    $domain->is_pool(1) if $add_to_pool;
    $domain->_rrd_remove();

    return $domain;
}

sub _change_hardware_install($self, $domain, $hardware) {

    for my $item (sort keys %$hardware) {
        Ravada::Request->change_hardware(
            uid => Ravada::Utils::user_daemon->id
            ,id_domain=> $domain->id
            ,hardware => $item
            ,data => $hardware->{$item}
        );
    }

}

sub _set_ascii_name($self, $name) {
    my $length = length($name);
    $name =~ tr/.âêîôûáéíóúàèìòùäëïöüçñ'/-aeiouaeiouaeiouaeioucn_/;
    $name =~ tr/ÂÊÎÔÛÁÉÍÓÚÀÈÌÒÙÄËÏÖÜÇÑ€$/AEIOUAEIOUAEIOUAEIOUCNES/;
    $name =~ tr/A-Za-z0-9_\.\-/\-/c;
    $name =~ s/^\-*//;
    $name =~ s/\-*$//;
    $name =~ s/\-\-+/\-/g;
    if (length($name) < $length) {
        $name .= "-" if length($name);
        $name .= Ravada::Utils::random_name($length-length($name));
    }
    for (;;) {
        last if !$self->_check_duplicate_name($name,0);
        $name .= Ravada::Utils::random_name(1);
    }
    return $name;
}

sub _set_alias_unique($self, $alias) {
    my $alias0 = $alias;
    my $n = 2;
    for (;;) {
        last if !$self->_check_duplicate_name($alias,0);
        $alias ="$alias0-$n";
        $n++;
    }
    return $alias;

}

sub _add_instance_db($self, $id_domain) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM domain_instances "
        ." WHERE id_domain=? AND id_vm=?"
    );
    $sth->execute($id_domain, $self->id);
    my ($row) = $sth->fetchrow;
    return if $row;

    $sth = $$CONNECTOR->dbh->prepare("INSERT INTO domain_instances (id_domain, id_vm) "
        ." VALUES (?, ?)"
    );
    eval {
        $sth->execute($id_domain, $self->id);
    };
    confess $@ if $@;
}

sub _define_spice_password($self, $remote_ip) {
    my $spice_password = Ravada::Utils::random_name(4);
    if ($remote_ip) {
        my $network = Ravada::Route->new(address => $remote_ip);
        $spice_password = undef if !$network->requires_password;
    }
    return $spice_password;
}

sub _check_duplicate_name($self, $name, $die=1) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id,name,vm FROM domains where name=? or alias=?");
    $sth->execute($name,$name);
    my $row = $sth->fetchrow_hashref;
    confess "Error: machine with name '$name' already exists ".Dumper($row)
        if $row->{id} && $die;
    return 0 if !$row || !$row->{id};
    return 1;
}

sub _around_import_domain {
    my $orig = shift;
    my $self = shift;
    my ($name, $user, $spinoff, $import_base) = @_;

    die "Error: base for '$name' can't be imported when volumes are"
        ." spinned off\n" if $spinoff && $import_base;

    my $domain = $self->$orig($name, $user, $spinoff);

    $domain->_insert_db(name => $name, id_owner => $user->id);

    if ($spinoff) {
        warn "Spinning volumes off their backing files ...\n"
            if $ENV{TERM} && $0 !~ /\.t$/;
        $domain->spinoff();
    }
    if ($import_base) {
        $self->_import_base($domain);
    }
    $domain->_data('id_vm' => $self->id)
    if !defined $domain->_data('id_vm');

    return $domain;
}

sub _import_base($self, $domain) {
    my @img;
    for my $vol ( $domain->list_volumes_info ) {
        next if !$vol->file;
        next if !$vol->backing_file;
        push @img,[$vol->backing_file, $vol->info->{target}];
    }
    return if !@img;
    $domain->_prepare_base_db(@img);
    $domain->_post_prepare_base( Ravada::Utils::user_daemon());
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

    $name = $self->display_ip();

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

sub nat_ip($self, $value=undef) {
    $self->_data( nat_ip => $value ) if defined $value;
    if ($self->is_local) {
        return $self->_data('nat_ip') if $self->_data('nat_ip');
        return Ravada::nat_ip(); #deprecated
    }
    return $self->_data('nat_ip');
}

=head2 display_ip

Returns the display IP of the Virtual Manager

=cut

sub display_ip($self, $value=undef) {
    return $self->_set_display_ip($value) if defined $value;

    if ($self->is_local) {
        return $self->_data('display_ip') if $self->_data('display_ip');
        return Ravada::display_ip(); #deprecated
    }
    return $self->_data('display_ip');
}

sub _set_display_ip($self, $value) {
    if (defined $value && length $value ) {
        my %ip_address = $self->_list_ip_address();

        confess "Error: $value is not in any interface in node ".$self->name
        .". Found ".Dumper(\%ip_address)
        if !exists $ip_address{$value};
    }

    $self->_data( display_ip => $value );
}

sub _list_ip_address($self) {
    my @cmd = ("ip","address","show");
    my ($out, $err) = $self->run_command(@cmd);
    my $dev;
    my %address;
    for my $line (split /\n/,$out) {
        my ($dev_found) = $line =~ /^\d+: (.*?):/;
        if ($dev_found) {
            $dev = $dev_found;
            next;
        }
        my ($inet) = $line =~ m{inet (\d+\.\d+\.\d+\.\d+)/};
        if ($inet) {
            die "Error: no device found for $inet in node ".$self->name."\n$out" if !$dev;
            $address{$inet} = $dev;
        }
    }
    return %address;
}

sub _ip_a($self, $dev) {
    my ($out, $err) = $self->run_command_cache("/sbin/ip","-o","a");
    die $err if $err;
    for my $line ( split /\n/,$out) {
        my ($ip) = $line =~ m{^\d+:\s+$dev.*inet\d* (.*?)/};
        return $ip if $ip;
    }
    warn "Warning $dev not found in active interfaces";
}

sub _interface_ip($self, $remote_ip=undef) {
    return '127.0.0.1' if $remote_ip && $remote_ip =~ /^127\./;
    my ($out, $err) = $self->run_command_cache("/sbin/ip","route");
    my %route;
    my ($default_gw , $default_ip);

    my $remote_ip_addr = NetAddr::IP->new($remote_ip)
                or confess "I can't find netaddr for $remote_ip";

    for my $line ( split( /\n/, $out ) ) {
        if ( $line =~ m{^default via ([\d\.]+)} ) {
            $default_gw = NetAddr::IP->new($1);
        }
        if ($line =~ m{^default via.*dev (.*?)(\s|$)}) {
            my $dev = $1;
            $default_ip = $self->_ip_a($dev) if !$default_ip;
        }
        if ( $line =~ m{^([\d\.\/]+).*src ([\d\.\/]+)} ) {
            my ($network, $ip) = ($1, $2);
            if ($ip) {
                $route{$network} = $ip;

                return $ip if $remote_ip && $remote_ip eq $ip;

                my $netaddr = NetAddr::IP->new($network)
                    or confess "I can't find netaddr for $network";
                return $ip if $remote_ip_addr->within($netaddr);

                $default_ip = $ip if defined $default_gw && $default_gw->within($netaddr);
            }
        }
        if ( $line =~ m{^([\d\.\/]+).*dev (.+?) } ) {
            my ($network, $dev) = ($1, $2);
            my $ip = $self->_ip_a($dev);
            if ($ip) {
                $route{$network} = $ip;

                return $ip if $remote_ip && $remote_ip eq $ip;

                my $netaddr = NetAddr::IP->new($network)
                    or confess "I can't find netaddr for $network";
                return $ip if $remote_ip_addr->within($netaddr);
            }
        }
    }
    return $default_ip;
}

=head2 listen_ip

Returns the IP where virtual machines must be bound to

Arguments: optional remote ip

=cut

sub listen_ip($self, $remote_ip=undef) {
    return Ravada::display_ip() if $self->is_local && Ravada::display_ip();
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

    die "ERROR: Low Disk '$args{disk}' required ".($MIN_DISK_MB/1024/1024)." Gb "
    if $args{disk} < $MIN_DISK_MB;
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

    delete @args{'_vm','name','vm', 'memory','description','id_iso','listen_ip','spice_password','from_pool', 'volatile', 'alias','storage', 'options', 'network','enable_host_devices'};

    confess "ERROR: Unknown arguments ".join(",",keys %args)
        if keys %args;

    my $base = Ravada::Domain->open($id_base);
    my %ignore_requests = map { $_ => 1 } qw(clone refresh_machine set_base_vm start_clones shutdown_clones shutdown force_shutdown refresh_machine_ports set_time open_exposed_ports manage_pools screenshot remove_clones
    list_cpu_models
    );
    my @requests;
    for my $req ( $base->list_requests ) {
        push @requests,($req) if !$ignore_requests{$req->command};
    }
    if (@requests) {
        confess "ERROR: Domain ".$base->name." has ".scalar(@requests)
                            ." requests.\n"
                            .Dumper(\@requests)
            unless scalar @requests == 1 && $request
                && $requests[0]->id eq $request->id;
    }


    die "ERROR: Domain ".$self->name." is not base"
            if !$base->is_base();

#   Do not check if base is public to allow not public machines to be copied

#    my $user = Ravada::Auth::SQL->search_by_id($id_owner);

#    die "ERROR: Base ".$base->name." is not public\n"
#        unless $user->is_admin || $base->is_public;
}

=head2 id

Returns the id value of the domain. This id is used in the database
tables and is not related to the virtual machine engine.

=cut

sub id {
    return $_[0]->_data('id');
}

sub _data($self, $field, $value=undef) {
    if (defined $value && $self->store
        && (
          !exists $self->{_data}->{$field}
          || !defined $self->{_data}->{$field}
          || $value ne $self->{_data}->{$field}
        )
    ) {
        confess if $field eq 'id_vm' && $self->is_base;
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

sub _set_by_id($id, $field, $value) {
    my $sth = $$CONNECTOR->dbh->prepare(
    "UPDATE vms set $field=?"
    ." WHERE id=?"
    );
    $sth->execute($value, $id);
    $sth->finish;

    return $value;
}

sub _timed_data_cache($self) {
    return if !$self->{$FIELD_TIMEOUT} || time - $self->{$FIELD_TIMEOUT} < $CACHE_TIMEOUT;
    return _clean($self);
}

sub _get_name_by_id($id) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM vms WHERE id=?");
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    return $name;
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

sub default_storage_pool_name($self, $value=undef) {
    confess if defined $value && $value eq '';

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

=head2 dir_clone

Returns the directory where clone images are stored in this Virtual Manager

=cut


sub dir_clone($self) {

    my $dir_img  = $self->dir_img;
    my $clone_pool = $self->clone_storage_pool();
    $dir_img = $self->_storage_path($clone_pool) if $clone_pool;

    return $dir_img;
}

=head2 dir_base

Returns the directory where base images are stored in this Virtual Manager

=cut


sub dir_base($self, $volume_size) {
    my $pool_base = $self->default_storage_pool_name;
    $pool_base = $self->base_storage_pool()    if $self->base_storage_pool();
    $pool_base = $self->storage_pool()         if !$pool_base;

    $self->_check_free_disk($volume_size * 2, $pool_base);
    return $self->_storage_path($pool_base);

}

=head2 min_free_memory

Returns the minimun free memory necessary to start a new virtual machine

=cut

sub min_free_memory {
    my $self = shift;
    return ($self->_data('min_free_memory') or $Ravada::Domain::MIN_FREE_MEMORY);
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
    return 1 if !$self->host
        || $self->host eq 'localhost'
        || $self->host eq '127.0.0,1'
        ;
    return 0;
}

=head2 is_locked

This node has requests running or waiting to be run

=cut

sub is_locked($self) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id, at_time, args, command "
        ." FROM requests "
        ." WHERE status <> 'done' "
        ."   AND command <> 'start' AND command <> 'start_domain'"
        ."   AND command not like '%shutdown'"
    );
    $sth->execute;
    my ($id, $at, $args, $command);
    $sth->bind_columns(\($id, $at, $args, $command));
    while ( $sth->fetch ) {
        next if defined $at && $at < time + 2;
        next if !$args;
        my $args_d = decode_json($args);
        if ( exists $args_d->{id_vm} && $args_d->{id_vm} == $self->id ) {
            warn "locked by $command\n";
            return 1;
        }
    }
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

=head2 list_bases

Returns a list of domains that are base in this node

=cut

sub list_bases($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT d.id FROM domains d,bases_vm bv"
        ." WHERE d.is_base=1"
        ."  AND d.id = bv.id_domain "
        ."  AND bv.id_vm=?"
        ."  AND bv.enabled=1"
    );
    my @bases;
    $sth->execute($self->id);
    while ( my ($id_domain) = $sth->fetchrow ) {
        push @bases,($id_domain);
    }
    $sth->finish;
    return @bases;
}

=head2 ping

Returns if the virtual manager connection is available

=cut

sub ping($self, $option=undef, $cache=1) {
    confess "ERROR: option unknown" if defined $option && $option ne 'debug';

    return 1 if $self->is_local();

    my $cache_key = "ping_".$self->host;
    if ($cache) {
        my $ping = $self->_get_cache($cache_key);
        return $ping if defined $ping;
    } else {
        $self->_delete_cache($cache_key);
    }

    my $debug = 0;
    $debug = 1 if defined $option && $option eq 'debug';

    my $ping = $self->_do_ping($self->host, $debug);
    $self->_set_cache($cache_key => $ping)  if $cache;
    return $ping;
}

sub _ping_nocache($self,$option=undef) {
    return $self->ping($option,0);
}

sub _delete_cache($self, $key) {
    $key = "_cache_$key";
    delete $self->{$key};
}
sub _set_cache($self, $key, $value) {
    $key = "_cache_$key";
    $self->{$key} = [ $value, time ];
}

sub _get_cache($self, $key, $timeout=30) {
    $key = "_cache_$key";
    return if !exists $self->{$key};
    my ($value, $time) = @{$self->{$key}};
    if ( time - $time > $timeout ) {
        delete $self->{$key};
        return ;
    }
    return $value;
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

sub _around_ping($orig, $self, $option=undef, $cache=1) {

    my $ping = $self->$orig($option, $cache);

    if ($cache) {
        $self->_cached_active($ping);
        $self->_cached_active_time(time);
    }

    return $ping;
}

sub _insert_network($self, $net) {
    delete $net->{id};
    $net->{id_owner} = Ravada::Utils::user_daemon->id
    if !exists $net->{id_owner};

    $net->{id_vm} = $self->id;
    $net->{is_public}=1 if !exists $net->{is_public};

    my @fields = grep !/^_/, sort keys %$net;

    my $sql = "INSERT INTO virtual_networks ("
    .join(",",@fields).")"
    ." VALUES(".join(",",map { '?' } @fields).")";
    my $sth = $self->_dbh->prepare($sql);
    $sth->execute(map { $net->{$_} } @fields);

    $net->{id} = Ravada::Utils::last_insert_id($$CONNECTOR->dbh);
}

sub _update_network($self, $net) {
    my $sth = $self->_dbh->prepare("SELECT * FROM virtual_networks "
        ." WHERE id_vm=? AND ( internal_id=? OR name = ?)"
    );
    $sth->execute($self->id,$net->{internal_id}, $net->{name});
    my $db_net = $sth->fetchrow_hashref();
    if (!$db_net || !$db_net->{id}) {
        $self->_insert_network($net);
    } else {
        $self->_update_network_db($db_net, $net);
        $net->{id}  = $db_net->{id};
    }
    delete $db_net->{date_changed};
    #    delete $db_net->{id};
}

sub _update_network_db($self, $old, $new0) {
    my $new = dclone($new0);
    my $id = $old->{id} or confess "Missing id";
    my $sql = "";
    for my $field (sort keys %$new) {
        if (    exists $old->{$field} && defined $old->{$field}
            &&  exists $new->{$field} && defined $new->{$field}
            && $new->{$field} eq $old->{$field}) {
            delete $new->{$field};
            next;
        }
        $sql .= ", " if $sql;
        $sql .=" $field=? "
    }
    if ($sql) {
        $sql = "UPDATE virtual_networks set $sql WHERE id=?";
        my $sth = $self->_dbh->prepare($sql);
        my @values = map { $new->{$_} } sort keys %$new;

        $sth->execute(@values, $id);
    }
}

sub _around_new_network($orig, $self, $name) {
    my $data = $self->$orig($name);
    $data->{id_vm} = $self->id;
    $data->{is_active}=1;
    $data->{autostart}=1;
    return $data;
}

sub _around_create_network($orig, $self,$data, $id_owner, $request=undef) {
    my $owner = Ravada::Auth::SQL->search_by_id($id_owner) or confess "Unknown user id: $id_owner";
    die "Error: Access denied: ".$owner->name." can not create networks"
    unless $owner->can_create_networks();

    for my $field (qw(name bridge)) {
        next if !$data->{$field};
        my ($found) = grep { $_->{$field} eq $data->{$field} }
        $self->list_virtual_networks();

        die "Error: network $field=$data->{$field} already exists in "
            .$self->name."\n"
        if $found;
    }

    $data->{is_active}=0 if !exists $data->{is_active};
    $data->{autostart}=0 if !exists $data->{autostart};
    my $ip = $data->{ip_address} or die "Error: missing ip address";
    $ip =~ s/(.*)\..*/$1/;
    $data->{dhcp_start}="$ip.2" if !exists $data->{dhcp_start};
    $data->{dhcp_end}="$ip.254" if !exists $data->{dhcp_end};
    delete $data->{_update};
    delete $data->{internal_id} if exists $data->{internal_id};
    eval { $self->$orig($data) };
    $request->error(''.$@) if $@ && $request;
    $data->{id_owner} = $id_owner;
    $data->{is_public} = 0 if !$data->{is_public};
    delete $data->{isolated};
    $self->_insert_network($data);
}

sub _around_remove_network($orig, $self, $user, $id_net) {
    die "Error: Access denied: ".$user->name." can not remove networks"
    unless $user->can_create_networks();

    confess "Error: undefined network" if !defined $id_net;

    my $name = $id_net;
    if ($id_net =~ /^\d+$/) {
        my ($net) = grep { $_->{id} eq $id_net } $self->list_virtual_networks();
        die "Error: network id $id_net not found" if !$net;
        $name = $net->{name};
    }


    $self->$orig($name);

    my $sth = $self->_dbh->prepare("DELETE FROM virtual_networks WHERE id=?");
    $sth->execute($id_net);
}

sub _around_change_network($orig, $self, $data, $uid) {
    delete $data->{date_changed};

    for my $field (keys %$data) {
        delete $data->{$field} if $field =~ /^_/;
    }

    my $data2 = dclone($data);

    my $id_owner = delete $data->{id_owner};

    my $id = delete $data2->{id};
    my $sth0 = $self->_dbh->prepare("SELECT * FROM virtual_networks WHERE id=?");
    $sth0->execute($id);
    my $old = $sth0->fetchrow_hashref;

    # this field is only in DB
    delete $data->{is_public};
    my $changed = $orig->($self, $data);

    my $user=Ravada::Auth::SQL->search_by_id($uid);

    $self->_update_network_db($old, $data2);

}

sub _check_networks($self) { }

sub _around_list_networks($orig, $self) {
    my $sth_previous = $self->_dbh->prepare(
        "SELECT count(*) FROM virtual_networks "
        ." WHERE id_vm=?"
    );
    $sth_previous->execute($self->id);
    my ($count) = $sth_previous->fetchrow;
    my $first_time = !$count;

    my @list = $orig->($self);
    for my $net ( @list ) {
        $net->{id_vm}=$self->id;
        $self->_update_network($net);
    }
    my $sth = $self->_dbh->prepare(
        "SELECT id,name,id_owner,is_public FROM virtual_networks "
        ." WHERE id_vm=?");
    my $sth_delete = $self->_dbh->prepare("DELETE FROM virtual_networks where id=?");
    $sth->execute($self->id);
    while (my ($id, $name, $id_owner, $is_public) = $sth->fetchrow) {
        my ($found) = grep {$_->{name} eq $name } @list;
        if ( $found ) {
            $found->{id_owner} = $id_owner;
            $found->{id} = $id;
            $found->{is_public} = $is_public;
            next;
        }
        $sth_delete->execute($id);
    }

    $self->_check_networks() if $first_time;

    return @list;
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
    return $self->_do_is_active($force) if $self->is_local || $force;

    return $self->_cached_active if time - $self->_cached_active_time < 60;
    return $self->_do_is_active();
}

sub _do_is_active($self, $force=undef) {
    my $ret = 0;
    $self->_data('cached_down' => 0);
    if ( $self->is_local ) {
        eval {
        $ret = 1 if $self->vm;
        };
    } else {
        my @ping_args = ();
        @ping_args = (undef,0) if $force; # no cache
        if ( !$self->ping(@ping_args) ) {
            $ret = 0;
        } else {
            if ( $self->is_alive ) {
                $ret = 1;
            }
        }
    }
    $self->_cached_active($ret);
    $self->_cached_active_time(time);

    my $cache_key = "ping_".$self->host;
    $self->_delete_cache($cache_key);
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

=head2 public_ip

Returns the public IP of the virtual manager if defined

=cut


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

    my ($out,$err) = $self->run_command_cache("ls");

=cut

sub run_command($self, @command) {

    my ($exec) = $command[0];
    if ($exec !~ m{^/}) {
        my ($exec_command,$args) = $exec =~ /(.*?) (.*)/;
        $exec_command = $exec if !defined $exec_command;
        $exec = $self->_which($exec_command);
        confess "Error: $exec_command not found" if !$exec;
        $command[0] = $exec;
        $command[0] .= " $args" if $args;
    }
    return $self->_run_command_local(@command) if $self->is_local();

    my $ssh = $self->_ssh or confess "Error: Error connecting to ".$self->host;

    my ($out, $err) = $ssh->capture2({timeout => 10},join " ",@command);
    chomp $err if $err;
    $err = '' if !defined $err;

    confess "Error: Failed remote command on ".$self->host." err='$err'\n"
    ."ssh error: '".$ssh->error."'\n"
    ."command: ". Dumper(\@command)
    if $ssh->error && $ssh->error !~ /^child exited with code/;


    return ($out, $err);
}

=head2 run_command_cache

Run a command on the node

    my ($out,$err) = $self->run_command_cache("ls");

=cut


sub run_command_cache($self, @command) {
    my $key = join(" ",@command);
    return @{$self->{_run}->{$key}} if exists $self->{_run}->{$key};

    my ($out, $err) = $self->run_command(@command);
    $self->{_run}->{$key}=[$out,$err];
    return ($out, $err);
}

=head2 run_command_nowait

Run a command on the node

    $self->run_command_nowait("/sbin/poweroff");

=cut

sub run_command_nowait($self, @command) {

    return $self->_run_command_local(@command) if $self->is_local();

    return $self->run_command(@command);

=pod

    warn "1 ".localtime(time) if $self->_data('hostname') =~ /192.168.122./;
    my $chan = $self->_ssh_channel() or die "ERROR: No SSH channel to host ".$self->host;
    warn "2 ".localtime(time) if $self->_data('hostname') =~ /192.168.122./;

    my $command = join(" ",@command);
    $chan->exec($command);# or $self->{_ssh}->die_with_error;

    $chan->send_eof();

    return;

=cut

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

    my $ssh = $self->_ssh or confess "Error: no ssh connection";
    unless ( $file =~ /^[a-z0-9 \/_:\-\.]+$/i ) {
        my $file2=$file;
        $file2 =~ tr/[a-z0-9 \/_:\-\.]/*/c;
        die "Error: insecure character in '$file': '$file2'";
    }
    my ($rin, $pid) = $self->_ssh->pipe_in("cat > '$file'")
        or die "pipe_in method failed ".$self->_ssh->error;

    print $rin $contents;
    close $rin;
}

sub _write_file_local( $self, $file, $contents ) {
    my ($path) = $file =~ m{(.*)/};
    make_path($path) or die "$! $path"
        if ! -e $path;
    CORE::open(my $out,">",$file) or confess "$! $file";
    print $out $contents;
    close $out or die "$! $file";
}

=head2 read_file

Reads a file in memory from the storage of the virtual manager

=cut

sub read_file( $self, $file ) {
    return $self->_read_file_local($file) if $self->is_local;

    my ($rout, $pid) = $self->_ssh->pipe_out("cat $file")
        or die "pipe_out method failed ".$self->_ssh->error;

    return join ("",<$rout>);
}

sub _read_file_local( $self, $file ) {
    confess "Error: file undefined" if !defined $file;
    CORE::open my $in,'<',$file or croak "$! $file";
    return join('',<$in>);
}

=head2 create_iptables_chain

Creates a new chain in the system iptables

=cut

sub create_iptables_chain($self, $chain, $jchain='INPUT') {
    my ($out, $err) = $self->run_command("iptables","-n","-L",$chain);

    $self->run_command('iptables', '-N' => $chain)
        if $out !~ /^Chain $chain/;

    ($out, $err) = $self->run_command("iptables","-n","-L",$jchain);
    return if grep(/^$chain /, split(/\n/,$out));

    $self->run_command("iptables", '-I', $jchain, '-j' => $chain);

}

=head2 iptables

Runs an iptables command in the virtual manager

Example:

    $vm->iptables( A => 'INPUT', p => 22, j => 'ACCEPT');

=cut

sub iptables($self, @args) {
    my @cmd = ('iptables','-w');
    my $delete=0;
    for ( ;; ) {
        my $key = shift @args or last;

        return if $key =~ /state|established/i && $delete;

        $delete++ if $key eq 'D';

        my $field = "-$key";
        $field = "-$field" if length($key)>1;
        push @cmd,($field);
        push @cmd,(shift @args);

    }
    my ($out, $err) = $self->run_command(@cmd);
    confess "@cmd $err" if $err && $err !~ /does a matching rule exist in that chain/ && $err !~ /RULE_DELETE failed/;
    warn $err if $err;
}

=head2 iptables_unique

Runs an iptables command in the virtual manager only if it wasn't already there

Example:

    $vm->iptables_unique( A => 'INPUT', p => 22, j => 'ACCEPT');

=cut

sub iptables_unique($self,@rule) {
    return if $self->_search_iptables(@rule);
    return $self->iptables(@rule);
}

sub _search_iptables($self, %rule) {
    delete $rule{s} if exists $rule{s} && $rule{s} eq '0.0.0.0/0';

    my $table = 'filter';
    $table = delete $rule{t} if exists $rule{t};
    my $iptables = $self->iptables_list();

    if (exists $rule{I}) {
        $rule{A} = delete $rule{I};
    }
    $rule{m} = $rule{p} if exists $rule{p} && !exists $rule{m};
    $rule{d} = "$rule{d}/32" if exists $rule{d} && defined $rule{d} && $rule{d} !~ m{/\d+$};
    $rule{s} = "$rule{s}/32" if exists $rule{s} && $rule{s} !~ m{/\d+$};

    for my $line (@{$iptables->{$table}}) {

        my %args = @$line;
        delete $args{s} if exists $args{s} && $args{s} eq '0.0.0.0/0';
        my $match = 1;
        for my $key (keys %rule) {
            $match = 0 if !exists $args{$key} || !exists $rule{$key}
            || !defined $rule{$key}
            || $args{$key} ne $rule{$key};
            last if !$match;
        }
        if ( $match ) {
            return 1;
        }
    }
    return 0;
}

=head2 iptables_list

Returns the list of the system iptables

=cut

sub iptables_list($self) {
#   Extracted from Rex::Commands::Iptables
#   (c) Jan Gehring <jan.gehring@gmail.com>
    my ($out,$err) = $self->run_command("iptables-save");
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

=head2 balance_vm

Returns a Virtual Manager from all the nodes to run a virtual machine.
When the optional base argument is passed it returns a node from the list
of VMs where the base is prepared.

Arguments

=over

=item uid

=item base [optional]

=item id_domain [optional]

=cut

sub balance_vm($self, $uid, $base=undef, $id_domain=undef, $host_devices=1) {

    my @vms;
    if ($base) {
        confess "Error: base is not an object ".Dumper($base)
        if !ref($base);

        if ($id_domain) {
            my @vms_all = $base->list_vms(0,1);
            push @vms_all,($self) if !@vms_all;
            if ( $host_devices ) {
                @vms = $self->_filter_host_devices($id_domain, @vms_all);
            } else {
                @vms = @vms_all;
            }
        } else {
            @vms= $base->list_vms($host_devices,1);
        }

    } else {
        @vms = $self->list_nodes();
    }

    my @vms_active;
    for my $vm (@vms) {
        push @vms_active,($vm) if $vm && $vm->vm && $vm->is_active && $vm->enabled;
    }
    return $vms_active[0] if scalar(@vms_active)==1;

    if ($base && $base->_data('balance_policy') == 1 ) {
        my $vm = $self->_balance_already_started($uid, $id_domain, \@vms_active);
        return $vm if $vm;
    }
    my $vm = $self->_balance_free_memory($base, \@vms_active);
    return $vm if $vm;
    die "Error: No available devices or no free nodes.\n" if $host_devices;
    die "Error: No free nodes available.\n";
}

sub _filter_host_devices($self, $id_domain, @vms_all) {
    my $domain = Ravada::Domain->open($id_domain);

    my @host_devices = $domain->list_host_devices();
    return @vms_all if !@host_devices;

    my @vms;
    for my $vm (@vms_all) {
        next if !$domain->_available_hds($vm->id, \@host_devices);
        push @vms, ($vm);
    }

    die "Error: No available devices in ".join(" , ",map { $_->name } @host_devices)."\n"
    if !scalar(@vms);

    return @vms;
}

sub _balance_already_started($self, $uid, $id_domain, $vms) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id_vm,name,status "
        ." FROM domains "
        ." WHERE id_owner=? "
        ."   AND id <> ? "
        ."   AND id_vm IS NOT NULL "
        ." ORDER BY status DESC"
    );
    $sth->execute($uid, $id_domain);
    my ($id_vm);
    my %valid_id = map { $_->id => $_ } @$vms;

    my $id_hibernated;
    my $id_starting;
    while (my ($id_vm, $name, $status) = $sth->fetchrow ) {
        next if ! $valid_id{$id_vm};
        $id_hibernated = $id_vm if $status =~ /h.bernated/;
        $id_starting = $id_vm if $status =~ /starting/;
        next if $status ne 'active';
        return $valid_id{$id_vm}
    }
    return if !defined $id_hibernated && !defined $id_starting;
    return $valid_id{$id_hibernated} if $id_hibernated;
    return $valid_id{$id_starting} if $id_starting;
    return;
}

sub _balance_free_memory($self , $base, $vms) {

    my $min_memory = $Ravada::Domain::MIN_FREE_MEMORY;
    $min_memory = $base->get_info->{memory} if $base;

    my %vm_list;
    my @status;

    for my $vm (_random_list( @$vms )) {
        next if !$vm || !$vm->vm || !$vm->enabled();
        my $active = 0;
        eval { $active = $vm->is_active() };
        my $error = $@;
        if ($error && !$vm->is_local) {
            warn "[balancing] ".$vm->name." $error";
            next;
        }

        next if !$active;
        next if $base && !$vm->is_local && !$base->base_in_vm($vm->id);
        next if $vm->is_locked();

        my $free_memory;
        eval { $free_memory = $vm->free_memory };
        if ($@) {
            warn $@;
            $vm->enabled(0) if !$vm->is_local();
            next;
        }
        next if $free_memory < $min_memory;

        my $n_active = $vm->_count_domains(status => 'active')
                        + $vm->_count_domains(status => 'starting');

        $free_memory = int($free_memory / 1024 );
        my $key = $n_active.".".$free_memory;
        $vm_list{$key} = $vm;
        last if $key =~ /^[01]+\./; # don't look for other nodes when this one is empty !
    }
    my @sorted_vm = _sort_vms(\%vm_list);
#    warn Dumper([ map {  [$_ , $vm_list{$_}->name ] } keys %vm_list]);
#    warn "sorted ".Dumper([ map { $_->name } @sorted_vm ]);
    for my $vm (@sorted_vm) {
        return $vm;
    }
    return;
}

sub _sort_vms($vm_list) {
    my @sorted_vm = map { $vm_list->{$_} } sort {
        my ($ad, $am) = $a =~ m{(\d+)\.(\d+)};
        my ($bd, $bm) = $b =~ m{(\d+)\.(\d+)};
        $ad <=> $bd || $bm <=> $am;
    } keys %$vm_list;
    return @sorted_vm;
}

sub _count_domains($self, %args) {
    my $query = "SELECT count(*) FROM domains WHERE id_vm = ? AND ";
    $query .= join(" AND ",map { "$_ = ?" } sort keys %args );
    my $sth = $$CONNECTOR->dbh->prepare($query);
    $sth->execute( $self->id, map { $args{$_} } sort keys %args );
    my ($count) = $sth->fetchrow;
    return $count;
}

=head2 shutdown_domains

Shuts down all the virtual machines in the node

=cut

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

sub _shared_storage_cache($self, $node, $dir, $value=undef) {
    my ($id_node1, $id_node2) = ($self->id, $node->id);
    ($id_node1, $id_node2) = reverse ($self->id, $node->id) if $self->id < $node->id;
    my $cached_storage = $self->_get_shared_storage_cache($id_node1, $id_node2, $dir);
    return $cached_storage if !defined $value;

    return $value if defined $cached_storage && $cached_storage == $value;

    confess "Error: conflicting storage, cached=$cached_storage , new=$value"
    if defined $cached_storage && $cached_storage != $value;

    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO storage_nodes (id_node1, id_node2, dir, is_shared) "
        ." VALUES (?,?,?,?)"
    );
    eval { $sth->execute($id_node1, $id_node2, $dir, $value) };
    confess $@ if $@ && $@ !~ /Duplicate entry/i;
    return $value;
}

sub _get_shared_storage_cache($self, $id_node1, $id_node2, $dir) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM storage_nodes "
        ." WHERE dir= ? "
        ." AND ((id_node1 = ? AND id_node2 = ? ) "
        ."      OR (id_node2 = ? AND id_node1 = ? )) "
    );
    $sth->execute($dir, $id_node1, $id_node2, $id_node2, $id_node1);
    my @is_shared;
    my $is_shared;
    my $conflict_is_shared;
    while ( my $row = $sth->fetchrow_hashref ) {
        if (defined $is_shared && defined $row->{shared} && $is_shared != $row->{is_shared}) {
            $conflict_is_shared=1;
        }
        push @is_shared,($row);
        $is_shared = $row->{is_shared}
        unless $is_shared && !$row->{is_shared};
    }
    if (scalar(@is_shared)>1 && $conflict_is_shared) {
        warn "Warning: error in storage_nodes , conflicting duplicated entries "
        .Dumper(\@is_shared)
    }
    return $is_shared;
}

=head2 shared_storage

Returns true if there is shared storage among to nodes

Arguments:

=over

=item * node

=item * directory

=back

=cut

sub shared_storage($self, $node, $dir) {
    $dir .= '/' if $dir !~ m{/$};
    my $shared_cache = $self->_shared_storage_cache($node, $dir);
    return $shared_cache if defined $shared_cache;

    return if !$node->is_active || !$self->is_active;

    my $file;
    for ( ;; ) {
        $file = $dir.Ravada::Utils::random_name(4).".tmp";
        my $exists;
        eval {
            $exists = $self->file_exists($file) || $node->file_exists($file);
        };
        next if $exists;
        return if $@ && $@ =~ /onnect to SSH/i;
        last;
    }
    $self->write_file($file,''.localtime(time));
    my $shared;
    for (1 .. 10 ) {
        $shared = $node->file_exists($file);
        last if $shared;
        sleep 1;
    }
    $self->remove_file($file);
    $shared = 0 if !defined $shared;
    $self->_shared_storage_cache($node, $dir, $shared);

    return $shared;
}

=head2 copy_file_storage

Copies a volume file to another storage

Args:

=over

=item * file

=item * storage

=back

=cut

sub copy_file_storage($self, $file, $storage) {
    die "Error: file '$file' does not exist" if !$self->file_exists($file);

    my ($pool) = grep { $_->{name} eq $storage } $self->list_storage_pools(1);
    die "Error: storage pool $storage does not exist" if !$pool;

    my $path = $pool->{path};

    die "TODO remote" if !$self->is_local;

    copy($file, $path) or die "$! $file -> $path";

    my ($filename) = $file =~ m{.*/(.*)};
    die "Error: file '$file' not copied to '$path'" if ! -e "$path/$filename";

    return "$path/$filename";

}

sub _fetch_tls_host_subject($self) {

    return '' if !$self->dir_cert();

    my $key = 'subject';
    my $subject = $self->_fetch_tls_cached($key);
    return $subject if $self->readonly || $subject;

    return $self->_do_fetch_tls_host_subject();

}

sub _do_fetch_tls_host_subject($self) {
    return '' if !$self->dir_cert();

    my $key = 'subject';
    return $self->_fetch_tls_cached($key)
    if $self->readonly;

    my @cmd= qw(/usr/bin/openssl x509 -noout -text -in );
    push @cmd, ( $self->dir_cert."/server-cert.pem" );

    my ($out, $err) = $self->run_command(@cmd);
    die $err if $err;

    my $subject;
    for my $line (split /\n/,$out) {
        chomp $line;
        next if $line !~ /^\s+Subject:\s+(.*)/;
        $subject = $1;
        $subject =~ s/ = /=/g;
        $subject =~ s/, /,/g;
        last;
    }
    $self->_store_tls( $key => $subject );
    return $subject;
}

sub _fetch_tls_cached($self, $field) {
    my $tls_json = $self->_data('tls');
    return if !$tls_json;
    my $tls = {};
    eval {
        $tls = decode_json($tls_json) if length($tls);
    };
    warn $@ if $@;
    return ( $tls->{$field} or '');
}

sub _store_tls($self, $field, $value ) {
    my $tls_json = $self->_data('tls');
    my $tls = {};
    eval {
        $tls = decode_json($tls_json) if length($tls_json);
    };
    warn $@ if $@;
    $tls = {} if $@;
    $tls->{$field} = $value;
    $self->_data( 'tls' => encode_json($tls) );
    return ( $tls->{$field} or '');
}

sub _fetch_tls_ca($self) {
    my $ca = $self->_fetch_tls_cached('ca');
    return $ca if $self->readonly || $ca;

    return $self->_do_fetch_tls_ca();
}

sub _do_fetch_tls_ca($self) {
    my ($out, $err) = $self->run_command("/bin/cat", $self->dir_cert."/ca-cert.pem");

    my $ca = join('\n', (split /\n/,$out) );
    $self->_store_tls( ca => $ca );

    return $ca;
}

sub _fetch_tls_dates($self) {
    return if $self->readonly;
    my ($out, $err) = $self->run_command("openssl","x509","-in", $self->dir_cert."/ca-cert.pem"
    ,"-dates","-noout");
    for my $line (split /\n/,$out) {
        my ($field,$value) = $line =~ m{(.*?)=(.*)};
        next if !$field || !$value;
        $self->_store_tls( $field => $value );
    }
}

sub _fetch_tls($self) {

    return if $self->readonly || $self->type ne 'KVM' || $self->{_tls_fetched}++;

    my $tls = $self->_data('tls');
    my $tls_hash = {};
    eval {
        $tls_hash = decode_json($tls) if length($tls);
    };
    for (keys %$tls_hash) {
        delete $tls_hash->{$_} if !$tls_hash->{$_};
    }
    my $time = $tls_hash->{time};
    if (!defined $tls || !$tls
        || !$time
        || ( time-$time > 300  &&  rand(10)<2)
        || !$tls_hash || !ref($tls_hash) || !keys(%$tls_hash)) {
        $self->_do_fetch_tls();
    }

}

sub _do_fetch_tls($self) {
    $self->_store_tls( time => time );
    $self->_do_fetch_tls_host_subject();
    $self->_do_fetch_tls_ca();
    $self->_fetch_tls_dates();
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

sub _wake_on_lan( $self=undef ) {
    return if $self && ref($self) && $self->is_local;

    my ($mac_addr, $id_node);
    if (ref($self)) {
        $mac_addr = $self->_data('mac');
        $id_node = $self->id;
    } else {
        $id_node = $self;
        my $sth = $$CONNECTOR->dbh->prepare("SELECT mac FROM vms WHERE id=?");
        $sth->execute($id_node);
        $mac_addr = $sth->fetchrow();
    }
    die "Error: I don't know the MAC address for node $id_node"
        if !$mac_addr;

    my $sock = new IO::Socket::INET(Proto=>'udp', Timeout => 60)
        or die "Error: I can't create an UDP socket";
    my $host = '255.255.255.255';
    my $port = 9;

    my $ip_addr = inet_aton($host);
    my $sock_addr = sockaddr_in($port, $ip_addr);
    $mac_addr =~ s/://g;
    my $packet = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

    setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1);
    send($sock, $packet, MSG_DONTWAIT , $sock_addr);
    close ($sock);

}

=head2 start

Starts the node

=cut

sub start($self) {
    $self->_wake_on_lan();
    $self->_data('is_active' => 1);
}

=head2 shutdown

Shuts down the node

=cut

sub shutdown($self) {
    die "Error: local VM can't be shut down\n" if $self->is_local;
    $self->is_active(0);
    $self->run_command_nowait('/sbin/poweroff');
}

sub _check_free_disk($self, $size, $storage_pool=undef) {

    my $size_out = int($size / 1024 / 1024 / 1024 ) * 1024 *1024 *1024;

    my $free = $self->free_disk($storage_pool);
    my $free_out = int($free / 1024 / 1024 / 1024 ) * 1024 *1024 *1024;

    confess "Error creating volume, out of space."
    ." Requested: ".Ravada::Utils::number_to_size($size_out)
    ." , Disk free: ".Ravada::Utils::number_to_size($free_out)
    ."\n"
    if $size > $free;

}
sub _list_used_ports_sql($self, $used_port) {

    my $sth = $$CONNECTOR->dbh->prepare("SELECT public_port FROM domain_ports ");
    $sth->execute();
    my ($port, $json_extra);
    $sth->bind_columns(\$port);

    while ($sth->fetch ) {
        $used_port->{$port}++ if defined $port;
    };

    # do not use ports in displays
    $sth = $$CONNECTOR->dbh->prepare("SELECT port,extra FROM domain_displays ");
    $sth->execute();
    $sth->bind_columns(\$port,\$json_extra);

    while ($sth->fetch ) {
        $used_port->{$port}++ if defined $port;
        my $extra = {};
        eval { $extra = decode_json($json_extra) if $extra };
        my $tls_port;
        $tls_port = $extra->{tls_port} if $extra && $extra->{tls_port};
        $used_port->{$tls_port}++ if $tls_port;
    };

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
        next if !exists $rule{A} || $rule{A} ne 'PREROUTING' || !$rule{dport};
        $used_port->{$rule{dport}} = $rule{'to-destination'};
    }
}

sub _new_free_port($self, $used_port={}) {
    $self->_list_used_ports_sql($used_port);
    $self->_list_used_ports_ss($used_port);
    $self->_list_used_ports_iptables($used_port);

    my $min_free_port = Ravada::setting(undef,'/backend/expose_port_min');
    my $free_port = $min_free_port;
    for (;;) {
        last if !$used_port->{$free_port};
        $free_port++ ;
        die "Error: no free ports available from $min_free_port.\n"
        if $free_port > 65535;
    }
    return $free_port;
}

=head2 list_network_interfaces

Returns a list of all the known interface

Argument: type ( nat or bridge )

=cut

sub list_network_interfaces($self, $type) {
    my $sub = {
        nat => \&_list_nat_interfaces
        ,bridge => \&_list_bridges
    };

    my $cmd = $sub->{$type} or confess "Error: Unknown interface type $type";
    return $cmd->($self);
}

sub _list_nat_interfaces($self) {

    my @nets = $self->list_virtual_networks();
    my @networks;
    for my $net (@nets) {
        push @networks,($net->{name}) if $net->{name};
    }
    return @networks;
}

sub _list_qemu_bridges($self) {
    my %bridge;
    my @networks = $self->list_virtual_networks();
    for my $net (@networks) {
        next if !$net->{bridge};
        my $nat_bridge = $net->{bridge};
        $bridge{$nat_bridge}++;
    }
    return keys %bridge;
}

sub _which($self, $command) {
    return $self->{_which}->{$command} if exists $self->{_which} && exists $self->{_which}->{$command};

    my $bin_which = $self->{_which}->{which};
    if (!$bin_which) {
        for my $try ( "/bin/which","/usr/bin/which") {
            $bin_which = $try if $self->file_exists($try);
            last if $bin_which;
        }
        if (!$bin_which) {
            die "Error: No which found in /bin nor /usr/bin ".$self->name."\n";
            $bin_which = "which";
        }
    }
    my @cmd = ( $bin_which,$command);
    my ($out,$err) = $self->run_command(@cmd);
    chomp $out;
    $self->{_which}->{$command} = $out;
    return $out;
}

sub _list_bridges($self) {

    my %qemu_bridge = map { $_ => 1 } $self->_list_qemu_bridges();

    my $brctl = 'brctl';
    my @cmd = ( $self->_which($brctl),'show');
    die "Error: missing $brctl" if !$cmd[0];
    my ($out,$err) = $self->run_command(@cmd);

    die $err if $err;
    my @lines = split /\n/,$out;
    shift @lines;

    my @networks;
    for (@lines) {
        my ($bridge, $interface) = /\s*(.*?)\s+.*\s(.*)/;
        push @networks,($bridge) if $bridge && !$qemu_bridge{$bridge};
    }
    $self->{_bridges} = \@networks;
    return @networks;
}

sub _check_equal_storage_pools($vm1, $vm2) {
    my @sp;
    push @sp,($vm1->default_storage_pool_name)  if $vm1->default_storage_pool_name;
    push @sp,($vm1->base_storage_pool)  if $vm1->base_storage_pool;
    push @sp,($vm1->clone_storage_pool) if $vm1->clone_storage_pool;

    my %sp1 = map { $_ => 1 } @sp;

    my @sp1 = grep /./,keys %sp1;

    my %sp2 = map { $_ => 1 } $vm2->list_storage_pools();

    for my $pool ( @sp1 ) {
        die "Error: Storage pool '$pool' not found on node ".$vm2->name."\n"
            .Dumper([keys %sp2])
        if !$sp2{ $pool };

        my ($path1, $path2) = ($vm1->_storage_path($pool), $vm2->_storage_path($pool));

        confess "Error: Storage pool '$pool' different. In ".$vm1->name." $path1 , "
            ." in ".$vm2->name." $path2" if $path1 ne $path2;
    }
    return 1;
}

sub _max_hd($self, $name) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT MAX(name) FROM host_devices "
        ." WHERE name like ? AND id_vm = ?"
    );
    $sth->execute("$name%", $self->id);

    my ($found ) =$sth->fetchrow;

    return 0 if !$found;

    my ($max) = $found =~ /.*?(\d+)$/;
    return ($max or 0);

}

=head2 add_host_device

Add a new host device configuration to this Virtual Machines Manager from a previous template

   $vm->add_host_device(template => 'name');

=cut

sub add_host_device($self, %args) {
    _init_connector();

    my $template = delete $args{template} or confess "Error: template required";
    my $name = delete $args{name};

    my $info = Ravada::HostDevice::Templates::template($self->type, $template);
    my $template_list = delete $info->{templates};
    $info->{id_vm} = $self->id;

    $info->{name}.= " ".($self->_max_hd($info->{name})+1);

    $info->{name} = $name if $name;

    my $query = "INSERT INTO host_devices "
    ."( ".join(", ",sort keys %$info)." ) "
    ." VALUES ( ".join(", ",map { '?' } keys %$info)." ) "
    ;

    my $sth = $$CONNECTOR->dbh->prepare($query);
    eval {
    $sth->execute(map { $info->{$_} } sort keys %$info );
    };
    die Dumper([$info,$@]) if $@;

    my $id = Ravada::Request->_last_insert_id( $$CONNECTOR );

    for my $template( @$template_list ) {
        $template->{id_host_device} = $id;
        $template->{type} = 'node' if !exists $template->{type};
        $query = "INSERT INTO host_device_templates "
        ."( ".join(", ",sort keys %$template)." ) "
        ." VALUES ( ".join(", ",map { '?' } keys %$template)." ) "
        ;

        my $sth2= $$CONNECTOR->dbh->prepare($query);
        $sth2->execute(map { $template->{$_} } sort keys %$template);

    }

    return $id;
}

=head2 list_host_devices

List all the configured host devices in this node

=cut

sub list_host_devices($self) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM host_devices WHERE id_vm=?");
    $sth->execute($self->id);

    my @found;
    while (my $row = $sth->fetchrow_hashref) {
	    $row->{devices} = '' if !defined $row->{devices};
	    $row->{devices_node} = '' if !defined $row->{devices_node};
        push @found,(Ravada::HostDevice->new(%$row));
    }

    return @found;
}

=head2 list_machine_types

Placeholder for list machine types that returns an empty list by default.
It can be overloaded in each backend module.

=cut

sub list_machine_types($self) {
    return ();
}

=head2 dir_backup

Directory where virtual machines backup will be stored. It can
be changed from the frontend nodes page management.

=cut

sub dir_backup($self) {
    my $dir_backup = $self->_data('dir_backup');

    if (!$dir_backup) {
        $dir_backup = $self->dir_img."/backup";
        $self->_data('dir_backup', $dir_backup);
    }
    if (!$self->file_exists($dir_backup)) {
        if ($self->is_local) {
            make_path($dir_backup) or die "$! $dir_backup";
        } else {
            my ($out,$error)= $self->run_command("mkdir","-p",$dir_backup);
            die "Error on mkdir -p $dir_backup $error" if $error;
        }
    }
    return $dir_backup;
}

sub _follow_link($self, $file) {
    my ($dir, $name) = $file =~ m{(.*)/(.*)};
    my $file2 = $file;
    if ($dir) {
        my $dir2 = $self->_follow_link($dir);
        $file2 = "$dir2/$name";
    }

    if (!defined $self->{_is_link}->{$file2} ) {
        my ($out,$err) = $self->run_command("stat","-c",'"%N"', $file2);
        chomp $out;
        my ($link) = $out =~ m{ -> '(.+)'};
        if ($link) {
            if ($link !~ m{^/}) {
                my ($path) = $file2 =~ m{(.*/)};
                $path = "/" if !$path;
                $link = "$path$link";
            }
            $self->{_is_link}->{$file2} = $link;
        }
    }
    $self->{_is_link}->{$file2} = $file2 if !exists $self->{_is_link}->{$file2};
    return $self->{_is_link}->{$file2};
}

sub _is_link_remote($self, $vol) {

    my ($out,$err) = $self->run_command("stat",$vol);
    chomp $out;
    $out =~ m{ -> (/.*)};
    return $1 if $1;

    my $path = "";
    my $path_link;
    for my $dir ( split m{/},$vol ) {
        next if !$dir;
        $path_link .= "/$dir" if $path_link && $dir;
        $path.="/$dir";

        ($out,$err) = $self->run_command("stat",$path);
        chomp $out;
        my ($dir_link) = $out =~ m{ -> (/.*)};

        $path_link = $dir_link if $dir_link;
    }
    return $path_link if $path_link;

}

sub _is_link($self,$vol) {
    return $self->_is_link_remote($vol) if !$self->is_local;

    my $link = readlink($vol);
    return $link if $link;

    my $path = "";
    my $path_link;
    for my $dir ( split m{/},$vol ) {
        next if !$dir;
        $path_link .= "/$dir" if $path_link && $dir;
        $path.="/$dir";
        my $dir_link = readlink($path);
        $path_link = $dir_link if $dir_link;
    }
    return $path_link if $path_link;
}

=head2 list_unused_volumes

Returns a list of unused volume files

=cut

sub list_unused_volumes($self) {
    my @all_vols = $self->list_volumes();

    my @used = $self->list_used_volumes();
    my %used;
    for my $vol (@used) {
        $used{$vol}++;
        my $link = $self->_follow_link($vol);
        $used{$link}++ if $link;
    }

    my @vols;
    my %duplicated;
    for my $vol ( @all_vols ) {
        next if $used{$vol};

        my $link = $self->_follow_link($vol);
        next if $used{$link};
        next if $duplicated{$link}++;

        push @vols,($link);
    }
    return @vols;
}

=head2 can_list_cpu_models

Default for Virtual Managers that can list cpu models is 0

=cut

sub can_list_cpu_models($self) {
    return 0;
}

sub _around_copy_file_storage($orig, $self, $file, $storage) {
    my $sth = $self->_dbh->prepare("SELECT id,info FROM volumes"
        ." WHERE file=? "
    );
    $sth->execute($file);
    my ($id,$infoj) = $sth->fetchrow;

    my $new_file = $self->$orig($file, $storage);

    if ($id) {
        my $info = decode_json($infoj);
        $info->{file} = $new_file;
        my $sth_update = $self->_dbh->prepare(
            "UPDATE volumes set info=?,file=?"
            ." WHERE id=?"
        );
        $sth_update->execute(encode_json($info), $new_file, $id);
    }

    return $new_file;
}

sub _list_files_local($self, $dir, $pattern) {
    opendir my $ls,$dir or die "$! $dir";
    my @list;
    while (my $file = readdir $ls) {
        next if defined $pattern && $file !~ $pattern;
        push @list,($file);
    }
    return @list;
}

sub _list_files_remote($self, $dir, $pattern) {
    my @cmd=("ls",$dir);
    my ($out, $err) = $self->run_command(@cmd);
    my @list;
    for my $file (split /\n/,$out) {
        push @list,($file) if !defined $pattern || $file =~ $pattern;
    }
    return @list;
}

=head2 list_files

List files in a Virtual Manager

Arguments: dir , optional regexp pattern

=cut

sub list_files($self, $dir, $pattern=undef) {
    return $self->_list_files_local($dir, $pattern) if $self->is_local;
    return $self->_list_files_remote($dir, $pattern);
}

1;


