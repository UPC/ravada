use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use Test::Mojo;
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::JSON qw(decode_json);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

$ENV{MOJO_MODE} = 'development';
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

my ($USERNAME, $PASSWORD);

##############################################################################3

sub _list_nodes_active($t) {

    $t->get_ok("/list_nodes_active.json")->status_is(200);
    my $body = $t->tx->res->body;

    die $body if !$t->success;
    my $body_json;
    eval { $body_json = decode_json($body)};

    return $body_json;
}

sub test_connect_node($t) {

    my $body_json = _list_nodes_active($t);
    die "Error: I need more than one node ".Dumper($body_json)
    unless scalar (@$body_json)>1;

    my ($selected) = grep { $_->{_selected}} @$body_json;

    die "Expecting one _selected node".Dumper($body_json)
    unless $selected;

    my ($new_node) = grep { $_->{id} != $selected->{id}} @$body_json;

    $t->post_ok("/request/connect_node/" => json => { id_node => $new_node->{id}})
        ->status_is(200);

    my $body = $t->tx->res->body;
    my $args = decode_json($body);
    like($args->{request},qr/^\d+$/);

    wait_request(debug => 0, check_error => 0);
    my $req = Ravada::Request->open($args->{request});
    is($req->status(),'done');
}
 
sub _get_item($t, $item) {

    $item = 'networks' if $item eq 'network';

    $t->get_ok("/v2/$item/list")->status_is(200);
    my $body = $t->tx->res->body;
    die "/v2/$item/list" if !$t->success();

    my $items = decode_json($body);

    return @$items;

}

