package Ravada::Domain;

use warnings;
use strict;

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
