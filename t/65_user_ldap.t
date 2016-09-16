use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;
use YAML qw(LoadFile DumpFile);

use_ok('Ravada');
use_ok('Ravada::Auth::LDAP');

my $FILE_CONFIG = "t/etc/ravada_ldap.conf";
my $ADMIN_GROUP = "test.admin.group";

if (! -e $FILE_CONFIG ) {
    my ($LDAP_USER , $LDAP_PASS) = ("cn=Directory Manager","saysomething");
    my $config = { 
        ldap => {
            admin_user => { cn => $LDAP_USER , password => $LDAP_PASS }
            ,admin_group => $ADMIN_GROUP
        }    
    };
    DumpFile($FILE_CONFIG,$config);
}

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');
my $ravada = Ravada->new(config => 't/etc/ravada_ldap.conf', connector => $test->connector);


my @USERS;

sub test_user_fail {
    my $user_fail;
    eval { $user_fail = Ravada::Auth::LDAP->new(name => 'root',password => 'fail')};
    
    ok(!$user_fail,"User should fail, got ".Dumper($user_fail));
}
    
sub test_user{
    my $name = (shift or 'jimmy.mcnulty');
    if ( Ravada::Auth::LDAP::search_user($name) ) {
        diag("Removing $name");
        Ravada::Auth::LDAP::remove_user($name)  
    }

    my $user = Ravada::Auth::LDAP::search_user($name);
    ok(!$user,"I shouldn't find user $name in the LDAP server") or return;

    eval { Ravada::Auth::LDAP::add_user($name,'jameson') };
    push @USERS,($name);

    ok(!$@,$@) or return;
    my $mcnulty;
    eval { $mcnulty = Ravada::Auth::LDAP->new(name => $name,password => 'jameson') };
    
    ok($mcnulty,($@ or "ldap login failed for $name")) or return;
    ok(!$mcnulty->is_admin,"User ".$mcnulty->name." should not be admin "
            .Dumper($mcnulty->{_data}));


    my $mcnulty_sql = Ravada::Auth::SQL->new(name => $name);
    ok($mcnulty_sql,"I can't find mcnulty in the SQL db");
    ok($mcnulty_sql->{name} eq $name, "Expecting '$name', got $mcnulty_sql->{name}");
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

    my $name = $ADMIN_GROUP;

    Ravada::Auth::LDAP::remove_group($name)
        if Ravada::Auth::LDAP::search_group(name => $name);

    my $group0 = Ravada::Auth::LDAP::search_group(name => $name);
    ok(!$group0,"Group $name shouldn't exist") or return;

    diag("Adding group $name");
    Ravada::Auth::LDAP::add_group($name);

    my $group = Ravada::Auth::LDAP::search_group(name => $name);
    ok($group,"Group $name not created") or return;

    my $uid = 'ragnar.lothbrok';
    my $user = test_user($uid);
    
    ok(!$user->is_admin,"User $uid should not be admin");

    Ravada::Auth::LDAP::add_to_group($uid, $name);
    ok($user->is_admin,"User $uid should be admin") or exit;

    Ravada::Auth::LDAP::remove_user($uid);
    Ravada::Auth::LDAP::remove_group($name);

    my $group2 = Ravada::Auth::LDAP::search_group(name => $name);
    ok(!$group2,"Group $name not removed");

}

    
SKIP: {
    my $ldap;

    eval { $ldap = Ravada::Auth::LDAP::_init_ldap_admin() };

    if ($@ =~ /Bad credentials/) {
        diag("$@\nFix admin credentials in $FILE_CONFIG");
    } else {
        diag("Skipped LDAP tests ".($@ or '')) if !$ldap;
    }

    skip( ($@ or "No LDAP server found"),6) if !$ldap && $@ !~ /Bad credentials/;

    ok(!$@ ) and do {
        test_user_fail();
        test_user();

        test_add_group();
        test_manage_group();

        remove_users();
    };
};
    
done_testing();
