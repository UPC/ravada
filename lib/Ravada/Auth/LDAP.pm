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
use Digest::SHA qw(sha1_hex sha256_hex);
use Encode;
use PBKDF2::Tiny qw/derive/;
use MIME::Base64;
use Moose;
use Net::LDAP;
use Net::LDAPS;
use Net::LDAP::Entry;
use Net::LDAP::Util qw(escape_filter_value);
use Net::Domain qw(hostdomain);

no warnings "experimental::signatures";
use feature qw(signatures);

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

our $PBKDF2_SALT_LENGTH = 64;
our $PBKDF2_ITERATIONS_LENGTH = 4;
our $PBKDF2_HASH_LENGTH = 256;
our $PBKDF2_LENGTH = $PBKDF2_SALT_LENGTH + $PBKDF2_ITERATIONS_LENGTH + $PBKDF2_HASH_LENGTH;

=head2 BUILD

Internal OO build

=cut

sub BUILD {
    my $self = shift;
    die "ERROR: Login failed '".$self->name."'"
        if !$self->login;
    return $self;
}

=head2 add_user

Adds a new user in the LDAP directory

    Ravada::Auth::LDAP::add_user($name, $password, $is_admin);

=cut

sub add_user($name, $password, $storage='rfc2307', $algorithm=undef ) {

    _init_ldap_admin();

    $name = escape_filter_value($name);
    $password = escape_filter_value($password);

    confess "No dc base in config ".Dumper($$CONFIG->{ldap})
        if !_dc_base();
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
        ,userPassword => _password_store($password, $storage, $algorithm)
    );
    my $dn = "cn=$name,"._dc_base();

    my $mesg = $LDAP_ADMIN->add($dn, attr => [%entry]);
    if ($mesg->code) {
        die "Error afegint $name to $dn ".$mesg->error;
    }
}

sub _password_store($password, $storage, $algorithm) {
    return _password_rfc2307($password, $algorithm) if lc($storage) eq 'rfc2307';
    return _password_pbkdf2($password, $algorithm)  if lc($storage) eq 'pbkdf2';

    confess "Error: Unknown storage '$storage'";

}

sub _password_pbkdf2($password, $algorithm='SHA-256') {
    $algorithm = 'SHA-256' if ! defined $algorithm;

    my $salt = encode('ascii',Ravada::Utils::random_name($PBKDF2_SALT_LENGTH));

    die "wrong salt length ".length($salt)." != $PBKDF2_SALT_LENGTH"
    if length($salt) != $PBKDF2_SALT_LENGTH;

    my $iterations = 1024;
    my $derive = derive($algorithm
        , encode('ascii',$password)
        , $salt
        , $iterations
        , $PBKDF2_HASH_LENGTH);

    my $iterations_n = pack('N', $iterations);

    die "wrong iterations length ".length($iterations_n)." != $PBKDF2_ITERATIONS_LENGTH"
    if length($iterations_n) != $PBKDF2_ITERATIONS_LENGTH;

    my $pbkdf2 = $iterations_n.$salt.$derive;

    die "wrong pass length ".length($pbkdf2)." != $PBKDF2_LENGTH"
    if length($pbkdf2) != $PBKDF2_LENGTH;

    $algorithm =~ s/-//;
    return "\{PBKDF2_$algorithm}"
        .encode_base64($pbkdf2,"");
}

sub _password_rfc2307($password, $algorithm='MD5') {

    my $apr=Authen::Passphrase::SaltedDigest->new(passphrase => $password
        , algorithm => ($algorithm or 'MD5'));
    return $apr->as_rfc2307();
}

=head2 remove_user

Removes the user

    Ravada::Auth::LDAP::remove_user($name);

=cut

sub remove_user {
    my $name = shift;
    _init_ldap_admin();
    my ($entry) = search_user(name => $name);
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
    my %args;

    if ( scalar @_>1 ) {
        %args = @_;
    } else {
        $args{name} = $_[0];
    }

    my $username = delete $args{name} or confess "Missing user name";
    my $retry = (delete $args{retry} or 0);
    my $field = (delete $args{field} or $$CONFIG->{ldap}->{field} or 'uid');
    my $ldap = (delete $args{ldap} or _init_ldap_admin());
    my $base = (delete $args{base} or _dc_base());
    my $typesonly= (delete $args{typesonly} or 0);

    confess "ERROR: Unknown fields ".Dumper(\%args) if keys %args;
    confess "ERROR: I can't connect to LDAP " if!$ldap;

    $username = escape_filter_value($username);
    $username =~ s/ /\\ /g;

    my $filter = "($field=$username)";
    if ( exists $$CONFIG->{ldap}->{filter} ) {
        my $filter_config = $$CONFIG->{ldap}->{filter};
        $filter_config = escape_filter_value($filter_config);
        $filter = "(&($field=$username) ($filter_config))";
    }

    my $mesg = $ldap->search(      # Search for the user
    base   => $base,
    scope  => 'sub',
    filter => $filter,
    typesonly => $typesonly,
    attrs  => ['*']

    );

    warn "LDAP retry ".$mesg->code." ".$mesg->error if $retry > 1;

    if ( $retry <= 3 && $mesg->code && $mesg->code != 4 ) {
         warn "LDAP error ".$mesg->code." ".$mesg->error."."
            ."Retrying ! [$retry]"  if $retry;
         $LDAP_ADMIN = undef;
         sleep ($retry + 1);
         _init_ldap_admin();
         return search_user(
                name => $username
               ,base => $base
              ,field => $field
              ,retry => ++$retry
              ,typesonly => $typesonly
         );
    }

    die "ERROR: ".$mesg->code." : ".$mesg->error
        if $mesg->code;

    return if !$mesg->count();

    return $mesg->entries;
}

