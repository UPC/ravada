package Ravada::Auth;

use warnings;
use strict;

our $LDAP_OK;
our $CAS_OK;

use Ravada::Auth::SQL;

=head1 NAME

Ravada::Auth - Authentication library for Ravada users

=cut

=head2 init

Initializes the submodules

=cut

sub init {
    my ($config, $db_con) = @_;
    if ($config->{ldap}) {
        eval {
            require Ravada::Auth::LDAP;
            Ravada::Auth::LDAP::init($config);
            $LDAP_OK = 1;
        };
        warn $@ if $@;
    } else {
        $LDAP_OK = 0;
    }

    if ($config->{cas}) {
        eval {
            require Ravada::Auth::CAS;
            Ravada::Auth::CAS::init($config);
            $CAS_OK = 1;
        };
        warn $@ if $@;
    } else {
        $CAS_OK = 0;
    }


#    Ravada::Auth::SQL::init($config, $db_con);
}

=head2 login

Tries login in all the submodules

    my $ok = Ravada::Auth::login($name, $pass);

=cut

sub login {
    my ($name, $pass, $quiet) = @_;

    my $login_ok;
    if (!defined $LDAP_OK || $LDAP_OK) {
        eval {
            $login_ok = Ravada::Auth::LDAP->new(name => $name, password => $pass);
        };
        warn $@ if $@ && $LDAP_OK && !$quiet;
        if ( $login_ok ) {
            return $login_ok;
        }
    }
    return Ravada::Auth::SQL->new(name => $name, password => $pass);
}

=head2 login_external

Tries login_external in all the submodules

    my $ok = Ravada::Auth::login_external();

=cut

sub login_external {
    my ($ticket, $cookie, $quiet) = @_;

    my $login_ok;
    if (!defined $CAS_OK || $CAS_OK) {
        eval {
            $login_ok = Ravada::Auth::CAS::login_external($ticket, $cookie);
        };
        warn $@ if $@ && $CAS_OK && !$quiet;
        if ( $login_ok ) {
            $login_ok->{'mode'} = 'external';
            return $login_ok;
        }
    }
    return undef;
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


=head2 enable_CAS

Sets or get CAS support.

    Ravada::Auth::enable_CAS(0);

    print "CAS is supported" if Ravada::Auth::enable_CAS();

=cut

sub enable_CAS {
    my $value = shift;
    return $CAS_OK if !defined $value;

    $CAS_OK = $value;
    return $value;
}
1;
