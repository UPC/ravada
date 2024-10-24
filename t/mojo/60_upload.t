use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';
use Mojo::JSON qw(encode_json decode_json);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $SECONDS_TIMEOUT = 15;

my $t;

my $URL_LOGOUT = '/logout';
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

################################################################################

sub _clean(@name) {
    for my $name (@name) {
        my $user = Ravada::Auth::SQL->new(name => $name);
        $user->remove() if $user;
    }
}

sub _clean_ldap(@name) {
    for my $name (@name) {
        if ( Ravada::Auth::LDAP::search_user($name) ) {
            Ravada::Auth::LDAP::remove_user($name)  
        }
    }
}

sub _create($type, %users) {
    return if $type eq 'sql';
    while (my ($name, $pass) = each %users) {
        if ( $type eq 'ldap') {
            create_ldap_user($name, $pass);
        }
    }
}

sub test_upload_users_nopassword( $type, $mojo=0 ) {

    my $user1 = new_domain_name();
    my $user2 =  new_domain_name();

    _clean_ldap($user1, $user2);
    _clean($user1, $user2);

    my $users = $user1."\n"
                .$user2."\n"
    ;

    if ($mojo) {
        $t->post_ok('/admin/users/upload.json' => form => {
                type => $type
                ,create => 0
                ,users => { content => $users, filename => 'users.txt', 'Content-Type' => 'text/csv' },
            })->status_is(200);
        die $t->tx->res->body if $t->tx->res->code != 200;

        my $response = $t->tx->res->json();
        is($response->{output}->{users_added} ,2);
        is_deeply($response->{error},[]);
    } else {
        rvd_front->upload_users($users, $type);
    }

    test_users_added($type, $user1,$user2);
}

sub test_upload_users( $type, $create=0, $mojo=0 ) {

    my ($user1, $pass1) = ( new_domain_name(), $$.1);
    my ($user2, $pass2) = ( new_domain_name(), $$.2);
    _clean_ldap($user1, $user2);

    _create($type, $user1, $pass1, $user2, $pass2) if !$create;
    _clean($user1, $user2);

    my $users = join(":",($user1, $pass1)) ."\n"
                .join(":",($user2, $pass2)) ."\n"
    ;

    if ($mojo) {
        $t->post_ok('/admin/users/upload.json' => form => {
                type => $type
                ,create => $create
                ,users => { content => $users, filename => 'users.txt', 'Content-Type' => 'text/csv' },
            })->status_is(200);
        die $t->tx->res->body if $t->tx->res->code != 200;

        my $response = $t->tx->res->json();
        is($response->{output}->{users_added} ,2);
        is_deeply($response->{error},[]);
    } else {
        rvd_front->upload_users($users, $type, $create);
    }
    if ($type ne 'sso') {
        $t->post_ok('/login' => form => {login => $user1, password => $pass1})
        ->status_is(302);
        $t->get_ok('/logout');
        $t->post_ok('/login' => form => {login => $user2, password => $pass2})
        ->status_is(302);
        $t->get_ok('/logout');

        _login($t);
    }
    $t->post_ok('/admin/users/upload.json' => form => {
            type => 'sql'
            ,users => { content => $users, filename => 'users.txt', 'Content-Type' => 'text/csv' },
})->status_is(200);

    exit if $t->tx->res->code == 401;
    die $t->tx->res->body if $t->tx->res->code != 200;

    my $response = $t->tx->res->json();
    is($response->{output}->{users_added},0);
    is(scalar(@{$response->{error}}),2);

    test_users_added($type, $user1, $user2);

    for my $name ($user1, $user2) {
        my $user = Ravada::Auth::SQL->new(name => $name);

        $t->get_ok('/admin/user/'.$user->id.".html")->status_is(200);
        die $t->tx->res->body if $t->tx->res->code != 200;

        $t->get_ok('/admin/user/'.$user->id.".json")->status_is(200);

        my $body = $t->tx->res->body;
        my $json;
        eval { $json = decode_json($body) };
        is($@, '') or die $body;

        is($json->{name}, $user->name);
    }

}

