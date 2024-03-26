package Ravada::Auth::Group;

use warnings;
use strict;

=head1 NAME

Ravada::Auth::Group - Group management library for Ravada

=cut

use Carp qw(carp);
use Data::Dumper qw(Dumper);
use Hash::Util qw(lock_hash);

use Moose;

use feature qw(signatures);
no warnings "experimental::signatures";

has 'name' => (
    is => 'rw'
    ,isa => 'Str'
    ,required => 1
);

our $CON;

sub _init_connector {
    my $connector = shift;

    $CON = \$connector                 if defined $connector;
    return if $CON;

    $CON= \$Ravada::CONNECTOR          if !$CON || !$$CON;
    $CON= \$Ravada::Front::CONNECTOR   if !$CON || !$$CON;

    if (!$CON || !$$CON) {
        my $connector = Ravada::_connect_dbh();
        $CON = \$connector;
    }

    die "Undefined connector"   if !$CON || !$$CON;
}

sub BUILD {
    my $self = shift;
    _init_connector();
    $self->_load_data();
}

sub _load_data($self) {
   _init_connector();

    confess "No group name nor id " if !defined $self->name && !$self->id;

    confess "Undefined \$\$CON" if !defined $$CON;
    my $sth = $$CON->dbh->prepare(
       "SELECT * FROM groups_local WHERE name=? ");
    $sth->execute($self->name);
    my ($found) = $sth->fetchrow_hashref;
    $sth->finish;

    return if !$found->{name};

    lock_hash %$found;
    $self->{_data} = $found if ref $self && $found;

}

sub id {
    my $self = shift;
    my $id;
    eval { $id = $self->{_data}->{id} };
    confess $@ if $@;

    return $id;
}

sub add_group(%args) {
}

1;
