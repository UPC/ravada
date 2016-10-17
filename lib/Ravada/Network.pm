package Ravada::Network;

use strict;
use warnings;

use Moose;
use MooseX::Types::NetAddr::IP qw( NetAddrIP );
use Moose::Util::TypeConstraints;

use NetAddr::IP;

has 'address' => ( is => 'ro', isa => NetAddrIP, coerce => 1 );

sub allowed {
    my $self = shift;
    my $id_domain = shift;

    my $localnet = NetAddr::IP->new('127.0.0.0','255.0.0.0');

    return 1 if $self->address->within($localnet);

    return 0;
}

1;
