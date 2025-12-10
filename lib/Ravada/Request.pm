package Ravada::Request;

use strict;
use warnings;

=head1 NAME

Ravada::Request - Requests library for Ravada

=cut

use Carp qw(confess cluck);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use JSON::XS;
use Hash::Util;
use Storable qw(dclone);
use Time::Piece;
use Ravada;
use Ravada::Front;
use Ravada::Utils;

use vars qw($AUTOLOAD);

no warnings "experimental::signatures";
use feature qw(signatures);

=pod

Request a command to the ravada backend

=cut

my $COUNT = 0;
our %FIELD = map { $_ => 1 } qw(error output);
our %FIELD_RO = map { $_ => 1 } qw(id name);

our $args_manage = { name => 1 , uid => 1, after_request => 2 };
our $args_prepare = { id_domain => 1 , uid => 1, with_cd => 2, publish => 2 };
our $args_remove_base = { id_domain => 1 , uid => 1 };
our $args_manage_iptables = {uid => 1, id_domain => 1, remote_ip => 1};

our %VALID_ARG = (
    create_domain => {
              vm => 2
           ,name => 1
           ,swap => 2
         ,id_iso => 2
         ,iso_file => 2
        ,id_base => 2
       ,id_owner => 1
    ,id_template => 2
         ,memory => 2
           ,disk => 2
           #        ,network => 2
      ,remote_ip => 2
          ,start => 2
           ,data => 2
           ,options => 2
           ,storage => 2
           ,id_vm => 2
    }
    ,open_iptables => $args_manage_iptables
      ,remove_base => $args_remove_base
     ,prepare_base => $args_prepare
     ,spinoff => { id_domain => 1, uid => 1 }
     ,pause_domain => $args_manage
    ,resume_domain => {%$args_manage, remote_ip => 1 }
    ,remove_domain => $args_manage
    ,restore_domain => { id_domain => 1, uid => 1 }
    ,shutdown_domain => { name => 2, id_domain => 2, uid => 1, timeout => 2, at => 2
                       , check => 2
                       , id_vm => 2 }
    ,force_shutdown_domain => { id_domain => 1, uid => 1, at => 2, id_vm => 2 }
    ,force_shutdown => { id_domain => 1, uid => 1, at => 2, id_vm => 2 }
    ,reboot_domain => { name => 2, id_domain => 2, uid => 1, timeout => 2, at => 2
                       , id_vm => 2 }
    ,force_reboot_domain => { id_domain => 1, uid => 1, at => 2, id_vm => 2 }
    ,shutdown_start =>{ name => 2, id_domain => 2, uid => 1, timeout => 2
        , at => 2 , id_vm => 2 }
    ,screenshot => { id_domain => 1 }
    ,domain_autostart => { id_domain => 1 , uid => 1, value => 2 }
    ,copy_screenshot => { id_domain => 1 }
    ,start_domain => {%$args_manage, remote_ip => 2, name => 2, id_domain => 2, enable_host_devices => 2 }
    ,start_clones => { id_domain => 1, uid => 1, remote_ip => 1, sequential => 2 }
    ,shutdown_clones => { id_domain => 1, uid => 1, timeout => 2 }
    ,rename_domain => { uid => 1, name => 1, id_domain => 1}
    ,dettach => { uid => 1, id_domain => 1 }
    ,set_driver => {uid => 1, id_domain => 1, id_option => 1}
    ,hybernate=> {uid => 1, id_domain => 1}
    ,download => {uid => 2, id_iso => 1, id_vm => 2, vm => 2, verbose => 2, delay => 2, test => 2}
    ,refresh_storage => { id_vm => 2, uid => 1 }
    ,list_storage_pools => { id_vm => 1 , uid => 1, data => 2 }
    ,active_storage_pool => { uid => 1, id_vm => 1, name => 1, value => 1}
    ,remove_storage_pool => { uid => 1, id_vm => 1, name => 1}
    ,check_storage => { uid => 1 }
    ,create_storage_pool => { uid => 1, id_vm => 1, name => 1, directory => 1 }
    ,set_base_vm=> {uid => 1, id_vm=> 1, id_domain => 1, value => 2 }
    ,cleanup => { timeout => 2 }
    ,clone => { uid => 1, id_domain => 1, name => 2, memory => 2, number => 2, volatile => 2, id_owner => 2
                # If base has pools, from_pool = 1 if undefined
                # when from_pool is true the clone is picked from the pool
                # when from_pool is false the clone is created
                ,from_pool => 2
                # If base has pools, create anew and add to the pool
                ,add_to_pool => 2
                ,start => 2,
                ,remote_ip => 2
                ,with_cd => 2
                ,storage => 2
                ,options => 2
                ,enable_host_devices => 2
    }
    ,change_owner => {uid => 1, id_domain => 1}
    ,add_hardware => {uid => 1, id_domain => 1, name => 1, number => 2, data => 2 }
    ,remove_hardware => {uid => 1, id_domain => 1, name => 1, index => 2, option => 2 }
    ,change_hardware => {uid => 1, id_domain => 1, hardware => 1, index => 2, data => 1 }
    ,enforce_limits => { timeout => 2, _force => 2 }
    ,refresh_machine => { id_domain => 1, uid => 1 }
    ,refresh_machine_ports => { id_domain => 1, uid => 1, timeout => 2 }
    ,rebase => { uid => 1, id_base => 1, id_domain => 1 }
    ,set_time => { uid => 1, id_domain => 1 }
    ,rsync_back => { uid => 1, id_domain => 1, id_node => 1 }
    # ports
    ,expose => { uid => 1, id_domain => 1, port => 1, name => 2, restricted => 2, id_port => 2}
    ,remove_expose => { uid => 1, id_domain => 1, port => 1}
    ,open_exposed_ports => {uid => 1, id_domain => 1, remote_ip => 2 }
    ,close_exposed_ports => { uid => 1, id_domain => 1, port => 2, clean => 2 }
    # Virtual Managers or Nodes
    ,refresh_vms => { _force => 2, timeout_shutdown => 2, uid => 2 }

    ,shutdown_node => { id_node => 1, at => 2 }
    ,start_node => { id_node => 1, at => 2 }
    ,connect_node => { backend => 2, hostname => 2, id_node =>2, timeout => 2 }
    ,migrate => { uid => 1, id_node => 1, id_domain => 1, start => 2, remote_ip => 2
        ,shutdown => 2, shutdown_timeout => 2
    }
    ,compact => { uid => 1, id_domain => 1 , keep_backup => 2 }
      ,purge => { uid => 1, id_domain => 1 }
      ,backup => { uid => 1, id_domain => 1, compress => 2}
      ,restore_backup => { uid => 1, file => 1, id_domain => 2 }

    ,list_machine_types => { uid => 1, id_vm => 2, vm_type => 2}
    ,list_cpu_models => { uid => 1, id_domain => 1}

    #users
    ,post_login => { user => 1, locale => 2 }

    #networks
    ,list_network_interfaces => { uid => 1, vm_type => 1, type => 2 }

    #isos
    ,list_isos => { id_vm => 1 }

    ,manage_pools => { uid => 2, id_domain => 2 }
    ,ping_backend => {}

    ,list_host_devices => {
        uid => 1
        ,id_host_device => 2
        ,id_node => 2
        ,_force => 2
    }
    ,remove_host_device => {
        uid => 1
        ,id_host_device => 1
        ,id_domain => 2
    }

    ,discover => { uid => 1, id_vm => 1 }
    ,import_domain => { uid => 1, vm => 1, id_owner => 1, name => 1
        ,spinoff_disks => 2
    }
    ,update_iso_urls => { uid => 1 }
    ,list_unused_volumes => {uid => 1, id_vm => 1, start => 2, limit => 2 }
    ,remove_files => { uid => 1, id_vm => 1, files => 1 }
    ,move_volume => { uid => 1, id_domain => 1, volume => 1, storage => 1 }
    
    ,list_networks => { uid => 1, id_vm => 1}
    ,new_network => { uid => 1, id_vm => 1, name => 2 }
    ,create_network => { uid => 1, id_vm => 1, data => 1 }
    ,remove_network => { uid => 1, id => 1, id_vm => 2, name => 2 }
    ,change_network => { uid => 1, data => 1 }

    ,remove_clones => { uid => 1, id_domain => 1 }
);

