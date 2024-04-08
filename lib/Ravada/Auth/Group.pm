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

sub open($self, $id) {
    my $sth = $$CON->dbh->prepare(
        "SELECT name FROM groups_local WHERE id=?"
    );
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    die "Error: unknown group id '$id'" if !$name;

    return $self->new(name => $name);
}

sub id {
    my $self = shift;
    my $id;
    eval { $id = $self->{_data}->{id} };
    confess $@ if $@;

    return $id;
}

sub add_group(%args) {
   _init_connector();
    my $name = delete $args{name};
    my $external_auth = delete $args{external_auth};
    my $is_external = 0;
    $is_external = 1 if $external_auth;

    confess "WARNING: Unknown arguments ".Dumper(\%args)
        if keys %args;


    my $sth;
    eval { $sth = $$CON->dbh->prepare(
            "INSERT INTO groups_local(name,is_external,external_auth)"
            ." VALUES(?,?,?)");
        $sth->execute($name, $is_external, $external_auth);
    };
    confess $@ if $@;
    return Ravada::Auth::Group->new(name => $name);
}

sub _remove_all_members($self) {
    my $sth = $$CON->dbh->prepare("DELETE FROM users_group "
        ." WHERE id_group=?"
    );
    $sth->execute($self->id);
}

sub _remove_access($self) {
    my $sth = $$CON->dbh->prepare("DELETE FROM group_access "
        ." WHERE type='local'"
        ."  AND name=?"
    );
    $sth->execute($self->name);
}

sub members_info($self) {
    my $sth = $$CON->dbh->prepare(
        "SELECT u.id,u.name FROM users u,users_group ug "
        ." WHERE u.id = ug.id_user "
        ."   AND ug.id_group=?"
        ." ORDER BY name"
    );
    $sth->execute($self->id);
    my @members;
    while (my ($uid,$name) = $sth->fetchrow) {
        push @members,({ id => $uid, name => $name});
    }
    return @members;
}

sub remove($self) {
    my $id = $self->id;

    $self->_remove_all_members();
    $self->_remove_access();

    my $sth = $$CON->dbh->prepare(
        "DELETE FROM groups_local WHERE id=?"
    );
    $sth->execute($id);
}

1;
