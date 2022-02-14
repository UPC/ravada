use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use YAML qw(LoadFile DumpFile);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');
use_ok('Ravada::Auth::LDAP');

my $ADMIN_GROUP = "test.admin.group";
my $RAVADA_POSIX_GROUP = "rvd_posix_group";
my @FILTER = ("sn=bar", '&(sn=bar)(sn=bar)');

my ($LDAP_USER , $LDAP_PASS) = ("cn=Directory Manager","saysomething");

init();

my @USERS;

sub test_user_fail {
    my $user_fail;
    eval { $user_fail = Ravada::Auth::LDAP->new(name => 'root',password => 'fail')};
    
    ok(!$user_fail,"User should fail, got ".Dumper($user_fail));
}
    

sub _remove_user_ldap($name) {
    eval { Ravada::Auth::LDAP::remove_user($name) };
    ok(!$@ || $@ =~ /Entry.* not found/i) or exit;

    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    my $base = Ravada::Auth::LDAP::_dc_base();
    my $mesg = $ldap->search( filter => "cn=$name",base => $base );
    for my $entry ( $mesg->entries ) {
        diag("removing ".$entry->dn." from LDAP");
        my $mesg = $ldap->delete($entry);
        die $mesg->code." ".$mesg->error if $mesg->code && $mesg->code;
    }
}

sub test_user($name, $with_posix_group=0, $password='jameson', $storage=undef, $algorithm=undef) {
    if ( Ravada::Auth::LDAP::search_user($name) ) {
        Ravada::Auth::LDAP::remove_user($name)  
    }
    _remove_user_ldap($name);

    my $user = Ravada::Auth::LDAP::search_user($name);
    ok(!$user,"I shouldn't find user $name in the LDAP server") or return;

    my $user_db = Ravada::Auth::SQL->new( name => $name);
    $user_db->remove();
    # check for the user in the SQL db, he shouldn't be  there
    #
    my $sth = connector->dbh->prepare("SELECT * FROM users WHERE name=?");
    $sth->execute($name);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    ok(!$row->{name},"I shouldn't find $name in the SQL db ".Dumper($row));


    my @options;
    push @options, ( $storage )      if defined $storage;
    push @options, ( $algorithm )  if defined $algorithm;

    eval { Ravada::Auth::LDAP::add_user($name,$password, @options) };
    push @USERS,($name);

    ok(!$@, $@) or return;

    _add_to_posix_group($name, $with_posix_group);

    my $mcnulty;
    eval { $mcnulty = Ravada::Auth::LDAP->new(name => $name,password => $password) };
    is($@,'', Dumper($Ravada::CONFIG)) or confess;

    ok($mcnulty,($@ or "ldap login failed for $name")) or return;
    ok(ref($mcnulty) =~ /Ravada/i,"User must be Ravada::Auth::LDAP , it is '".ref($mcnulty));

    ok(!$mcnulty->is_admin,"User ".$mcnulty->name." should not be admin "
            .Dumper($mcnulty->{_data}));

    ok($mcnulty->ldap_entry,"Expecting User LDAP entry");
    eval { $mcnulty->allowed_access(1) };
    is($@,'');
    # try to login
    my $mcnulty_login = Ravada::Auth::login($name,$password);
    ok($mcnulty_login,"No login");
    ok(ref $mcnulty_login && ref($mcnulty_login) eq 'Ravada::Auth::LDAP',
            "ref should be Ravada::Auth::LDAP , got ".ref($mcnulty_login));
    ok($mcnulty_login->ldap_entry,"Expecting User LDAP entry");
    # check for the user in the SQL db
    # 
    $sth = connector->dbh->prepare("SELECT * FROM users WHERE name=?");
    $sth->execute($name);
    $row = $sth->fetchrow_hashref;
    $sth->finish;
    ok($row->{name} && $row->{name} eq $name 
        && $row->{id},"I can't find $name in the users SQL table ".Dumper($row));

    my $mcnulty_sql = Ravada::Auth::SQL->new(name => $name);
    ok($mcnulty_sql,"I can't find mcnulty in the SQL db");
    ok($mcnulty_sql->{name} eq $name, "Expecting '$name', got $mcnulty_sql->{name}");
    
    # login again to check it doesn't get added twice
 
    my $mcnulty2;
    eval { $mcnulty2 = Ravada::Auth::LDAP->new(name => $name,password => $password) };
    
    ok($mcnulty2,($@ or "ldap login failed for $name")) or return;
    $sth = connector->dbh->prepare("SELECT count(*) FROM users WHERE name=?");
    $sth->execute($name);
    my ($count) = $sth->fetchrow;
    $sth->finish;
    
    ok($count == 1,"Found $count $name, expecting 1");

    my $auth_ok;
    eval { $auth_ok = Ravada::Auth::login($name, $password)};
    is($@,'');
    ok($auth_ok,"Expecting auth_ok: ".Dumper($auth_ok));
    is($auth_ok->is_external,1);

    my $user_sql = Ravada::Auth::SQL->new(name => $name);
    ok($user_sql,"Expecting a SQL user for $name");
    ok($user_sql->is_external,"Expecting is_external");

    $auth_ok = undef;
    eval { $auth_ok = Ravada::Auth::login($name, 'fail','quiet')};
    ok($@,"Expecting fails, got : ".($@ or ''));
    ok(!$auth_ok,"Expecting no auth_ok. got: ".Dumper($auth_ok));

    return $mcnulty;
}

