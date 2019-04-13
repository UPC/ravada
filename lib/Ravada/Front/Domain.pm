package Ravada::Front::Domain;

use warnings;
use strict;

=head2 NAME

Ravada::Front::Domain - Frontent domain information for Ravada

=cut

use Carp qw(cluck confess croak);
use Data::Dumper;
use JSON::XS;
use Moose;

use Ravada::Front::Domain::KVM;
use Ravada::Front::Domain::Void;

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

our $CONNECTOR;
#
###########################################################################

sub _init_connector {
    $CONNECTOR= \$Ravada::CONNECTOR;
    $CONNECTOR= \$Ravada::Front::CONNECTOR   if !$$CONNECTOR;
}

sub BUILD($self, $arg) {
    my $id = $arg->{id};
    my $name = $arg->{name};

    $self->_select_domain_db( id => $id)    if defined $id;
    $self->_select_domain_db( name => $name)    if defined $name;

    $self->{_data}->{id} = $id      if defined $id;
    $self->{_data}->{name} = $name  if defined $name;

#    confess "ERROR: Domain '".$self->name." not found "
#        if $self->is_volatile && ! $self->is_active;
}

sub open($self, $id) {
    my $domain = Ravada::Front::Domain->new( id => $id );
    if ($domain->type eq 'KVM') {
        $domain = Ravada::Front::Domain::KVM->new( id => $id );
    } elsif ($domain->type eq 'Void') {
        $domain = Ravada::Front::Domain::Void->new( id => $id );
    }
    die "ERROR: Unknown domain id: $id\n"
        unless exists $domain->{_data}->{name} && $domain->{_data}->{name};
    return $domain;
}

sub autostart($self )    { return $self->_data('autostart') }
sub _do_force_shutdown  { confess "TODO" }
sub add_volume          { confess "TODO" }
sub remove_volume       { confess "TODO" }
sub clean_swap_volumes  { confess "TODO" }
sub disk_device         { confess "TODO" }
sub disk_size           { confess "TODO" }

sub display($self, $user) {
    my $info = $self->display_info($user);
    return $info->{display};
}

sub display_info($self, $user) {
    return decode_json($self->_data('display'));
}

sub display_file_tls($self, $user) {
    return $self->_data('display_file');
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

sub is_volatile_clones($self) { return $self->_data('volatile_clones')}

sub is_hibernated($self) {
    return 1 if $self->_data('status') eq 'hibernated';
    return 0;
}

sub is_paused($self) {
    return 1 if $self->_data('status') eq 'paused';
    return 0;
}

sub is_removed          { return 0 }
sub list_volumes($self, $attribute=undef, $value=undef)
{
    _init_connector();
    my $sth = $$CONNECTOR->dbh->prepare(
        "SELECT * FROM volumes "
        ." WHERE id_domain=?"
        ." ORDER BY id"
    );
    $sth->execute($self->id);
    my @volumes;
    while (my $row = $sth->fetchrow_hashref) {
        $row->{info} = decode_json($row->{info}) if $row->{info};
        $row->{info}->{capacity} = Ravada::Utils::number_to_size($row->{info}->{capacity})
            if defined $row->{info}->{capacity} && $row->{info}->{capacity} =~ /^\d+$/;
        $row->{info}->{allocation} = Ravada::Utils::number_to_size($row->{info}->{allocation})
            if defined $row->{info}->{allocation} && $row->{info}->{allocation} =~ /^\d+$/;
        $row->{driver} = delete $row->{info}->{driver};

        next if defined $attribute
        && ( !exists $row->{$attribute}
                || $row->{$attribute} != $value);
        push @volumes, ($row);
    }
    $sth->finish;
    return @volumes;
}

sub list_volumes_info($self, @args) { return $self->list_volumes(@args) }

sub migrate             { confess "TODO" }

sub name($self) {
    return $self->{_data}->{name}   if exists $self->{_data} && $self->{_data}->{name};
    return $self->_data('name') 
}

sub pause               { confess "TODO" }
sub prepare_base        { confess "TODO" }
sub remove              { confess "TODO" }
sub rename              { confess "TODO" }
sub resume              { confess "TODO" }
sub screenshot          { confess "TODO" }

sub search_domain($self,$name) {
    _init_connector();
    my $sth = $$CONNECTOR->dbh->prepare("SELECT id FROM domains WHERE name=?");
    $sth->execute($name);
    my ($id) = $sth->fetchrow;
    $sth->finish;
    return if !$id;
    return Ravada::Front::Domain->new(id => $id);
}

sub set_max_mem         { confess "TODO" }
sub set_memory          { confess "TODO" }
sub shutdown            { confess "TODO" }
sub shutdown_now        { confess "TODO" }
sub spinoff_volumes     { confess "TODO" }
sub start               { confess "TODO" }

sub dettach             { confess "TODO" }

sub get_driver {}
sub get_controller_by_name { }
sub list_controllers {}

sub set_controller {}
sub remove_controller {}
sub change_hardware { die "TODO" }
1;
