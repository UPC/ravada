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
$Test::Ravada::BACKGROUND=1;
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

    _test_change_own_password( $username, $password );
    _test_change_password(403);
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

    _test_change_password(200);
    _test_user_grants($user, 200);
    $user->remove();
}

sub _mojo_login($admin) {
    my ($username, $password) = ( new_domain_name(),new_domain_name());
    my $user_db = Ravada::Auth::SQL->new( name => $username);
    $user_db->remove();

    my $user= create_ldap_user( $username, $password);
    $user_db = Ravada::Auth::SQL->new( name => $username);
    user_admin->make_admin($user_db->id) if $admin;

    mojo_login($t, $username, $password);

    return $user_db;
}

sub _create_base($vm_name) {
    my $name = new_domain_name();

    my $args = {
            backend => $vm_name
            ,id_iso => search_id_iso('Alpine%64 bits')
            ,name => $name
            ,disk => 1
            ,submit => 1
    };

    mojo_check_login($t);
    $t->post_ok('/new_machine.html' => form => $args)->status_is(302) or return;

    wait_request();

    my $domain = rvd_front->search_domain($name);

    mojo_request($t,"prepare_base", {id_domain => $domain->id });
    $domain->is_public(1);

    return $domain;

}

sub test_clone($base,$expected=0) {
    my @clones0 = $base->clones();
    my $expected_status = 200;
    $expected_status = 403 if !$expected;
    $t->get_ok("/machine/clone/".$base->id.".html")->status_is($expected_status);
    wait_request();

    my @clones = $base->clones();
    is(scalar(@clones),scalar(@clones0)+$expected);

    if (scalar(@clones)>scalar(@clones0)) {
        my $req= Ravada::Request->remove_domain(
            name => $clones[-1]->{name}
            ,uid => user_admin->id
        );
        wait_request();

    }
}

sub test_clone_request($base, $expected=0) {

    my @clones0 = $base->clones();
    my $id_req = mojo_request($t,"clone", {id_domain => $base->id });
    my $request = Ravada::Request->open($id_req);
    wait_request();
    is($request->status,'done');
    if (!$expected) {
        like($request->error,qr/user.*can not clone/);
    } else {
        is($request->error,'');
    }
    my @clones = $base->clones();
    is(scalar(@clones),scalar(@clones0)+$expected);

    if (scalar(@clones)>scalar(@clones0)) {
        my $req= Ravada::Request->remove_domain(
            name => $clones[-1]->{name}
            ,uid => user_admin->id
        );
        wait_request();
    }

}
sub test_access($vm_name) {
    my $user_admin = _mojo_login(1);
    #create base
    my $base = _create_base($vm_name);

    my $user= _mojo_login(0);

    test_clone($base,1);
    test_clone_request($base,1);

    $base->allow_ldap_access('cn' => $user->ldap_entry->get_value('cn'),0);

    is($user->allowed_access($base->id),0);

    test_clone($base);
    test_clone_request($base);
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

    my $group = create_group();

    $user->add_to_group($group);

    for my $grant ( user_admin->list_all_permissions) {
        my $value0 = ( $user->can_do($grant->{name}) or 0 );
        for my $value ( 1, 0) {

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
        if ($expected_code == 200 ) {
            _test_group_grant($user, $group, $grant);
        }

    }

}

sub _test_group_grant($user, $group, $grant) {
    die "Error: it should be granted to 0 here"
    if $user->can_do($grant->{name});

    my $url = "/group/grant/".$group->id."/$grant->{name}/1";
    $t->get_ok($url);
    is($t->tx->res->code(), 200) or do {
        open my $out ,">","error.html";
        print $out $t->tx->res->to_string;
        close $out;
        exit;
    };


    $user->_reload_grants();
    is($user->can_do($grant->{name}),1,"Expecting user ".$user->name." ".$user->id
                ." can $grant->{name} ") or die;

    $url = "/group/grant/".$group->id."/$grant->{name}/0";
    $t->get_ok($url);

    $user->_reload_grants();
    is($user->can_do($grant->{name}),0,"Expecting user ".$user->name." ".$user->id
                ." can not $grant->{name} ") or die;

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

sub _test_change_own_password($username, $current_password) {

    my $new_password = "$username.12ab";
    $t->post_ok("/user_settings", form => {
            'password-form' => 1
            ,'current_password' => $current_password
            ,password => $new_password
            ,'conf_password' => 'fail'
        }
    )->status_is(200);

    my $user_db = Ravada::Auth::SQL->new( name => $username);
    is($user_db->compare_password($current_password), 1);

    $t->post_ok("/user_settings", form => {
            'password-form' => 1
            ,'current_password' => $current_password
            ,password => $new_password
            ,'conf_password' => $new_password
        }
    )->status_is(200);

    $user_db = Ravada::Auth::SQL->new( name => $username);
    is($user_db->compare_password($new_password), 1);

}

sub _test_change_password($expected_status) {
    my $n = 1;
    for my $force_change ( undef,0,1 ) {
        my ($username, $password) = ( new_domain_name(),$$);
        my $user_db = Ravada::Auth::SQL->new( name => $username);
        $user_db->remove();

        my $user = create_user( $username, $password);

        my $new_password = "hola1234".$n++;

        my %args = ( password => $new_password);
        $args{force_change_password} = $force_change
        if defined $force_change;

        $t->post_ok("/admin/user/".$user->id.".html" => form => \%args)->status_is($expected_status);

        $user_db = Ravada::Auth::SQL->new( name => $username);
        if ($expected_status == 200 ) {
            is($user_db->compare_password($new_password), 1);
            my $curr_force_change = ($force_change or 0 );
            is($user_db->password_will_be_changed(), $curr_force_change);
        } else {
            is($user_db->compare_password($new_password), 0);
            is($user_db->password_will_be_changed(), 0);
        }
    }
}

################################################################

test_non_admin();
test_admin();

if (ping_backend()) {
    remove_old_domains_req(1); # 0=do not wait for them
    wait_request();
    for my $vm_name( 'Void' ) {
        test_access($vm_name);
    }

    remove_old_domains_req(0); # 0=do not wait for them
} else {
    diag("SKIPPED: no backend");
}

done_testing();
