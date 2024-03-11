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

$ENV{MOJO_MODE} = 'development';
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

my $URL_LOGOUT = '/logout';

init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

$Test::Ravada::BACKGROUND=1;
my $t;

sub list_anonymous_users() {
    my $sth = $connector->dbh->prepare("SELECT count(*) FROM users WHERE is_temporary=1");
    $sth->execute();
    my ($n) = $sth->fetchrow;
    return $n;
}

#################################################

sub _id_net($net) {
    my $sth =connector->dbh->prepare("SELECT id FROM networks WHERE name=?");
    $sth->execute($net);
    my ($id) = $sth->fetchrow();
    confess "Error: $net not found" if !$id;
    return $id;
}

sub _id_domain($name) {
    my $sth = connector->dbh->prepare("SELECT id FROM domains where name=?");
    $sth->execute($name);
    my ($id) = $sth->fetchrow;
    confess "Error: $name not found" if !$id;
    return $id;
}

sub _allow_anonymous_base() {
    my $id_net = _id_net('localnet');
    my $id_domain = _id_domain('zz-test-base-alpine');

    mojo_login($t, user_admin->name,"$$ $$");
    $t->get_ok("/v2/route/set/$id_net/anonymous/$id_domain/1");

    my $sth = connector->dbh->prepare("UPDATE domains set is_public=1"
        ." WHERE id=?");
    $sth->execute($id_domain);

    $t->ua->get($URL_LOGOUT);
}

sub _deny_anonymous_base() {
    my $id_domain = _id_domain('zz-test-base-alpine');

    my $sth = connector->dbh->prepare("UPDATE domains_network set anonymous=?");
    $sth->execute(0);


    my $sth2 = connector->dbh->prepare("UPDATE domains set is_public=1"
        ." WHERE id=?");
    $sth2->execute($id_domain);

}

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

my $n_anonymous = list_anonymous_users();

_deny_anonymous_base();

$t->get_ok("/anonymous");

is($t->tx->res->code(), 403 ) or exit;
is(list_anonymous_users(), $n_anonymous);

_allow_anonymous_base();

$t->get_ok("/anonymous");

is($t->tx->res->code(), 200 ) or exit;

is(list_anonymous_users(), $n_anonymous + 1);

my $bases = rvd_front->list_bases_anonymous('127.0.0.1');
ok($bases->[0]->{alias});
ok($bases->[0]->{list_clones});
my $url_view = "/anonymous/".$bases->[0]->{id}.".html";
$t->get_ok($url_view) or exit;

_deny_anonymous_base();

$t->get_ok("/logout");

for my $action ( qw(clone display info view ) ) {
    my $url = "/machine/$action/1.html";
    $n_anonymous = list_anonymous_users();
    $t->reset_session;
    $t->get_ok($url);
    is($t->tx->res->code(), 403,$url);
    is(list_anonymous_users(), $n_anonymous, $url);
}

for my $route ( qw( list_bases_anonymous request/1.json ws/subscribe anonymous_logout.html anonymous/1.html anonymous/request/1.html) ) {
    my $url = "/$route";
    $n_anonymous = list_anonymous_users();
    $t->reset_session;
    $t->get_ok($url);
    is($t->tx->res->code(), $route eq "anonymous_logout.html" ? 302 : 403
    ,$url);
    is(list_anonymous_users(), $n_anonymous, $url);
}

wait_request();
remove_volatile_clones(@$bases);

remove_old_domains_req(0);
done_testing();
