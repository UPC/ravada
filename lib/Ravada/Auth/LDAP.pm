package Ravada::Auth::LDAP;

use strict;
use warnings;

=head1 NAME

Ravada::Auth::LDAP - LDAP library for Ravada

=cut

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

our $STATUS_EOF = 1;
our $STATUS_DISCONNECTED = 81;
our $STATUS_BAD_FILTER = 89;

=head2 BUILD

Internal OO build

=cut

sub BUILD {
    my $self = shift;
    die "ERROR: Login failed ".$self->name
        if !$self->login;
    return $self;
}

=head2 add_user

Adds a new user in the LDAP directory

    Ravada::Auth::LDAP::add_user($name, $password, $is_admin);

=cut

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

=head2 remove_user

Removes the user

    Ravada::Auth::LDAP::remove_user($name);

=cut

sub remove_user {
    my $name = shift;
    _init_ldap_admin();
    my ($entry) = search_user($name, $LDAP_ADMIN);
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
    my $retry = ( shift or 0 );
    confess "Missing LDAP" if !$ldap;

    my $base = _dc_base();
    my $mesg = $ldap->search(      # Search for the user
    base   => $base,
    scope  => 'sub',
    filter => "(&(uid=$username))",
    attrs  => ['*']
    );

    return if $mesg->code == 32;
    if ( !$retry && (
             $mesg->code == $STATUS_DISCONNECTED 
             || $mesg->code == $STATUS_EOF
            )
     ) {
         warn "LDAP disconnected Retrying ! [$retry]";# if $Ravada::DEBUG;
         $LDAP_ADMIN = undef;
         sleep ($retry + 1);
         _init_ldap_admin();
         return search_user($username,undef, ++$retry);
    }

    die "ERROR: ".$mesg->code." : ".$mesg->error
        if $mesg->code;

    return if !$mesg->count();

    my @entries = $mesg->entries;
#    warn join ( "\n",map { $_->dn } @entries);

    return @entries;
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

=head2 remove_group

Removes the group from the LDAP directory. Use with caution

    Ravada::Auth::LDAP::remove_group($name, $base);

=cut


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

    my @user = search_user($uid)                        or die "No such user $uid";
    warn "Found ".scalar(@user)." users $uid , getting the first one ".Dumper(\@user)
        if scalar(@user)>1;

    my $user = $user[0];

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

    _init_ldap_admin();
    my $user_ok;

    my @entries = search_user($username);

    for my $entry (@entries) {


#       my $mesg;
#       eval { $mesg = $LDAP->bind( $user_dn, password => $password )};
#       return 1 if $mesg && !$mesg->code;

#       warn "ERROR: ".$mesg->code." : ".$mesg->error. " : Bad credentials for $username";
        $user_ok = $self->_match_password($entry, $password);
        warn $entry->dn." : $user_ok" if $Ravada::DEBUG;
        last if $user_ok;
    }

    $self->_check_user_profile($username)   if $user_ok;

    return $user_ok;
}

sub _check_user_profile {
    my $self = shift;
    my $user_sql = Ravada::Auth::SQL->new(name => $self->name);
    return if $user_sql->id;

    Ravada::Auth::SQL::add_user(name => $self->name);
}

sub _match_password {
    my $self = shift;
    my $user = shift;
    my $password = shift or die "ERROR: Missing password for ".$user->get_value('cn'); # We won't allow empty passwords

    _init_ldap_admin();

    die "No userPassword for ".$user->get_value('uid')
        if !$user->get_value('userPassword');
    my $password_ldap = $user->get_value('userPassword');

#    warn $user->get_value('uid')."\n".$user->get_value('userPassword')
#        ."\n"
#        .sha1_hex($password);

    return Authen::Passphrase->from_rfc2307($password_ldap)->match($password);
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
    
    for my $retry ( 1 .. 3 ) {
        if ($port == 636 ) {
            $ldap = Net::LDAPS->new($host, port => $port, verify => 'none') 
        } else {
            $ldap = Net::LDAP->new($host, port => $port, verify => 'none') 
        }
        last if $ldap;
        warn "WARNING: I can't connect to LDAP server at $host / $port : $@ [ retry $retry ]";
        sleep 1 + $retry;
    }
    die "I can't connect to LDAP server at $host / $port : $@"  if !$ldap;

    if ($dn) {
        my $mesg = $ldap->bind($dn, password => $pass);
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
        confess "ERROR: Missing ldap section in config file ".Dumper($$CONFIG)."\n"
    }
    confess "ERROR: Missing ldap -> admin_user -> dn "
        if !$dn;
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


    my ($user) = search_user($self->name);
    my $dn = $user->dn;
    return grep /^$dn$/,$group->get_value('uniqueMember');

}

=head2 init

LDAP init, don't call, does nothing

=cut

sub init {
}

1;
