package Ravada::Auth::LDAP;

use strict;
use warnings;

=head1 NAME

Ravada::Auth::LDAP - LDAP library for Ravada

=cut

use Authen::Passphrase;
use Authen::Passphrase::SaltedDigest;
use Carp qw(carp croak);
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

our @OBJECT_CLASS_POSIX = (@OBJECT_CLASS,'posixAccount');

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

=head2 add_user_posix

Adds a new user in the LDAP directory

    Ravada::Auth::LDAP::add_user_posix($name, $password);

=cut

sub add_user_posix(%args) {
    my $name = delete $args{name} or croak "Error: missing name";
    my $password = delete $args{password} or croak "Error: missing password";
    my $gid = (delete $args{gid} or _get_gid());
    my $storage = ( delete $args{storage} or 'rfc2307');
    my $algorithm = delete $args{algorithm};
    confess "Error : unknown args ".dumper(\%args) if keys %args;

    _init_ldap_admin();

    $name = escape_filter_value($name);
    $password = escape_filter_value($password);

    confess "No dc base in config ".Dumper($$CONFIG->{ldap})
        if !_dc_base();
    my ($givenName, $sn) = $name =~ m{(\w+)\.(.*)};

    my %entry = (
        cn => $name
        , uid => $name
        , uidNumber => _new_uid()
        , gidNumber => $gid
        , objectClass => \@OBJECT_CLASS_POSIX
        , givenName => ($givenName or $name)
        , sn => ($sn or $name)
        ,homeDirectory => "/home/$name"
        ,userPassword => _password_store($password, $storage, $algorithm)
    );
    my $dn = "cn=$name,"._dc_base();

    my $mesg = $LDAP_ADMIN->add($dn, attr => [%entry]);
    if ($mesg->code) {
        die "Error afegint $name to $dn ".$mesg->error;
    }
}

sub _get_gid() {
    my @group = search_group(name => "*");
    my ($group_users) = grep { $_->get_value('cn') eq 'users' } @group;
    $group_users = $group[0] if !$group_users;
    if (!$group_users) {
        add_group('users');
        ($group_users) = search_group(name => 'users');
        confess "Error: I can create nor find LDAP group 'users'" if !$group_users;
    }
    return $group_users->get_value('gidNumber');
}

sub _new_uid($ldap=_init_ldap_admin(), $base=_dc_base()) {

    my $id = 1000;
    for (;;) {
        my $mesg = $ldap->search(      # Search for the user
            base   => $base,
            scope  => 'sub',
            filter => "uidNumber=$id",
            typesonly => 0,
            attrs  => ['*']
        );

        confess "LDAP error ".$mesg->code." ".$mesg->error if $mesg->code;

        my @entries = $mesg->entries;
        return $id if !scalar @entries;
        $id++;
        $id+= int(rand(10))+1;
    }
}

sub _password_store($password, $storage, $algorithm=undef) {
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
    my $escape_username = 1;
    $escape_username = delete $args{escape_username} if exists $args{escape_username};
    my $filter_orig = delete $args{filter};
    my $sizelimit = (delete $args{sizelimit} or 100);
    my $timelimit = (delete $args{timelimit} or 60);

    confess "ERROR: Unknown fields ".Dumper(\%args) if keys %args;
    confess "ERROR: I can't connect to LDAP " if!$ldap;

    $username = escape_filter_value($username) if $escape_username;
    $username =~ s/ /\\ /g;

    my $filter = "($field=$username)";
    if (!defined $filter_orig && exists $$CONFIG->{ldap}->{filter} ) {
        my $filter_config = $$CONFIG->{ldap}->{filter};
        $filter = "(&($field=$username) ($filter_config))";
    } else {
        $filter = "(&($field=$username) ($filter_orig))" if $filter_orig;
    }

    my $mesg = $ldap->search(      # Search for the user
    base   => $base,
    scope  => 'sub',
    filter => $filter,
    typesonly => $typesonly,
    attrs  => ['*'],
    sizelimit => $sizelimit,
    timelimit => $timelimit

    );

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
              ,filter => $filter_orig
              ,sizelimit => $sizelimit
         );
    }

    die "ERROR: ".$mesg->code." : ".$mesg->error
        if $mesg->code;

    return if !$mesg->count();

    my @entries = $mesg->entries;
    return $entries[0] if !wantarray;
    return @entries;
}

=head2 add_group

Add a group to the LDAP

=cut

sub add_group($name, $base=_dc_base(), $class=['groupOfUniqueNames','nsMemberOf','posixGroup','top' ]) {
    my $ldap = _init_ldap_admin();
    $base = _dc_base() if !defined $base;
    $name = escape_filter_value($name);
    my $oc_posix_group;
    $oc_posix_group = grep { /^posixGroup$/ } @$class;

    my @attrs =( cn=>$name
                    ,objectClass => $class
                    ,description => "Group for $name"
    );
    push @attrs, (gidNumber => _search_new_gid()) if $oc_posix_group;

    my @data = (
        dn => "cn=$name,ou=groups,$base"
        , cn => $name
        , attrs => \@attrs
      );
    my $mesg = $ldap->add(@data);
    if ($mesg->code) {
        die "Error creating group $name : ".$mesg->error."\n".Dumper(\@data);
    }

}

