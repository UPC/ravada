package Ravada::Auth::LDAP;

use strict;
use warnings;

use Authen::Passphrase;
use Authen::Passphrase::SaltedDigest;
use Carp qw(carp);
use Data::Dumper;
use Digest::SHA qw(sha1_hex);
use Moose;
use Net::LDAP;
use Net::LDAPS;
use Net::LDAP::Entry;
use Net::Domain qw(hostdomain);

use Ravada::Auth::SQL;

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

    my $ldap = (shift or $LDAP_ADMIN);
    confess "Missing LDAP" if !$ldap;

    my $base = _dc_base();
    my $mesg = $ldap->search(      # Search for the user
    base   => $base,
    scope  => 'sub',
    filter => "(&(uid=$username))",
    attrs  => ['*']
    );

    die "ERROR: ".$mesg->code." : ".$mesg->error
        if $mesg->code;

    return if !$mesg->count();

    my @entry = $mesg->entries;

    return $entry[0];
}

=head2 add_group

Add a group to the LDAP

=cut

sub add_group {
    my $name = shift;
    my $base = (shift or _dc_base());

    my $mesg = $LDAP_ADMIN->add(
        cn => $name
        ,dn => "cn=$name,ou=groups,$base"
        , attrs => [ cn=>$name
                    ,objectClass => ['groupOfUniqueNames','top']
                    ,ou => 'Groups'
                    ,description => "Group for $name"
          ]
    );
    if ($mesg->code) {
        die "Error afegint $name ".$mesg->error;
    }

}

sub remove_group {
    my $name = shift;
    my $base = shift;

    $base = "ou=groups,"._dc_base() if !$base;

    my $entry = search_group(name => $name, base => $base);
    if (!$entry) {
        die "I can't find cn=$name at base: ".($base or _dc_base());
    }
    my $mesg = $LDAP_ADMIN->delete($entry);
    die "ERROR: ".$mesg->code." : ".$mesg->error
        if $mesg->code;
}

=head2 search_group

    Search group by name

=cut

sub search_group {
    my %args = @_;

    my $name = $args{name} or confess "Missing group name";
    my $base = ( $args{base} or "ou=groups,"._dc_base() );
    my $ldap = ( $args{ldap} or $LDAP );

    my $mesg = $ldap ->search (
        filter => "cn=$name"
         ,base => $base
    );
    if ($mesg->code){
        die "ERROR searching for group $name at $base :".$mesg->code." ".$mesg->error;
    }
    my @entries = $mesg->entries;

    return $entries[0]
}

=head2 add_to_group

Adds user to group

    add_to_group($uid, $group_name);

=cut

sub add_to_group {
    my ($uid, $group_name) = @_;

    my $user = search_user($uid)                        or die "No such user $uid";
    my $group = search_group(name => $group_name, ldap => $LDAP_ADMIN)   
        or die "No such group $group_name";

    $group->add(uniqueMember=> $user->dn);
    my $mesg = $group->update($LDAP_ADMIN);
    die $mesg->error if $mesg->code;

}

=head2 login

    $user->login($name, $password);

=cut

sub login {
    my $self = shift;
    my ($username, $password) = ($self->name , $self->password);

    my $entry = search_user($username);

    my $user_dn;
    eval { $user_dn = $entry->dn };
    die "Failed fetching user $username dn" if !$user_dn;

    my $mesg;
#    eval { $mesg = $LDAP->bind( $user_dn, password => $password )};
    return 1 if $mesg && !$mesg->code;

#    warn "ERROR: ".$mesg->code." : ".$mesg->error. " : Bad credentials for $username";
    my $user_ok = $self->_match_password($username, $password);

    $self->_check_user_profile($username)   if $user_ok;

    return $user_ok;
}

sub _check_user_profile {
    my $self = shift;
    my $user_sql = Ravada::Auth::SQL->new(name => $self->name);
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

#    warn $user->get_value('uid')."\n".$user->get_value('userPassword')
#        ."\n"
#        .sha1_hex($password);

    return $user->get_value('uid') eq $cn
        && Authen::Passphrase->from_rfc2307($password_ldap)->match($password);
}

sub _dc_base {
    
    return $$CONFIG->{ldap}->{base}
        if $$CONFIG->{ldap}->{base};

    my $base = '';
    for my $part (split /\./,hostdomain()) {
        $base .= "," if $base;
        $base .= "dc=$part";
    }
    return $base;
}

sub _connect_ldap {
    my ($dn, $pass) = @_;
    $pass = '' if !defined $pass;

    my $host = ($$CONFIG->{ldap}->{server} or 'localhost');
    my $port = ($$CONFIG->{ldap}->{port} or 389);

    my $ldap;
    
    if ($port == 636 ) {
        $ldap = Net::LDAPS->new($host, port => $port, verify => 'none') 
            or die "I can't connect to LDAP server at $host / $port : $@";
    } else {
         $ldap = Net::LDAP->new($host, port => $port, verify => 'none') 
            or die "I can't connect to LDAP server at $host / $port : $@";

    }
    if ($dn) {
        my $mesg = $ldap->bind($dn, password => $pass);
        warn "$dn/$pass ".$mesg->error if $mesg->code;
        die "ERROR: ".$mesg->code." : ".$mesg->error. " : Bad credentials for $dn\n"
            if $mesg->code;

    }

    return $ldap;
}

sub _init_ldap_admin {
    return $LDAP_ADMIN if $LDAP_ADMIN;

    my ($dn, $pass);
    if ($$CONFIG->{ldap} ) {
        ($dn, $pass) = ( $$CONFIG->{ldap}->{admin_user}->{dn} 
            , $$CONFIG->{ldap}->{admin_user}->{password});
    } else {
        die "Missing ldap section in config file ".Dumper($$CONFIG)."\n"
    }
    $LDAP_ADMIN = _connect_ldap($dn, $pass) ;
    return $LDAP_ADMIN;
}

sub _init_ldap {
    return if $LDAP;

    $LDAP = _connect_ldap();
}

=head2 is_admin

Returns wether an user is admin

=cut

sub is_admin {
    my $self = shift;
    my $verbose = shift;

    my $admin_group =  $$CONFIG->{ldap}->{admin_group}
        or die "ERROR: Missing ldap -> admin_group entry in the config file\n";
    my $group = search_group(name => $admin_group)
        or do {
            warn "WARNING: I can't find group $admin_group in the LDAP directory\n"
                if $verbose;
            return 0;
        };

    my $dn = search_user($self->name)->dn;
    return grep /^$dn$/,$group->get_value('uniqueMember');

}

sub init {
}

1;
