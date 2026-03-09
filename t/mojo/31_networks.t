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
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

my %FILES;
my %HREFS;

my %MISSING_LANG = map {$_ => 1 }
    qw(ca-valencia he ko cs);

my $ID_DOMAIN;

sub _remove_nodes($vm_name) {
    my @list_nodes = rvd_front->list_vms();

    my $name = base_domain_name();
    my @found = grep { $_->{name} =~ /^$name/} @list_nodes;

    for my $found (@found) {

        $t->get_ok("/v1/node/remove/".$found->{id});
        is($t->tx->res->code(),200) or die $t->tx->res->body;
    }

}

sub _remove_networks($id_vm) {
    my $sth = connector->dbh->prepare("SELECT vn.id FROM virtual_networks vn, vms v"
        ." WHERE vn.id_vm=v.id "
        ."   AND v.id=? AND vn.name like ?"
    );
    $sth->execute($id_vm, base_domain_name."%");

    while ( my ($id) = $sth->fetchrow) {
        my $id_req = mojo_request($t, "remove_network", { id => $id});
        if ($id_req) {
            my $req = Ravada::Request->open($id_req);
            die "Error in ".$req->command." id=$id" if $req->error;
        }
    }

}

sub _id_vm($vm_name) {
    my $sth = connector->dbh->prepare("SELECT id,hostname FROM vms "
        ." WHERE vm_type=? AND is_active=1");
    $sth->execute($vm_name);
    my @vm;
    while (my $row = $sth->fetchrow_hashref ) {
        push @vm,($row);
    }
    my ($vm) = grep { $_->{hostname} eq 'localhost' } @vm;

    my $id_vm;
    $id_vm = $vm->{id}      if $vm;
    $id_vm = $vm[0]->{id}   if !$id_vm;

    return $id_vm;
}

sub test_networks_access($vm_name) {

    my ($name, $pass) = (new_domain_name, "$$ $$");
    my $user = create_user($name, $pass,0 );
    is($user->is_admin,0 );
    mojo_login($t, $name, $pass);

    my $id_vm = _id_vm($vm_name);

    my @urls =(
        "/admin/networks", "/network/new"
        , "/v2/vm/list_networks/$id_vm","/v2/network/new/".$id_vm);
    for my $url (@urls) {
        $t->get_ok($url)->status_is(403);
    }

    user_admin->grant($user,'create_networks');
    for my $url (@urls) {
        $t->get_ok($url)->status_is(200);
    }

    user_admin->revoke($user,'create_networks');
    user_admin->grant($user,'manage_all_networks');
    for my $url (@urls) {
        $t->get_ok($url)->status_is(200);
    }

    $user->remove();
    mojo_login($t, $USERNAME, $PASSWORD);

}

sub test_networks_access_grant($vm_name) {

    my ($name, $pass) = (new_domain_name, "$$ $$");
    my $user = create_user($name, $pass,0 );
    user_admin->grant($user,"create_networks");
    mojo_login($t, $name, $pass);

    my $id_vm = _id_vm($vm_name);

    $t->post_ok("/v2/network/new/".$id_vm => json => { name => base_domain_name() });
    my $data = decode_json($t->tx->res->body);
    ok(keys %$data) or die Dumper($data);

    $t->post_ok("/v2/network/set/" => json => $data );
    my $new_ok = decode_json($t->tx->res->body);
    ok($new_ok->{id_network}) or return;

    $t->get_ok("/settings/network".$new_ok->{id_network}.".html");

    $t->get_ok("/v2/vm/list_networks/".$id_vm);
    my $networks2 = decode_json($t->tx->res->body);
    my ($old) = grep { $_->{name} ne $data->{name} } @$networks2;
    ok($old,"Expecting more networks for VM $vm_name [ $id_vm ]")
        or die Dumper([map {$_->{name} } @$networks2]);

    is($old->{_can_change},0) or exit;

    $t->get_ok("/network/settings/".$old->{id}.".html")->status_is(403);
    $old->{autostart}=0;

    $t->post_ok("/v2/network/set/" => json => $old)->status_is(403);

    my ($new) = grep { $_->{name} eq $data->{name} } @$networks2;
    ok($new,"Expecting new network $data->{name}")
        or die Dumper([map {$_->{name} } @$networks2]);
    is($new->{_owner}->{id},$user->id);
    is($new->{_can_change},1) or exit;

    for ( 1 .. 2 ) {
        $new->{is_active} = 0+(!$new->{is_active} or 0);
        $t->post_ok("/v2/network/set/" => json => $new)->status_is(200);
        wait_request();

        $t->get_ok("/v2/vm/list_networks/".$id_vm);

        my $networks3 = decode_json($t->tx->res->body);
        my ($net3) = grep { $_->{name} eq $new->{name}} @$networks3;
        is($net3->{is_active}, $new->{is_active}) or die $net3->{name};
    }

    for ( 1 .. 2 ) {
        $new->{is_public} = 0+(!$new->{is_public} or 0);
        $t->post_ok("/v2/network/set/" => json => $new)->status_is(200);
        wait_request();

        $t->get_ok("/v2/vm/list_networks/".$id_vm);
        my $networks4 = decode_json($t->tx->res->body);
        my ($net4) = grep { $_->{name} eq $new->{name}} @$networks4;
        is($net4->{is_public}, $new->{is_public}) or exit;
    }

    mojo_login($t, $USERNAME, $PASSWORD);

}