sub remove_users {
    for my $name (@USERS) {
        my $user = Ravada::Auth::LDAP::search_user($name);
        next if !$user;
        Ravada::Auth::LDAP::remove_user($name);

        $user = Ravada::Auth::LDAP::search_user($name);
        ok(!$user,"I shouldn't find user $name in the LDAP server") or return;
    }
}

sub test_add_group {

    Ravada::Auth::LDAP::init();
    my $name = "grup.test";

    Ravada::Auth::LDAP::remove_group($name)
        if Ravada::Auth::LDAP::search_group(name => $name);

    my $group0 = Ravada::Auth::LDAP::search_group(name => $name);
    ok(!$group0,"Group $name shouldn't exist") or return;

    Ravada::Auth::LDAP::add_group($name);

    my $group = Ravada::Auth::LDAP::search_group(name => $name);
    ok($group,"Group $name not created");

    Ravada::Auth::LDAP::remove_group($name) if $group;

    my $group2 = Ravada::Auth::LDAP::search_group(name => $name);
    ok(!$group2,"Group $name not removed");

}

sub test_manage_group {
    my $with_admin = shift;
    my $with_posix_group = shift;

    my $name = $ADMIN_GROUP;

    diag("Testing LDAP admin with group $ADMIN_GROUP enabled= $with_admin");

    Ravada::Auth::LDAP::remove_group($name)
        if Ravada::Auth::LDAP::search_group(name => $name);

    my $group0 = Ravada::Auth::LDAP::search_group(name => $name);
    ok(!$group0,"Group $name shouldn't exist") or return;

    Ravada::Auth::LDAP::add_group($name);

    my $group = Ravada::Auth::LDAP::search_group(name => $name);
    ok($group,"Group $name not created") or return;

    my $uid = 'ragnar.lothbrok';
    my $user = test_user($uid, $with_posix_group);

    my $is_admin;
    eval { $is_admin = $user->is_admin };
    ok(!$@,$@);
    ok(!$is_admin,"User $uid should not be admin");

    Ravada::Auth::LDAP::init();
    Ravada::Auth::LDAP::add_to_group($uid, $name);

    if ($with_admin) {

        my $admin_group = $$Ravada::Auth::LDAP::CONFIG->{ldap}->{admin_group};
        SKIP: {
            if (!$admin_group) {
                diag("Missing admin_group in config file , got : \n"
                        .Dumper($$Ravada::Auth::LDAP::CONFIG->{ldap}));
                skip("No admin group defined",1);
            }
            ok($user->is_admin,"User $uid (".(ref $user).") "
                            ."should be admin, he was added to $name  group")
                            or die Dumper([Ravada::Auth::LDAP::_group_members($name)]);
        };
    }

    Ravada::Auth::LDAP::remove_user($uid);
    Ravada::Auth::LDAP::remove_group($name);

    my $group2 = Ravada::Auth::LDAP::search_group(name => $name);
    ok(!$group2,"Group $name not removed");

}

