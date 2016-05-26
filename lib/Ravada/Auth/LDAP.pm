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

sub BUILD {
    my $self = shift;
    die "ERROR: Login failed ".$self->name
        if !$self->login;
    return $self;
}

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

sub remove_user {
    my $name = shift;
    my $entry = _search_uid($name);
    $LDAP->delete($entry);
}

sub _search_uid {
    my $username = shift;

    _init_ldap();

    my $base = _dc_base();
    my $search = $LDAP->search(      # Search for the user
    base   => $base,
    scope  => 'sub',
    filter => "(&(uid=$username))",
    attrs  => ['dn']
    );
    die "uid=$username not found" if not $search->count;
    return $search->entry;
}

sub login {
    my $self = shift;
    my ($username, $password) = ($self->name , $self->password);

    my $entry = _search_uid($username);

    my $user_dn = $entry->dn;

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
