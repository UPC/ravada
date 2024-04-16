use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use HTML::Lint;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';
use Mojo::JSON qw(decode_json);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $SECONDS_TIMEOUT = 15;

my $t;

my $URL_LOGOUT = '/logout';
my ($USERNAME, $PASSWORD);
my ($USERNAME2, $PASSWORD2);
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

$ENV{MOJO_MODE} = 'devel';

sub _clean_group($name) {
    my $ldap = Ravada::Auth::LDAP::_init_ldap_admin();
    for my $group (Ravada::Auth::LDAP::search_group(name => $name)) {
        diag("removing old LDAP group ".$group->dn);
        my $mesg=$ldap->delete($group);
        warn "ERROR: removing ".$group->dn." ".$mesg->code." : ".$mesg->error
        if $mesg->code;
    }
    my $group = Ravada::Auth::Group->new(name => $name);
    if ($group && $group->id) {
        diag("removing old group ".$name);
        $group->remove;
    }
    my $sth = connector->dbh->prepare("DELETE FROM group_access WHERE name=?");
    $sth->execute($name);
}

sub test_group_created($type, $name) {
    if ($type eq 'ldap') {
        my $group = Ravada::Auth::LDAP::search_group(name => $name);
        ok($group,"Expecting group $name in LDAP") or exit;
    } elsif ($type eq 'local') {
        my $group = Ravada::Auth::Group->new(name => $name);
        ok($group->id,"Expecting group $name in SQL") or exit;
    } else {
        die "Unknown type '$type'";
    }
}

sub test_list_users($type, $user_name) {

    $t->get_ok("/user/$type/list")->status_is(200);
    my $result = decode_json($t->tx->res->body);
    my ($found) = grep { $_->{name} eq $user_name} @{$result->{entries}};

    my ($filter) = $user_name =~ /(.)/;

    $t->get_ok("/user/$type/list")->status_is(200);
    $result = decode_json($t->tx->res->body);
    ($found) = grep { $_->{name} eq $user_name} @{$result->{entries}};
}

###################################################################
sub test_group($type) {
    my $group_name = new_domain_name();
    _clean_group($group_name);
    $t->post_ok("/group/new",json => { type => $type , group_name => $group_name })
    ->status_is(200);

    test_group_created($type, $group_name);

    my $user_name = new_domain_name();
    my $id_group;
    my @args;
    my $url_list_members = "/group/$type/list_members/$group_name";
    my $url_admin_group = "/admin/group/$type/$group_name";
    if ($type eq 'ldap') {
        create_ldap_user($user_name,$$);
        push @args,(name => $user_name);
        push @args,(group => $group_name);

    } else {
        my $group = Ravada::Auth::Group->new(name => $group_name);
        my $id_group = $group->id;
        $url_list_members = "/group/$type/list_members/$id_group";
        $url_admin_group = "/admin/group/$type/$id_group";
        my $login;
        eval { $login = Ravada::Auth::SQL->new(name => $user_name ) };
        $login->remove if $login && $login->id;
        my $user = create_user($user_name);
        push @args,( id_user => $user->id );
        push @args,( id_group => $group->id);
    }

    test_list_users($type,$user_name);

    $t->post_ok("/group/$type/add_member", json => {@args})->status_is(200);
    my $result = decode_json($t->tx->res->body);
    is($result->{error},'');

    diag($url_list_members);
    $t->get_ok($url_list_members)->status_is(200);
    my $members = decode_json($t->tx->res->body);
    my ($found) = grep {$_->{name} eq $user_name } @$members;
    ok($found) or warn "Expecting $user_name in group $group_name ".Dumper($members);
    die if !$found;

    my $id_domain = test_access($type, $group_name, $user_name);

    if ($type eq 'ldap') {
        my $entry = Ravada::Auth::LDAP::search_user(name => $user_name);
        my $dn = $entry->dn;
        $url_list_members = "/group/$type/list_members/$group_name";
        $url_admin_group = "/admin/group/$type/$group_name";
    }
    $t->post_ok("/group/$type/remove_member", json => {@args})->status_is(200);
    die $t->tx->res->body if $t->tx->res->code != 200;
    my $result2 = decode_json($t->tx->res->body);
    is($result2->{error},'');

    $t->get_ok($url_list_members)->status_is(200);
    my $members2 = decode_json($t->tx->res->body);
    is_deeply($members2,[]) or exit;

    $t->get_ok($url_admin_group)->status_is(200);
    die $t->tx->res->body if $t->tx->res->code != 200;

    test_list_groups($type, $group_name);

    test_group_removed($type, $group_name, $user_name, $id_domain);

    mojo_login($t, $USERNAME2, $PASSWORD2);
    $t->get_ok($url_admin_group)->status_is(403);

    mojo_login($t, $USERNAME, $PASSWORD);

}

sub test_list_groups($type, $group_name) {
    $t->get_ok("/group/$type/list")->status_is(200);
    return if $t->tx->res->code != 200; my $list = decode_json($t->tx->res->body);
    return if ref($list) ne 'ARRAY';


    ok(grep({$_ eq $group_name } @$list), "Missing $type $group_name in ".Dumper($list));

    my ($first) = $group_name =~ /^(.)/;
    $t->get_ok("/group/$type/list/$first")->status_is(200);
    $list = decode_json($t->tx->res->body);
    return if ref($list) ne 'ARRAY';

    ok(grep({$_ eq $group_name } @$list), "Missing $type $group_name in ".Dumper($list));

}