sub _search_new_gid() {
    my %gid;
    for my $group (  search_group( name => '*' ) ) {
        my $gid_number = $group->get_value('gidNumber');
        next if !$gid_number;
        $gid{$gid_number}++;
    }
    my $new_gid = 100;
    for (;;) {
        return $new_gid if !$gid{$new_gid};
        $new_gid++;
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

    my $name = delete $args{name} or confess "Error: missing name";
    my $base = ( delete $args{base} or "ou=groups,"._dc_base() );
    my $ldap = ( delete $args{ldap} or _init_ldap_admin());
    my $retry =( delete $args{retry} or 0);

    confess "ERROR: Unknown fields ".Dumper(\%args) if keys %args;
    confess "ERROR: I can't connect to LDAP " if!$ldap;
    my $filter = "cn=$name";
    my $mesg = $ldap ->search (
        filter => $filter
         ,base => $base
         ,sizelimit => 100
    );
    warn "LDAP retry ".$mesg->code." ".$mesg->error." [filter: $filter , base: $base]" if $retry > 1;
    if ($mesg->code == 4 ) {
        if ( $name eq '*' ) {
            $name = 'a*';
        } elsif ($name eq 'a*' ) {
            $name = 'a*a*';
        } else {
            die "LDAP error: ".$mesg->code." ".$mesg->error;
        }
        return search_group(
            name => $name
            ,base => $base
            ,ldap => $ldap
            ,retry => $retry+1
        );
    }

    if ( $retry <= 3 && $mesg->code){
        warn "LDAP error ".$mesg->code." ".$mesg->error.". [cn=$name] "
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
    return @entries if wantarray;

    return $entries[0];
}

=head2 search_group_members

=cut

sub search_group_members($cn, $retry = 0) {
    my $base = "ou=groups,"._dc_base();
    my $ldap = _init_ldap_admin();
    my $mesg = $ldap ->search (
        filter => "memberuid=$cn"
         ,base => $base
         ,sizelimit => 100
    );
    if ( ($mesg->code == 1 || $mesg->code == 81) && $retry <3 ) {
        $LDAP_ADMIN = undef;
        return search_group_members($cn, $retry+1);
    }
    warn $mesg->code." ".$mesg->error." [base: $base]" if $mesg->code;

    my @entries = map { $_->get_value('cn') } $mesg->entries();

    $mesg = $ldap ->search (
        filter => "member=cn=$cn,"._dc_base()
         ,base => $base
         ,sizelimit => 100
    );
    my @entries2 = map { $_->get_value('cn') } $mesg->entries();

    return (sort (@entries,@entries2));
}

=head2 add_to_group

Adds user to group

    add_to_group($dn, $group_name);

=cut

sub add_to_group {
    my ($dn, $group_name) = @_;
    if ( $dn !~ /=.*,/ ) {
        my $user = search_user(name => $dn, field => 'uid');
        $user = search_user(name => $dn, field => 'cn') if !$user;

        confess "Error: user '$dn' not found" if !$user;
        $dn = $user->dn;
    }

    my $group = search_group(name => $group_name, ldap => $LDAP_ADMIN)   
        or die "No such group $group_name";

    if ( grep {/^groupOfNames$/} $group->get_value('objectClass') ) {
        $group->add(member => $dn)
    } elsif ( grep {/^posixGroup$/} $group->get_value('objectClass') ) {
        my ($cn) = $dn =~ /^cn=(.*?),/;
        ($cn) = $dn =~ /^uid=(.*?),/ if !$cn;
        die "Error: I can't find cn in $dn" if !$cn;
        my @attributes = $group->attributes;
        my $attribute;
        for (qw(uniqueMember memberUid)) {
            $attribute = $_ if grep /^$_$/,@attributes;
        }
        ($attribute) = grep /member/i,@attributes if !$attribute;
        if ($attribute eq 'memberUid') {
            $group->add($attribute => $cn);
        } else {
            $group->add($attribute => $dn);
        }
    } else {
        die "Error: group $group_name class unknown ".Dumper($group->get_value('objectClass'));
    }
    my $mesg = $group->update($LDAP_ADMIN);
    die "Error: adding member ".$dn." ".$mesg->error if $mesg->code;

}

=head2 remove_from_group

Removes user from group

    add_to_group($dn, $group_name);

=cut

sub remove_from_group {
    my ($dn, $group_name) = @_;

    my $group = search_group(name => $group_name, ldap => $LDAP_ADMIN)
        or die "No such group $group_name";

    my $found = 0;
    for my $attribute ( $group->attributes() ) {
        next if $attribute !~ /member/i;
        my $uid = $dn;
        $uid =~s/.*?=(.*?),.*/$1/ if $attribute eq 'memberUid';
        my $mesg  = $group->delete($attribute => $uid )->update(_init_ldap_admin());

        die "Error: [".$mesg->code."] removing $uid from $group_name - $attribute ".$mesg->error
        if $mesg->code;

        $found++;

    }
    die "Error: group $group_name class unknown ".Dumper($group->get_value('objectClass'))
    if !$found;

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

=head2 group_members

Returns a list of the group members

=cut

sub group_members {
    return _group_members(@_);
}

sub _group_members($group_name = $$CONFIG->{ldap}->{group}) {
    my $group = $group_name;
    if (!ref($group)) {
        $group = search_group(name => $group_name);
        if (!$group) {
            confess "Warning: group $group_name not found";
            return;
        }
    }
    confess "Error: invalid object ".ref($group) if ref($group)!~ /^Net::LDAP/;
    my @oc = $group->get_value('objectClass');

    my @members;
    for my $attribute ($group->attributes) {
        next if $attribute !~ /member/i;
        push @members, $group->get_value($attribute);
    }
    my %members = map { $_ => 1 } @members;
    @members = sort keys %members;
    return @members;
}

sub _check_posix_group($self) {
    my $posix_group_name = $$CONFIG->{ldap}->{ravada_posix_group};
    return 1 if !$posix_group_name;

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
}

sub login($self) {
    my $user_ok;
    my $allowed;

    return if !$self->_check_posix_group();

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
    my %user = map { $_->dn => $_ } @user;

    my @error;
    for my $dn ( sort keys %user ) {
        if ($$CONFIG->{ldap}->{group} && !is_member($dn,$$CONFIG->{ldap}->{group})) {
            push @error, ("Warning: $dn does not belong to group $$CONFIG->{ldap}->{group}");
            next;
        }
        $found++;
        my $ldap;
        eval { $ldap = _connect_ldap($dn, $password) };
        warn "ERROR: Bad credentials for $dn"
            if $Ravada::DEBUG && $@;
        if ( $ldap ) {
            $self->{_auth} = 'bind';
            $self->{_ldap_entry} = $user{$dn} if $user{$dn};
            return 1;
        }
        push @error,("ERROR: Bad credentials for $dn");
    }
    warn Dumper(\@error)
            if $Ravada::DEBUG && scalar (@error);
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

    my @error;
    for my $entry (@entries) {

        if ($$CONFIG->{ldap}->{group} && !is_member($entry->dn,$$CONFIG->{ldap}->{group})) {
            push @error, ("Warning: ".$entry->dn.." does not belong to group $$CONFIG->{ldap}->{group}");
            next;
        }
#       my $mesg;
#       eval { $mesg = $LDAP->bind( $user_dn, password => $password )};
#       return 1 if $mesg && !$mesg->code;

#       warn "ERROR: ".$mesg->code." : ".$mesg->error. " : Bad credentials for $username";
        eval { $user_ok = $self->_match_password($entry, $password) };
        warn $@ if $@;

        if ( $user_ok ) {
            $self->{_ldap_entry} = $entry;
            last;
        }
    }

    if ($user_ok) {
        $self->{_auth} = 'match';
    }

    warn Dumper(\@error)
            if $Ravada::DEBUG && scalar (@error);
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

    return _match_pbkdf2($password_ldap,$password) if $storage eq 'PBKDF2';
    return _match_ssha($password_ldap,$password) if $storage eq 'SSHA';

    confess "Error: storage $storage can't do match. Use bind.";
}

sub _ntohl {
    return unless defined wantarray;
    confess "Wrong number of arguments ($#_) to " . __PACKAGE__ . "::ntohl, called"
    if @_ != 1 and !wantarray;
    unpack('L*', pack('N*', @_));
}

sub _match_ssha($password_ldap, $password) {
    return Authen::Passphrase->from_rfc2307($password_ldap)->match($password);
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

    } else {
        return;
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


    return is_member($self->name, $admin_group);

}

=head2 is_member

Returns if an user is member of a group

    if (is_member($group, $cn)) {
    }

=cut

sub is_member($cn, $group) {
    my $user;
    my $dn;
    if (ref($cn) && ref($cn) =~ /Net::LDAP::Entry/) {
        $user = $cn;
        $cn = $user->get_value('cn');
        $dn = $user->dn;
    } elsif($cn=~/=.*,/) {
        $dn = $cn;
        $cn =~ s/.*?=(.*?),.*/$1/;
    }

    my @members = _group_members($group);
    return 1 if grep /^$cn$/, @members;

    if (!$dn) {
        if (!$user) {
            for my $field ( 'uid','cn') {
                $user = search_user(name => $cn, field => $field);
                last if $user;
            }
            confess "Error: unknown user '$cn'" if !$user;
        }
        $dn = $user->dn if !$dn;
    }

    return 1 if grep /^$dn$/, @members;

    my $group_name = $group;
    $group_name = $group->dn if ref($group);

    return 0;
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
