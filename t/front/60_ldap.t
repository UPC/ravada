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
my $USER_DATA = { name => 'jimmy', password => 'jameson' };

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

    $Ravada::CONFIG->{ldap}->{auth} = 'match';
    $login_ok = undef;
    eval { $login_ok = Ravada::Auth::LDAP->new( %$USER_DATA ); };
    is($@, '');
    ok($login_ok,"Expecting login with $USER_DATA->{name}");
    is($login_ok->{_auth},'match',"Expecting match login with $USER_DATA->{name}")
        if $login_ok;

    ok(Ravada::Auth::LDAP::_init_ldap_admin(),"Expecting LDAP admin connected");
}

#########################################################################

SKIP: {
<<<<<<< HEAD
    my $ravada = Ravada->new(config => $CONFIG_FILE
                        , connector => connector());
    $ravada->_install();
    my $ldap;


    eval { $ldap = Ravada::Auth::LDAP::_init_ldap_admin() };

    if ($@ =~ /Bad credentials/) {
        diag("$@\nFix admin credentials in $CONFIG_FILE");
||||||| parent of 6811de74... Feature #894 master (#897)
    my $ok = 1;
    $USER_DATA = LoadFile($file_test_data)  if -e $file_test_data;
    if (!-e $file_test_data || !$USER_DATA->{name} || !$USER_DATA->{password}) {
        my $config = {
            name => 'ldap.cn', password => '****'
        };
        warn "SKIPPED: To test Front LDAP create the file $file_test_data with\n"
            .YAML::Dump($config);
        $ok = 0;
=======
    my $ravada = Ravada->new(config => $CONFIG_FILE
                        , connector => connector);
    $ravada->_install();
    my $ldap;


    eval { $ldap = Ravada::Auth::LDAP::_init_ldap_admin() };

    if ($@ =~ /Bad credentials/) {
        diag("$@\nFix admin credentials in $CONFIG_FILE");
>>>>>>> 6811de74... Feature #894 master (#897)
    } else {
        diag("Skipped LDAP tests ".($@ or '')) if !$ldap;
    }

    skip( ($@ or "No LDAP server found"),6) if !$ldap && $@ !~ /Bad credentials/;

    ok($ldap) and do {

        test_ldap();

    };
}

done_testing();
