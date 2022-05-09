package Ravada::Auth::Kerberos;

use strict;
use warnings;

=head1 NAME

Ravada::Auth::Kerberos - Kerberos library for Ravada

=cut

use Data::Dumper;
use Moose;
use Authen::Krb5::Simple;

no warnings "experimental::signatures";
use feature qw(signatures);

use Ravada::Auth::SQL;

with 'Ravada::Auth::User';

our $CONFIG = \$Ravada::CONFIG;

our $KERBEROS;

sub BUILD($self) {
    die "ERROR: Login failed '".$self->name."'"
        if !$self->login;
}

sub _connect_kerberos($self) {
    return $KERBEROS if $KERBEROS;

    my $server = $$CONFIG->{kerberos}->{server} or die "Error: missing kerberos server in config file";
    $KERBEROS = Authen::Krb5::Simple->connect($server);
}

sub login($self) {
    $self->_connect_kerberos();
    return $KERBEROS->auth($self->login, $self->password);
}

sub add_user($self) {
    die "Error: Not implemented";
}

sub is_admin($self) {
    # This one is probably not necessary because we rely on is_admin
    # field stored in the database
    die "Error: No implemented";
}

sub is_external($self) {
    return 1;
}

sub init($self) {
    $KERBEROS = undef;
}

1;