$VALID_ARG{shutdown} = $VALID_ARG{shutdown_domain};

our %CMD_SEND_MESSAGE = map { $_ => 1 }
    qw( create start shutdown force_shutdown reboot prepare_base remove remove_base rename_domain screenshot download
            clone
            set_base_vm remove_base_vm
            domain_autostart hibernate hybernate
            change_owner
            add_hardware remove_hardware set_driver change_hardware
            expose remove_expose
            rebase rebase_volumes
            shutdown_node reboot_node start_node
            compact purge backup
            start_domain

            create_network change_network remove_network
    );

our %CMD_NO_DUPLICATE = map { $_ => 1 }
qw(
    clone
    set_base_vm
    remove_base_vm
    rsync_back
    cleanup
    list_host_devices
    list_storage_pools
    refresh_machine
    refresh_machine_ports
    refresh_vms
    refresh_storage
    set_time
    open_exposed_ports
    manage_pools
    screenshot
    prepare_base
    download
);

our $TIMEOUT_SHUTDOWN = 120;
our $TIMEOUT_REBOOT = 20;

our $CONNECTOR;

our %COMMAND = (
    long => {
        limit => 4
        ,priority => 10
    } #default

    # list from low to high priority
    ,disk_low_priority => {
        limit => 2
        ,commands => ['rsync_back','check_storage', 'refresh_vms','move_volume']
        ,priority => 30
    }
    ,disk => {
        limit => 2
        ,commands => ['prepare_base','remove_base','set_base_vm','rebase_volumes'
                    , 'remove_base_vm'
                    , 'screenshot'
                    , 'cleanup'
                    , 'compact','spinoff','backup'
                ]
        ,priority => 20
    }
    ,huge => {
        limit => 1
        ,commands => ['download','manage_pools']
        ,priority => 15
    }

    ,secondary => {
        limit => 50
        ,priority => 4
        ,commands => ['shutdown','shutdown_now', 'enforce_limits', 'set_time'
            ,'remove_domain', 'remove', 'refresh_machine_ports'
            ,'connect_node','start_node','shutdown_node'
            ,'post_login'
        ]
    }

    ,important=> {
        limit => 20
        ,priority => 1
        ,commands => ['clone','start','start_clones','shutdown_clones','create','open_iptables','list_network_interfaces','list_isos','ping_backend','refresh_machine']
    }

    ,iptables => {
        limit => 4
        ,priority => 2
        ,commands => ['open_exposed_ports']
    }
);
lock_hash %COMMAND;

our %CMD_VALIDATE = (
    clone => \&_validate_clone
    ,create => \&_validate_create_domain
    ,create_domain => \&_validate_create_domain
    ,remove_hardware => \&_validate_remove_hardware
    ,start_domain => \&_validate_start_domain
    ,start => \&_validate_start_domain
    ,add_hardware=> \&_validate_change_hardware
    ,change_hardware=> \&_validate_change_hardware
    ,remove_hardware=> \&_validate_change_hardware
    ,move_volume => \&_validate_change_hardware
    ,compact => \&_validate_compact
    ,spinoff => \&_validate_compact
    ,prepare_base => \&_validate_prepare_base
    ,remove_base => \&_validate_remove_base
);

sub _init_connector {
    $CONNECTOR = \$Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR   if !$$CONNECTOR;

}

=head2 BUILD

    Internal object builder, do not call

=cut

sub BUILD {
    _init_connector();
}

sub _request {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $self = {};
    bless ($self, $class);
    return $self;
}

=head2 open

Opens the information of a previous request by id

  my $req = Ravada::Request->open($id);

=cut

sub open {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $id = shift or confess "Missing request id";

    _init_connector()   if !$CONNECTOR || !$$CONNECTOR;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM requests "
        ." WHERE id=?");
    $sth->execute($id);
    my $row = $sth->fetchrow_hashref;

    confess "I can't find id=$id " if !defined $row;
    $sth->finish;

    my $args = {};
    $args = decode_json($row->{args}) if $row->{args};

    $row->{args} = $args;

    bless ($row, $class);
    $row->{priority} = $row->_set_priority();

    return $row;
}

=head2 info

Returns information of the request

=cut

sub info {
    my $self = shift;
    my $user = shift;
    confess "USER ".$user->name." not authorized"
        unless $user->is_admin
            || ($self->defined_arg('uid') && $user->id == $self->args('uid'))
            || ($self->defined_arg('id_owner') && $user->id == $self->args('id_owner'));

    return {
        id => $self->id
        ,status => $self->status
        ,error => $self->error
        ,id_domain => $self->id_domain
        ,output => $self->output
        ,date_changed => $self->date_changed
    }
}

=head2 create_domain

    my $req = Ravada::Request->create_domain(
                        name => 'bla'
                    , id_iso => 1
    );


=cut

