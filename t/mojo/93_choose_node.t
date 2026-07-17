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
    $t->get_ok("/v2/$item/list")->status_is(200);
    my $body = $t->tx->res->body;
    die $body if !$t->success();

    my @items = decode_json($body);

    return @items;

}

sub _test_new_storage($t, $name, $id_node_exp) {

    $t->get_ok("/storage/new")->status_is(200);
    my $init = $t->tx->res->dom->at('div#page-wrapper')->attr('ng-init');
    my ($id_node) = $init =~ /init\((\d+)/;
    is($id_node, $id_node_exp);
}

sub _test_new_network($t, $name, $id_node_exp) {
    $t->get_ok("/network/new")->status_is(200);
    my $init = $t->tx->res->dom->at('div#page-wrapper')->attr('ng-init');
    my ($id_node) = $init =~ /.+\((\d+)/;
    is($id_node, $id_node_exp, $init);

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

}

sub test_choose_node($t) {

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

    test_new($t,'storage',$selected2->{id});
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

    warn 11;
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
    warn 12;
    return 0;
}

sub _create_new_node($t) {
    return if _remote_node_up();
    for my $n ( '1', '2') {
        my $name = 'ztest-'.$n;
        my $domain = rvd_front->search_domain($name);
        warn $name;
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
 
##############################################################################3

$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);

$Test::Ravada::BACKGROUND=1;

my $t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

$USERNAME = user_admin->name;
$PASSWORD = "$$ $$";

mojo_login($t,$USERNAME, $PASSWORD);

test_node_gone($t);
test_choose_node($t);
test_connect_node($t);

end();
done_testing();
