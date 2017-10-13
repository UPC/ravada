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
use Auth::ActiveDirectory;

use Ravada::Auth::SQL;

with 'Ravada::Auth::User';

our $CONFIG = \$Ravada::CONFIG;

######################################################3

has host => (
           is => 'ro'
         ,isa => 'Str'
    ,required =>1
);

has port => (
           is => 'ro'
         ,isa => 'Str'
    ,default => 389
);

has timeout => (
            is => 'ro'
         ,isa => 'Str'
    ,default => 60
);

has domain => (
           is => 'ro'
         ,isa => 'Str'
    ,required => 1
);

has principal => (
           is => 'ro'
         ,isa => 'Str'
    ,required => 1
);

#########################################################

sub add_user {
    die "TODO";
}

sub is_admin {
    die "TODO";
}

sub is_external {
    return 1;
}

sub BUILD {
    my $self = shift;

    die "ERROR: Login failed ".$self->name  if !$self->login;
}

sub login {
    my $self = shift;

    my $ad = Auth::ActiveDirectory->new(
       host      => $self->host,
       port      => $self->port || 389,
       timeout   => $self->timeout || 60,
       domain    => $self->domain,
       principal => $self->principal,
    );

    die $ad->error_message if $ad->error_message;

    return $ad->authenticate($self->name, $self->password);
}

1;
