package Ravada::Domain;

use warnings;
use strict;

use Carp qw(confess);
use Moose::Role;

requires 'name';
requires 'remove';

has 'domain' => (
    isa => 'Object'
    ,is => 'ro'
);

sub id {
    my $self = shift;

    return $self->{id} if exists $self->{id};

    my $sth = $self->connector->dbh->prepare("SELECT id FROM domains "
        ." WHERE name=?"
    );
    $sth->execute($self->name);
    my ($id) = $sth->fetchrow;
    $sth->finish;

    $self->{id} = $id;
    return $id;
}

sub open {
    my $self = shift;

    my %args = @_;

    my $id = $args{id} or confess "Missing required argument id";
    delete $args{id};

    my $row = $self->_select_domain_db ( id => $id );
    return $self->search_domain($row->{name});
#    confess $row;
}

sub _select_domain_db {
    my $self = shift;
    my %args = @_;

    my $sth = $self->connector->dbh->prepare(
        "SELECT * FROM domains WHERE ".join(",",map { "$_=?" } sort keys %args )
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    return $row;
}

sub _prepare_base_db {
    my $self = shift;
    my $file_img = shift;

    my $sth = $self->connector->dbh->prepare(
        "UPDATE domains set is_base='y',file_base_img=? "
        ." WHERE id=?"
    );
    $sth->execute($file_img , $self->id);
    $sth->finish;
}

1;
