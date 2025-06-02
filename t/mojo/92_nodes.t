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

my $URL_LOGOUT = '/logout';

##############################################################################3

sub test_new_node($t) {

    $t->get_ok("/admin/nodes")->status_is(200);
    $t->get_ok("/list_nodes.json")->status_is(200);
    my $body = $t->tx->res->body;
    my $body_json;
    eval { $body_json = decode_json($body)};

    my $name;
    for (;;) {
        $name = new_domain_name();
        last if !grep { $_->{name} eq $name } @$body_json;
    }

    $name .= int(rand(10));
    $t->get_ok("/v1/node/new")->status_is(200);
    my $dom = Mojo::DOM->new($t->tx->res->body);
    my $form = $dom->find('form')->grep( sub {$_->attr('name') eq 'new_nodeForm'});
    my $collection = $form->[0]->find('input');
    is(scalar(@$collection),3);
    ok(grep { $_->attr('name') eq 'name' } @$collection);
    ok(grep { $_->attr('name') eq 'hostname' } @$collection);

    $t->post_ok("/v1/node/new" => form => {
            name => $name
            ,hostname => '192.0.2.3'
            ,_submit => 'submit'
            ,vm_type => 'Void'
        }
    )->status_is(200);

    $t->get_ok("/list_nodes.json")->status_is(200);
    $body = $t->tx->res->body;
    eval { $body_json = decode_json($body)};

    my $new_node = grep {$_->{name} eq $name } @$body_json;
    ok($new_node);
    return $new_node;
}

sub test_update_node($t, $node) {
}

##############################################################################3

$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);

if (!ping_backend()) {
    diag("SKIPPED: no backend");
    done_testing();
    exit;
}
$Test::Ravada::BACKGROUND=1;

my $t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

$USERNAME = user_admin->name;
$PASSWORD = "$$ $$";

mojo_login($t,$USERNAME, $PASSWORD);

my $new_node = test_new_node($t);
test_update_node($t, $new_node);

end();
done_testing();