sub _test_new_storage($t, $name, $id_node_exp) {

    $t->get_ok("/storage/new")->status_is(200);
    my $init = $t->tx->res->dom->at('div#page-wrapper')->attr('ng-init');
    my ($id_node) = $init =~ /init\((\d+)/;
    is($id_node, $id_node_exp);

    $t->post_ok("/request/create_storage_pool" => json => { name => $name , directory => "/var/tmp"})
        ->status_is(200);

    _test_request($t, $id_node_exp);

}

sub _test_request($t, $id_node=undef) {
    my $body = $t->tx->res->body;
    my $content = decode_json($body);
    my $req = Ravada::Request->open($content->{request});

    if (defined $id_node) {
        is($req->args('id_vm'), $id_node) or die Dumper($req->args());
    }
    wait_request(debug => 1, request => $req);
    is($req->status(),'done');
    is($req->error,'');
    return $req;
}

sub _test_new_network($t, $name, $id_node_exp) {
    $t->get_ok("/network/new")->status_is(200);
    my $init = $t->tx->res->dom->at('div#page-wrapper')->attr('ng-init');
    my ($id_node) = $init =~ /.+\((\d+)/;
    is($id_node, $id_node_exp, $init);

    $t->post_ok("/request/new_network" => json => { name => $name});
    my $req = _test_request($t, $id_node_exp);

    my $data = decode_json($req->output);

    $t->post_ok("/request/create_network/" => json =>
        { data => $data })
        ->status_is(200);

    _test_request($t, $id_node_exp);
}

sub _test_remove($t, $item, $name, $id) {

    my $req = "remove_$item";

    my $args = { id => $id};

    if ($item eq 'storage') {
        $req = "remove_storage_pool";
        $args = { name => $name };
    } else {
        confess if !defined $id
    }

    $t->post_ok("/request/$req" => json =>  $args )
        ->status_is(200);

    _test_request($t);
    my @elements = _get_item($t, $item);

    my ($found) = grep { $_->{name} eq $name } @elements;
    ok(!$found, "Expecting $item $name not found in ".Dumper([map { $_->{name}} @elements])) or exit;
}

sub test_new($t, $item, $id_node) {

    my %sub = (
        storage => \&_test_new_storage
        ,network => \&_test_new_network
    );
    my $sub = $sub{$item};
    confess "Error: no test for new $item" if !$sub;

    my $name = new_domain_name();
    $sub->($t, $name, $id_node);

    my @elements = _get_item($t, $item);

    my ($found) = grep { $_->{name} eq $name } @elements;
    ok($found,"Expecting $item $name in node $id_node") or exit;

    _test_remove($t, $item, $name, $found->{id});
}

sub test_choose_node_wrong($t) {
    my $body_json = _list_nodes_active($t);
    die "Error: I need more than one node ".Dumper($body_json)
    unless scalar (@$body_json)>1;

    my %ids;
    for (@$body_json) {
        $ids{$_->{id}}++;
    }

    my $id_wrong=1;
    for (;;) {
        last if !exists $ids{$id_wrong};
        $id_wrong++;
    }

    $t->get_ok("/v3/choose_node/")->status_is(404);
    $t->get_ok("/v3/choose_node/".$id_wrong)->status_is(400);
}

sub test_choose_node($t, $create_storage=1) {

    my $body_json = _list_nodes_active($t);
    die "Error: I need more than one node ".Dumper($body_json)
    unless scalar (@$body_json)>1;

    my ($selected1) = grep { $_->{_selected}} @$body_json;

    ok($selected1,"Expecting one _selected node")
    or die Dumper($body_json);

    my ($new_node) = grep { $_->{id} != $selected1->{id}} @$body_json;

    $t->get_ok("/admin/networks/")->status_is(200);
    $t->get_ok("/admin/storage/")->status_is(200);

    my @networks1 = _get_item($t,'networks');
    my @storage1 = _get_item($t,'storage');

    $t->get_ok("/v3/choose_node/".$new_node->{id})->status_is(200);

    my $body_json2 = _list_nodes_active($t);

    my ($selected2) = grep { $_->{_selected}} @$body_json2;
    isnt($selected2, $selected1);
    ok($selected2,"Expecting one _selected") or die Dumper($body_json2);
    is($selected2->{name}, $new_node->{name}) or exit;

    my @networks2 = _get_item($t,'networks');
    isnt(join('',@networks1), join('',@networks2));

    test_new($t,'storage',$selected2->{id}) if $create_storage;
    test_new($t,'network',$selected2->{id});

    my @storage2= _get_item($t,'storage');
    isnt(join('',@storage1), join('',@storage2));

    $t->get_ok("/v3/choose_node/".$selected1->{id})->status_is(200);
}

sub _connect_node($name) {
    my ($node) = grep { $_->{name} eq $name } rvd_front->list_vms();
    return if !$node;
    Ravada::Request->connect_node(
        uid => user_admin->id
        ,id_node => $node->{id}
    );
    wait_request(debug => 0);
    return 1;
}

sub _remote_node_up() {
    my $sth = connector->dbh->prepare(
        "SELECT id,name,enabled,is_active "
        ." FROM vms WHERE hostname <> 'localhost'"
    );
    $sth->execute();

    while (my ($id,$name, $enabled, $is_active) = $sth->fetchrow) {
        diag("Node $name [ $id ] enable=$enabled active=$is_active");
        return $id if $enabled && $is_active;
        my $domain = rvd_front->search_domain($name);
        next if !$domain;
        Ravada::Request->start_domain(
            uid => user_admin->id
            ,id_domain => $domain->id
        );
        wait_request(debug => 0);
        wait_ip($domain->id);
        return _connect_node($domain->name);
    };
    return 0;
}

sub _create_new_node($t) {
    return if _remote_node_up();
    for my $n ( '1', '2') {
        my $name = 'ztest-'.$n;
        my $domain = rvd_front->search_domain($name);
        if ( $domain ) {
            rvd_front->add_node(
                name => 'ztest-'.$n
                ,'hostname' => '192.168.122.15'.$n
                ,'vm_type' => 'KVM'
            );
            wait_request();
        }
        last if _connect_node($name);
    }
}

sub _choose_remote_node($t) {

    my $body_json = _list_nodes_active($t);

    my ($selected) = grep { $_->{_selected}} @$body_json;

    return if $selected->{hostname} ne 'localhost' && $selected->{hostname} !~ /^127\./;

    my ($new_node) = grep {
        $_->{hostname} ne 'localhost'
        && $_->{hostname} !~ /^127/
    } @$body_json;

    return $new_node if $new_node;

    if ( !$new_node ) {
        _create_new_node($t);
        $body_json = _list_nodes_active($t);

        ($new_node) = grep {
            $_->{hostname} ne 'localhost'
            && $_->{hostname} !~ /^127/
        } @$body_json;

        return $new_node if $new_node;
    }

    die "Error: can not select active remote node ".Dumper($body_json);
}

sub test_node_gone($t) {
    my $node = _choose_remote_node($t);

    my $new_name = new_domain_name();

    rvd_front->add_node(
        name => $new_name
        ,'hostname' => $node->{hostname}
        ,'vm_type' => 'Void'
    );
    wait_request();

    my ($new_node) = grep { $_->{name} eq $new_name } rvd_front->list_vms();
    $t->get_ok("/v3/choose_node/".$new_node->{id})->status_is(200);
    $t->get_ok('/v1/node/remove/'.$new_node->{id})->status_is(200);

    my $body_json = _list_nodes_active($t);
    my ($selected) = grep { $_->{_selected}} @$body_json;
    isnt($selected->{id}, $node->{id});
}

sub test_choose_node_oper($t) {

    my $user = create_user( new_domain_name(), $$);
    user_admin->grant($user,"create_networks");

    is($user->is_operator(),1);
    mojo_login($t,$user->name, $$);

    test_choose_node($t, 0);

    mojo_login($t,$USERNAME, $PASSWORD);
}

##############################################################################

$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);

$Test::Ravada::BACKGROUND=1;

my $t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

$USERNAME = user_admin->name;
$PASSWORD = "$$ $$";

mojo_login($t,$USERNAME, $PASSWORD);

test_choose_node_wrong($t);
test_node_gone($t);
test_choose_node($t);
test_connect_node($t);

test_choose_node_oper($t);

end();
done_testing();