sub test_networks_admin($vm_name) {
    mojo_check_login($t);

    for my $url (qw( /admin/networks/ /network/new) ) {
        $t->get_ok($url);
        is($t->tx->res->code(),200, "Expecting access to $url");
    }

    my $id_vm = _id_vm($vm_name);
    die "Error: I can't find if for vm type = $vm_name" if !$id_vm;

    _remove_networks($id_vm);

    $t->get_ok("/v2/vm/list_networks/".$id_vm);
    my $networks = decode_json($t->tx->res->body);
    ok(scalar(@$networks));

    $t->post_ok("/v2/network/new/".$id_vm => json => { name => base_domain_name() });
    my $data = decode_json($t->tx->res->body);

    $t->post_ok("/v2/network/set/" => json => $data );

    my $new_ok = decode_json($t->tx->res->body);
    ok($new_ok->{id_network}) or die Dumper([$t->tx->res->body, $new_ok]);

    $t->get_ok("/v2/vm/list_networks/".$id_vm);
    my $networks2 = decode_json($t->tx->res->body);
    my ($new) = grep { $_->{name} eq $data->{name} } @$networks2;

    ok($new);
    is($new->{_can_change},1) or exit;
    is($new->{_owner}->{id},user_admin->id) or exit;
    $new->{is_active} = 0;

    $t->post_ok("/v2/network/set/" => json => $new);
    wait_request(debug => 0);
    $t->get_ok("/v2/vm/list_networks/".$id_vm);

    my $networks3 = decode_json($t->tx->res->body);
    my ($changed) = grep { $_->{name} eq $data->{name} } @$networks3;
    is($changed->{is_active},0) or die $changed->{name};

    $t->get_ok("/v2/network/info/".$changed->{id});

    my $changed4 = decode_json($t->tx->res->body);
    is($changed4->{is_active},0) or exit;

    $new->{is_public}=1;
    $t->post_ok("/v2/network/set/" => json => $new);
    wait_request(debug => 0);
    $t->get_ok("/v2/vm/list_networks/".$id_vm);

    my $networks5 = decode_json($t->tx->res->body);
    my ($changed5) = grep { $_->{name} eq $data->{name} } @$networks5;
    is($changed5->{is_public},1) or warn Dumper($changed5);

}

sub clean_clones() {
    wait_request( check_error => 0, background => 1);
    for my $domain (@{rvd_front->list_domains}) {
        my $base_name = base_domain_name();
        next if $domain->{name} !~ /$base_name/;
        remove_domain_and_clones_req($domain,0);
    }
}

sub _create_storage_pool($id_vm , $vm_name) {
    $t->get_ok("/list_storage_pools/$vm_name");
    my $sp = decode_json($t->tx->res->body);
    my $name = new_pool_name();
    my ($found) = grep { $_->{name} eq $name } @$sp;
    return $name if $found;

    my $dir0 = "/var/tmp/$$/";

    mkdir $dir0 if !-e $dir0;

    my $dir = $dir0."/".new_pool_name();

    mkdir $dir or die "$! $dir" if !-e $dir;


    my $req = Ravada::Request->create_storage_pool(
        uid => user_admin->id
        ,id_vm => $id_vm
        ,name => $name
        ,directory => $dir
    );
    wait_request( );
    is($req->error,'');

    return $name;
}

sub test_storage_pools($vm_name) {

    my $id_vm = _id_vm($vm_name);
    my $sp_name = _create_storage_pool($id_vm, $vm_name);

    $t->get_ok("/list_storage_pools/$vm_name");

    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $sp = decode_json($t->tx->res->body);
    ok(scalar(@$sp));

    $t->get_ok("/list_storage_pools/$id_vm");

    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $sp_id = decode_json($t->tx->res->body);
    ok(scalar(@$sp_id));
    is_deeply($sp_id, $sp);

    my ($sp_inactive) = grep { $_->{name} ne 'default' } @$sp_id;

    my $name_inactive= $sp_inactive->{name};
    die "Error, no name in ".Dumper($sp_inactive) if !$name_inactive;

    mojo_request($t, "active_storage_pool"
        ,{ id_vm => $id_vm, name => $name_inactive, value => 0 });

    $t->get_ok("/list_storage_pools/$vm_name?active=1");

    is($t->tx->res->code(),200) or die $t->tx->res->body;

    my $sp_active = decode_json($t->tx->res->body);
    my ($found) = grep { $_->{name} eq $name_inactive } @$sp_active ;
    ok(!$found,"Expecting $name_inactive not found");

    mojo_request($t, "active_storage_pool"
        ,{ id_vm => $id_vm, name => $name_inactive, value => 1 });

    $t->get_ok("/list_storage_pools/$vm_name?active=1");
    $sp_active = decode_json($t->tx->res->body);
    ok(scalar(@$sp_active));
    ($found) = grep { $_->{name} eq $name_inactive } @$sp_active ;
    ok($found,"Expecting $name_inactive found");

}

sub  _search_public_base() {
    my $sth = connector->dbh->prepare(
        "SELECT id FROM domains WHERE is_public=1 "
        ." AND name <> 'ztest'"
    );
    $sth->execute();
    my ($id) = ($sth->fetchrow or '999');
    return $id;
}

########################################################################################

$ENV{MOJO_MODE} = 'devel';
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

if (!rvd_front->ping_backend) {
    diag("SKIPPED: no backend");
    done_testing();
    exit;
}
$Test::Ravada::BACKGROUND=1;

($USERNAME, $PASSWORD) = ( user_admin->name, "$$ $$");

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

mojo_login($t, $USERNAME, $PASSWORD);

remove_old_domains_req(0); # 0=do not wait for them
clean_clones();
remove_networks_req();

$ID_DOMAIN = _search_public_base();

for my $vm_name (reverse @{rvd_front->list_vm_types} ) {

    diag("Testing settings in $vm_name");

    test_networks_access( $vm_name );
    test_networks_access_grant($vm_name);
    test_networks_admin( $vm_name );
}

clean_clones();
remove_old_users();
remove_networks_req();

done_testing();
