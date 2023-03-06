package Ravada::Auth;

use warnings;
use strict;

our $LDAP_OK;
our $SSO_OK;

use Ravada::Auth::SQL;

=head1 NAME

Ravada::Auth - Authentication library for Ravada users

=cut

=head2 init

Initializes the submodules

=cut

sub init {
    my ($config, $db_con) = @_;
    if (exists $config->{ldap} && $config->{ldap} && (!defined $LDAP_OK || $LDAP_OK) ) {
        eval {
            $LDAP_OK = 0;
            require Ravada::Auth::LDAP;
            Ravada::Auth::LDAP::init($config);
            $LDAP_OK = 1;
        };
        warn $@ if $@;
    } else {
        $LDAP_OK = 0;
    }

    if (exists $config->{sso} && $config->{sso} && (!defined $SSO_OK || $SSO_OK) ) {
        eval {
		    $SSO_OK = 0;
            require Ravada::Auth::SSO;
            Ravada::Auth::SSO::init($config);
            $SSO_OK = 1;
        };
        warn $@ if $@;
    } else {
        $SSO_OK = 0;
    }

#    Ravada::Auth::SQL::init($config, $db_con);
}

=head2 login

Tries login in all the submodules

    my $ok = Ravada::Auth::login($name, $pass);

=cut

sub login {
    my ($name, $pass, $quiet) = @_;

    my ($login_ok, $ldap_err);
    if (!defined $LDAP_OK || $LDAP_OK) {
        eval {
            $login_ok = Ravada::Auth::LDAP->new(name => $name, password => $pass);
        };
        $ldap_err = $@ if $@ && $LDAP_OK && !$quiet;
        if ( $login_ok ) {
            warn $ldap_err if $ldap_err && $LDAP_OK && !$quiet;
            return $login_ok;
        }
    }
    my $sql_login = Ravada::Auth::SQL->new(name => $name, password => $pass);
    unless ($sql_login) {
        warn $ldap_err if $ldap_err && $LDAP_OK && !$quiet;
    }
    return $sql_login;
}

=head2 login_external

Tries login_external in all the submodules

    my $ok = Ravada::Auth::login_external();

=cut

sub login_external {
    my ($ticket, $cookie, $quiet) = @_;

    my $login_ok;
    if (!defined $SSO_OK || $SSO_OK) {
        eval {
            $login_ok = Ravada::Auth::SSO::login_external($ticket, $cookie);
        };
        warn $@ if $@ && $SSO_OK && !$quiet;
        if ( $login_ok ) {
            $login_ok->{'mode'} = 'external';
            return $login_ok;
        }
    }
    return;
}

=head2 enable_LDAP

Sets or get LDAP support.

    Ravada::Auth::enable_LDAP(0);

    print "LDAP is supported" if Ravada::Auth::enable_LDAP();

=cut

sub enable_LDAP {
    my $value = shift;
    return $LDAP_OK if !defined $value;

    $LDAP_OK = $value;
    return $value;
}

=head2 enable_SSO

Sets or get SSO support.

    Ravada::Auth::enable_SSO(0);

    print "SSO is supported" if Ravada::Auth::enable_SSO();

=cut

sub enable_SSO {
    my $value = shift;
    return $SSO_OK if !defined $value;

    $SSO_OK = $value;
    return $value;
}

1;