sub test_user_bind {
    my $user = shift;
    my $file_config = shift;
    my $with_posix_group = shift;

    my $config = LoadFile($file_config);
    $config->{ldap}->{auth} = 'bind';

    my $file_config_bind = "/var/tmp/ravada_test_ldap_bind_$$.conf";
    DumpFile($file_config_bind, $config);
    my $ravada = Ravada->new(config => $file_config_bind
        , connector => connector);

    Ravada::Auth::LDAP::init();

    _add_to_posix_group($user->name, $with_posix_group);

    my $mcnulty;
    eval { $mcnulty = Ravada::Auth::LDAP->new(name => $user->name,password => 'jameson') };
    is($@,'') or die $file_config_bind;

    ok($mcnulty,($@ or "ldap login failed ")) or return;

    is($mcnulty->{_auth}, 'bind');

    test_uid_cn($user, $with_posix_group);

    unlink $file_config_bind;

    $ravada = Ravada->new(config => $file_config
        , connector => connector);

    Ravada::Auth::LDAP::_init_ldap_admin();

}

sub _search_posix_group($ravada_posix_group) {
    my $base = "ou=groups,".Ravada::Auth::LDAP::_dc_base();
    my ($entry) = _search_ldap($ravada_posix_group, $base);
    if (!$entry) {
        _add_posix_group();
        ($entry) = _search_ldap($ravada_posix_group, $base);
    }
    confess "Error, no ravada_posix_group $ravada_posix_group"
    if !$entry;

    return $entry->dn;
}

sub _init_config(%arg) {
    my $with_admin = delete $arg{with_admin};
    my $with_filter = ( delete $arg{with_filter} or 0 );
    my $file_config = delete $arg{file_config};
    my $with_posix_group = delete $arg{with_posix_group};
    my $with_dn_posix_group = delete $arg{with_dn_posix_group};
    my $with_cn_posix_group = delete $arg{with_cn_posix_group};

    confess "Error: unknown args ".Dumper(\%arg) if keys %arg;

    my $ravada_posix_group = $RAVADA_POSIX_GROUP;
    if ( $with_dn_posix_group ) {
         $ravada_posix_group = _search_posix_group($ravada_posix_group);
    } elsif ( $with_cn_posix_group ) {
        $ravada_posix_group = "cn=$ravada_posix_group";
    }
    if ( ! -e $file_config) {
        my $config = {
        ldap => {
            admin_user => { dn => $LDAP_USER , password => $LDAP_PASS }
            ,base => "dc=example,dc=com"
            ,admin_group => $ADMIN_GROUP
            ,auth => 'match'
            ,ravada_posix_group => $ravada_posix_group
        }
        };
        DumpFile($file_config,$config);
    }
    my $config = LoadFile($file_config);
    delete $config->{ldap}->{admin_group}   if !$with_admin;
    if ($with_posix_group) {
            $config->{ldap}->{ravada_posix_group} = $ravada_posix_group;
            diag("Adding ravada_posix_group = $ravada_posix_group in $file_config");
    } else {
        delete $config->{ldap}->{ravada_posix_group};
    }

    if ($with_filter) {
        $config->{ldap}->{filter} = $with_filter;
    } else {
        delete $config->{ldap}->{filter};
    }

    if ($with_admin) {
        $config->{ldap}->{admin_group} = $ADMIN_GROUP;
    } else {
        delete $config->{ldap}->{admin_group};
    }

    $config->{vm}=['KVM','Void'];
    delete $config->{ldap}->{ravada_posix_group}   if !$with_posix_group;

    my $fly_config = "/var/tmp/$$.config";
    DumpFile($fly_config, $config);
    return $fly_config;
}

sub _add_posix_group {
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();

    my $base = "ou=groups,".Ravada::Auth::LDAP::_dc_base();

    my $mesg;
    for ( 1 .. 10 ) {
        $mesg = $ldap->add(
        cn => $RAVADA_POSIX_GROUP
        ,dn => "cn=$RAVADA_POSIX_GROUP,$base"
        ,attrs => [ cn => $RAVADA_POSIX_GROUP
                    ,objectClass=> [ 'posixGroup' ]
                    ,gidNumber => 999
                ]
    );
    last if !$mesg->code;
    warn "Error ".$mesg->code." adding $RAVADA_POSIX_GROUP ".$mesg->error
        if $mesg->code && $mesg->code != 68;

        Ravada::Auth::LDAP::init();
        $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    }

    $mesg = $ldap->search( filter => "cn=$RAVADA_POSIX_GROUP",base => $base );
    my @group = $mesg->entries;
    ok($group[0],"Expecting group $RAVADA_POSIX_GROUP") or return;
    push @USERS,($group[0]);
    return $group[0];
}

