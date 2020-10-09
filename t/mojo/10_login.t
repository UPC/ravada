use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';

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

sub remove_machines {
    my $t0 = time;
    for my $name ( @_ ) {
        my $domain = rvd_front->search_domain($name) or next;
        my $n_clones = scalar($domain->clones);
        my $req_clone;
        for my $clone ($domain->clones) {
            $req_clone = Ravada::Request->remove_domain(
                name => $clone->{name}
                ,uid => user_admin->id
            );
        }
        _wait_request(debug => 1, background => 1, check_error => 0, timeout => 60+2*$n_clones);

        my @after_req = ();
        @after_req = ( after_request => $req_clone->id ) if $req_clone;
        my $req = Ravada::Request->remove_domain(
            name => $name
            ,uid => user_admin->id
        );
    }
    _wait_request(debug => 1, background => 1, timeout => 120);
    if ( time - $t0 > $SECONDS_TIMEOUT ) {
        login();
    }
}

sub _wait_request(@args) {
    my $t0 = time;
    wait_request(@args);

    if ( time - $t0 > $SECONDS_TIMEOUT ) {
        login();
    }

}


sub login( $user=$USERNAME, $pass=$PASSWORD ) {
    $t->ua->get($URL_LOGOUT);

    $t->post_ok('/login' => form => {login => $user, password => $pass});
    like($t->tx->res->code(),qr/^(200|302)$/);
    #    ->status_is(302);

    exit if !$t->success;
}

sub test_many_clones($base) {
    login();

    my $n_clones = 30;
    $n_clones = 100 if $base->type =~ /Void/i;

    $n_clones = 10 if !$ENV{TEST_STRESS} && ! $ENV{TEST_LONG};

    $t->post_ok('/machine/copy' => json => {id_base => $base->id, copy_number => $n_clones});
    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body->to_string;

    my $response = $t->tx->res->json();
    ok(exists $response->{request}) or return;
    wait_request(request => $response->{request}, background => 1);

    login();
    $t->post_ok('/request/start_clones' => json =>
        {   id_domain => $base->id
        }
    );
    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body->to_string;
    $response = $t->tx->res->json();
    ok(exists $response->{request}) and do {
        wait_request(request => $response->{request}, background => 1);
    };

    test_re_expose($base) if $base->type eq 'Void';
    test_different_mac($base, $base->clones) if $base->type ne 'Void';
    for my $clone ( $base->clones ) {
        my $req = Ravada::Request->remove_domain(
            name => $clone->{name}
            ,uid => user_admin->id
        );
    }
}

sub test_different_mac(@domain) {
    my %found;
    for my $domain (@domain) {
        $domain = Ravada::Front::Domain->open($domain->{id})
            if ref($domain) !~/^Ravada/;
        my $xml = XML::LibXML->load_xml(string => $domain->_data_extra('xml'));
        my (@if_mac) = $xml->findnodes('/domain/devices/interface/mac');
        for my $if_mac (@if_mac) {
            my $mac = $if_mac->getAttribute('address');
            ok(!exists $found{$mac},"Error: MAC $mac from ".$domain->name
                ." also in domain : ".($found{$mac} or '')) or exit;
            $found{$mac} = $domain->name;
        }
    }
}

sub test_re_expose($base) {
    diag("Test re-expose");
    for my $clone ( $base->clones ) {
        my $req = Ravada::Request->force_shutdown_domain(
            id_domain => $clone->{id}
            , uid => user_admin->id
        )
    }
    wait_request(background => 1);
    Ravada::Request->expose(uid => user_admin->id, id_domain => $base->id, port => 22);
    wait_request(background => 1);

    for my $clone ( $base->clones ) {
        my $req = Ravada::Request->start_domain(
            id_domain => $clone->{id}
            , uid => user_admin->id
            , remote_ip => '1.2.3.4'
        );
    }
    wait_request(background => 1, check_error => 1);
}
sub _init_mojo_client {
    my $user_admin = user_admin();
    my $pass = "$$ $$";

    $USERNAME = $user_admin->name;
    $PASSWORD = $pass;

    login($user_admin->name, $pass);
    $t->get_ok('/')->status_is(200)->content_like(qr/choose a machine/i);
}

sub test_copy_without_prepare($clone) {
    is ($clone->is_base,0) or die "Clone ".$clone->name." is supposed to be non-base";

    my $n_clones = 3;
    mojo_request($t, "clone", { id_domain => $clone->id, number => $n_clones });
    wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);

    my @clones = $clone->clones();
    is(scalar @clones, $n_clones) or exit;

    remove_machines($clone);
}

########################################################################################

init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

if (!rvd_front->ping_backend) {
    diag("SKIPPED: no backend");
    done_testing();
    exit;
}

remove_old_domains_req();

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);
my @bases;
my @clones;

for my $vm_name (@{rvd_front->list_vm_types} ) {

    diag("Testing new machine in $vm_name");

    my $name = new_domain_name()."-".$vm_name;
    remove_machines($name,"$name-".user_admin->name);

    _init_mojo_client();

    $t->post_ok('/new_machine.html' => form => {
            backend => $vm_name
            ,id_iso => search_id_iso('Alpine%')
            ,name => $name
            ,disk => 1
            ,ram => 1
            ,swap => 1
            ,submit => 1
        }
    )->status_is(302);

    _wait_request(debug => 1, background => 1, check_error => 1);
    my $base = rvd_front->search_domain($name);
    ok($base, "Expecting domain $name create") or next;
    push @bases,($base->name);

    mojo_request($t, "add_hardware", { id_domain => $base->id, name => 'network' });
    wait_request(debug => 1, check_error => 1, background => 1, timeout => 120);

    $t->get_ok("/machine/prepare/".$base->id.".json")->status_is(200);
    _wait_request(debug => 0, background => 1, check_error => 1);
    $base = rvd_front->search_domain($name);
    is($base->is_base,1);

    is(scalar($base->list_ports),0);
    $t->get_ok("/machine/clone/".$base->id.".json")->status_is(200);
    _wait_request(debug => 0, background => 1, check_error => 1);
    my $clone = rvd_front->search_domain($name."-".user_admin->name);
    ok($clone,"Expecting clone created") or next;
    if ($clone) {
        is($clone->is_volatile,0) or exit;
        is(scalar($clone->list_ports),0);
    }

    push @bases, ( $clone );
    test_copy_without_prepare($clone);
    test_many_clones($base);
}
ok(@bases,"Expecting some machines created");
remove_machines(@bases);
_wait_request(background => 1);
remove_old_domains_req();

done_testing();