sub create_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my %args = @_;

    my $args = _check_args('create_domain', @_ );

    confess "ERROR: Argument vm or id_vm required without id_base"
        if !exists $args->{vm} && !exists $args->{id_base} && !exists $args->{id_vm};

    my $self = {};
    if ($args->{network}) {
        $args->{network} = JSON::XS->new->convert_blessed->encode($args->{network});
    }

    bless($self,$class);
    return $self->_new_request(command => 'create' , args => encode_json($args));
}

=head2 remove_domain

    my $req = Ravada::Request->remove_domain(
                     name => 'bla'
                    , uid => $user->id
    );


=cut


sub remove_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my %args = @_;
    confess "Missing domain name"   if !$args{name};
    confess "Name is not scalar"    if ref($args{name});
    confess "Missing uid"           if !$args{uid};

    for (keys %args) {
        confess "Invalid argument $_" if !$VALID_ARG{'remove_domain'}->{$_};
    }

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'remove' , args => \%args);

}

=head2 start_domain

Requests to start a domain

  my $req = Ravada::Request->start_domain(
     name => 'name'
    , uid => $user->id
  );

Mandatory arguments: one of those must be passed:

=over

=item * name or id_domain

=item * uid: user id

=item * remote_ip: [optional] IP of the remote client that requested to start the domain

=back

=cut

sub start_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('start_domain', @_);

    confess "ERROR: choose either id_domain or name "
        if $args->{id_domain} && $args->{name};

    confess "Error: remote ip invalid '$args->{remote_ip}'"
    if $args->{remote_ip} && $args->{remote_ip} !~ /^(localhost|\d+\.\d+\.\d+\.\d+)$/;

    _remove_low_priority_requests($args->{id_domain} or $args->{name});

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'start' , args => $args);
}

sub _remove_low_priority_requests($id_domain) {

    _init_connector()   if !$CONNECTOR || !$$CONNECTOR;

    if ($id_domain !~ /^\d+$/) {
        $id_domain = _search_domain_id(undef,$id_domain);
    }
    for my $command (sort @{$COMMAND{disk_low_priority}->{commands}}) {
        my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM requests "
            ." WHERE command=? AND id_domain=? "
            ."    AND status <> 'done' "
        );
        $sth->execute($command, $id_domain);
        while ( my ($id_request) = $sth->fetchrow ) {
            my $req = Ravada::Request->open($id_request);
            $req->stop();
            warn "Stopping request $id_request";
        }
    }

}


=head2 start_clones

Requests to start the clones of a base

  my $req = Ravada::Request->start_clones( name => 'name', uid => $user->id );

=cut

sub start_clones {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('start_clones', @_);

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'start_clones' , args => $args);
}

=head2 pause_domain

Requests to pause a domain

  my $req = Ravada::Request->pause_domain( name => 'name', uid => $user->id );

=cut

sub pause_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('pause_domain', @_);

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'pause' , args => $args);
}

=head2 resume_domain

Requests to pause a domain

  my $req = Ravada::Request->resume_domain( name => 'name', uid => $user->id );

=cut

sub resume_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('resume_domain', @_);

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'resume' , args => $args);
}



sub _check_args {
    my $sub = shift;
    confess "Odd number of elements ".Dumper(\@_)   if scalar(@_) % 2;
    my $args = { @_ };

    my $valid_args = $VALID_ARG{$sub};
    for (qw(at after_request after_request_ok retry _no_duplicate _force uid)) {
        $valid_args->{$_}=2 if !exists $valid_args->{$_};
    }

    confess "Unknown method $sub" if !$valid_args;
    for (keys %{$args}) {
        confess "Invalid argument $_ , valid args ".Dumper($valid_args)
            if !$valid_args->{$_};
    }

    for (keys %{$VALID_ARG{$sub}}) {
        next if $VALID_ARG{$sub}->{$_} == 2; # optional arg
        confess "Missing argument $_"   if !exists $args->{$_} || !defined $args->{$_};
    }

    return $args;
}

=head2 force_shutdown_domain

Requests to stop a domain now !

  my $req = Ravada::Request->force_shutdown_domain( name => 'name' , uid => $user->id );

=cut

sub force_shutdown_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('force_shutdown_domain', @_ );

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'force_shutdown' , args => $args);
}

=head2 shutdown_domain

Requests to stop a domain

  my $req = Ravada::Request->shutdown_domain( name => 'name' , uid => $user->id );
  my $req = Ravada::Request->shutdown_domain( name => 'name' , uid => $user->id
                                            ,timeout => $timeout );

=cut

sub shutdown_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('shutdown_domain', @_ );

    confess "ERROR: You must supply either id_domain or name ".Dumper($args)
        if !$args->{id_domain} && !$args->{name};

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'shutdown' , args => $args);
}

=head2 force_reboot_domain

Requests to stop a domain now !

  my $req = Ravada::Request->force_reboot_domain( name => 'name' , uid => $user->id );

=cut

sub force_reboot_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('force_reboot_domain', @_ );

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'force_reboot' , args => $args);
}

=head2 reboot_domain

Requests to reboot a domain

  my $req = Ravada::Request->reboot_domain( name => 'name' , uid => $user->id );
  my $req = Ravada::Request->reboot_domain( name => 'name' , uid => $user->id
                                            ,timeout => $timeout );

=cut

sub reboot_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('reboot_domain', @_ );

    $args->{timeout} = $TIMEOUT_REBOOT if !exists $args->{timeout};

    confess "ERROR: You must supply either id_domain or name ".Dumper($args)
        if !$args->{id_domain} && !$args->{name};

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'reboot' , args => $args);
}

=head2 new_request

Creates a new request

    $req = Ravada::Request->new_request(
        start_domain
        ,uid => $user->id
        ,id_domain => $domain->id
    );

=cut

sub new_request($self, $command, @args) {
    die "Error: Unknown request '$command'" if !$VALID_ARG{$command};
    return _new_request(
        $self
        ,command => $command
           ,args => _check_args($command, @args)
    );
}

