use warnings;
use strict;

package Ravada::Auth;

our $LDAP=0;
$Ravada::DEBUG = 1;

use Ravada::Auth::SQL;

eval { 
    require Ravada::Auth::LDAP; 
    $LDAP = 1 
};
warn $@  if $Ravada::DEBUG && $@;
warn "LDAP loaded=$LDAP"    if $Ravada::DEBUG;

sub init {
    my ($config, $db_con) = @_;
    if ($config->{ldap}) {
        Ravada::Auth::LDAP::init($config);
    } else {
        $LDAP = 0;
    }
#    Ravada::Auth::SQL::init($config, $db_con);
}

sub login {
    my ($name, $pass) = @_;

    my $login_ok;
    eval {
        warn "Trying LDAP" if $Ravada::DEBUG;
        $login_ok = Ravada::Auth::LDAP->new(name => $name, password => $pass);
    } if $LDAP;
    return $login_ok if $login_ok;

    warn $@ if $@;
    if ($@ =~ /I can't connect/i) {
        $LDAP = 0;
    }
    return Ravada::Auth::SQL->new(name => $name, password => $pass);
}

1;