sub test_users_added($type, @name) {
    my $sth = connector->dbh->prepare(
        "SELECT * FROM users WHERE name=?"
    );
    for my $name (@name) {
        $sth->execute($name);
        my $row = $sth->fetchrow_hashref;
        is($row->{name},$name);
        if ($type eq 'sql') {
            is($row->{external_auth}, undef);
        } else {
            is($row->{external_auth},$type,"Expecting $name in $type");
        }
    }
}

sub _login($t) {
    my $user_name = new_domain_name();

    my $user_db = Ravada::Auth::SQL->new( name => $user_name);
    $user_db->remove();

    my $user = create_user($user_name, $$);
    user_admin->make_admin($user->id);

    mojo_login($t, $user_name, $$);
}

sub test_upload_no_admin($t) {
    my $user_name = new_domain_name();

    my $user_db = Ravada::Auth::SQL->new( name => $user_name);
    $user_db->remove();

    my $user = create_user($user_name, $$);
    die "Error, it shouldn't be admin" if $user->is_admin;

    mojo_login($t,$user_name, $$);
    my $users = join(":",('a','b' ));

    for my $type ( ('json','html', 'foo')) {
        $t->post_ok("/admin/users/upload.$type" => form => {
                type => 'sql'
                ,users => { content => $users, filename => 'users.txt', 'Content-Type' => 'text/csv' },
            })->status_is(403);

        die $t->tx->res->body if $t->tx->res->code != 403;
    }

}

sub _upload_group_members($group_name, $users, $mojo, $strict=0) {
    if ($mojo==1) {
        $t->post_ok("/group/upload_members.json" =>
            form => {
                users => { content => $users, filename => 'users.txt'
                            ,'Content-Type' => 'text/csv'
                }
                ,group => $group_name
                ,strict=> $strict
                },
            )->status_is(200);
        die $t->tx->res->body if $t->tx->res->code != 200;
    } elsif($mojo==2) {
        $t->post_ok("/admin/group/local/".$group_name =>
            form => {
                members => { content => $users, filename => 'users.txt'
                            ,'Content-Type' => 'text/csv'
                }
                ,group => $group_name
                ,strict=> $strict
                },
            )->status_is(200);
        die $t->tx->res->body if $t->tx->res->code != 200;

    } else {
        rvd_front->upload_group_members($group_name, $users, $strict);
    }
}


sub test_upload_group($mojo=0) {
    my ($user1) = ( new_domain_name(), $$.1);
    my ($user2) = ( new_domain_name(), $$.2);
    _clean($user1, $user2);

    my $users = $user1."\n".$user2."\n" ;

    my $group_name = new_domain_name();

    for ( 1 .. 2 ) {
        _upload_group_members($group_name, $users, $mojo);
        my $group = Ravada::Auth::Group->new( name => $group_name );

        my %members = map { $_ => 1 } $group->members;
        is(scalar(keys %members),2);
        ok($members{$user1});
        ok($members{$user2});
    }

    _upload_group_members($group_name, $user1, $mojo);

    my $group = Ravada::Auth::Group->new( name => $group_name );
    my %members = map { $_ => 1 } $group->members;
    is(scalar(keys %members),2);
    ok($members{$user1});
    ok($members{$user2});

    _upload_group_members($group_name, $user2, $mojo, 1);
    %members = map { $_ => 1 } $group->members;
    is(scalar(keys %members),1,"strict update mojo=$mojo failed");
    ok(!$members{$user1});
    ok($members{$user2});

}

sub test_upload_json_fail() {

    _do_upload_users_fail(0);
    _do_upload_users_fail(1);
}