sub _search_ldap($cn, $base=Ravada::Auth::LDAP::_dc_base()) {
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    my $mesg = $ldap->search( filter => "cn=$cn", base => $base );
    my @found = $mesg->entries;
    return @found;
}

sub _add_to_posix_group($user_name, $with_posix_group) {
    my $group = _add_posix_group();

    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    if ($with_posix_group) {
        $group->add(memberUid => $user_name);
        my $mesg = $group->update($ldap);
                                                            # 20: no such object
        die $mesg->code." ".$mesg->error if $mesg->code && $mesg->code != 20;
    } else {
        $group->delete(memberUid => $user_name );
        my $mesg = $group->update($ldap);
                                                            # 16: no such attrib
        die $mesg->code." ".$mesg->error if $mesg->code && $mesg->code != 16;
    }
    my @member = $group->get_value('memberUid');

    my ($found) = grep /^$user_name$/,@member;

    ok( $found, "Expecting $user_name in $RAVADA_POSIX_GROUP") if $with_posix_group;
    ok( !$found ) if !$with_posix_group;
}

sub _create_groups {
    my @groups;
    my %dupe_gid;
    for my $g_name0 (qw(npc wizards fighters)) {
        my $g_name=new_domain_name().".$g_name0";
        my $group = Ravada::Auth::LDAP::search_group(name => $g_name);
        my $gid;
        $gid = $group->get_value('gidNumber') if $group;
        if ($group && ( !$gid || $dupe_gid{$gid}++)) {
            Ravada::Auth::LDAP::_init_ldap_admin->delete($group);
            $group = undef;
        }
        if (!$group) {
            Ravada::Auth::LDAP::add_group($g_name);
            $group = Ravada::Auth::LDAP::search_group(name => $g_name) or die "I can create group $g_name";
        }
        push @groups,($group);
    }
    return @groups;

}

sub _create_users(@groups) {
    my @users;
    my %gid_dupe;
    for my $group (@groups) {
        my $name = new_domain_name();
        my ($user) = Ravada::Auth::LDAP::search_user(name => $name, filter => '');
        if (defined $user
            && defined($user->get_value('gidNumber'))
            && $user->get_value('gidNumber') != $group->get_value('gidNumber')) {
                Ravada::Auth::LDAP::_init_ldap_admin()->delete($user);
                $user = undef;
        }
        if (!$user) {
            my $gid = $group->get_value('gidNumber');
            die "Error: gid $gid duplicated ".Dumper(\%gid_dupe)
            if $gid_dupe{$gid};
            $gid_dupe{$gid} = $group->get_value('cn');
            Ravada::Auth::LDAP::add_user_posix(
                name => $name
                ,password => "p.$name"
                ,gid => $gid
            );
            ($user) = Ravada::Auth::LDAP::search_user(name => $name, filter => '');
            is($user->get_value('gidNumber'),$gid,"gid wrong for user $name") or exit;
        }
        push @users, ($user);
    }
    return @users;
}

sub _init_ravada($fly_config) {
    my $ravada;
    $ravada = Ravada->new(config => $fly_config
        , connector => connector);
    $ravada->_install();
    Ravada::Auth::LDAP::init();
    Ravada::Auth::LDAP::_init_ldap_admin();
    return $ravada;
}