sub _duplicated_request($self=undef, $command=undef, $args=undef) {
    _init_connector()   if !$CONNECTOR || !$$CONNECTOR;

    my $args_d;
    if ($self) {
        confess "Error: do not supply args if you supply request" if $args;
        confess "Error: do not supply command if you supply request" if $command;
        $args_d = $self->args;
        $command = $self->command;
    } else {
        $args_d = decode_json($args);
    }
    confess "Error: missing command " if !$command;
    #    delete $args_d->{uid} unless $command eq 'clone';
    delete $args_d->{uid} if $command =~ /(cleanup|refresh_vms|set_base_vm)/;
    delete $args_d->{uid} if exists $args_d->{uid} && !defined $args_d->{uid};
    delete $args_d->{at};
    delete $args_d->{status};
    delete $args_d->{timeout};

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id,args FROM requests WHERE (status <> 'done')"
        ." AND command=?"
        ." AND ( error = '' OR error is NULL OR error like '% waiting for process%')"
    );
    $sth->execute($command);
    while (my ($id,$args_found) = $sth->fetchrow) {
        next if $self && $self->id && $self->id == $id;

        my $args_found_d = decode_json($args_found);
        delete $args_found_d->{uid};
        delete $args_found_d->{at};
        delete $args_found_d->{status};
        delete $args_found_d->{timeout};

        next if join(".",sort keys %$args_d) ne join(".",sort keys %$args_found_d);
        my $args_d_s = join(".",map { $args_d->{$_} } sort keys %$args_d);
        my $args_found_s = join(".",map {$args_found_d->{$_} } sort keys %$args_found_d);

        next if $args_d_s ne $args_found_s;

        return $id;
    }
    return 0;
}

sub _new_request {
    my $self = shift;
    if ( !ref($self) ) {
        my $proto = $self ;
        my $class = ref($proto) || $proto;
        $self = {};
        bless ($self, $class);
    }
    my %args = @_;

    $args{status} = 'requested';
    $self->{command} = $args{command};

    if ($args{name}) {
        $args{domain_name} = $args{name};
        delete $args{name};
    }
    my $no_duplicate = delete $args{_no_duplicate};
    my $force;

    my $uid;
    if ( ref $args{args} ) {
        $force = delete $args{args}->{_force};
        $args{args}->{uid} = $args{args}->{id_owner}
            if !exists $args{args}->{uid};
        $uid = $args{args}->{uid} if exists $args{args}->{uid};

        $args{at_time} = $args{args}->{at} if exists $args{args}->{at};
        my $id_domain_args = $args{args}->{id_domain};

        if ($id_domain_args) {
            confess "ERROR: Different id_domain: ".Dumper(\%args)
                if $args{id_domain} && $args{id_domain} ne $id_domain_args;
            $args{id_domain} = $id_domain_args;
        }
        for (qw(after_request after_request_ok retry)) {
            $args{$_} = delete $args{args}->{$_}
            if exists $args{args}->{$_};
        }

        $args{args} = encode_json($args{args});
    }
    $self->{args} = decode_json($args{args});
    _init_connector()   if !$CONNECTOR || !$$CONNECTOR;
    if (!$force
        && ( $CMD_NO_DUPLICATE{$args{command}} || $no_duplicate)
        ){
        my $id_dupe = $self->_duplicated_request();

        my $req_recent;
        $req_recent = $self->done_recently()
        if $args{command} !~ /^(clone|migrate|set_base_vm)$/;

        my $id_recent;
        $id_recent = $req_recent->id if $req_recent;

        my $id = ( $id_dupe or $id_recent );
        if ($id ) {
            unless ($args{command} eq 'prepare_base' && done_recently(undef,60,'remove_base')) {
                my $req = Ravada::Request->open($id);
                $req->{_duplicated} = 1;
                return $req;
            }
        }

    }

    $args{date_changed} = Ravada::Utils::date_now();
    $args{error} = '';
    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO requests (".join(",",sort keys %args).")"
        ."  VALUES ( "
                .join(",", map { '?' } keys %args)
                ." )"
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    $sth->finish;

    $self->{id} = $self->_last_insert_id();

    $sth = $$CONNECTOR->dbh->prepare(
    "UPDATE requests set date_req=date_changed"
    ." WHERE id=?");
    $sth->execute($self->{id});

    my $request;
    eval { $request = $self->open($self->{id}) };
    warn $@ if $@ && $@ !~ /I can't find id=/;
    return if !$request;
    $request->_validate();
    $request->status('requested') if $request->status ne'done';

    $self->lock_domain() if ! $args{at};

    return $request;
}

sub id_domain($self, $value=undef) {

    return $self->_data('id_domain' => $value) if defined $value;

    my $id_domain = $self->{_data}->{id_domain};
    return $id_domain if defined $id_domain;
    $id_domain = $self->defined_arg('id_domain');
    $self->{_data}->{id_domain} = $id_domain;
    return $id_domain;
}

=head2 lock_domain

  Checks if that request belongs to a virtual machine and sets it as locked

=cut

sub lock_domain($self) {
    my $id_domain = $self->id_domain;
    if (!defined $id_domain) {
        $id_domain = $self->defined_arg('id_domain');
    }
    return if !defined $id_domain;

    my $sth = $self->_dbh->prepare(
        "UPDATE domains set is_locked=? "
        ." WHERE id=?"
    );
    $sth->execute($self->id, $id_domain);
}

=head2 unlock_domain

  Checks if that request belongs to a virtual machine and unlocks it

=cut

sub unlock_domain($self) {
    my $id_domain = $self->id_domain;
    if (!defined $id_domain) {
        $id_domain = $self->defined_arg('id_domain');
    }
    return if !defined $id_domain;

    my $sth = $self->_dbh->prepare(
        "UPDATE domains set is_locked=0 "
        ." WHERE id=?"
        ."   AND is_locked<>0"
    );
    $sth->execute($id_domain);

}

sub _validate($self) {
    return if !exists $CMD_VALIDATE{$self->command};
    my $method = $CMD_VALIDATE{$self->command};
    return if !$method;
    $method->($self);
}

sub _validate_remove_base($self) {
    my $id_domain = $self->args('id_domain');
    my $domain = Ravada::Front::Domain->open($id_domain);
    my @reqs_base = grep { $_->command eq 'prepare_base' || $_->command eq 'remove_base'}
        $domain->list_requests;

    my $n = scalar(@reqs_base);

    if ($n >= 2
            && $reqs_base[$n-2]->command eq 'prepare_base'
            && $reqs_base[$n-2]->status eq 'requested'
            && $reqs_base[$n-1]->command eq 'remove_base'
            && $reqs_base[$n-1]->status eq 'requested'
        ) {
        $reqs_base[-1]->status('done');
        $reqs_base[-2]->status('done');
    }
}

sub _validate_remove_hardware($self) {
    my $name = $self->args('name');

    my $args = $self->args();

    die "Error: you must pass option or index"
    if !exists $args->{option} && !exists $args->{index}
    && !defined $args->{option} && !defined $args->{index};

    die "Error: attribute value must be defined ".
        join(" ", map { $_ or '<UNDEF>' } %{$args->{option}})
    if $args->{option} && grep { !defined } values %{$args->{option}};

}