sub _do_upload_users_fail($mojo, $type='openid') {
    my ($result, $error);
    if (!$mojo) {
        ($result, $error)=rvd_front->upload_users_json("wrong", $type);
    } else {
        $t->post_ok('/admin/users/upload.json' => form => {
                type => $type
                ,create => 0
                ,users => { content => "wrong", filename => 'data.json'
                    , 'Content-Type' => 'application/json' },
            })->status_is(200);
        die $t->tx->res->body if $t->tx->res->code != 200;

        my $response = $t->tx->res->json();
        $result = $response->{output};
        $error = $response->{error};
    }
    like($error->[0],qr/malformed JSON/);
    is_deeply($result, { groups_found => 0 , groups_added => 0, users_found => 0, users_added => 0});
}

sub test_upload_json() {

    test_upload_json_members();

    test_upload_json_members_flush();
    test_upload_json_members_remove_empty();

    test_upload_json_users_groups();
    test_upload_json_users_groups2();
    test_upload_json_users_admin();
    test_upload_json_users_pass();
    test_upload_json_users();
}

sub _do_upload_users_json($data, $mojo, $exp_result=undef, $type='openid') {

    confess if ref($mojo);
    confess if defined $exp_result && !ref($exp_result);

    my $data_h = $data;
    if (ref($data)) {
        $data = encode_json($data);
    } else {
        $data_h = decode_json($data);
    }
    if (!defined $exp_result) {
        $exp_result= { groups_found => 0, groups_added => 0, users_found=>0, users_added => 0};
        if ($data_h->{groups}) {
            $exp_result->{groups_found} = scalar(@{$data_h->{groups}});
            $exp_result->{groups_added} = scalar(@{$data_h->{groups}});
            confess"not array groups\n".Dumper($data_h) if ref($data_h->{groups}) ne 'ARRAY';
            for my $g ($data_h->{groups}) {
                next if !ref($g) || ref($g) ne 'HASH' || !exists $g->{members};
                $exp_result->{users_found} += scalar(@{$g->{members}});
                $exp_result->{users_added} += scalar(@{$g->{members}});
            }
        }
        if ($data_h->{users}) {
            $exp_result->{users_found} += scalar(@{$data_h->{users}});
            $exp_result->{users_added} += scalar(@{$data_h->{users}});
        };
    }
    my $users = $data_h->{users};
    if ($users) {
        for my $user (@$users) {
            my $name = $user;
            $name = $user->{name} if ref($user);
            next if !$name;
            remove_old_user($name);
        }
    }
    my ($result, $error);
    if (!$mojo) {
        ($result, $error)=rvd_front->upload_users_json($data, $type);
    } else {
        my $url='/admin/users/upload.json';
        $t->post_ok( $url => form => {
                type => $type
                ,create => 0
                ,users => { content => $data, filename => 'data.json'
                    , 'Content-Type' => 'application/json' },
            })->status_is(200);
        die $t->tx->res->body if $t->tx->res->code != 200;

        my $response = $t->tx->res->json();
        $result = $response->{output};
        $error = $response->{error};
    }

    for my $err (@$error) {
        ok(0,$err) unless $err =~ /already added|empty removed/;
    }
    is_deeply($result, $exp_result) or die Dumper(["mojo=$mojo",$data,$error,$result, $exp_result]);

}

sub test_upload_json_users() {
    _do_test_upload_json_users(0);
    _do_test_upload_json_users(1);
}

sub _do_test_upload_json_users($mojo) {
    my @users = ( new_domain_name(), new_domain_name() );
    my $data = {
        users => \@users
    };

    _do_upload_users_json( { users => \@users },$mojo );

    for my $name ( @users ) {
        my $user = Ravada::Auth::SQL->new(name => $name);
        ok($user->id, "Expecting user $name created");
        is($user->external_auth, 'openid');

        $user = undef;
        eval {
        $user = Ravada::Auth->login( $name , '');
        };
        like($@,qr/login failed/i);
        ok(!$user) or warn $user->name;
    }
}

