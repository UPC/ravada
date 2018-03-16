package Ravada::Request;

use strict;
use warnings;

=head1 NAME

Ravada::Request - Requests library for Ravada

=cut

use Carp qw(confess);
use Data::Dumper;
use JSON::XS;
use Hash::Util;
use Ravada;
use Ravada::Front;

use vars qw($AUTOLOAD);

=pod

Request a command to the ravada backend

=cut

our %FIELD = map { $_ => 1 } qw(error);
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
        ,network => 2
    }
    ,open_iptables => $args_manage_iptables
      ,remove_base => $args_remove_base
     ,prepare_base => $args_prepare
     ,pause_domain => $args_manage
    ,resume_domain => {%$args_manage, remote_ip => 1 }
    ,remove_domain => $args_manage
    ,shutdown_domain => { name => 2, id_domain => 2, uid => 1, timeout => 2, at => 2 }
    ,force_shutdown_domain => { id_domain => 1, uid => 1, at => 2 }
    ,screenshot_domain => { id_domain => 1, filename => 2 }
    ,autostart_domain => { id_domain => 1 , uid => 1, value => 2 }
    ,copy_screenshot => { id_domain => 1, filename => 2 }
    ,start_domain => {%$args_manage, remote_ip => 1 }
    ,rename_domain => { uid => 1, name => 1, id_domain => 1}
    ,set_driver => {uid => 1, id_domain => 1, id_option => 1}
    ,hybernate=> {uid => 1, id_domain => 1}
    ,download => {uid => 2, id_iso => 1, id_vm => 2, delay => 2, verbose => 2}
    ,refresh_storage => { id_vm => 2 }
    ,clone => { uid => 1, id_domain => 1, name => 1, memory => 2 }
);

our %CMD_SEND_MESSAGE = map { $_ => 1 }
    qw( create start shutdown prepare_base remove remove_base rename_domain screenshot download
            autostart_domain
    );

our $CONNECTOR;

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
    return $row;
}

=head2 create_domain

    my $req = Ravada::Request->create_domain( name => 'bla'
                    , id_iso => 1
    );


=cut

sub create_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my %args = @_;

    my $args = _check_args('create_domain', @_ );

    my $self = {};
    if ($args->{network}) {
        $args->{network} = JSON::XS->new->convert_blessed->encode($args->{network});
    }

    bless($self,$class);
    return $self->_new_request(command => 'create' , args => encode_json($args));
}

=head2 remove_domain

    my $req = Ravada::Request->remove_domain( name => 'bla'
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

    return $self->_new_request(command => 'remove' , args => encode_json(\%args));

}

=head2 start_domain

Requests to start a domain

  my $req = Ravada::Request->start_domain( name => 'name', uid => $user->id );

=cut

sub start_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('start_domain', @_);

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'start' , args => encode_json($args));
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

    return $self->_new_request(command => 'pause' , args => encode_json($args));
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

    return $self->_new_request(command => 'resume' , args => encode_json($args));
}



sub _check_args {
    my $sub = shift;
    confess "Odd number of elements ".Dumper(\@_)   if scalar(@_) % 2;
    my $args = { @_ };

    my $valid_args = $VALID_ARG{$sub};

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

    $args->{timeout} = 10 if !exists $args->{timeout};

    confess "ERROR: You must supply either id_domain or name ".Dumper($args)
        if !$args->{id_domain} && !$args->{name};

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'shutdown' , args => $args);
}

=head2 prepare_base

Returns a new request for preparing a domain base

  my $req = Ravada::Request->prepare_base( $name );

=cut

sub prepare_base {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my %args = @_;
    confess "Missing uid"           if !$args{uid};

    my $args = _check_args('prepare_base', @_);

    my $self = {};
    bless($self,$class);

    return $self->_new_request(command => 'prepare_base'
        , id_domain => $args{id_domain}
        , args => encode_json( $args ));

}

=head2 remove_base

Returns a new request for making a base regular domain. It marks it
as 'non base' and removes the files.

It must have not clones. All clones must be removed before calling
this method.

  my $req = Ravada::Request->remove_base( $name );

