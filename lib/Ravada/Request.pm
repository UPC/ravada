package Ravada::Request;

use strict;
use warnings;

=head1 NAME

Ravada::Request - Requests library for Ravada

=cut

use Carp qw(confess);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use JSON::XS;
use Hash::Util;
use Time::Piece;
use Ravada;
use Ravada::Front;

use vars qw($AUTOLOAD);

no warnings "experimental::signatures";
use feature qw(signatures);

=pod

Request a command to the ravada backend

=cut

my $COUNT = 0;
our %FIELD = map { $_ => 1 } qw(error output);
our %FIELD_RO = map { $_ => 1 } qw(id name);

our $args_manage = { name => 1 , uid => 1 };
our $args_prepare = { id_domain => 1 , uid => 1 };
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
    }
    ,open_iptables => $args_manage_iptables
      ,remove_base => $args_remove_base
     ,prepare_base => $args_prepare
     ,pause_domain => $args_manage
    ,resume_domain => {%$args_manage, remote_ip => 1 }
    ,remove_domain => $args_manage
    ,shutdown_domain => { name => 2, id_domain => 2, uid => 1, timeout => 2, at => 2
                       , id_vm => 2 }
    ,force_shutdown_domain => { id_domain => 1, uid => 1, at => 2, id_vm => 2 }
    ,screenshot_domain => { id_domain => 1, filename => 2 }
    ,domain_autostart => { id_domain => 1 , uid => 1, value => 2 }
    ,copy_screenshot => { id_domain => 1, filename => 2 }
    ,start_domain => {%$args_manage, remote_ip => 2, name => 2, id_domain => 2 }
    ,start_clones => { id_domain => 1, uid => 1, remote_ip => 1 }
    ,rename_domain => { uid => 1, name => 1, id_domain => 1}
    ,dettach => { uid => 1, id_domain => 1 }
    ,set_driver => {uid => 1, id_domain => 1, id_option => 1}
    ,hybernate=> {uid => 1, id_domain => 1}
    ,download => {uid => 2, id_iso => 1, id_vm => 2, verbose => 2, delay => 2, test => 2}
    ,refresh_storage => { id_vm => 2 }
    ,set_base_vm=> {uid => 1, id_vm=> 1, id_domain => 1, value => 2 }
    ,cleanup => { }
    ,clone => { uid => 1, id_domain => 1, name => 2, memory => 2, number => 2, is_pool => 2
                ,start => 2, no_pool => 2
                ,remote_ip => 2
    }
    ,change_owner => {uid => 1, id_domain => 1}
    ,add_hardware => {uid => 1, id_domain => 1, name => 1, number => 2, data => 2 }
    ,remove_hardware => {uid => 1, id_domain => 1, name => 1, index => 1}
    ,change_hardware => {uid => 1, id_domain => 1, hardware => 1, index => 1, data => 1 }
    ,change_max_memory => {uid => 1, id_domain => 1, ram => 1}
    ,change_curr_memory => {uid => 1, id_domain => 1, ram => 1}
    ,enforce_limits => { timeout => 2, _force => 2 }
    ,refresh_machine => { id_domain => 1, uid => 1 }
    ,rebase_volumes => { uid => 1, id_base => 1, id_domain => 1 }
    # ports
    ,expose => { uid => 1, id_domain => 1, port => 1, name => 2, restricted => 2, id_port => 2}
    ,remove_expose => { uid => 1, id_domain => 1, port => 1}
    ,open_exposed_ports => {uid => 1, id_domain => 1 }
    # Virtual Managers or Nodes
    ,refresh_vms => { _force => 2, timeout_shutdown => 2 }

    ,shutdown_node => { id_node => 1, at => 2 }
    ,start_node => { id_node => 1, at => 2 }
    ,connect_node => { backend => 2, hostname => 2, id_node =>2, timeout => 2 }

    #users
    ,post_login => { user => 1, locale => 2 }

    #networks
    ,list_network_interfaces => { uid => 1, vm_type => 1, type => 2 }

    #isos
    ,list_isos => { vm_type => 1 }

    ,manage_pools => { uid => 2, id_domain => 2 }
    ,ping_backend => {}
);

our %CMD_SEND_MESSAGE = map { $_ => 1 }
    qw( create start shutdown prepare_base remove remove_base rename_domain screenshot download
            set_base_vm remove_base_vm
            domain_autostart hibernate hybernate
            change_owner
            change_max_memory change_curr_memory
            add_hardware remove_hardware set_driver change_hardware
            set_base_vm
            shutdown_node start_node
    );

our $TIMEOUT_SHUTDOWN = 120;

our $CONNECTOR;

