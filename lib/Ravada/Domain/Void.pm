package Ravada::Domain::Void;

use warnings;
use strict;

use Carp qw(cluck croak);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Moose;

with 'Ravada::Domain';

has 'domain' => (
    is => 'ro'
    ,isa => 'Str'
    ,required => 1
);

#######################################3

sub name { 
    my $self = shift;
    return $self->domain;
};

sub display {
    return 'void://hostname:000/';
}

sub is_active {}

sub pause {}
sub remove {}
sub shutdown {}
sub start {}

1;
