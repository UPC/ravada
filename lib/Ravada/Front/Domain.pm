package Ravada::Front::Domain;

use warnings;
use strict;

=head2 NAME

Ravada::Front::Domain - Frontent domain information for Ravada

=cut

use Carp qw(cluck confess croak);
use JSON::XS;
use Moose;

no warnings "experimental::signatures";
use feature qw(signatures);

with 'Ravada::Domain';

###########################################################################
#
has 'readonly' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => 1
);

our $CONNECTOR = \$Ravada::Front::CONNECTOR;
#
###########################################################################

sub BUILD($self, $arg) {
    my $id = $arg->{id} or confess "ERROR: id required";
    my $ret = $self->_select_domain_db( id => $id);

    die "ERROR: Domain '".$self->name." not found "
        if $self->is_volatile && ! $self->is_active;
}

sub autostart($self )    { return $self->_data('autostart') }
sub _do_force_shutdown  { confess "TODO" }
sub add_volume          { confess "TODO" }
sub clean_swap_volumes  { confess "TODO" }
sub disk_device         { confess "TODO" }
sub disk_size           { confess "TODO" }

sub display($self, $user) {
    return $self->_data('display');
}

sub force_shutdown      { confess "TODO" }

sub get_info($self) {
     my $info = $self->_data('info');
     return {} if !$info;
     return decode_json($info);
}
sub hybernate           { confess "TODO" }
sub hibernate           { confess "TODO" }

sub internal_id($self) { return $self->_data('internal_id')}

sub is_active($self) {
    return 1 if $self->_data('status') eq 'active';
    return 0;
}

sub is_hibernated($self) {
    return 1 if $self->_data('status') eq 'hibernated';
    return 0;
}

sub is_paused($self) {
    return 1 if $self->_data('status') eq 'paused';
    return 0;
}

sub is_removed          { confess "TODO" }
sub list_volumes        { confess "TODO" }

sub name($self) {
    return $self->_data('name') 
}

sub pause               { confess "TODO" }
sub prepare_base        { confess "TODO" }
sub remove              { confess "TODO" }
sub rename              { confess "TODO" }
sub resume              { confess "TODO" }
sub screenshot          { confess "TODO" }

sub search_domain($self,$name) {
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM domains WHERE name=?");
    $sth->execute($name);
    my ($id) = $sth->fetchrow;
    $sth->finish;
    return Ravada::Front::Domain->new(id => $id);
}

sub set_max_mem         { confess "TODO" }
sub set_memory          { confess "TODO" }
sub shutdown            { confess "TODO" }
sub shutdown_now        { confess "TODO" }
sub spinoff_volumes     { confess "TODO" }
sub start               { confess "TODO" }
1;
