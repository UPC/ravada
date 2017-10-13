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

use feature qw(signatures);
no warnings "experimental::signatures";

with 'Ravada::Auth::User';

our $CONFIG = \$Ravada::CONFIG;

######################################################3

our ($HOST, $DOMAIN, $PRINCIPAL);
our ($PORT, $TIMEOUT) = ( 389, 60 );

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

sub init($rvd_conf) {
    my %config = %{$rvd_conf->{ActiveDirectory}};

         $HOST = delete $config{host}     or die "ERROR: host required in ".Dumper($rvd_conf);
       $DOMAIN = delete $config{domain}   or die "ERROR: domain required in ".Dumper($rvd_conf);
    $PRINCIPAL = delete $config{principal}
            or die "ERROR: principal required in ".Dumper($rvd_conf);

    $TIMEOUT = delete $config{timeout}  if exists $config{timeout};
       $PORT = delete $config{port}     if exists $config{port};

    warn "WARNING: Unknown fields ".join(",", keys %config)
        if keys %config;

    return 1;
}

sub login($self) {

    my $ad = Auth::ActiveDirectory->new(
       host      => $HOST,
       port      => $PORT,
       timeout   => $TIMEOUT,
       domain    => $DOMAIN,
       principal => $PRINCIPAL,
    );

    die $ad->error_message if $ad->error_message;

    return $ad->authenticate($self->name, $self->password);
}

1;
