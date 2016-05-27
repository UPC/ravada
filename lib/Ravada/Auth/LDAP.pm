package Ravada::Auth::LDAP;

use strict;
use warnings;

use Authen::Passphrase;
use Authen::Passphrase::SaltedDigest;
use Data::Dumper;
use Digest::SHA qw(sha1_hex);
use Moose;
use Net::LDAP;
use Net::Domain qw(hostdomain);

with 'Ravada::Auth::User';

our $CONFIG = \$Ravada::CONFIG;

our $LDAP;
our $LDAP_ADMIN;
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

    _init_ldap_admin();
    my ($givenName, $sn) = $name =~ m{(\w+)\.(.*)};

    my $apr=Authen::Passphrase::SaltedDigest->new(passphrase => $password, algorithm => "MD5");

    my %entry = (
        cn => $name
        , uid => $name
#        , uidNumber => _new_uid()
#        , gidNumber => $GID
        , objectClass => [@OBJECT_CLASS]
        , givenName => ($givenName or $name)
        , sn => ($sn or $name)
#        , homeDirectory => "/home/$name"
        ,userPassword => $apr->as_rfc2307()
    );
    my $dn = "cn=$name,"._dc_base();

    my $mesg = $LDAP_ADMIN->add($dn, attr => [%entry]);
    if ($mesg->code) {
        die "Error afegint $name ".$mesg->error;
    }
}

sub remove_user {
    my $name = shift;
    _init_ldap_admin();
    my $entry = search_user($name, $LDAP_ADMIN);
    die "ERROR: Entry for user $name not found\n" if !$entry;

#    $LDAP->delete($entry);
#    warn Dumper($entry);
    my $mesg = $LDAP_ADMIN->delete($entry);
    die "ERROR: ".$mesg->code." : ".$mesg->error
        if $mesg->code;

#    $entry->delete->update($LDAP);
}

=head2 search_user

Search user by uid

  my $entry = Ravada::Auth::LDAP::search_user($uid);

=cut

sub search_user {
    my $username = shift;
    _init_ldap();

    my $ldap = (shift or $LDAP);
    confess "Missing LDAP" if !$ldap;

    my $base = _dc_base();
    my $search = $ldap->search(      # Search for the user
    base   => $base,
    scope  => 'sub',
    filter => "(&(uid=$username))",
    attrs  => ['*']
    );
    return if !$search->count();

    return $search->entry;
}

sub login {
    my $self = shift;
    my ($username, $password) = ($self->name , $self->password);

    my $entry = search_user($username);

    my $user_dn = $entry->dn;

    my $mesg = $LDAP->bind( $user_dn, password => $password );
    return 1 if !$mesg->code;

#    warn "ERROR: ".$mesg->code." : ".$mesg->error. " : Bad credentials for $username";
    return $self->_match_password($username, $password);
}

sub _match_password {
    my $self = shift;
    my ($cn, $password) = @_;

    confess "Missing cn" if !$cn;
    confess "Missing password" if !$password;

    _init_ldap_admin();

    my $user = search_user($cn, $LDAP_ADMIN);

    die "No userPassword for ".$user->get_value('uid')
        if !$user->get_value('userPassword');
    my $password_ldap = $user->get_value('userPassword');

    warn $user->get_value('uid')."\n".$user->get_value('userPassword')
        ."\n"
        .sha1_hex($password);

    return $user->get_value('uid') eq $cn
        && Authen::Passphrase->from_rfc2307($password_ldap)->match($password);
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

sub _connect_ldap {
    my ($cn, $pass) = @_;
    $pass = '' if !defined $pass;

    my ($host, $port) = ('localhost', 389);

    my $ldap = Net::LDAP->new($host, port => $port, verify => 'none') 
        or die "I can't connect to LDAP server at $host / $port : $@";

    if ($cn) {
        my $mesg = $ldap->bind($cn, password => $pass);
        die "ERROR: ".$mesg->code." : ".$mesg->error. " : Bad credentials for $cn\n"
            if $mesg->code;

    }

    return $ldap;
}

sub _init_ldap_admin {
    return $LDAP_ADMIN if $LDAP_ADMIN;

    my ($cn, $pass);
    if ($$CONFIG->{ldap} ) {
        ($cn, $pass) = ( $$CONFIG->{ldap}->{cn} , $$CONFIG->{ldap}->{password});
    } else {
        die "Missing ldap section in config file ".Dumper($$CONFIG)."\n"
    }
    $LDAP_ADMIN = _connect_ldap($cn, $pass);
    return $LDAP_ADMIN;
}

sub _init_ldap {
    return if $LDAP;

    $LDAP = _connect_ldap();
}

sub is_admin {
    my $self = shift;
    return;
}

sub init {
}

1;