sub _validate_start_domain($self) {

    my $id_domain = $self->defined_arg('id_domain');
    if (!$id_domain) {
        my $domain_name = $self->defined_arg('name');
        $id_domain = _search_domain_id(undef,$domain_name);
    }
    return if !$id_domain;
    for my $command ('start','%_hardware') {
        my $req=$self->_search_request($command, id_domain => $id_domain);
        next if !$req;
        next if $req->at_time;
        next if $command eq 'start' && !$req->after_request();
        $self->after_request($req->id) if $req && $req->id < $self->id;
    }
}

sub _validate_prepare_base($self) {
    $self->_validate_compact();

    my $req_create = $self->_search_request('create'
        , id_base=> $self->args('id_domain'));

    if ($req_create) {
        $req_create->after_request($self->id);
    }
}

sub _validate_compact($self) {
    return if $self->after_request();

    my $id_domain = $self->defined_arg('id_domain');

    my $req_compact = $self->_search_request('compact', id_domain => $id_domain);
    my $req_spinoff = $self->_search_request('spinoff', id_domain => $id_domain);

    return if !$req_compact && !$req_spinoff;

    my $id;
    $id = $req_compact->id if $req_compact;

    if ( !$id || ( $req_spinoff && $req_spinoff->id > $id) ) {
        $id = $req_spinoff->id;
    }
    $req_compact->at(0) if $req_compact;
    $req_spinoff->at(0) if $req_spinoff;

    $self->after_request($id) if $id;

}

sub _validate_change_hardware($self) {

    return if $self->after_request();

    my $id_domain = $self->defined_arg('id_domain');
    if (!$id_domain) {
        my $domain_name = $self->defined_arg('name');
        $id_domain = _search_domain_id(undef,$domain_name);
    }
    return if !$id_domain;
    my $req = $self->_search_request('%_hardware', id_domain => $id_domain);
    my $req_move = $self->_search_request('move_volume', id_domain => $id_domain);

    return if !$req && ! $req_move;

    my $id;
    $id = $req->id if $req;

    if ( !$id || ( $req_move && $req_move->id > $id) ) {
        $id = $req_move->id;
    }

    $self->after_request($id);
}

sub _validate_create_domain($self) {

    my $base;
    my $id_base = $self->defined_arg('id_base');

    my $id_owner = $self->defined_arg('id_owner') or confess "ERROR: Missing id_owner";
    my $owner = Ravada::Auth::SQL->search_by_id($id_owner) or confess "Unknown user id: $id_owner";

    $self->_validate_clone($id_base, $id_owner) if $id_base;

    unless ( $owner->is_admin
            || $owner->can_create_machine()
            || ($id_base && $owner->can_clone)) {

        return $self->_status_error("done","Error: access denied to user ".$owner->name);
    }

    $self->_check_downloading();
}

sub _check_downloading($self) {
    my $id_iso = $self->defined_arg('id_iso');

    return if !$id_iso;

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id,downloading,has_cd,name,url "
        ." FROM iso_images "
        ." WHERE id=? "
    );
    $sth->execute($id_iso);
    my ($id_iso2,$downloading, $has_cd, $iso_name, $iso_url)
        = $sth->fetchrow;

    return if !$downloading;

    my $req_download = $self->_search_request('download', id_iso => $id_iso2);

    if ($has_cd && !$req_download) {
        $req_download = Ravada::Request->download(
            id_iso => $id_iso2
            ,uid => Ravada::Utils::user_daemon->id
            ,vm => $self->defined_arg('vm')
        );
    }
    if (! $req_download) {
        _mark_iso_downloaded($id_iso2);
    } else {
        $self->after_request($req_download->id);
    }
    $sth = $$CONNECTOR->dbh->prepare("SELECT args FROM requests"
            ." WHERE id=?"
    );
    $sth->execute($self->id);
    my $args_json = $sth->fetchrow();
    my $args = decode_json($args_json);

    if (exists $args->{iso_file} && !$args->{iso_file}) {
        delete $args->{iso_file};
        $sth = $$CONNECTOR->dbh->prepare("UPDATE requests set args=?"
            ." WHERE id=?"
        );
        $sth->execute(encode_json($args), $self->id);
    }

}

sub _mark_iso_downloaded($id_iso) {
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE iso_images "
        ." set downloading=0 "
        ." WHERE id=?"
    );
    $sth->execute($id_iso);
}

sub _search_request($self,$command,%fields) {
    my $query =
        "SELECT id, args FROM requests WHERE command like ?"
        ." AND status <> 'done' ";
    $query .= "AND id <> ".$self->id if $self;
    $query .= " ORDER BY date_req,id DESC ";
    my $sth= $$CONNECTOR->dbh->prepare($query);
    $sth->execute($command);

    my @reqs;
    while ( my ($id, $args_json) = $sth->fetchrow ) {
        return Ravada::Request->open($id) if !keys %fields;

        my $args = decode_json($args_json);
        my $found=1;
        for my $key (keys %fields) {
            if (!exists $args->{$key} || !defined $args->{$key}
                || $args->{$key} ne $fields{$key} ) {
                $found = 0;
                last;
            }
        }
        next if !$found;
        my $req = Ravada::Request->open($id);
        return $req if !wantarray;
        push @reqs,($req);
    }
    return @reqs;
}

sub _validate_clone($self
                , $id_base= $self->args('id_domain')
                , $uid=$self->args('uid')) {

    my $base = Ravada::Front::Domain->open($id_base);

    if ( !$uid ) {
        $self->status('done');
        $self->error("Error: missing uid");
        return;
    }
    my $user = Ravada::Auth::SQL->search_by_id($uid);
    if ( !$user ) {
        $self->status('done');
        $self->error("Error: user id='$uid' does not exist");
        return;
    }

    my ($req_base) = grep { $_->command eq 'prepare_base' }
        $base->list_requests;

    $self->after_request($req_base->id) if $req_base;

    return if $user->is_admin;
    return if $user->can_clone_all;
    return $self->_status_error('done'
        ,"Error: user ".$user->name." can not clone.")
        if !$user->can_clone();

    return $self->_status_error('done'
        ,"Error: ".$base->name." is not public.")
        if !$base->is_public;
}

sub _last_insert_id {
    _init_connector();
    return Ravada::Utils::last_insert_id($$CONNECTOR->dbh);
}

=head2 status

Returns or sets the status of a request

  $req->status('done');

  my $status = $req->status();

=cut

