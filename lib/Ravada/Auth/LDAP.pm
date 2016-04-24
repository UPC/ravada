package Ravada::Auth::LDAP;

use Net::LDAPS;

our $LDAP;

sub login {
    my ($username, $password) = @_;

    _init_ldap();

    my $search = $ldap->search(      # Search for the user
    base   => 'DC=casa,DC=guru',
    scope  => 'sub',
    filter => "(&(uid=$username))",
    attrs  => ['dn']
    );
    die "not found" if not $search->count;

    my $user_dn = $search->entry->dn;

    warn $user_dn;

    $LDAP->bind( $user_dn, password => $pass );
    return 1 if !$ldap->error;
    warn "ERROR: ".$ldap->error. "Bad credentials for $username";
    return;
}

sub _init_ldap {
    # TODO ping ldap and reconnect
    return if $LDAP;

    my ($host, $port) = ('localhost', 389);

    $LDAP = Net::LDAPS->new($host, port => $port, verify => 'none') 
        or die "I can't connect to LDAP server at $host / $port : $@";
}

1;
