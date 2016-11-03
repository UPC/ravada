use warnings;
use strict;

package Ravada::Auth;

our $LDAP;

use Ravada::Auth::SQL;

eval { 
    require Ravada::Auth::LDAP; 
    $LDAP = 1 
};
warn $@  if $Ravada::DEBUG && $@;
warn "LDAP loaded=".($LDAP or '<UNDEF>')    if $Ravada::DEBUG;

=head2 init

Initializes the submodules

=cut

sub init {
    my ($config, $db_con) = @_;
    if ($config->{ldap}) {
        Ravada::Auth::LDAP::init($config);
    } else {
        $LDAP = 0;
    }
#    Ravada::Auth::SQL::init($config, $db_con);
}

=head2 login

Tries login in all the submodules

    my $ok = Ravada::Auth::login($name, $pass);

=cut

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
        $LDAP = 0 if !defined $LDAP;
    }
    return Ravada::Auth::SQL->new(name => $name, password => $pass);
}

=head2 LDAP

Sets or get LDAP support.

    Ravada::Auth::LDAP(0);

    print "LDAP is supported" if Ravada::Auth::LDAP();

=cut

sub LDAP {
    my $value = shift;
    return $LDAP if !defined $value;

    $LDAP = $value;
    return $value;
}
1;
