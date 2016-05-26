use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;
use YAML qw(LoadFile);

use_ok('Ravada');
use_ok('Ravada::Auth::LDAP');


my $ravada = Ravada->new();#connector => $test->connector);

my $FILE_CONFIG = "ldap.conf";

my ($LDAP_USER , $LDAP_PASS) = ("cn=Directory Manager","");

if (!-e $FILE_CONFIG ) {
    my $config = LoadFile("ldap.conf");
    ($LDAP_USER , $LDAP_PASS) = ($config->{cn} , $config->{password});
}

sub test_user_fail {
    my $user_fail;
    eval { $user_fail = Ravada::Auth::LDAP->new(name => 'root',password => 'fail')};
    
    ok(!$user_fail,"User should fail, got ".Dumper($user_fail));
}
    
sub test_user_root {
    my $user = Ravada::Auth::LDAP->new(name => 'root',password => 'root');
    
    ok($user);
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
        diag("Write admin credentials in ldap.conf");
    } else {
        diag("Skipped LDAP tests ".($@ or '')) if !$ldap;
    }

    skip( ($@ or "No LDAP server found"),6) if !$ldap && $@ !~ /Bad credentials/;

    Ravada::Auth::LDAP::add_user('root','root', 1);
    test_user_root();
    test_user_fail();
    test_user();
};
    
done_testing();
