package Ravada::Domain::Void;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;

with 'Ravada::Domain';

sub display {}
sub is_active {}

sub name {
    my $self = shift;
    return $self->domain;
}

sub pause {}
sub remove {}
sub shutdown {}
sub start {}

1;
