use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;
use YAML qw(LoadFile DumpFile);

use_ok('Ravada');
use_ok('Ravada::Auth::LDAP');

my $ADMIN_GROUP = "test.admin.group";


my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my ($LDAP_USER , $LDAP_PASS) = ("cn=Directory Manager","saysomething");

my @USERS;

sub test_user_fail {
    my $user_fail;
    eval { $user_fail = Ravada::Auth::LDAP->new(name => 'root',password => 'fail')};
    
    ok(!$user_fail,"User should fail, got ".Dumper($user_fail));
}
    
sub test_user{
    my $name = (shift or 'jimmy.mcnulty');
    my $password = 'jameson';

    if ( Ravada::Auth::LDAP::search_user($name) ) {
        diag("Removing $name");
        Ravada::Auth::LDAP::remove_user($name)  
    }

    my $user = Ravada::Auth::LDAP::search_user($name);
    ok(!$user,"I shouldn't find user $name in the LDAP server") or return;

    my $user_db = Ravada::Auth::SQL->new( name => $name);
    $user_db->remove();
    # check for the user in the SQL db, he shouldn't be  there
    #
    my $sth = $test->connector->dbh->prepare("SELECT * FROM users WHERE name=?");
    $sth->execute($name);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    ok(!$row->{name},"I shouldn't find $name in the SQL db ".Dumper($row));


    eval { Ravada::Auth::LDAP::add_user($name,$password) };
    push @USERS,($name);

    ok(!$@,$@) or return;
    my $mcnulty;
    eval { $mcnulty = Ravada::Auth::LDAP->new(name => $name,password => $password) };
    is($@,'');

    ok($mcnulty,($@ or "ldap login failed for $name")) or return;
    ok(ref($mcnulty) =~ /Ravada/i,"User must be Ravada::Auth::LDAP , it is '".ref($mcnulty));

    ok(!$mcnulty->is_admin,"User ".$mcnulty->name." should not be admin "
            .Dumper($mcnulty->{_data}));

    # try to login
    my $mcnulty_login = Ravada::Auth::login($name,$password);
    ok($mcnulty_login,"No login");
    ok(ref $mcnulty_login && ref($mcnulty_login) eq 'Ravada::Auth::LDAP',
            "ref should be Ravada::Auth::LDAP , got ".ref($mcnulty_login));
    # check for the user in the SQL db
    # 
    $sth = $test->connector->dbh->prepare("SELECT * FROM users WHERE name=?");
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
    $sth = $test->connector->dbh->prepare("SELECT count(*) FROM users WHERE name=?");
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
    my $user = test_user($uid);

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
    my $file_config = shift;

    my $config = LoadFile($file_config);
    $config->{ldap}->{auth} = 'bind';

    my $file_config_bind = "/var/tmp/ravada_test_ldap_bind_$$.conf";
    DumpFile($file_config_bind, $config);
    my $ravada = Ravada->new(config => $file_config_bind
        , connector => $test->connector);

    Ravada::Auth::LDAP::init();

    my $mcnulty;
    eval { $mcnulty = Ravada::Auth::LDAP->new(name => 'jimmy.mcnulty',password => 'jameson') };
    is($@,'');

    ok($mcnulty,($@ or "ldap login failed ")) or return;

    is($mcnulty->{_auth}, 'bind');

    unlink $file_config_bind;

    $ravada = Ravada->new(config => $file_config
        , connector => $test->connector);

    Ravada::Auth::LDAP::_init_ldap_admin();

}

sub _init_config {
    my ($file_config, $with_admin) = @_;
    return if -e $file_config;
    my $config = {
        ldap => {
            admin_user => { dn => $LDAP_USER , password => $LDAP_PASS }
            ,base => "dc=example,dc=com"
            ,admin_group => $ADMIN_GROUP
            ,auth => 'match'
        }
    };
    delete $config->{ldap}->{admin_group}   if !$with_admin;
    DumpFile($file_config,$config);
}

SKIP: {
    my $with_admin = 0;
    for my $file_config ( "t/etc/ravada_ldap_1.conf"
                        , "t/etc/ravada_ldap_2.conf") {

        _init_config($file_config, $with_admin);
        my $ravada = Ravada->new(config => $file_config
                        , connector => $test->connector);
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
            test_user();

            test_add_group();
            test_manage_group($with_admin);

            test_user_bind($file_config);

            remove_users();
        };
        $with_admin++;
    }
};

done_testing();
