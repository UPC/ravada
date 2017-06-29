package Ravada::NetInterface;

use warnings;
use strict;

use Moose::Role;

##############################################################
#
# methods
#

requires 'type';
requires 'source';
requires 'xml_source';

##############################################################
#
# attributes
#

has '_net' => (
    isa => 'Object'
    ,is => 'ro'
);

##############################################################

sub TO_JSON {
    my $self = shift;
    return { type => $self->type , source => $self->source };
}

1;