sub status {
    my $self = shift;
    my $status = shift;
    my $message = shift;

    if (!defined $status) {
        my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM requests "
            ." WHERE id=?");
        $sth->execute($self->{id});
        my $row = $sth->fetchrow_hashref;
        $sth->finish;

        return ($row->{status} or 'unknown');
    }

    my $date_changed = $self->date_changed;
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE requests set status=? "
                ." WHERE id=?");
    for ( 1 .. 10 ) {
        eval {

            $status = substr($status,0,64);

            $sth->execute($status, $self->{id});
            $sth->finish;
        };
        last if !$@;
        die $@ if $@ !~ /Deadlock found/;
        warn "Warning: retrying '$@'";
    }

    $self->_send_message($status, $message)
        if $CMD_SEND_MESSAGE{$self->command} || $self->error ;

    if ($status eq 'done' && $date_changed && $date_changed eq $self->date_changed) {
        sleep 1;
        for ( 1 .. 10 ) {
            eval {
                my $sth2=$$CONNECTOR->dbh->prepare(
                    "UPDATE requests set date_changed=?"
                    ." WHERE id=?"
                );
                $sth2->execute(Ravada::Utils::date_now, $self->{id});
            };
            if ($@) {
                warn "Warning: $@";
                sleep 1;
            } else {
                last;
            }
        }
    }
    return $status;
}

sub _status_error($self, $status, $error) {
    $self->status($status);
    return $self->error($error);
}

=head2 at

Sets the time when the request will be scheduled

=cut

sub at($self, $value) {
    my $sth = $$CONNECTOR->dbh->prepare("UPDATE requests set at_time=? "
            ." WHERE id=?");
    $sth->execute($value, $self->{id});
}

sub _search_domain_name {
    my $self = shift;
    my $domain_id = shift;

    _init_connector();

    my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM domains where id=?");
    $sth->execute($domain_id);
    return $sth->fetchrow;
}

sub _dbh($self=undef) {

    _init_connector();
    return $$CONNECTOR->dbh;

}

sub _search_domain_id($self,$domain_name) {

    my $sth = _dbh($self)->prepare("SELECT id FROM domains where name=?");
    $sth->execute($domain_name);
    return $sth->fetchrow;
}


sub _send_message {
    my $self = shift;
    my $status = shift;
    my $message = ( shift or $self->error );

    my $uid;

    $uid = $self->args('id_owner') if $self->defined_arg('id_owner');
    $uid = $self->args('uid')      if !$uid && $self->defined_arg('uid');

    if (!$uid) {
        my $user = $self->defined_arg('user');
        if ( $user ) {
            my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM users where name=?");
            $sth->execute($user);
            ($uid) = $sth->fetchrow;
        }
    }

    return if !$uid || $uid == Ravada::Utils::user_daemon->id;

    my $domain_name = $self->defined_arg('name');
    if (!$domain_name) {
        my $domain_id = $self->defined_arg('id_domain');
        $domain_name = $self->_search_domain_name($domain_id)   if $domain_id;
        $domain_name = '' if !defined $domain_name;
    }
    $domain_name = "$domain_name "  if length $domain_name;

    $self->_remove_unnecessary_messages() if $self->status eq 'done';

    my $subject = $self->command." $domain_name ".$self->status;
    $subject = $message if $message && $self->status eq 'done'
            && length ($message)<60;

    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO messages ( id_user, id_request, subject, message, date_shown ) "
        ." VALUES ( ?,?,?,?, NULL)"
    );
    $subject = substr($subject,0,60) if length($subject)>60;
    $sth->execute($uid, $self->id,$subject, $message);
    $sth->finish;
}

sub _remove_unnecessary_messages {
    my $self = shift;

    my $uid;
    $uid = $self->defined_arg('id_owner');
    $uid = $self->defined_arg('uid')        if !$uid;
    return if !$uid;


    my $sth = $$CONNECTOR->dbh->prepare(
        "DELETE FROM messages WHERE id_user=? AND id_request=? "
        ." AND (message='' OR message IS NULL)"
    );

    $sth->execute($uid, $self->id);
    $sth->finish;

}

sub _remove_messages {
    my $self = shift;

    my $uid;
    $uid = $self->defined_arg('id_owner');
    $uid = $self->defined_arg('uid')        if !$uid;
    return if !$uid;


    my $sth = $$CONNECTOR->dbh->prepare(
        "DELETE FROM messages WHERE id_user=? AND id_request=? "
    );

    $sth->execute($uid, $self->id);
    $sth->finish;

}



=head2 result

  Returns the result of the request if any

  my $result = $req->result;

=cut

sub result {
    my $self = shift;

    my $value = shift;

    if (defined $value ) {
        my $sth = $$CONNECTOR->dbh->prepare("UPDATE requests set result=? "
            ." WHERE id=?");
        $sth->execute(encode_json($value), $self->{id});
        $sth->finish;

    } else {
        my $sth = $$CONNECTOR->dbh->prepare("SELECT result FROM requests where id=? ");
        $sth->execute($self->{id});
        ($value) = $sth->fetchrow;
        $value = decode_json($value)    if defined $value;
        $sth->finish;

    }

    return $value;
}

=head2 command

Returns the requested command

=cut

sub command {
    my $self = shift;
    return $self->{command};
}

=head2 args

Returns the requested command

  my $command = $req->command;

=cut


=head2 args

Returns the arguments of a request or the value of one argument field

  my $args = $request->args();
  print $args->{name};

  print $request->args('name');

=cut


sub args {
    my $self = shift;
    my $name = shift;

    if ( !$name ) {
        my $args = $self->{args};
        $args = dclone($self->{args}) if ref($args);
        return $args;
    }

    confess "Unknown argument $name ".Dumper($self->{args})
        if !exists $self->{args}->{$name};

    my $ret = $self->{args}->{$name};
    if (ref($ret)) {
        return dclone($ret);
    }
    return $ret;
}

=head2 arg

Sets or gets de value of an argument of a Request

=cut

sub arg($self, $name, $value=undef) {

    confess "Unknown argument $name ".Dumper($self->{args})
        if !exists $self->{args}->{$name} && !defined $value;

    if (defined $value) {
        $self->{args}->{$name} = $value;

        my $sth = $$CONNECTOR->dbh->prepare("SELECT args FROM requests"
            ." WHERE id=?"
        );
        $sth->execute($self->id);
        my $args_json = $sth->fetchrow();
        my $args = decode_json($args_json);
        $args->{$name} = $value;
        $sth = $$CONNECTOR->dbh->prepare("UPDATE requests set args=?"
            ." WHERE id=?"
        );
        $sth->execute(encode_json($args),$self->id);
    }
    return $self->{args}->{$name};
}


=head2 defined_arg