sub test_upload_json_users_groups() {

    _do_test_upload_json_users_groups(0);
    _do_test_upload_json_users_groups(1);
}

sub _do_test_upload_json_users_groups($mojo) {
    my @users = (
         {name => new_domain_name() }
       , {name => new_domain_name(), is_admin => 1 }
    );
    my @groups = (
        new_domain_name()
        ,new_domain_name()
    );
    my $data = {
        users => \@users
        ,groups => \@groups
    };

    _do_upload_users_json( encode_json( $data ), $mojo, { groups_found => 2, groups_added => 2, users_found => 2, users_added => 2} );
    for my $u ( @users ) {
        my $user = Ravada::Auth::SQL->new(name => $u->{name});
        ok($user->id, "Expecting user $u->{name} created");
    }
    for my $g ( @groups) {
        my $group = Ravada::Auth::Group->new(name => $g);
        ok($group->id, "Expecting group $g created");
    }

}

sub test_upload_json_users_groups2() {
    _do_test_upload_json_users_groups2(0);
    _do_test_upload_json_users_groups2(1);
}

sub _do_test_upload_json_users_groups2($mojo) {
    my @users = (
         {name => new_domain_name() }
       , {name => new_domain_name(), is_admin => 1 }
    );
    my @groups = (
         {name => new_domain_name() }
        ,{name => new_domain_name() }
    );
    my $data = {
        users => \@users
        ,groups => \@groups
    };

    _do_upload_users_json( $data, $mojo );
    for my $u ( @users ) {
        my $user = Ravada::Auth::SQL->new(name => $u->{name});
        ok($user->id, "Expecting user $u->{name} created");
    }
    for my $g ( @groups) {
        my $group = Ravada::Auth::Group->new(name => $g->{name});
        ok($group->id, "Expecting group $g->{name} created");
    }

}

sub test_upload_json_members() {
    _do_test_upload_json_members(0);
    _do_test_upload_json_members(1);
}

sub _do_test_upload_json_members($mojo=0) {
    my @users_g0 = (
         new_domain_name()
         ,new_domain_name()
    );

    my @groups = (
         {name => new_domain_name()
             ,members => \@users_g0 }
        ,{name => new_domain_name() }
    );
    my $data = {
        groups => \@groups
    };

    _do_upload_users_json( encode_json( $data ),$mojo,{ groups_found => 2,groups_added => 2, users_found => 2, users_added => 2} );
    for my $u ( @users_g0 ) {
        my $user = Ravada::Auth::SQL->new(name => $u );
        ok($user->id, "Expecting user $u created");
    }
    for my $g ( @groups) {
        my $group = Ravada::Auth::Group->new(name => $g->{name});
        ok($group->id, "Expecting group $g->{name} created");
    }

    my $g0 = Ravada::Auth::Group->new(name => $groups[0]->{name});
    ok($g0->members,"Expecting members in ".$g0->name);

    for my $m (@{$groups[0]->{members}}) {
        my ($found) = grep (/^$m$/ , $g0->members);
        ok($found,"Expecting $m member");
    }

    my $g1 = Ravada::Auth::Group->new(name => $groups[1]->{name});
    ok(!$g1->members,"Expecting no members in ".$g1->name);

    # add more users
    my @users_g0b = (
         new_domain_name()
         ,new_domain_name()
         ,$users_g0[0]
    );

    $groups[0]->{members} = \@users_g0b;

    _do_upload_users_json( encode_json( {groups => \@groups}),$mojo, { groups_found => 2,groups_added => 0, users_found => 3, users_added => 2} );

    for my $name ( @users_g0 , @users_g0b ) {

        my $user = Ravada::Auth::SQL->new(name => $name );
        ok($user->id, "Expecting user $name created mojo=$mojo") or exit;

        my $g0 = Ravada::Auth::Group->new(name => $groups[0]->{name});
        my ($found) = grep (/^$name$/ , $g0->members);
        ok($found,"Expecting $name member");
    }
}

