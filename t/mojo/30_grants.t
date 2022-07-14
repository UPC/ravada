use warnings;
use strict;

use Data::Dumper;
use HTML::Lint;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $t;

my $URL_LOGOUT = '/logout';
my ($USERNAME, $PASSWORD);
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

sub test_non_admin() {
    my ($username, $password) = ( new_domain_name(),$$);
    my $user_db = Ravada::Auth::SQL->new( name => $username);
    $user_db->remove();

    my $user = create_user( $username, $password);
    mojo_login($t, $user->name, $password);
    _test_user_grants($user, 403);
    $user->remove();
}

sub test_admin() {
    my ($username, $password) = ( new_domain_name(),$$);
    my $user_db = Ravada::Auth::SQL->new( name => $username);
    $user_db->remove();

    my $user_login = create_user( $username, $password, 1);
    mojo_login($t, $user_login->name, $password);

    ($username, $password) = ( new_domain_name(),$$);
    $user_db = Ravada::Auth::SQL->new( name => $username);
    $user_db->remove();

    my $user= create_user( $username, $password);

    _test_user_grants($user, 200);
    $user->remove();
}



sub  _test_user_grants($user, $expected_code) {

    $t->get_ok("/admin/users");
    is($t->tx->res->code(),$expected_code);

    $t->get_ok("/admin/user/".$user->id.".html");
    is($t->tx->res->code(),$expected_code);

    $t->get_ok("/user/grants/".$user->id);
    is($t->tx->res->code(),$expected_code);

    $t->get_ok("/user/info/".$user->id);
    is($t->tx->res->code(),$expected_code);

    _test_set_admin($user, $expected_code);

    _test_all_grants($expected_code);
    _test_grant($user, $expected_code);

}

sub _test_set_admin($user,$expected_code) {
    $t->post_ok("/user/set/".$user->id => json => {is_admin => 'true'});
    is($t->tx->res->code(),$expected_code);
    if ( $expected_code == 200 ) {
        is($t->tx->res->json->{error},'');
        $user->_load_data();
        is($user->is_admin,1,"Expected ".$user->name." is admin");
    }

    $t->post_ok("/user/set/".$user->id => json => {is_admin => 'false'});
    is($t->tx->res->code(),$expected_code);
    if ( $expected_code == 200 ) {
        is($t->tx->res->json->{error},'');
        $user->_load_data();
        is($user->is_admin,0);
    }

    $t->post_ok("/user/set/".$user->id => json => {is_admin => 1 });
    is($t->tx->res->code(),$expected_code);
    if ( $expected_code == 200 ) {
        is($t->tx->res->json->{error},'');
        $user->_load_data();
        is($user->is_admin,1,"Expected ".$user->name." is admin");
    }

    $t->post_ok("/user/set/".$user->id => json => {is_admin => 0 });
    is($t->tx->res->code(),$expected_code);
    if ( $expected_code == 200 ) {
        is($t->tx->res->json->{error},'');
        $user->_load_data();
        is($user->is_admin,0);
    }

}

sub _test_all_grants($expected_code) {
    return if $expected_code != 200;
    my ($username, $password) = ( new_domain_name(),$$);
    my $user_db = Ravada::Auth::SQL->new( name => $username);
    $user_db->remove();

    my $user = create_user( $username, $password);

    for my $grant ( user_admin->list_all_permissions) {
        my $value0 = ( $user->can_do($grant->{name}) or 0 );
        for my $value ( !$value0, $value0) {

            my $value2 = ($value or 0 );

            my $url = "/user/grant/".$user->id."/$grant->{name}/".$value2;
            $t->get_ok($url);
            is($t->tx->res->code(),$expected_code) or do {
                open my $out ,">","error.html";
                print $out $t->tx->res->to_string;
                close $out;
                exit;
            };

            is($t->tx->res->json->{error},'');
            $user->_reload_grants();
            is($user->can_do($grant->{name}),$value2,"Expecting user ".$user->name." ".$user->id." can do $grant->{name} $value2") or die;

        }

    }

}

sub _test_grant($user, $expected_code) {

    $t->get_ok("/user/grant/".$user->id."/missing grant/true");
    is($t->tx->res->code(),$expected_code);
    if ( $expected_code == 200 ) {
        my $error = $t->tx->res->json->{error};
        like($error,qr/Permission.*invalid/);
    }

    $t->get_ok("/user/grant/".$user->id."/clone/false");
    is($t->tx->res->code(),$expected_code);

    if ($expected_code == 200 ) {
        is($t->tx->res->json->{error},'');
        $user->_load_data();
        is($user->can_clone, 0,"Expecting user ".$user->name." ".$user->id." can not clone") or die;
    } else {
        ok($user->can_clone);
    }

    $t->get_ok("/user/grant/".$user->id."/clone/1");
    is($t->tx->res->code(),$expected_code);

    if ($expected_code == 200 ) {
        is($t->tx->res->json->{error},'');
        $user->_reload_grants();
        is($user->can_clone,1,"Expecting user ".$user->name." ".$user->id." can clone") or die;
    }

    $t->get_ok("/user/grant/".$user->id."/clone_all/true");
    is($t->tx->res->code(),$expected_code);

    if ($expected_code == 200 ) {
        is($t->tx->res->json->{error},'');
        $user->_reload_grants();
        is($user->can_clone_all, 1,"Expecting user ".$user->name." ".$user->id." can clone all") or die;
    } else {
        ok(!$user->can_clone_all);
    }

    $t->get_ok("/user/grant/".$user->id."/start_limit/4");
    is($t->tx->res->code(),$expected_code);

    if ($expected_code == 200 ) {
        is($t->tx->res->json->{error},'');
        $user->_reload_grants();
        is($user->can_start_limit, 4,"Expecting user ".$user->name." ".$user->id." start limit changed") or die;
    } else {
        ok(!$user->can_start_limit);
    }


    $user->remove();
}

test_non_admin();
test_admin();

done_testing();
