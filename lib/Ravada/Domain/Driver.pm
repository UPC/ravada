package Ravada::Domain::Driver;

use warnings;
use strict;

use Moose;

_init_connector();

has 'domain' => (
    isa => 'Any'
    ,is => 'ro'
);

has 'id' => (
    isa => 'Int'
    ,is => 'ro'
);

##############################################################################

our $CONNECTOR;
our $TABLE_DRIVERS = "domain_drivers_types";
our $TABLE_OPTIONS= "domain_drivers_options";

sub _init_connector {
    return if $CONNECTOR && $$CONNECTOR;
    $CONNECTOR = \$Ravada::CONNECTOR if $Ravada::CONNECTOR;
    $CONNECTOR = \$Ravada::Front::CONNECTOR if !defined $$CONNECTOR
                                                && defined $Ravada::Front::CONNECTOR;
}

##############################################################################

sub get_value {
    my $self = shift;
    return $self->domain->get_driver($self->name);
}

sub name {
    my $self = shift;
    return $self->_data('name');
}

sub _data {
    my $self = shift;
    my $field = shift or confess "Missing field name";

    _init_connector();

    return $self->{_data}->{$field} if exists $self->{_data}->{$field};
    $self->{_data} = $self->_select_driver_db( id => $self->id);

    confess "No DB info for driver ".$self->id      if !$self->{_data};
    confess "No field $field in drivers "           if !exists$self->{_data}->{$field};

    return $self->{_data}->{$field};
}

sub _select_driver_db {
    my $self = shift;
    my %args = @_;

    _init_connector();

    if (!keys %args) {
        %args =( id => $self->id );
    }

    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM $TABLE_DRIVERS WHERE ".join(",",map { "$_=?" } sort keys %args )
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    $self->{_data} = $row;
    return $row if $row->{id};

}

sub get_options {
    my $self = shift;

    _init_connector();
    my $query = "SELECT * from $TABLE_OPTIONS WHERE id_driver_type=? ORDER by name";

    my $sth = $$CONNECTOR->dbh->prepare($query);
    $sth->execute($self->id);

    my @ret;
    while (my $row = $sth->fetchrow_hashref) {
        push @ret,($row);
    }
    return @ret;

}

1;
