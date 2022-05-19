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
use_ok('Ravada::Auth::Kerberos');

#######################################################3

sub _init_config() {
    my $fly_config = "/var/tmp/ravada_kerberos.$$.config";
    my $config = {
        kerberos => { realm => 'test'}
    };
    DumpFile($fly_config, $config);
    return $fly_config;
}


sub _init_ravada($fly_config) {
    my $ravada;
    $ravada = Ravada->new(config => $fly_config
        , connector => connector);
    $ravada->_install();
    return $ravada;
}

sub test_load {
    ok($Ravada::Auth::KERBEROS_OK);
}

sub test_user_missing {
    my $name = new_domain_name();
    my $user;
    eval {
        $user
        = Ravada::Auth::Kerberos->new(name => $name, password => "fail")
    };
    # It is ok if it returns "login failed". It means it tried
    # Kerberos and the user just doesn't exist. Doing great !
    like($@, qr/login failed/i);
}

# I am not sure this is possible to do.
sub test_login {

    my $krb = Ravada::Auth::Kerberos::_connect_kerberos(undef);

    my ($name,$password) = (new_domain_name(),"$$");
    # add an user to kerberos somewhow, this method was just made up
    # $krb->add_user($name, $password);

    my $user;
    eval {
        $user
        = Ravada::Auth::Kerberos->new(name => $name, password => $password)
    };
    is($@,undef);
    ok($user);

}

#######################################################3

my $ravada = _init_ravada(_init_config());

test_load();
test_user_missing();

test_login();

done_testing();
