use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;
use YAML qw(LoadFile Dump);

use_ok('Ravada');
use_ok('Ravada::Auth::LDAP');

my $ADMIN_GROUP = "test.admin.group";


my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

my $FILE_CONFIG = "t/etc/ravada_ad.conf";
my $FILE_DATA = "t/etc/test_ad_data.conf";

my @USERS;

sub test_user_fail {
    my $user_fail;
    eval { $user_fail = Ravada::Auth::LDAP->new(name => 'missing.user',password => 'fail')};

    ok(!$user_fail,"User should fail, got ".Dumper($user_fail));
}

sub _init_config {
    my $config = LoadFile($FILE_DATA);

    my @fields = ('name','password');

    my @error;
    for my $field (@fields) {
        push @error, ("ERROR: $FILE_CONFIG must have a $field field")
            if !exists $config->{$field};
    }
    die join("\n",@error)."\n"
            .Dumper($config)
        if @error;

    return $config;
}

sub test_user {
    my $data = shift;

    my $user;
    eval { $user = Ravada::Auth::ActiveDirectory->new(%$data) };
    is($@,'');
    ok($user,"Expecting an user object , got ".($user or '<UNDEF>'));

    my $user_login;
    eval { $user_login = Ravada::Auth::login($data->{name}, $data->{password}) };
    is($@,'')   or return;

    ok($user_login) or return;

}
###################################################
my $AD = 0;
use_ok('Ravada::Auth::ActiveDirectory');
$AD = 1;

SKIP: {
    my $msg = "Module for ActiveDirectory not loaded" if !$AD;

    $msg = "No data file $FILE_DATA found"  if !$FILE_DATA && !$msg;

    my $data;
    if ($FILE_DATA) {
        eval { $data = _init_config() }   if $FILE_DATA;

        $msg = "Error reading file $FILE_DATA\n".($@ or '') if $@;
    }

    my $ravada;
    eval{
        $ravada = Ravada->new( config => $FILE_CONFIG
                                ,connector => $test->connector);
    }   if $data;

    if ($msg) {
        diag($msg);
        skip($msg,6);
    }

    test_user($data);
};

done_testing();
