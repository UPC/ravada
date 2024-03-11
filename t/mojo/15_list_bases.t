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

########################################################################################

sub _create_base($vm_name) {
    my $name = new_domain_name();

    my $iso_name = 'Alpine%';
    mojo_check_login($t);
    $t->post_ok('/new_machine.html' => form => {
            backend => $vm_name
            ,id_iso => search_id_iso($iso_name)
            ,name => $name
            ,disk => 1
            ,ram => 1
            ,swap => 1
            ,start => 0
            ,submit => 1
        }
    )->status_is(302);
    die $t->tx->res->body if $t->tx->res->code() != 302;
    wait_request();
    my $base=_wait_domain($name);

    die "Error: $name not created" if !$base;
    mojo_request($t, 'prepare_base',{ id_domain => $base->id });
    for ( 1 .. 120 ) {
        return $base if $base->is_base;
        sleep 1;
    }
    die "Error: $name not prepared" if !$base->is_base;
    return $base;
}

sub test_list_machines_user($vm_name) {
    mojo_check_login($t, $USERNAME, $PASSWORD);
    my $base = _create_base($vm_name);
    $base->is_public(1);

    $t->ua->get($URL_LOGOUT);
    my $user = create_user();

    mojo_login($t, $user->name,$$);

    $t->get_ok("/list_machines_user.json")->status_is(200);
    my $body = $t->tx->res->body;
    my $bases0;
    eval { $bases0 = decode_json($body) };
    is($@, '') or return;

    my ($base_f) = grep { $_->{id} == $base->id } @$bases0;
    ok($base_f) or die "Expecting ".$base->name." in listing";

    $t->get_ok("/machine/clone/".$base->id.".html")
        ->status_is(200);

    return if $t->tx->res->code != 200;

    $base->is_public(0);
    $base->show_clones(0);

    $t->get_ok("/machine/clone/".$base->id.".html")
        ->status_is(403);

    my $clone = _wait_domain($base->name."-".$user->name);
    ok($clone) or exit;

    $t->get_ok("/machine/view/".$clone->id.".html")
        ->status_is(403);

    $base->show_clones(1);
    $t->get_ok("/machine/clone/".$base->id.".html")
        ->status_is(200);

    $t->get_ok("/machine/view/".$clone->id.".html")
        ->status_is(200);

    my $user2 = create_user();

    mojo_login($t, $user2->name,$$);

    $t->get_ok("/list_machines_user.json")->status_is(200);
    $body = $t->tx->res->body;
    eval { $bases0 = decode_json($body) };
    is($@, '') or return;

    my ($base_f2) = grep { $_->{id} == $base->id } @$bases0;
    ok(!$base_f2) or die "Expecting ".$base->name." in listing";

    $t->get_ok("/machine/clone/".$base->id.".html")
        ->status_is(403);
}

sub _wait_domain($name) {
    for ( 1 .. 120 ) {
        my $domain = rvd_front->search_domain($name);
        return $domain if $domain;
        sleep 1;
        diag("waiting for $name");
    }
}

########################################################################################

$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

if (!ping_backend()) {
    diag("SKIPPED: no backend");
    done_testing();
    exit;
}
$Test::Ravada::BACKGROUND=1;

remove_old_domains_req(1); # 0=do not wait for them

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

$USERNAME = user_admin->name;
$PASSWORD = "$$ $$";

for my $vm_name (reverse @{rvd_front->list_vm_types} ) {

    diag("Testing new machine in $vm_name");

    test_list_machines_user($vm_name);
}
remove_old_domains_req(0); # 0=do not wait for them
remove_old_users();

done_testing();
