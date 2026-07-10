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

    wait_request(debug => 1, check_error => 0);
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

sub _test_new_storage($t, $name) {
}

sub _test_new_network($t, $name) {

}


sub test_new($t, $item) {

    diag("/$item/new");
    $t->get_ok("/$item/new")->status_is(200);

    my %sub = (
        storage => \&_test_new_storage
        ,network => \&_test_new_network
    );
    my $sub = $sub{$item};
    confess "Error: no test for new $item" if !$sub;

    my $name = new_domain_name();
    $sub->($t, $name);

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

    test_new($t,'network');
    test_new($t,'storage');

    my @storage2= _get_item($t,'storage');
    isnt(join('',@storage1), join('',@storage2));

    $t->get_ok("/v3/choose_node/".$selected1->{id})->status_is(200);
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

test_choose_node($t);
test_connect_node($t);

end();
done_testing();
