package Ravada::NetInterface::Void;

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
#
sub type { return 'void' };

=head2 xml_source

    Returns the XML for the network Interface

=cut

sub xml_source {
    return '<source network="void"/>';
}

sub source {
    return { network => 'void' };
}

1;

