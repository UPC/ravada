package Ravada::VM::Proxmox;

=head1 NAME

Ravada::VM::Proxmox - Direct integration with Proxmox

=cut

use Carp qw(croak carp cluck);
use Data::Dumper;

use Moose;

#use Ravada::Domain::Proxmox
use Ravada::Utils

#with 'Ravada::VM';

has type => (
    is => 'ro'
    ,isa => 'Str'
    ,default => 'Proxmox'
);

############################################################################

sub connect {
    return 1;
}

1;