=cut

sub remove_base {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my %_args = @_;
    confess "Missing uid"           if !$_args{uid};

    my $args = _check_args('remove_base', @_);

    my $self = {};
    bless($self,$class);

    my $req = $self->_new_request(command => 'remove_base'
        , id_domain => $args->{id_domain}
        , args => encode_json( $args ));

    return $req;
}


=head2 ping_backend

Returns wether the backend is alive or not

=cut

sub ping_backend {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $self = {};
    bless ($self, $class);
    return $self->_new_request( command => 'ping_backend' );
}


=head2 domdisplay

Returns the domdisplay of a domain

Arguments:

* domain name

=cut

sub domdisplay {
   my $proto = shift;
    my $class=ref($proto) || $proto;

    my $name = shift;
    my $uid = shift;

    my $self = {};
    bless ($self, $class);
    return $self->_new_request( command => 'domdisplay'
        ,args => { name => $name, uid => $uid });
}

sub _new_request {
    my $self = shift;
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
        }
        $args{args} = encode_json($args{args});
    }
    _init_connector()   if !$CONNECTOR || !$$CONNECTOR;

    my $sth = $$CONNECTOR->dbh->prepare(
        "INSERT INTO requests (".join(",",sort keys %args).")"
        ."  VALUES ( "
                .join(",", map { '?' } keys %args)
                ." )"
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    $sth->finish;

    $self->{id} = $self->_last_insert_id();

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

=head2 open_iptables

Request to open iptables for a remote client

=cut

sub open_iptables {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('open_iptables', @_ );

    my $self = {};
    bless($self,$class);

    return $self->_new_request(
            command => 'open_iptables'
        , id_domain => $args->{id_domain}
             , args => $args);
}

=head2 rename_domain

Request to rename a domain

=cut

sub rename_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $args = _check_args('rename_domain', @_ );

    my $self = {};
    bless($self,$class);

    return $self->_new_request(
            command => 'rename_domain'
        , id_domain => $args->{id_domain}
             , args => encode_json($args)
    );

}

=head2 set_driver

Sets a driver to a domain

    $domain->set_driver(
        id_domain => $domain->id
        ,uid => $USER->id
        ,id_driver => $driver->id
    );

=cut

sub set_driver {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('set_driver', @_ );

    my $self = {};
    bless($self,$class);

    return $self->_new_request(
            command => 'set_driver'
        , id_domain => $args->{id_domain}
             , args => encode_json($args)
    );

}

=head2 hybernate

Hybernates a domain.

    Ravada::Request->hybernate(
        id_domain => $domain->id
             ,uid => $user->id
    );

=cut

sub hybernate {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('hybernate', @_ );

    my $self = {};
    bless($self,$class);

    return $self->_new_request(
            command => 'hybernate'
        , id_domain => $args->{id_domain}
             , args => encode_json($args)
    );

}

=head2 download

Downloads a file. Actually used only to download iso images
for KVM domains.

=cut

sub download {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('download', @_ );

    my $self = {};
    bless($self,$class);

    return $self->_new_request(
            command => 'download'
             , args => encode_json($args)
    );

}

=head2 refresh_storage

Refreshes a storage pool

=cut

sub refresh_storage {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('refresh_storage', @_ );

    my $self = {};
    bless($self,$class);

    return $self->_new_request(
        command => 'refresh_storage'
        , args => $args
    );


}

=head2 clone

Copies a virtual machine

    my $req = Ravada::Request->clone(
             ,uid => $user->id
        id_domain => $domain->id
    );

=cut

sub clone {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('clone', @_ );

    my $self = {};
    bless($self,$class);

    return _new_request($self
        , command => 'clone'
        , args =>$args
    );
}

=head2 domain_autostart

Sets the autostart flag on a domain

=cut

sub domain_autostart {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $args = _check_args('autostart_domain', @_ );

    my $self = {};
    bless($self, $class);

    return _new_request($self
        , command => 'domain_autostart'
        , args => $args
    );
}
sub AUTOLOAD {
    my $self = shift;

    my $name = $AUTOLOAD;
    $name =~ s/.*://;

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
