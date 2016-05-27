use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;
use YAML qw(LoadFile DumpFile);

use_ok('Ravada');
use_ok('Ravada::Auth::LDAP');

my $FILE_CONFIG = "t/ravada_ldap.conf";
if (! -e $FILE_CONFIG ) {
    my ($LDAP_USER , $LDAP_PASS) = ("cn=Directory Manager","saysomething");
    my $config = {ldap => { cn => $LDAP_USER , password => $LDAP_PASS }};
    DumpFile($FILE_CONFIG,$config);
}

my $ravada = Ravada->new(config => 't/ravada_ldap.conf');#connector => $test->connector);


my @USERS;

sub test_user_fail {
    my $user_fail;
    eval { $user_fail = Ravada::Auth::LDAP->new(name => 'root',password => 'fail')};
    
    ok(!$user_fail,"User should fail, got ".Dumper($user_fail));
}
    
sub test_user_admin {

    my ($name, $pass) = ($0, $$);

    Ravada::Auth::LDAP::remove_user($name) if Ravada::Auth::LDAP::search_user($name);
    ok(!$@,$@);

    my $user = Ravada::Auth::LDAP::search_user($name);
    ok(!$user,"I shouldn't find user $name in the LDAP server") or return;

    Ravada::Auth::LDAP::add_user($name, $pass , 1);
    push @USERS,($name);
    eval { $user = Ravada::Auth::LDAP->new(name => $name,password => $pass) };
    diag($@);
    
    ok($user,($@ or 'Login failed ')) or return;
    ok($user->is_admin,"User ".$user->name." should be admin ".Dumper($user->{_data}));
}
    
    
sub test_user{
    my $name = 'jimmy.mcnulty';
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
    
SKIP: {
    my $ldap;

    eval { $ldap = Ravada::Auth::LDAP::_init_ldap_admin() };

    if ($@ =~ /Bad credentials/) {
        diag("Fix admin credentials in $FILE_CONFIG");
    } else {
        diag("Skipped LDAP tests ".($@ or '')) if !$ldap;
    }

    skip( ($@ or "No LDAP server found"),6) if !$ldap && $@ !~ /Bad credentials/;

    ok(!$@ ) and do {
        test_user_admin();
        test_user_fail();
        test_user();
        remove_users();
    };
};
    
done_testing();
