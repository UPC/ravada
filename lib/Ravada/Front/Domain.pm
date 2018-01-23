package Ravada::Front::Domain;

use warnings;
use strict;

=head2 NAME

Ravada::Front::Domain - Frontent domain information for Ravada

=cut

use Carp qw(cluck confess croak);
use Moose;

no warnings "experimental::signatures";
use feature qw(signatures);

with 'Ravada::Domain';

sub _do_force_shutdown  { confess "TODO" }
sub add_volume          { confess "TODO" }
sub clean_swap_volumes  { confess "TODO" }
sub disk_device         { confess "TODO" }
sub disk_size           { confess "TODO" }
sub display             { confess "TODO" }
sub force_shutdown      { confess "TODO" }
sub get_info            { confess "TODO" }
sub hybernate           { confess "TODO" }
sub is_active           { confess "TODO" }
sub is_hibernated       { confess "TODO" }
sub is_paused           { confess "TODO" }
sub is_removed          { confess "TODO" }
sub list_volumes        { confess "TODO" }
sub name                { confess "TODO" }
sub pause               { confess "TODO" }
sub prepare_base        { confess "TODO" }
sub remove              { confess "TODO" }
sub rename              { confess "TODO" }
sub resume              { confess "TODO" }
sub screenshot          { confess "TODO" }
sub set_max_mem         { confess "TODO" }
sub set_memory          { confess "TODO" }
sub shutdown            { confess "TODO" }
sub shutdown_now        { confess "TODO" }
sub spinoff_volumes     { confess "TODO" }
sub start               { confess "TODO" }
1;
