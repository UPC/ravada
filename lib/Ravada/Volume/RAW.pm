package Ravada::Volume::RAW;

# RAW volumes  are like qcow2 but original won't get clone after prepare base

use Moose;

extends 'Ravada::Volume::QCOW2';

no warnings "experimental::signatures";
use feature qw(signatures);

has 'clone_original' => (
    isa => 'Int'
    ,is => 'ro'
    ,default => sub { 0 }
);

sub base_extension($self) {
    return 'qcow2';
}

1;
