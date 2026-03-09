package Ravada::Volume::ISO;

use Moose;

extends 'Ravada::Volume';
with 'Ravada::Volume::Class';

no warnings "experimental::signatures";
use feature qw(signatures);

has 'clone_base_after_prepare' => (
    isa => 'Int'
    ,is => 'rw'
    ,default => sub { 0 }
);

sub prepare_base($self, $req=undef) {
    $self->clone_base_after_prepare(0);
    return $self->file;
}

sub capacity($self) {
    return 1;
}

sub backing_file($self) {
    return;
}

sub clone($self, $filename) {
    confess "Error: ISO file clone is himself because it is read only"
        if $filename ne $self->file;
    return $self->file;
}

sub clone_filename($self, $name=undef) {
    return $self->file;
}

sub base_filename($self) {
    return $self->file;
}

sub spinoff($self) {
    confess "Error: ISO files can't be spinned off";
}

1;
