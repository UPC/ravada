package Ravada::Request;

use strict;
use warnings;

use Carp qw(confess);
use Data::Dumper;
use JSON::XS;
use Ravada;
use Ravada::Front;

use vars qw($AUTOLOAD);

=pod

Request a command to the ravada backend

=cut

our %FIELD = map { $_ => 1 } qw(error);
our %FIELD_RO = map { $_ => 1 } qw(name);

our %VALID_ARG = (
    create_domain => { 
              vm => 1
           ,name => 1
         ,id_iso => 1
    ,id_template => 1
    }
);

our $CONNECTOR;

sub _init_connector {
    $CONNECTOR = \$Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR   if !$$CONNECTOR;

}

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

    my $args = decode_json($row->{args}) if $row->{args};
    $args = {} if !$args;

    $row->{args} = $args;

    bless ($row,$class);
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

    confess "Missing domain name "
        if !$args{name};

    for (keys %args) {
        confess "Invalid argument $_" if !$VALID_ARG{'create_domain'}->{$_};
    }
    my $self = {};

    bless($self,$class);
    return $self->_new_request(command => 'create' , args => encode_json(\%args));
}

=head2 remove_domain

    my $req = Ravada::Request->create_domain( name => 'bla'
                    , id_iso => 1
    );


=cut


sub remove_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $name = shift;
    $name = $name->name if ref($name) =~ /Domain/;

    my %args = ( name => $name )    or confess "Missing domain name";

    my $self = {};
    bless($self,$class);
    return $self->_new_request(command => 'remove' , args => encode_json({ name => $name }));

}

=head2 start_domain

Requests to start a domain

  my $req = Ravada::Request->start_domain( name => 'name' );

=cut

sub start_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $name = shift;
    $name = $name->name if ref($name) =~ /Domain/;

    my %args = ( name => $name )    or confess "Missing domain name";

    my $self = {};
    bless($self,$class);
    return $self->_new_request(command => 'start' , args => encode_json({ name => $name }));
}


=head2 shutdown_domain

Requests to stop a domain

  my $req = Ravada::Request->shutdown_domain( 'name' );
  my $req = Ravada::Request->shutdown_domain( 'name' , $timeout );

=cut

sub shutdown_domain {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $name = shift;
    $name = $name->name if ref($name) =~ /Domain/;

    my $timeout = ( shift or 10 );

    my %args = ( name => $name, timeout => $timeout )    or confess "Missing domain name";

    my $self = {};
    bless($self,$class);
    return $self->_new_request(command => 'shutdown' , args => encode_json(\%args));
}

=head2 prepare_base

Returns a new request for preparing a domain base

  my $req = Ravada::Request->prepare_base( $name );

=cut

sub prepare_base {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $name = shift;
    $name = $name->name if ref($name) =~ /Domain/;

    my %args = ( name => $name )    or confess "Missing domain name";

    my $self = {};
    bless($self,$class);
    return $self->_new_request(command => 'prepare_base' 
        , args => encode_json({ name => $name }));

}

=head2 list_vm_types

Returns a list of VM types

    my $req = Ravada::Request->list_vm_types();

    my $types = $req->result;

=cut

sub list_vm_types {
    my $proto = shift;
    my $class=ref($proto) || $proto;

    my $self = {};
    bless ($self, $class);
    return $self->_new_request( command => 'list_vm_types' );

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

sub _new_request {
    my $self = shift;
    my %args = @_;

    $args{status} = 'requested';

    if ($args{name}) {
        $args{domain_name} = $args{name};
        delete $args{name};
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
    return $status;
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

    confess "Unknown argument $name"
        if !exists $self->{args}->{name};
    return $self->{args}->{$name};
}

sub AUTOLOAD {
    my $self = shift;


    my $name = $AUTOLOAD;
    $name =~ s/.*://;

    confess "Can't locate object method $name via package $self"
        if !ref($self);

    my $value = shift;
    $name =~ tr/[a-z]/_/c;

    confess "ERROR: Unknown field $name "
        if !exists $self->{$name} || !exists $FIELD{$name};
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
    $sth->execute($value, $self->{id});
    $sth->finish;
    return $value;

}

1;