=head2 add_group

Add a group to the LDAP

=cut

sub add_group {
    my $name = shift;
    my $base = (shift or _dc_base());

    $name = escape_filter_value($name);

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

    my $name = delete $args{name} or confess "Missing group name";
    my $base = ( delete $args{base} or "ou=groups,"._dc_base() );
    my $ldap = ( delete $args{ldap} or _init_ldap_admin());
    my $retry =( delete $args{retry} or 0);

    confess "ERROR: Unknown fields ".Dumper(\%args) if keys %args;
    confess "ERROR: I can't connect to LDAP " if!$ldap;

    $name = escape_filter_value($name);


    my $mesg = $ldap ->search (
        filter => "cn=$name"
         ,base => $base
    );
    warn "LDAP retry ".$mesg->code." ".$mesg->error if $retry > 1;

    if ( $retry <= 3 && $mesg->code){
        warn "LDAP error ".$mesg->code." ".$mesg->error."."
            ."Retrying ! [$retry]"  if $retry;
         $LDAP_ADMIN = undef;
         sleep ($retry + 1);
         _init_ldap_admin();
         return search_group (
                name => $name
               ,base => $base
              ,retry => ++$retry
         );
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

    my @user = search_user(name => $uid)                        or die "No such user $uid";
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

sub _search_posix_group($self, $name) {
    my $base = 'ou=groups,'._dc_base();
    my $field = 'cn';
    if ($name =~ /(.*?)=(.*)/) {
        $field = $1;
        $name = $2;
        if ($name =~ /(.*?),(.*)/) {
            $name = $1;
            $base = $2;
        }
    }
    my @posix_group = search_user (
        name => $name
        ,base => $base
        ,field => $field
    );
    warn "WARNING: found too many entries for posix_group $name"
    .Dumper([map {$_->dn } @posix_group])
        if (scalar @posix_group > 1);
    return $posix_group[0];
}

sub login($self) {
    my $user_ok;
    my $allowed;
    my $posix_group_name = $$CONFIG->{ldap}->{ravada_posix_group};

    if ($posix_group_name) {
        my $posix_group = $self->_search_posix_group($posix_group_name);
        if (!$posix_group) {
            warn "Warning: posix group $posix_group_name not found";
            return;
        }
        my @member = $posix_group->get_value('memberUid');
        my $user_name = $self->name;
        my ($found) = grep /^$user_name$/,@member;
        if (!$found) {
            warn "Error: $user_name is not a member of posix group $posix_group_name\n";
            warn Dumper(\@member) if $Ravada::DEBUG;
            return;
        }
        $self->{_ldap_entry} = $posix_group;
    }

        $user_ok = $self->_login_bind()
        if !exists $$CONFIG->{ldap}->{auth} || $$CONFIG->{ldap}->{auth} =~ /bind|all/i;

        $user_ok = $self->_login_match()
            if !$user_ok && exists $$CONFIG->{ldap}->{auth}
            && $$CONFIG->{ldap}->{auth} =~ /match|all/i;

        $self->_check_user_profile($self->name)   if $user_ok;
        $LDAP_ADMIN->unbind if $LDAP_ADMIN && exists $self->{_auth} && $self->{_auth} eq 'bind';
        return $user_ok;
}

sub _login_bind {
    my $self = shift;

    my ($username, $password) = ($self->name , $self->password);

    my $found = 0;

    my @user;
    if (exists $$CONFIG->{ldap}->{field} && defined $$CONFIG->{ldap}->{field} ) {
        @user = search_user( name => $self->name );
    } else {
        @user = (search_user(name => $self->name, field => 'uid')
                ,search_user(name => $self->name, field => 'cn'));
    }
    for my $user (@user) {
        my $dn = $user->dn;
        $found++;
        my $ldap;
        eval { $ldap = _connect_ldap($dn, $password) };
        if ( $ldap ) {
            $self->{_auth} = 'bind';
            $self->{_ldap_entry} = $user;
            return 1;
        }
        warn "ERROR: Bad credentials for $dn"
            if $Ravada::DEBUG && $@;
    }
    return 0;
}

=head2 ldap_entry

Returns the ldap entry as a Net::LDAP::Entry of the user if it has
LDAP external authentication

=cut

sub ldap_entry($self) {
    return $self->{_ldap_entry};
}

sub _login_match {
    my $self = shift;
    my ($username, $password) = ($self->name , $self->password);

    $LDAP_ADMIN = undef;
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
        if ( $user_ok ) {
            $self->{_ldap_entry} = $entry;
            last;
        }
    }

    if ($user_ok) {
        $self->{_auth} = 'match';
    }

    return $user_ok;
}

sub _check_user_profile {
    my $self = shift;
    my $user_sql = Ravada::Auth::SQL->new(name => $self->name);
    if ( $user_sql->id ) {
        if ($user_sql->external_auth ne 'ldap') {
            $user_sql->external_auth('ldap');
        }
        return;
    }

    Ravada::Auth::SQL::add_user(name => $self->name, is_external => 1, is_temporary => 0
        , external_auth => 'ldap');
}

sub _match_password {
    my $self = shift;
    my $user = shift;
    my $password = shift or die "ERROR: Missing password for ".$user->get_value('cn'); # We won't allow empty passwords
    confess "ERROR: Wrong entry ".$user->dump
        if !scalar($user->attributes);

    die "ERROR: No userPassword for ".$user->get_value('uid')
            .Dumper($user)
        if !$user->get_value('userPassword');
    my $password_ldap = $user->get_value('userPassword');

#    warn $user->get_value('uid')."\n".$user->get_value('userPassword')
#        ."\n"
#        .sha1_hex($password);

    my ($storage) = $password_ldap =~ /^{([a-z0-9]+)[_}]/i;
    my ($password_ldap_hex) = $password_ldap =~ /.*?}(.*)/;
    return Authen::Passphrase->from_rfc2307($password_ldap)->match($password)
        if $storage =~ /rfc2307|md5/i;

    return _match_pbkdf2($password_ldap,$password) if $storage =~ /pbkdf2|SSHA/i;

    confess "Error: storage $storage can't do match. Use bind.";
}