our %COMMAND = (
    long => {
        limit => 4
        ,priority => 4
    } #default
    ,huge => {
        limit => 1
        ,commands => ['download']
        ,priority => 5
    }
    ,disk => {
        limit => 1
        ,commands => ['prepare_base','remove_base','set_base_vm','rebase_volumes'
                    , 'manage_pools']
        ,priority => 6
    }
    ,important=> {
        limit => 20
        ,priority => 1
        ,commands => ['clone','start','start_clones','create','open_iptables','list_network_interfaces','list_isos']
    }
    ,secondary => {
        limit => 50
        ,priority => 2
        ,commands => ['shutdown','shutdown_now']
    }
);
lock_hash %COMMAND;

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

    confess "ERROR: Argument vm required without id_base"
        if !exists $args->{vm} && !exists $args->{id_base};

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

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'start' , args => $args);
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
    for (qw(at after_request)) {
        $valid_args->{$_}=2 if !exists $valid_args->{$_};
    }

    confess "Unknown method $sub" if !$valid_args;
    for (keys %{$args}) {
        confess "Invalid argument $_ , valid args ".Dumper($valid_args)
            if !$valid_args->{$_};
    }

    for (keys %{$VALID_ARG{$sub}}) {
        next if $VALID_ARG{$sub}->{$_} == 2; # optional arg
        confess "Missing argument $_"   if !exists $args->{$_};
    }

    return $args;
}

=head2 force_shutdown_domain

Requests to stop a domain now !

  my $req = Ravada::Request->shutdown_domain( name => 'name' , uid => $user->id );

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

    $args->{timeout} = $TIMEOUT_SHUTDOWN if !exists $args->{timeout};

    confess "ERROR: You must supply either id_domain or name ".Dumper($args)
        if !$args->{id_domain} && !$args->{name};

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'shutdown' , args => $args);
}

sub new_request($self, $command, @args) {
    die "Error: Unknown request '$command'" if !$VALID_ARG{$command};
    return _new_request(
        $self
        ,command => $command
           ,args => _check_args($command, @args)
    );
}

sub _duplicated_request($command, $args) {
    return if !$args;
    my $args_d = decode_json($args);
    delete $args_d->{uid};
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id,args FROM requests WHERE status='requested'"
        ." AND command=?"
    );
    $sth->execute($command);
    while (my ($id,$args_found) = $sth->fetchrow) {

        my $args_found_d = decode_json($args_found);
        delete $args_found_d->{uid};

        next if join(".",sort keys %$args_d) ne join(".",sort keys %$args_found_d);
        my $args_d_s = join(".",map { $args_d->{$_} } sort keys %$args_d);
        my $args_found_s = join(".",map {$args_found_d->{$_} } sort keys %$args_found_d);
        next if $args_d_s ne $args_found_s;

        warn "$id\n$args_d_s\n$args_found_s\n"
            if $command eq 'clone' && $args =~ /a-1/;
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

    if ($args{name}) {
        $args{domain_name} = $args{name};
        delete $args{name};
    }
    if ( ref $args{args} ) {
        $args{args}->{uid} = $args{args}->{id_owner}
            if !exists $args{args}->{uid};
        $args{at_time} = $args{args}->{at} if exists $args{args}->{at};
        my $id_domain_args = $args{args}->{id_domain};

        if ($id_domain_args) {
            confess "ERROR: Different id_domain: ".Dumper(\%args)
                if $args{id_domain} && $args{id_domain} ne $id_domain_args;
            $args{id_domain} = $id_domain_args;
            $args{after_request} = delete $args{args}->{after_request}
                if exists $args{args}->{after_request};

        }
        $args{args} = encode_json($args{args});
    }
    _init_connector()   if !$CONNECTOR || !$$CONNECTOR;
    if ($args{command} =~ /^(clone|manage_pools)$/) {
        if ( _duplicated_request($args{command}, $args{args})
            || ( $args{command} ne 'clone' && done_recently(undef, 60, $args{command}))) {
            #            warn "Warning: duplicated request for $args{command} $args{args}";
            return;
        }
    }

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

    return $self->open($self->{id});
}

sub _last_insert_id {
    my $driver = $$CONNECTOR->dbh->{Driver}->{Name};

    if ( $driver =~ /sqlite/i ) {
        return _last_insert_id_sqlite(@_);
    } elsif ( $driver =~ /mysql/i ) {
        return _last_insert_id_mysql(@_);
    } else {
        confess "I don't know how to get last_insert_id for $driver";
    }
}

sub _last_insert_id_mysql {
    my $self = shift;
    my $sth = $$CONNECTOR->dbh->prepare("SELECT last_insert_id()");
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $sth->finish;
    return $id;

}

sub _last_insert_id_sqlite {
    my $self = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT last_insert_rowid()");
    $sth->execute;
    my ($id) = $sth->fetchrow;
    $sth->finish;
    return $id;
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

    my $sth = $$CONNECTOR->dbh->prepare("UPDATE requests set status=? "
            ." WHERE id=?");

    $status = substr($status,0,64);
    $sth->execute($status, $self->{id});
    $sth->finish;

    $self->_send_message($status, $message)
        if $CMD_SEND_MESSAGE{$self->command} || $self->error ;
    return $status;
}

