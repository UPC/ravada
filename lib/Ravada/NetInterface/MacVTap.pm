package Ravada::NetInterface::MacVTap;

use warnings;
use strict;

=head1 NAME

Ravada::NetInterface::MacVTap - MacVTAP network library for Ravada

=cut

use Carp qw(cluck confess croak);
use Data::Dumper;
use Hash::Util qw(lock_keys);
use Moose;
use Sys::Virt::Network;

use XML::LibXML;

with 'Ravada::NetInterface';

###########################################################################

has 'interface' => (
    isa => 'IO::Interface::Simple'
    ,is => 'ro'
    ,required => 1
);

###########################################################################

=head2 type

Returns the type for the interface in the domain

=cut

sub type {
    return 'direct';
}


=head2 xml_source

Returns the XML description for the domain source tag

=cut

sub xml_source {
    my $self = shift;
    return "<source dev='".$self->interface->name."' mode='".$self->mode."'/>"
}

sub source {
    my $self = shift;
    return { 
          dev => $self->interface->name 
        ,mode => $self->mode
    };
}

sub mode {
    return 'bridge';
}

1;
