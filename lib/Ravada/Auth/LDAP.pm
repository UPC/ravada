package Ravada::Auth::LDAP;

use strict;
use warnings;

use Net::LDAP;
use Net::Domain qw(hostdomain);

our $LDAP;
our $BASE;

sub login {
    my ($username, $password) = @_;

    _init_ldap();

    my $base = _dc_base();
    my $search = $LDAP->search(      # Search for the user
    base   => $base,
    scope  => 'sub',
    filter => "(&(uid=$username))",
    attrs  => ['dn']
    );
#    die "not found '$username' at '$base'" if not $search->count;
    return if not $search->count;

    my $user_dn = $search->entry->dn;

    warn $user_dn;

    my $mesg = $LDAP->bind( $user_dn, password => $password );
    return 1 if !$mesg->code;

    warn "ERROR: ".$mesg->code." : ".$mesg->error. " : Bad credentials for $username";
    return;
}

sub _dc_base {
    # TODO: from config

    my $base = '';
    for my $part (split /\./,hostdomain()) {
        $base .= "," if $base;
        $base .= "dc=$part";
    }
    return $base;
}

sub _init_ldap {
    # TODO ping ldap and reconnect
    return if $LDAP;

    my ($host, $port) = ('localhost', 389);

    $LDAP = Net::LDAP->new($host, port => $port, verify => 'none') 
        or die "I can't connect to LDAP server at $host / $port : $@";
}

1;
