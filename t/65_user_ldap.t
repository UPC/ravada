use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;
use YAML qw(LoadFile DumpFile);

use_ok('Ravada');
use_ok('Ravada::Auth::LDAP');


my $ravada = Ravada->new();#connector => $test->connector);

my $FILE_CONFIG = "ldap.conf";

my ($LDAP_USER , $LDAP_PASS) = ("cn=Directory Manager","saysomething");

if (! -e $FILE_CONFIG ) {
    my $config = { cn => $LDAP_USER , password => $LDAP_PASS };
    DumpFile($FILE_CONFIG,$config);
}
my $config = LoadFile("ldap.conf");
($LDAP_USER , $LDAP_PASS) = ($config->{cn} , $config->{password});

sub test_user_fail {
    my $user_fail;
    eval { $user_fail = Ravada::Auth::LDAP->new(name => 'root',password => 'fail')};
    
    ok(!$user_fail,"User should fail, got ".Dumper($user_fail));
}
    
sub test_user_root {

    my ($name, $pass) = ($0, $$);
    Ravada::Auth::LDAP::add_user($name, $pass , 1);
    my $user;
    eval { $user = Ravada::Auth::LDAP->new(name => $name,password => $pass) };
    
    ok($user,($@ or 'Login failed ');
    ok($user->is_admin,"User ".$user->name." should be admin ".Dumper($user->{_data}));
}
    
    
sub test_user{
    Ravada::Auth::LDAP::add_user('mcnulty','jameson');
    my $mcnulty= Ravada::Auth::LDAP->new(name => 'mcnulty',password => 'jameson');
    
    ok($mcnulty);
    ok(!$mcnulty->is_admin,"User ".$mcnulty->name." should not be admin "
            .Dumper($mcnulty->{_data}));
}
    
SKIP: {
    my $ldap;
    eval { $ldap = Ravada::Auth::LDAP::_init_ldap($LDAP_USER, $LDAP_PASS) };
    if ($@ =~ /Bad credentials/) {
        diag("Fix admin credentials in ldap.conf");
    } else {
        diag("Skipped LDAP tests ".($@ or '')) if !$ldap;
    }

    skip( ($@ or "No LDAP server found"),6) if !$ldap && $@ !~ /Bad credentials/;

    ok(!$@ ) and do {
        eval { Ravada::Auth::LDAP::remove_user($0) };
        ok(!$@,$@);
        test_user_root();
        test_user_fail();
        test_user();
    };
};
    
done_testing();