sub test_upload_json_members_flush() {
    _do_test_upload_json_members_flush(0);
    _do_test_upload_json_members_flush(1);
}

sub _do_test_upload_json_members_flush($mojo) {
    my @users_g0 = (
         new_domain_name()
         ,new_domain_name()
    );

    my @groups = (
         {name => new_domain_name()
             ,members => \@users_g0 }
        ,{name => new_domain_name() }
    );
    my $data = {
        groups => \@groups
    };

    _do_upload_users_json( encode_json( $data ),$mojo,{ groups_found => 2,groups_added => 2, users_found => 2, users_added => 2} );
    for my $u ( @users_g0 ) {
        my $user = Ravada::Auth::SQL->new(name => $u );
        ok($user->id, "Expecting user $u created");
    }
    for my $g ( @groups) {
        my $group = Ravada::Auth::Group->new(name => $g->{name});
        ok($group->id, "Expecting group $g->{name} created");
    }

    my $g0 = Ravada::Auth::Group->new(name => $groups[0]->{name});
    ok($g0->members,"Expecting members in ".$g0->name);

    for my $m (@{$groups[0]->{members}}) {
        my ($found) = grep (/^$m$/ , $g0->members);
        ok($found,"Expecting $m member");
    }

    my $g1 = Ravada::Auth::Group->new(name => $groups[1]->{name});
    ok(!$g1->members,"Expecting no members in ".$g1->name);

    # add more users
    my @users_g0b = (
         new_domain_name()
         ,new_domain_name()
         ,$users_g0[0]
    );

    $groups[0]->{members} = \@users_g0b;

    _do_upload_users_json( encode_json( {groups => \@groups, options => {'flush' => 1}}),$mojo, { groups_found => 2,groups_added => 0, users_found => 3, users_added => 2} );

    for my $name ( $users_g0[1] ) {

        my $user = Ravada::Auth::SQL->new(name => $name );
        ok($user->id, "Expecting user $name created");

        my $g0 = Ravada::Auth::Group->new(name => $groups[0]->{name});
        my ($found) = grep (/^$name$/ , $g0->members);
        ok(!$found,"Expecting no $name member") or exit;
    }

    for my $name ( @users_g0b ) {

        my $user = Ravada::Auth::SQL->new(name => $name );
        ok($user->id, "Expecting user $name created");

        my $g0 = Ravada::Auth::Group->new(name => $groups[0]->{name});
        my ($found) = grep (/^$name$/ , $g0->members);
        ok($found,"Expecting $name member");
    }

}

sub test_upload_json_members_remove_empty() {
    _do_test_upload_json_members_remove_empty(0);
    _do_test_upload_json_members_remove_empty(1);
}