sub test_add_access($type,$group_name, $user_name, $id_domain) {
    my $url_add_access = "/machine/add_access_group/$type/$id_domain";
    my $id_group = '';
    $t->post_ok($url_add_access, json => { group => $ group_name })
    ->status_is(200);
    my $result = decode_json($t->tx->res->body);
    is($result->{error},'');

    my $sth;
    if ($type eq 'ldap') {
        $sth = connector->dbh->prepare( "SELECT * FROM group_access WHERE name=?");
        $sth->execute($group_name);
    } else {
        my $group = Ravada::Auth::Group->new(name => $group_name);
        $sth = connector->dbh->prepare( "SELECT * FROM group_access WHERE id_group=?");
        $id_group = $group->id;
        $sth->execute($id_group);
    }
    my ($found) = $sth->fetchrow_hashref();
    ok($found,"Expecting group access by name=$group_name") or exit;
    is($found->{type}, $type);

    my $user = Ravada::Auth::SQL->new(name => $user_name);
    is($user->allowed_access($id_domain),1);
    my $list2 = rvd_front->list_machines_user($user);

    my ($found_machine) = grep { $_->{id} eq $id_domain } @$list2;
    ok($found_machine,"Expecting $id_domain") or die Dumper([ map {$_->{id} } @$list2]);

    $t->get_ok("/machine/list_access_groups/$type/$id_domain")->status_is(200);

    my $list_groups = decode_json($t->tx->res->body);
    is($result->{error},'');

    my ($found_groups) = grep ( { $_ eq $group_name } @$list_groups);
    is($found_groups,$group_name) or die Dumper($list_groups) ;

}

sub test_remove_access($type, $group_name, $user_name, $id_domain) {
    my $url = "/machine/remove_access_group/$type/$id_domain";
    $t->post_ok($url, json => { group => $group_name })
    ->status_is(200);
    $t->get_ok("/machine/list_access_groups/$type/$id_domain")->status_is(200);

    my $list_groups = decode_json($t->tx->res->body);

    my ($found_groups) = grep ( { $_ eq $group_name } @$list_groups);
    is($found_groups, undef) or die Dumper($list_groups);

}

sub _search_id_domain {
    my $list = rvd_front->list_machines_user(user_admin);
    my ($domain) = grep { $_->{is_public} } @$list;
    if (!$domain) {
        ($domain) = $list->[0];
    }
    return $domain->{id};
}

sub test_access($type, $group_name, $user_name) {
    my $id_domain = _search_id_domain();
    test_add_access($type, $group_name, $user_name, $id_domain);
    test_remove_access($type, $group_name, $user_name, $id_domain);
    return $id_domain;
}

sub test_group_removed($type, $group_name, $user_name, $id_domain) {

    my $group0 = Ravada::Auth::Group->new(name => $group_name);
    my $id_group = $group0->id;

    my $user = Ravada::Auth::SQL->new( name => $user_name);

    $t->post_ok("/group/$type/add_member", json => {id_user => $user->id, id_group => $id_group,group => $group_name })->status_is(200);

    $t->post_ok("/machine/add_access_group/$type/$id_domain",json => { group => $group_name})
        ->status_is(200);

    if ($type eq 'ldap') {
        $t->get_ok("/group/$type/remove/$group_name")->status_is(200);
    } else {
        $t->get_ok("/group/$type/remove/$id_group")->status_is(200);
    }

    die $t->tx->res->body if $t->tx->res->code != 200;

    if ($type eq 'ldap') {
        my $group = Ravada::Auth::LDAP::search_group(name => $group_name);
        ok(!$group,"Expecting no group $group_name in LDAP") or exit;
    } elsif ($type eq 'local') {
        my $group = Ravada::Auth::Group->new(name => $group_name);
        ok(!$group->id,"Expecting no group $group_name in SQL") or exit;

        my $sth = connector->dbh->prepare("SELECT count(*) FROM users_group "
            ." WHERE id_group=?"
        );
        $sth->execute($id_group);
        my ($found) = $sth->fetchrow;
        is($found,0);

    } else {
        die "Unknown type '$type'";
    }

    my $sth2 = connector->dbh->prepare("SELECT * FROM group_access "
        ." WHERE name = ?"
    );
    $sth2->execute($group_name);
    my ($found) = $sth2->fetchrow_hashref;
    is($found,undef);

    if ($type eq'ldap') {
        $t->get_ok("/admin/group/$type/$group_name")->status_is(404);
    } else {
        $t->get_ok("/admin/group/$type/$id_group")->status_is(404);
    }

}

###################################################################

init('/etc/ravada.conf',0);
$Test::Ravada::BACKGROUND=1;
($USERNAME, $PASSWORD) = ( user_admin->name, "$$ $$");
($USERNAME2, $PASSWORD2) = ( user->name, "$$ $$");

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);


mojo_login($t, $USERNAME, $PASSWORD);

test_group('ldap');
test_group('local');

done_testing();
