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
my $FILTER = "sn=bar";

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

sub test_user{
    my $name = (shift or 'jimmy.mcnulty');
    my $with_posix_group = ( shift or 0);
    my $password = 'jameson';

    if ( Ravada::Auth::LDAP::search_user($name) ) {
        diag("Removing $name");
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


    eval { Ravada::Auth::LDAP::add_user($name,$password) };
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
                            ."should be admin, he was added to $name  group") or exit;
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

    unlink $file_config_bind;

    $ravada = Ravada->new(config => $file_config
        , connector => connector);

    Ravada::Auth::LDAP::_init_ldap_admin();

}

sub _init_config($file_config, $with_admin, $with_posix_group, $with_filter = 0) {
    if ( ! -e $file_config) {
        my $config = {
        ldap => {
            admin_user => { dn => $LDAP_USER , password => $LDAP_PASS }
            ,base => "dc=example,dc=com"
            ,admin_group => $ADMIN_GROUP
            ,auth => 'match'
            ,ravada_posix_group => $RAVADA_POSIX_GROUP
        }
        };
        DumpFile($file_config,$config);
    }
    my $config = LoadFile($file_config);
    delete $config->{ldap}->{admin_group}   if !$with_admin;
    if ($with_posix_group) {
        if ( !exists $config->{ldap}->{ravada_posix_group}
                || !$config->{ldap}->{ravada_posix_group}) {
            $config->{ldap}->{ravada_posix_group} = $RAVADA_POSIX_GROUP;
            diag("Adding ravada_posix_group = $RAVADA_POSIX_GROUP in $file_config");
        }
    } else {
        delete $config->{ldap}->{ravada_posix_group};
    }

    if ($with_filter) {
        $config->{ldap}->{filter} = $FILTER;
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

sub test_filter {
    my $file_config = "t/etc/ravada_ldap.conf";
    my $fly_config = _init_config($file_config, 0, 0, 1);
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

SKIP: {
    test_filter();
    my $file_config = "t/etc/ravada_ldap.conf";
    for my $with_posix_group (0,1) {
    for my $with_admin (0,1) {
        my $fly_config = _init_config($file_config, $with_admin, $with_posix_group);
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
};

done_testing();
