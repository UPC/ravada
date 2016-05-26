package Ravada::Auth::LDAP;

use strict;
use warnings;

use Moose;
use Net::LDAP;
use Net::Domain qw(hostdomain);

with 'Ravada::Auth::User';

our $LDAP;
our $BASE;
our @OBJECT_CLASS = ('top'
                    ,'organizationalPerson'
                    ,'person'
                    ,'inetOrgPerson'
                   );

our $GID = 500;

sub add_user {
    my ($name, $password, $is_admin) = @_;

    my ($givenName, $sn) = $name =~ m{(\w+)\.(.*)};

    my %entry = (
        cn => $name
        , uid => $name
#        , uidNumber => _new_uid()
#        , gidNumber => $GID
        , objectClass => [@OBJECT_CLASS]
        , givenName => ($givenName or $name)
        , sn => ($sn or $name)
#        , homeDirectory => "/home/$name"
    );
    my $dn = "cn=$name,"._dc_base();

    my $mesg = $LDAP->add($dn, attr => [%entry]);
    if ($mesg->code) {
        die "Error afegint $name ".$mesg->error;
    }
}

sub _new_uid {
    my $n = rand(1000)+1000;

    return $n;
}

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
    die "not found" if not $search->count;

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
    my ($cn, $pass) = @_;
    $pass = '' if !defined $pass;

    # TODO ping ldap and reconnect
    return $LDAP if $LDAP;

    my ($host, $port) = ('localhost', 389);

    $LDAP = Net::LDAP->new($host, port => $port, verify => 'none') 
        or die "I can't connect to LDAP server at $host / $port : $@";

    if ($cn) {
        warn "Binding with $cn / $pass\n";
        my $mesg = $LDAP->bind($cn, password => $pass);
        die "ERROR: ".$mesg->code." : ".$mesg->error. " : Bad credentials for $cn\n"
            if $mesg->code;

    }

    return $LDAP;
}

sub is_admin {
    my $self = shift;
}

sub init {
}

1;