sub test_filter_gid {
    my $file_config = "t/etc/ravada_ldap.conf";
    my $ravada = _init_ravada(_init_config(file_config => $file_config));
    my @groups = _create_groups();
    my @users = _create_users(@groups);
    my $user_no = shift @users;

    my $name = $user_no->get_value('cn');
    my $user_login;
    eval { $user_login = Ravada::Auth::LDAP->new(name => $name, password => "p.".$name) };
    is($@, '');
    ok($user_login);

    my $filter = '|';
    my %gid_duplicated;
    for my $user ( @users ) {
        my $gid = $user->get_value('gidNumber');
        $filter .= "(gidNumber=$gid)";
        die "Error: gid $gid duplicated ".$user->get_value('cn')."\n".Dumper(\%gid_duplicated) if $gid_duplicated{$gid};
        $gid_duplicated{$gid}=$user->get_value('cn');
    }
    $ravada = _init_ravada(_init_config(file_config => $file_config, with_filter =>  $filter));

    $user_login = undef;
    eval { $user_login = Ravada::Auth::LDAP->new(name => $name, password => "p.".$name) };
    like($@, qr(Login failed));
    ok(!$user_login);

    for my $user (@users) {
        $name = $user->get_value('cn');
        $user_login = undef;
        eval { $user_login = Ravada::Auth::LDAP->new(name => $name, password => "p.".$name) };
        is($@, '');
        ok($user_login) or exit;
    }

}

sub test_filter {
    my $file_config = "t/etc/ravada_ldap.conf";
    for my $filter (@FILTER) {
    my $fly_config = _init_config(file_config => $file_config, with_filter =>  $filter);
    SKIP: {
        my $ravada;
        eval { $ravada = Ravada->new(config => $fly_config
                , connector => connector);
            $ravada->_install();
            Ravada::Auth::LDAP::init();
            Ravada::Auth::LDAP::_init_ldap_admin();
        };
        if ($@) {
            diag("Skipping: $@");
            skip($@, 6);
        }

        my ($user_name, $password) = ('mcnulty_'.new_domain_name(), 'jameson');
        _remove_user_ldap($user_name);
        my $user = create_ldap_user($user_name, $password);

        my $user_login;
        eval { $user_login= Ravada::Auth::LDAP->new(name => $user_name,password => $password) };
        like($@, qr(Login failed));

        is($user_login,undef);

        my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
        my $mesg = $ldap->search( filter => "cn=$user_name",base => Ravada::Auth::LDAP::_dc_base());
        my ($entry) = $mesg->entries;
        $entry->replace(sn => 'bar');
        $entry->update($ldap);

        is($entry->get_value('sn'),'bar');

        $mesg = $ldap->search( filter => "cn=$user_name",base => Ravada::Auth::LDAP::_dc_base());
        ($entry) = $mesg->entries;
        is($entry->get_value('sn'),'bar');

        eval { $user_login= Ravada::Auth::LDAP->new(name => $user_name,password => $password) };
        is($@, '');

        ok($user_login,"Expecting an object");

        Ravada::Auth::LDAP::remove_user($user_name);
    }
    }
}

sub test_posix_group {
    my $with_posix_group = shift;
    my $group = _add_posix_group();

    my ($user_name, $password) = ('mcnulty_'.new_domain_name(), 'jameson');

    my $user = create_ldap_user($user_name, $password);

    my $user_login;
    eval { $user_login= Ravada::Auth::LDAP->new(name => $user_name,password => $password) };
    my $error = $@;
    if ($with_posix_group) {
        ok(!$user_login,"Expecting no login $user_name with posix group ".Dumper($Ravada::CONFIG));
        like($error,qr(Login failed));
    } else {
        ok($user_login);
    }
    _add_to_posix_group($user_name, $with_posix_group);

    eval { $user_login= Ravada::Auth::LDAP->new(name => $user_name,password => $password) };
    is($@,'');
    ok($user_login);

    Ravada::Auth::LDAP::init();
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    my $mesg = $ldap->delete($user);
    die $mesg->code." ".$mesg->error if $mesg->code && $mesg->code;

    $mesg = $ldap->delete($group);
    die $mesg->code." ".$mesg->error if $mesg->code && $mesg->code;

}

sub _replace_field($entry, $field, $with_posix_group) {
    my $old_value = $entry->get_value($field);
    die "Error: No $field found in LDAP entry in ".$entry->get_value('cn')
        if !$old_value;

    my $new_value = new_domain_name();

    Ravada::Auth::LDAP::init();
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    $entry->replace($field => $new_value);
    my $mesg = $entry->update($ldap);
    confess $mesg->code." ".$mesg->error if $mesg->code && $mesg->code;

    _add_to_posix_group($new_value, $with_posix_group);

    return ($old_value, $new_value);
}

