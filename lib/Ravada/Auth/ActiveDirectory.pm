package Ravada::Auth::ActiveDirectory;

use strict;
use warnings;

=head1 NAME

Ravada::Auth::ActiveDirectory - AD library for Ravada

=cut

use Carp qw(carp);
use Data::Dumper;
use Digest::SHA qw(sha1_hex);
use Moose;

use Ravada::Auth::SQL;

with 'Ravada::Auth::User';

our $CONFIG = \$Ravada::CONFIG;

sub add_user {
    die "TODO";
}

sub is_admin {
    die "TODO";
}

sub is_external {
    return 1;
}

1;
