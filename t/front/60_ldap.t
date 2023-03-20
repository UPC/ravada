use warnings;
use strict;

use Data::Dumper;
use Hash::Util qw(lock_hash);
use Test::More;
use YAML qw( LoadFile );

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada::Front');
use_ok('Ravada::Auth');
use_ok('Ravada::Auth::LDAP');

my $CONFIG_FILE = 't/etc/ravada_ldap.conf';

init( $CONFIG_FILE);
rvd_back();

my $RVD_FRONT;
my $USER_DATA = { name => new_domain_name.'.jimmy', password => 'jameson' };

#########################################################################

sub test_ldap {
    $RVD_FRONT = Ravada::Front->new(
        config => $CONFIG_FILE
        ,connector => connector()
    );
    delete $Ravada::CONFIG->{ldap}->{ravada_posix_group};
    create_ldap_user($USER_DATA->{name}, $USER_DATA->{password});
    my $login_ok;
    eval { $login_ok = Ravada::Auth::login($USER_DATA->{name}, $USER_DATA->{password}) };
    is($@, '');
    ok($login_ok,"Expecting login with $USER_DATA->{name}");

    $login_ok = 0;
    eval { $login_ok = Ravada::Auth::SQL->new( %$USER_DATA ); };
    like($@, qr(Login failed));
    ok(!$login_ok,"Expecting no login with SQL");

    delete $Ravada::CONFIG->{ldap}->{auth};
    $login_ok = undef;
    eval { $login_ok = Ravada::Auth::LDAP->new( %$USER_DATA ); };
    is($@, '');
    ok($login_ok,"Expecting login with $USER_DATA->{name}");

    $Ravada::CONFIG->{ldap}->{auth} = 'bind';
    $login_ok = undef;
    eval { $login_ok = Ravada::Auth::LDAP->new( %$USER_DATA ); };
    is($@, '');
    ok($login_ok,"Expecting login with $USER_DATA->{name}");
    is($login_ok->{_auth},'bind',"Expecting bind login with $USER_DATA->{name}")
        if $login_ok;

    my $user_db = Ravada::Auth::SQL->new( name => $USER_DATA->{name});
    $user_db->remove();

    create_ldap_user($USER_DATA->{name}, $USER_DATA->{password});

    $Ravada::CONFIG->{ldap}->{auth} = 'match';
    $login_ok = undef;
    eval { $login_ok = Ravada::Auth::LDAP->new( %$USER_DATA ); };
    is($@, '');
    ok($login_ok,"Expecting login with $USER_DATA->{name}");
    is($login_ok->{_auth},'match',"Expecting match login with $USER_DATA->{name}")
        if $login_ok;

    ok(Ravada::Auth::LDAP::_init_ldap_admin(),"Expecting LDAP admin connected");
}

sub test_ldap_space {
    create_ldap_user($USER_DATA->{name}, $USER_DATA->{password});
    my %user = %$USER_DATA;
    $user{name} = " ".$user{name};
    my $login_ok;

    $Ravada::CONFIG->{ldap}->{auth} = 'bind';

    eval { $login_ok = Ravada::Auth::LDAP->new(name => $user{name}, password => $user{password}) };
    like($@, qr'.');
    ok(!$login_ok,"Expecting no login with $user{name}");

    eval { $login_ok = Ravada::Auth::login($user{name}, $user{password} , 1) };
    like($@, qr'.');
    ok(!$login_ok,"Expecting no login with $user{name}");

    $Ravada::CONFIG->{ldap}->{auth} = 'match';

    eval { $login_ok = Ravada::Auth::LDAP->new(name => $user{name}, password => $user{password}) };
    like($@, qr'.');
    ok(!$login_ok,"Expecting no login with $user{name}");

    eval { $login_ok = Ravada::Auth::login($user{name}, $user{password}, 1) };
    like($@, qr'.');
    ok(!$login_ok,"Expecting no login with $user{name}");
}

sub test_ldap_search_space {
    my @entries = Ravada::Auth::LDAP::search_user( name =>" $USER_DATA->{name}");
    is(scalar@entries, 0);
}

#########################################################################

SKIP: {
    my $ravada = Ravada->new(config => $CONFIG_FILE
                        , pid_name => "ravada_install".base_domain_name()
                        , connector => connector());
    $ravada->_install();
    my $ldap;

    delete $Ravada::CONFIG->{ldap}->{ravada_posix_group};

    eval { $ldap = Ravada::Auth::LDAP::_init_ldap_admin() };

    if ($@ =~ /Bad credentials/) {
        diag("$@\nFix admin credentials in $CONFIG_FILE");

    } else {
        diag("Skipped LDAP tests ".($@ or '')) if !$ldap;
    }

    skip( ($@ or "No LDAP server found"),6) if !$ldap && $@ !~ /Bad credentials/;

    ok($ldap) and do {

        test_ldap_space();
        test_ldap_search_space();

        test_ldap();

    };
}

end();
done_testing();