sub test_uid_cn($user, $with_posix_group) {
    Ravada::Auth::LDAP::init();
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    my $entry = $user->{_ldap_entry};
    my $field = 'uid';
    my $uid_value = new_domain_name();
    my $mesg = $entry->replace( $field => $uid_value )->update($ldap);
    $mesg->code  and  die $mesg->error;          # check for errors


    _add_to_posix_group($uid_value, $with_posix_group);

    my %data = (
        cn => $entry->get_value('cn')
        ,$field => $uid_value

    );

    test_login_fields(\%data);
    my ($old_value, $new_value) = _replace_field($entry, $field, $with_posix_group);

    $data{$field} = $new_value;
    test_login_fields(\%data);

    $entry->replace($field => $old_value);
    $entry->update($ldap);
}

sub test_login_fields($data) {
    my $password = 'jameson';
    my $login_ok;
    for my $field ( sort keys %$data ) {
        my $value = $data->{$field};
        $Ravada::CONFIG->{ldap}->{field} = $field;
        eval { $login_ok = Ravada::Auth::login($value, $password) };

        is($@,''," $field: $value") or confess;
        ok($login_ok, $value);
    }
    delete $Ravada::CONFIG->{ldap}->{field};
}

sub test_pass_storage($with_posix_group) {
    my %data = (
        rfc2307 => 'MD5'
        ,PBKDF2 => 'SHA-256'
    );
    for my $storage ( keys %data ) {
        for my $algorithm ( undef, $data{$storage} ) {
            my $name = "tst_".lc($storage)."_".lc($algorithm or 'none');
            my @args = ( $name, $with_posix_group, $$, $storage);
            push @args, ($algorithm) if $algorithm;

            $Ravada::Auth::LDAP_OK=undef;
            Ravada::Auth::LDAP::init();

            my $user = test_user(@args);
            my $sign = $storage;
            $sign = $data{$storage} if $sign eq 'rfc2307';
            like($user->{_ldap_entry}->get_value('userPassword'), qr/^{$sign/);

            $user->_login_match();
            $user->_login_bind();
            $user->_login_match();
            $user->_login_bind();

            _remove_user_ldap($name);
        }
    }
    Ravada::Auth::LDAP::init();
}

SKIP: {
    test_filter();
    test_filter_gid();
    my $file_config = "t/etc/ravada_ldap.conf";
    init($file_config);
    for my $with_posix_group (0,1) {
    for my $with_admin (0,1) {
    for my $with_dn_posix_group (0,1) {
    next if !$with_posix_group;
    for my $with_cn_posix_group (0,1) {
        my $fly_config = _init_config(
            file_config => $file_config
            ,with_admin => $with_admin
            ,with_posix_group => $with_posix_group
            ,with_dn_posix_group => $with_dn_posix_group
            ,with_cn_posix_group => $with_cn_posix_group
        );
        my $ravada = Ravada->new(config => $fly_config
                        , connector => connector);
        $ravada->_install();
        Ravada::Auth::LDAP::init();

        if ($with_posix_group) {
            ok($Ravada::CONFIG->{ldap}->{ravada_posix_group},
                    "Expecting ravada_posix_group on $fly_config\n"
                        .Dumper($Ravada::CONFIG->{ldap}))
                or exit;
        }
        my $ldap;

        eval { $ldap = Ravada::Auth::LDAP::_init_ldap_admin() };

        if ($@ =~ /Bad credentials/) {
            diag("$@\nFix admin credentials in $file_config");
        } else {
            diag("Skipped LDAP tests ".($@ or '')) if !$ldap;
        }

        skip( ($@ or "No LDAP server found"),6) if !$ldap && $@ !~ /Bad credentials/;

        ok($ldap) and do {

            test_user_fail();
            test_pass_storage($with_posix_group);

            my $user = test_user( 'pepe.mcnulty', $with_posix_group );

            test_add_group();
            test_manage_group($with_admin, $with_posix_group);
            test_posix_group($with_posix_group);

            test_user_bind($user, $fly_config, $with_posix_group);

            remove_users();
        };
        unlink($fly_config) if -e $fly_config;
    }
    }
    }
    }
};

end();
done_testing();