sub _do_test_upload_json_members_remove_empty($mojo) {
    my @users_g0 = (
         new_domain_name()
         ,new_domain_name()
    );

    my @groups = (
         {name => new_domain_name()
             ,members => \@users_g0 }
        ,{name => new_domain_name() }
    );
    my $data = {
        groups => \@groups
    };

    _do_upload_users_json( encode_json( $data ), $mojo, { groups_found => 2,groups_added => 2, users_found => 2, users_added => 2} );
    for my $u ( @users_g0 ) {
        my $user = Ravada::Auth::SQL->new(name => $u );
        ok($user->id, "Expecting user $u created");
    }
    for my $g ( @groups) {
        my $group = Ravada::Auth::Group->new(name => $g->{name});
        ok($group->id, "Expecting group $g->{name} created");
    }

    my $g0 = Ravada::Auth::Group->new(name => $groups[0]->{name});
    ok($g0->members,"Expecting members in ".$g0->name);

    for my $m (@{$groups[0]->{members}}) {
        my ($found) = grep (/^$m$/ , $g0->members);
        ok($found,"Expecting $m member");
    }

    my $g1 = Ravada::Auth::Group->new(name => $groups[1]->{name});
    ok(!$g1->members,"Expecting no members in ".$g1->name);

    # add more users
    my @users_g0b = (
         new_domain_name()
         ,new_domain_name()
         ,$users_g0[0]
    );

    $groups[1]->{members} = \@users_g0b;
    $groups[0]->{members} = [];

    _do_upload_users_json( encode_json( {groups => \@groups, options => {'flush'=>1,'remove_empty'=>1}}), $mojo, { groups_found => 2,groups_added => 0, users_found => 3, users_added => 2, groups_removed => 1} );

    for my $name ( @users_g0b ) {

        my $user = Ravada::Auth::SQL->new(name => $name );
        ok($user->id, "Expecting user $name created");

        my $g1 = Ravada::Auth::Group->new(name => $groups[1]->{name});
        ok($g1 && $g1->id) or exit;
        my ($found) = grep (/^$name$/ , $g0->members);
        ok(!$found,"Expecting $name member") or exit;
    }

    $g0 = Ravada::Auth::Group->new(name => $groups[0]->{name});
    ok(!$g0->id,"Expecting $groups[0]->{name} removed");

}




sub test_upload_json_users_admin() {
    _do_test_upload_json_users_admin(0);
    _do_test_upload_json_users_admin(1);
}

sub _do_test_upload_json_users_admin($mojo) {
    my @users = (
         {name => new_domain_name() }
       , {name => new_domain_name(), is_admin => 0 }
       , {name => new_domain_name(), is_admin => 1 }
   );
    my $data = {
        users => \@users
    };

    _do_upload_users_json( $data, $mojo  );

    for my $u ( @users ) {
        my ($name, $password) = ($u->{name} , $u->{password});
        my $user = Ravada::Auth::SQL->new(name => $name);
        ok($user->id, "Expecting user $name created");
        is($user->external_auth, 'openid') or exit;
        $u->{is_admin}=0 if !exists $u->{is_admin};
        is($user->is_admin, $u->{is_admin});
    }


}

sub test_upload_json_users_pass() {
    _do_test_upload_json_users_pass(0);
    _do_test_upload_json_users_pass(1);
}

sub _do_test_upload_json_users_pass($mojo) {
    my $p1='a';
    my $p2 = 'b';
    my @users = (
         {name => new_domain_name(), password => $p1 }
       , {name => new_domain_name(), password => $p2 }
   );

    _do_upload_users_json( encode_json( { users => \@users }), $mojo, undef, 'sql' );

    for my $u ( @users ) {
        my ($name, $password) = ($u->{name} , $u->{password});
        my $user = Ravada::Auth::SQL->new(name => $name);
        ok($user->id, "Expecting user $name created");
        is($user->external_auth, '') or exit;

        $user = undef;
        eval {
        $user = Ravada::Auth::login( $name , $password);
        };
        is($@,'');
        ok($user,"Expecting $name/$password") or exit;
    }
}

################################################################################

$ENV{MOJO_MODE} = 'development';
$t = Test::Mojo->new($SCRIPT);
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

test_upload_no_admin($t);

_login($t);

test_upload_json_fail();

test_upload_json();

test_upload_group();
test_upload_group(1); # mojo
test_upload_group(2); # mojo post


for my $type ('ldap','sso') {
    test_upload_users_nopassword( $type );
    test_upload_users_nopassword( $type, 1 );
}

test_upload_users( 'sql',0,1 ); #test with mojo
test_upload_users( 'sql' ); # test without mojo

test_upload_users( 'ldap', 1 ); # create users in Ravada
test_upload_users( 'ldap', 1, 1 ); # create users in Ravada
for my $type ( 'ldap', 'sso' ) {
    test_upload_users( $type, 0 ,1 ); # do not create users in Ravada
}

done_testing();