sub _search_domain_name {
    my $self = shift;
    my $domain_id = shift;

    my $sth = $$CONNECTOR->dbh->prepare("SELECT name FROM domains where id=?");
    $sth->execute($domain_id);
    return $sth->fetchrow;
}

sub _send_message {
    my $self = shift;
    my $status = shift;
    my $message = ( shift or $self->error );

    my $uid;

    $uid = $self->args('id_owner') if $self->defined_arg('id_owner');
    $uid = $self->args('uid')      if !$uid && $self->defined_arg('uid');
    return if !$uid;

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
    return $self->{args}    if !$name;

    confess "Unknown argument $name ".Dumper($self->{args})
        if !exists $self->{args}->{$name};
    return $self->{args}->{$name};
}

sub arg($self, $name, $value) {

    confess "Unknown argument $name ".Dumper($self->{args})
        if !exists $self->{args}->{$name} && !defined $value;

    $self->{args}->{$name} = $value if defined $value;
    return $self->{args}->{$name};
}


=head2 defined_arg

Returns if an argument is defined

=cut

sub defined_arg {
    my $self = shift;
    my $name = shift;
    confess "ERROR: missing arg name" if !defined $name;
    return $self->{args}->{$name};
}

=head2 screenshot_domain

Request the screenshot of a domain.

Arguments:

- optional filename , defaults to "storage_path/$id_domain.png"

Returns a Ravada::Request;

=cut

sub screenshot_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('screenshot_domain', @_ );

    $args->{filename} = '' if !exists $args->{filename};

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'screenshot' , id_domain => $args->{id_domain}
        ,args => $args);

}

=head2 copy_screenshot

Request to copy a screenshot from a domain to another

=cut

sub copy_screenshot {
  my $proto = shift;
  my $class=ref($proto) || $proto;

  my $args = _check_args('copy_screenshot', @_ );

  $args->{filename} = '' if !exists $args->{filename};

  my $self = {};
  bless($self,$class);

  return $self->_new_request(
       command => 'copy_screenshot'
      ,id_domain => $args->{id_domain}
      ,args => $args
      );

}

=head2 refresh_vms

Refreshes the Virtual Mangers

=cut

sub refresh_vms {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('refresh_vms', @_ );
    if  (!$args->{_force} ) {
          return if done_recently(undef,60,'refresh_vms') || _requested('refresh_vms');
    }

    $args->{timeout} = 120 if ! $args->{timeout};

    my $self = {};
    bless($self,$class);

    _init_connector();
    return $self->_new_request(
        command => 'refresh_vms'
        , args => $args
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

    return $self->_new_request(
            command => 'set_base_vm'
             , args => $args
    );

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


=head2 working_requests

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
    return $COMMAND{$type}->{limit};
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

    if (!$args->{at} && (my $id_request = $req->done_recently(30))) {
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

    return if done_recently(undef,60,'refresh_machine');

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

sub done_recently($self, $seconds=60,$command=undef) {
    _init_connector();
    my $id_req = 0;
    if ($self) {
        $id_req = $self->id;
        $command = $self->command;
    }
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT id FROM requests"
        ." WHERE date_changed > ? "
        ."        AND command = ? "
        ."         AND ( status = 'done' OR status ='working') "
        ."         AND  error = '' "
        ."         AND id <> ? "
    );
    my $date= Time::Piece->localtime(time - $seconds);
    $sth->execute($date->ymd." ".$date->hms, $command, $id_req);
    my ($id) = $sth->fetchrow;
    return $id;
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

sub stop($self) {
    warn "Killing ".$self->command
        ." , pid: ".$self->pid
        .", stale for ".(time - $self->start_time)." seconds\n";
    my $ok = kill (15,$self->pid);
    $self->status('done',"Killed start process after "
           .(time - $self->start_time)." seconds\n");

}

sub priority($self) {
    return $self->{priority};
}

sub requirements_done($self) {
    my $after_request = $self->after_request();
    return 1 if !defined $after_request;

    my $req = Ravada::Request->open($self->after_request);
    return 1 if $req->status eq 'done';
    return 0;
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

    confess "Can't locate object method $name via package $self"
        if !ref($self);

    my $value = shift;
    $name =~ tr/[a-z][A-Z]_/_/c;

    confess "ERROR: Unknown field $name "
        if !exists $self->{$name} && !exists $FIELD{$name} && !exists $FIELD_RO{$name};
    if (!defined $value) {
        my $sth = $$CONNECTOR->dbh->prepare("SELECT * FROM requests "
            ." WHERE id=?");
        $sth->execute($self->{id});
        my $row = $sth->fetchrow_hashref;
        $sth->finish;

        return $row->{$name};
    }

    confess "ERROR: field $name is read only"
        if $FIELD_RO{$name};

    my $sth = $$CONNECTOR->dbh->prepare("UPDATE requests set $name=? "
            ." WHERE id=?");
    eval {
        $sth->execute($value, $self->{id});
        $sth->finish;
    };
    warn "$name=$value\n$@" if $@;
    return $value;

}


sub DESTROY {}
1;
