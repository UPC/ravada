package Ravada::Domain;

use warnings;
use strict;

use Carp qw(confess);
use Moose::Role;

requires 'name';
requires 'remove';
requires 'display';

has 'domain' => (
    isa => 'Object'
    ,is => 'ro'
);

##################################################################################3
#
sub id {
    return $_[0]->_data('id');

}
sub file_base_img {
    return $_[0]->_data('file_base_img');
}

##################################################################################

sub _data {
    my $self = shift;
    my $field = shift or confess "Missing field name";

    return $self->{_data}->{$field} if exists $self->{_data}->{$field};
    $self->_load_sql_data();

    return $self->{_data}->{$field};
}

sub _load_sql_data {
    my $self = shift;
    my $sth = $self->connector->dbh->prepare("SELECT * FROM domains "
        ." WHERE name=?"
    );
    $sth->execute($self->name);
    my $data = $sth->fetchrow_hashref;
    $sth->finish;
    $self->{_data} = $data;

    return $data;
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
