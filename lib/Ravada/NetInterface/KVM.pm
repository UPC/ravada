package Ravada::NetInterface::KVM;

use warnings;
use strict;

use Carp qw(cluck confess croak);
use Data::Dumper;
use Hash::Util qw(lock_keys);
use Moose;
use Sys::Virt::Network;

use XML::LibXML;

with 'Ravada::NetInterface';

###########################################################################

has '_net' => (
    isa => 'Sys::Virt::Network'
    ,is => 'ro'
);
#
#

###########################################################################

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

    return "<source network=\"".$self->_net->get_name."\"/>";

}

=head2 source

Returns a hash with the attributes of the source element

=cut


sub source {
    my $self = shift;
    return { network => $self->_net->get_name };
}

1;

