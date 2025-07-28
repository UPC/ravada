package Ravada::Auth::Grants;

use warnings;
use strict;

=head1 NAME

Ravada::Auth::Grants - Grants authentication interface for Ravada

=cut

use Carp qw(carp);

use Ravada;
use Ravada::Utils;
use Ravada::Front;
use Digest::SHA qw(sha1_hex);
use Hash::Util qw(lock_hash);
use Mojo::JSON qw(decode_json);
use Moose::Role;

use feature qw(signatures);
no warnings "experimental::signatures";

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

=head2 grants_info

Returns a list of the permissions granted to an user as a hash.
Each entry is a reference to a list where the first value is
the grant and the second the type

=cut

sub grants_info($self) {
    my %grants = $self->grants();
    my %grants_info;
    for my $key ( keys %grants ) {
        $grants_info{$key}->[0] = $grants{$key};
        $grants_info{$key}->[1] = $self->{_grant_type}->{$key};
    }
    return %grants_info;
}

=head2 grants

Returns a list of permissions granted to the user in a hash

=cut

sub grants($self) {
    $self->_load_grants();
    return () if !$self->{_grant};
    return %{$self->{_grant}};
}

=head2 can_do

Returns if the group is allowed to perform a privileged action

    if ($group->can_do("remove")) { 
        ...

=cut

sub can_do($self, $grant) {
    $self->_load_grants();

    confess "Permission '$grant' invalid\n".Dumper($self->{_grant_alias})
        if $grant !~ /^[a-z_]+$/;

    $grant = $self->_grant_alias($grant);

    confess "Wrong grant '$grant'\n".Dumper($self->{_grant_alias})
        if $grant !~ /^[a-z_]+$/;

    return $self->{_grant}->{$grant} if defined $self->{_grant}->{$grant};
    confess "Unknown permission '$grant'. Maybe you are using an old release.\n"
            ."Try removing the table grant_types and start rvd_back again:\n"
            ."mysql> drop table grant_types;\n"
            .Dumper($self->{_grant}, $self->{_grant_alias})
        if !exists $self->{_grant}->{$grant};
    return $self->{_grant}->{$grant};
}

sub _load_aliases($self) {
    return if exists $self->{_grant_alias};

    _init_connector();

    my $sth = $$CON->dbh->prepare("SELECT name,alias FROM grant_types_alias");
    $sth->execute;
    while (my $row = $sth->fetchrow_hashref) {
        $self->{_grant_alias}->{$row->{name}} = $row->{alias};
    }

}

sub _grant_alias($self, $name) {
    my $alias = $name;
    return $self->{_grant_alias}->{$name} if exists $self->{_grant_alias}->{$name};
    return $name;# if exists $self->{_grant}->{$name};

}

1;