sub _ntohl {
    return unless defined wantarray;
    confess "Wrong number of arguments ($#_) to " . __PACKAGE__ . "::ntohl, called"
    if @_ != 1 and !wantarray;
    unpack('L*', pack('N*', @_));
}

sub _match_pbkdf2($password_db_64, $password) {

    my ($sign,$password_db) = $password_db_64 =~ /(\{.*?})(.*)/;
    $password_db=decode_base64($password_db);

    my ($algorithm,$n) = $sign =~ /_(.*?)(\d+)}/;

    die "password_db length wrong: ".length($password_db)
    ." != $PBKDF2_LENGTH"
        if length($password_db) != $PBKDF2_LENGTH;

    my ($iterations_db) = substr($password_db, 0, $PBKDF2_ITERATIONS_LENGTH);
    my $iterations = unpack 'V', $iterations_db;
    ($iterations) = _ntohl($iterations);

    my ($salt)
    = substr($password_db, $PBKDF2_ITERATIONS_LENGTH, $PBKDF2_SALT_LENGTH);
    my $derive = derive("$algorithm-$n", encode('ascii',$password), $salt
        , $iterations, $PBKDF2_HASH_LENGTH);

    my $match = $sign.encode_base64($iterations_db.$salt.$derive,"");

    return $password_db_64 eq $match;

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
    my $secure = 0;
    if (exists $$CONFIG->{ldap}->{secure} && defined $$CONFIG->{ldap}->{secure}) {
        $secure = $$CONFIG->{ldap}->{secure};
        $secure = 0 if $secure =~ /false|no/i;
    } else {
        $secure = 1 if $port == 636;
    }
    my $ldap;
    
    for my $retry ( 1 .. 3 ) {
        if ($secure ) {
            $ldap = _connect_ldaps($host, $port);
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

sub _connect_ldaps($host, $port) {
    my @args;
    push @args,(sslversion => $$CONFIG->{ldap}->{sslversion})
    if exists $$CONFIG->{ldap}->{sslversion};

    return Net::LDAPS->new($host, port => $port, verify => 'none'
        ,@args
    )

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
    return if !$dn;
    $LDAP_ADMIN = _connect_ldap($dn, $pass) ;
    return $LDAP_ADMIN;
}

sub _init_ldap {
    return $LDAP if $LDAP;

    $LDAP = _connect_ldap();
    return $LDAP;
}

=head2 is_admin

Returns wether an user is admin

=cut

sub is_admin {
    my $self = shift;
    my $verbose = shift;

    my $admin_group =  $$CONFIG->{ldap}->{admin_group} or return;
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

=head2 is_external

Returns true if the user authentication is external to SQL, so true for LDAP users always

=cut

sub is_external { return 1 }

=head2 init

LDAP init, don't call, does nothing

=cut

sub init {
    $LDAP = undef;
    $LDAP_ADMIN = undef;
}

1;
