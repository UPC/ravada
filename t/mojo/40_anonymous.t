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

$ENV{MOJO_MODE} = 'devel';
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

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

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

my $n_anonymous = list_anonymous_users();

$t->get_ok("/anonymous");

is($t->tx->res->code(), 403 );
is(list_anonymous_users(), $n_anonymous);

$t->get_ok("/logout");

for my $action ( qw(clone display info view ) ) {
    my $url = "/machine/$action/1.html";
    $n_anonymous = list_anonymous_users();
    $t->reset_session;
    $t->get_ok($url);
    is($t->tx->res->code(), 403 );
    is(list_anonymous_users(), $n_anonymous, $url);
}

for my $route ( qw( list_bases_anonymous request ws/subscribe anonymous_logout.html 
    anonymous/1.html anonymous/request/1.html
    ) ) {
    my $url = "/$route";
    $n_anonymous = list_anonymous_users();
    $t->reset_session;
    $t->get_ok($url);
    is($t->tx->res->code(), 403 );
    is(list_anonymous_users(), $n_anonymous, $url);

}

done_testing();