Returns if an argument is defined

=cut

sub defined_arg {
    my $self = shift;
    my $name = shift;
    confess "ERROR: missing arg name" if !defined $name;

    my $ret = $self->{args}->{$name};
    $ret = dclone($ret) if ref($ret);
    return $ret;
}

=head2 copy_screenshot

Request to copy a screenshot from a domain to another

=cut

sub copy_screenshot {
  my $proto = shift;
  my $class=ref($proto) || $proto;

  my $args = _check_args('copy_screenshot', @_ );

  my $self = {};
  bless($self,$class);

  return $self->_new_request(
       command => 'copy_screenshot'
      ,id_domain => $args->{id_domain}
      ,args => $args
      );

}

=head2 set_base_vm

Enables a base in a Virtual Manager

=cut

sub set_base_vm {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('set_base_vm', @_ );
    $args->{value} = 1 if !exists $args->{value};

    my $self = {};
    bless ($self, $class);

    my $req = $self->_new_request(
            command => 'set_base_vm'
             , args => $args
    );

    my $id_domain = $args->{id_domain};
    my $domain = Ravada::Front::Domain->open($id_domain);
    my $id_vm = $args->{id_vm};
    $id_vm = $args->{id_node} if exists $args->{id_node} && $args->{id_node};

    $domain->_set_base_vm_db($id_vm, $args->{value}, $req->id);

    return $req;
}

=head2 remove_base_vm

Disables a base in a Virtual Manager

=cut

sub remove_base_vm {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('set_base_vm', @_ );
    $args->{value} = 0;

    my $self = {};
    bless($self,$class);

    return $self->_new_request(
            command => 'remove_base_vm'
             , args => $args
    );

}


=head2 type

Returns the type of the request

=cut

sub type($self) {
    my $command = $self;
    $command = $self->command if ref($self);
    for my $type ( keys %COMMAND ) {
        return $type if grep /^$command$/, @{$COMMAND{$type}->{commands}};
    }
    return 'long';
}

sub _set_priority ($self) {
    my $command = $self;
    $command = $self->command if ref($self);
    for my $type ( keys %COMMAND ) {
        next if  !grep /^$command$/, @{$COMMAND{$type}->{commands}};
        return $COMMAND{$type}->{priority} if exists $COMMAND{$type}->{priority};
        return 10;
    }
}


=head2 count_requests

Returns the number of working requests of the same type

    my $n = $request->working_requests();

=cut

sub count_requests($self) {
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT command FROM requests"
        ." WHERE status = 'working' "
    );
    $sth->execute();
    my $n = 0;
    while ( my $command = $sth->fetchrow ) {
        $n++ if type($command) eq $self->type;
    }
    return $n;
}

=head2 requests_limit

    Returns the limit of requests of a type.

=cut

sub requests_limit($self, $type = $self->type) {
    confess "Error: no requests of type $type" if !exists $COMMAND{$type};

    my $limit = $COMMAND{$type}->{limit};

    return $limit;
}

=head2 domain_autostart

Sets the autostart flag on a domain

=cut

sub domain_autostart {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('domain_autostart', @_ );
    $args->{value} = 1 if !exists $args->{value};

    my $self = {};
    bless($self, $class);

    return _new_request($self
        , command => 'domain_autostart'
        , args => $args
    );
}

=head2 autostart_domain

Deprecated for domain_autostart

=cut

sub autostart_domain {
    return domain_autostart(@_);
}

=head2 enforce_limits

Enforces virtual machine limits, ie: an user can only run one virtual machine
at a time, so the older ones are shut down.


    my $req = Ravada::Request->enforce_limits(
        timeout => $timeout
    );

Arguments:

=over

=item * timeout: seconds that are given to a virtual machine to shutdown itself.
After this time, it gets powered off. Defaults to 120 seconds.

=back

It is advisable configure virtual machines so they shut down easily if asked to.
Just a few hints:

=over

=item * install ACPI services

=item * Set default action for power off to shutdown, do not ask the user

=cut


sub enforce_limits {
    my $proto = shift;

    my $class = ref($proto) || $proto;

    my $args = _check_args('enforce_limits', @_ );

    return if !$args->{_force} && _requested('enforce_limits');
    $args->{timeout} = $TIMEOUT_SHUTDOWN if !exists $args->{timeout};

    my $self = {};
    bless($self, $class);

    my $req = _new_request($self
        , command => 'enforce_limits'
        , args => $args
    );

    if (!$args->{at} && !$args->{_force} && (my $id_request = $req->done_recently(30))) {
        $req->status("done",$req->command." run recently by id_request: $id_request");
    }
    return $req;
}

=head2 refresh_machine

Refresh a machine information

=cut

sub refresh_machine {
    my $proto = shift;

    my $class = ref($proto) || $proto;

    my $args = _check_args('refresh_machine', @_ );

    my $self = {};
    bless($self, $class);

    my $id_domain = $args->{id_domain};
    my $id_requested = _requested('refresh_machine',id_domain => $id_domain);
    return Ravada::Request->open($id_requested) if $id_requested;

    return if $self->done_recently();

    my $req = _new_request($self
        , command => 'refresh_machine'
        , args => $args
    );

    return $req;

}

sub _new_request_generic {
    my $command = shift;

    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args($command, @_ );

    my $self = {};
    bless($self, $class);


    my $req = _new_request($self
        ,command => $command
        ,args => $args
    );
    return $req;
}

=head2 done_recently

Returns wether this command has been requested successfully recently.

  if ($request->done_recently($seconds)) {
    ... skips work ...
  } else {
    ... does work ...
  }

This method is used for commands that take long to run as garbage collection.

=cut

sub done_recently($self, $seconds=60,$command=undef, $args=undef) {
    _init_connector();
    my $id_req = 0;
    my $args_d= {};
    if ($self) {
        $id_req = ( $self->id or 0 );
        confess "Error: do not supply args if you supply request" if $args;
        confess "Error: do not supply command if you supply request" if $command;
        $args_d = $self->args;
        $command = $self->command;
    } else {
        $args_d = decode_json($args) if $args;
    }
    delete $args_d->{uid};
    delete $args_d->{at};

    my $query = "SELECT id,args FROM requests"
        ." WHERE date_changed >= ? "
        ."        AND command = ? "
        ."         AND ( status = 'done' OR status ='working' OR status = 'requested') "
        ."         AND ( error IS NULL OR error = '' ) "
        ."         AND id <> ? ";

    my $sth = $$CONNECTOR->dbh->prepare( $query );
    my $date= Time::Piece->localtime(time - $seconds);
    my $date_before = $date->ymd." ".$date->hms;
    $sth->execute($date_before, $command, $id_req);
    while (my ($id,$args_found, $date) = $sth->fetchrow) {
        next if $self && defined $self->id && $self->id == $id;

        return Ravada::Request->open($id) if !keys %$args_d;

        my $args_found_d = {};
        eval { $args_found_d = decode_json($args_found)};
        warn "Warning: request $id $@" if $@;
        delete $args_found_d->{uid};
        delete $args_found_d->{at};

        next if join(".",sort keys %$args_d) ne join(".",sort keys %$args_found_d);
        my $args_d_s = join(".",map { $args_d->{$_} } sort keys %$args_d);
        my $args_found_s = join(".",map {$args_found_d->{$_} } sort keys %$args_found_d);
        next if $args_d_s ne $args_found_s;

        return Ravada::Request->open($id);
    }

    return;
}

