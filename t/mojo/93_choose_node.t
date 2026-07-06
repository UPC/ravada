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
 
sub test_choose_node($t) {

    my $body_json = _list_nodes_active($t);
    die "Error: I need more than one node ".Dumper($body_json)
    unless scalar (@$body_json)>1;

    $t->get_ok("/admin/networks/")->status_is(200);
    $t->get_ok("/admin/storage/")->status_is(200);

    $t->get_ok("/v3/networks/list")->status_is(200);
    my $body_networks1 = $t->tx->res->body;
    die $body_networks1 if !$t->success();

    my @networks1 = decode_json($body_networks1);


    my ($selected) = grep { $_->{_selected}} @$body_json;

    ok($selected,"Expecting one _selected node")
    or die Dumper($body_json);

    my ($new_node) = grep { $_->{id} != $selected->{id}} @$body_json;

    $t->get_ok("/v3/choose_node/".$new_node->{id})->status_is(200);

    my $body_json2 = _list_nodes_active($t);

    my ($selected2) = grep { $_->{_selected}} @$body_json2;
    ok($selected2,"Expecting one _selected") or die Dumper($body_json2);
    is($selected2->{name}, $new_node->{name}) or exit;

    my $body_networks2 = $t->tx->res->body;
    my @networks2 = decode_json($body_networks2);

    isnt(join('',@networks1), join('',@networks2));

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
