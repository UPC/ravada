package Ravada::Volume::ISO;

use Moose;

extends 'Ravada::Volume';

no warnings "experimental::signatures";
use feature qw(signatures);

sub prepare_base($self) {
    return $self->file;
}

sub capacity($self) {
    return undef;
}

1;
