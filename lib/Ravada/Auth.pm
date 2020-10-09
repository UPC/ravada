package Ravada::Auth;

use warnings;
use strict;

our $LDAP_OK;
our $AD;

use feature qw(signatures);
no warnings "experimental::signatures";

use Data::Dumper;
use Ravada::Auth::SQL;

=head1 NAME

Ravada::Auth - Authentication library for Ravada users

=cut

eval {
    require Ravada::Auth::ActiveDirectory;
};
if ($@) {
    warn $@;
    $AD= 0;
}
warn "AD loaded=".($AD or '<UNDEF>')    if $Ravada::DEBUG;

=head2 init

Initializes the submodules

=cut

sub init($config) {
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
    if ($config->{ActiveDirectory}) {
        Ravada::Auth::ActiveDirectory::init($config);
        $AD = 1;
    } else {
        $AD = 0;
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

    $login_ok = _login_ad($name, $pass) if !defined $AD || $AD;
    return $login_ok if $login_ok;

    return Ravada::Auth::SQL->new(name => $name, password => $pass);
}

<<<<<<< HEAD
sub _login_ad {
    my ($name, $pass) = @_;
    my $login_ok;
    eval {
        $login_ok = Ravada::Auth::ActiveDirectory->new(
            name => $name
            , password => $pass);
    };
    warn $@ if $@;

    return $login_ok;
}

=head2 LDAP
=======
=head2 enable_LDAP
>>>>>>> develop

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
1;