sub _requested($command, %fields) {
    _init_connector();
    my $query =
        "SELECT id FROM requests"
        ."  WHERE command = ? "
        ."     AND status <> 'done' "
    ;
    my @values = ( $command );
    for my $key( keys %fields ) {
        $query.= " AND $key = ?";
        push @values,($fields{$key});
    }
    my $sth = $$CONNECTOR->dbh->prepare($query);
    $sth->execute(@values);
    my ($id) = $sth->fetchrow;
    return $id;

}

=head2 stop

Stops a request killing the process.

    $request->stop();

=cut

sub stop($self) {
    my $stale = '';
    my $run_time = '';
    if ($self->start_time) {
        $run_time = time - $self->start_time;
        $stale = ", stale for $run_time seconds.";
    }
    warn "Killing ".$self->command
        ." , pid: ".( $self->pid or '<UNDEF>')
        .$stale
        ."\n";
    kill (15,$self->pid) if $self->pid;
    $self->status('done',"Killed start process after $run_time seconds.");
}

sub _delete($self) {
    my $sth = $$CONNECTOR->dbh->prepare("DELETE FROM requests where id=?");
    $sth->execute($self->id);
}

=head2 priority

Returns the priority of the request

=cut

sub priority($self) {
    return $self->{priority};
}

=head2 requirements_done

    Returns wether a request requirements have been fulfilled

    ie when a request must execute after another request completes.

=cut

sub requirements_done($self) {
    my $after_request = $self->after_request();
    my $after_request_ok = $self->after_request_ok();
    return 1 if !defined $after_request && !defined $after_request_ok;

    my $ok = 0;
    if ($after_request) {
        $ok = 0;
        my $req;
        eval { $req = Ravada::Request->open($self->after_request) };
        die $@ if $@ && $@!~ /I can't find|not found/i;
        $ok = 1 if !$req || $req->status eq 'done';
    }
    if ($after_request_ok) {
        $ok = 0;
        my $req = Ravada::Request->open($self->after_request_ok);
        if ($req->status eq 'done' && $req->error ) {
            $self->status('done');
            $self->error($req->error);
        }
        $ok = 1 if $req->status eq 'done' && ( !defined $req->error || $req->error eq '' );
    }
    return $ok;
}

=head2 redo

    Set the request to be executed again

=cut

sub redo($self) {
    my $sth = $self->_dbh->prepare(
        "UPDATE requests SET status='requested',start_time=NULL "
        ." WHERE id=?"
    );
    $sth->execute($self->id);
}

=head2 remove

Remove all requests that comply with the conditions

=cut

sub remove($status, %args) {
    my $sth = _dbh->prepare(
        "SELECT * FROM requests where status = ? "
    );
    $sth->execute($status);

    my $sth_del = _dbh->prepare("DELETE FROM requests where id=?");

    while ( my $row = $sth->fetchrow_hashref ) {
        my $req_args = {};

        eval {
        $req_args = decode_json($row->{args}) if $row->{args};
        };
        warn "Warning: $@ ".$row->{args}
        ."\n".Dumper($row) if $@;

        next if $row->{status} ne $status;
        delete $req_args->{uid};
        next if scalar(keys%args) != scalar(keys(%$req_args));

        my $found = 1;
        for my $key (keys %$req_args) {

            next if exists $args{$key}
            && !defined $args{$key} && !defined $req_args->{$key};

            $found=0 if
            !exists $args{$key} ||
            $args{$key} ne $req_args->{$key};
        }
        next if !$found;

        for my $key (keys %args) {
            next if exists $req_args->{$key}
            && !defined $args{$key} && !defined $req_args->{$key};

            $found=0 if
            !exists $req_args->{$key} ||
            $args{$key} ne $req_args->{$key};
        }
        next if !$found;

        $sth_del->execute($row->{id});
    }
}

sub _data($self, $field, $value=undef) {
    if (defined $value
        && (
          !exists $self->{_data}->{$field}
          || !defined $self->{_data}->{$field}
          || $value ne $self->{_data}->{$field}
        )
    ) {
        confess "ERROR: field $field is read only"
            if $FIELD_RO{$field};

        $self->{_data}->{$field} = $value;
        my $sth = $$CONNECTOR->dbh->prepare(
            "UPDATE requests set $field=?"
            ." WHERE id=?"
        );
        $sth->execute($value, $self->id);
        $sth->finish;

        return $value;
    }
    return $self->{_data}->{$field}
    if exists $self->{_data}->{$field} && defined $self->{_data}->{$field};

    $self->{_data} = $self->_select_db( );

    return if !$self->{_data};
    confess "No field $field "          if !exists$self->{_data}->{$field};

    return $self->{_data}->{$field};

}

sub id($self) {
    return $self->{id};
}

sub _select_db($self) {

    _init_connector();

    my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM requests "
            ." WHERE id=?");
    $sth->execute($self->{id});
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    return if !$row;

    return $row;
}

=head2 refresh

Refresh request status and data

=cut

sub refresh($self) {
    delete $self->{_data};
}

sub AUTOLOAD {
    my $self = shift;

    my $name = $AUTOLOAD;
    $name =~ s/.*://;

    if(!ref($self) && $VALID_ARG{$name} ) {
        return _new_request($self
            , command => $name
            , args => _check_args($name, @_)
        );
    }

    confess "ERROR: Unknown field $name "
        if !exists $self->{$name} && !exists $FIELD{$name} && !exists $FIELD_RO{$name};

    confess "Can't locate object method $name via package $self"
        if !ref($self);

    my $value = shift;
    $name =~ tr/[a-z][A-Z]_/_/c;

    delete $self->{_data}->{$name} if $name eq 'error';
    return $self->_data($name, $value);

}


sub DESTROY {}
1;
