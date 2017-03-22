package Ravada::NetInterface::KVM;

use warnings;
use strict;

=head1 NAME

Ravada::NetInterface::KVM - KVM network interface management API for Ravada

=cut

use Carp qw(cluck confess croak);
use Data::Dumper;
use Hash::Util qw(lock_keys);
use Moose;

use XML::LibXML;

with 'Ravada::NetInterface';

###########################################################################

has 'name' => (
    isa => 'Str'
    ,is => 'ro'
);
#
#

###########################################################################

sub BUILD {
}


=head2 type

Returns the type for the interface in the domain

=cut

sub type {
    return 'network';
}


=head2 xml_source

Returns the XML description for the domain source tag

=cut

sub xml_source {
    my $self = shift;

    return "<source network=\"".$self->name."\"/>";

}

=head2 source

Returns a hash with the attributes of the source element

=cut


sub source {
    my $self = shift;
    return { network => $self->name };
}

1;

