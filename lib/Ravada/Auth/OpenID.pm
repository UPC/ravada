package Ravada::Auth::OpenID;

use strict;
use warnings;

use Data::Dumper;

use Ravada::Front;

=head1 NAME

Ravada::Auth::OpenID - OpenID library for Ravada

=cut

use Moose;

no warnings "experimental::signatures";
use feature qw(signatures state);

use Ravada::Auth::SQL;

with 'Ravada::Auth::User';

our $CONFIG = \$Ravada::CONFIG;
our $ERR;

sub BUILD {
    my $self = shift;
    die sprintf('ERROR: Login failed %s', $self->name)
        if !$self->login();
    return $self;
}

sub add_user($name, $password, $storage='rfc2307', $algorithm=undef) { }

sub remove_user { }

sub search_user { }

sub _check_user_profile($self) {
    my $user_sql = Ravada::Auth::SQL->new(name => $self->name);
    if ( $user_sql->id ) {
        if ($user_sql->external_auth ne 'openid') {
            $user_sql->external_auth('openid');
        }
        return $user_sql;
    }

    return if ! Ravada::Front::setting(undef,'/frontend/auto_create_users');

    Ravada::Auth::SQL::add_user(name => $self->name, is_external => 1, is_temporary => 0
        , external_auth => 'openid');

    return $user_sql;
}

sub is_admin { }

sub is_external { }

sub login_external($name, $header) {

    for my $field (qw(OIDC_CLAIM_exp OIDC_access_token_expires)) {
        if ( exists $header->{$field} && defined $header->{$field} && $header->{$field} < time() ) {
            warn localtime($header->{$field})." $field expired \n";
            return 0;
        }
    }

    my $self = Ravada::Auth::OpenID->new(name => $name);
    return if !$self->_check_user_profile();
    return $self;
}

sub login($self) {
    my $user_sql = Ravada::Auth::SQL->new(name => $self->name);
    return 1 if $user_sql->external_auth && $user_sql->external_auth eq 'openid';
    return 1;
}

1;
