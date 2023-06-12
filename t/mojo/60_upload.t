use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
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
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

################################################################################
sub test_upload_users() {

    my ($user1, $pass1) = ( new_domain_name(), $$.1);
    my ($user2, $pass2) = ( new_domain_name(), $$.2);
    for my $name ($user1, $user2) {
        my $user = Ravada::Auth::SQL->new(name => $name);
        $user->remove() if $user;
    }

    my $users = join(":",($user1, $pass1)) ."\n"
                .join(":",($user2, $pass2)) ."\n"
    ;
    $t->post_ok('/admin/users/upload' => form => {
            type => 'sql'
            ,users => { content => $users, filename => 'users.txt', 'Content-Type' => 'text/csv' },
    })->status_is(200);
    die $t->tx->res->body if $t->tx->res->code != 200;

    my $response = $t->tx->res->json();
    like($response->{output}, qr/2 users added/);
    is_deeply($response->{error},[]);

    $t->post_ok('/login' => form => {login => $user1, password => $pass1})
    ->status_is(302);
    $t->post_ok('/login' => form => {login => $user2, password => $pass2})
    ->status_is(302);

    mojo_check_login($t);

    $t->post_ok('/admin/users/upload' => form => {
            type => 'sql'
            ,users => { content => $users, filename => 'users.txt', 'Content-Type' => 'text/csv' },
})->status_is(200);
    die $t->tx->res->body if $t->tx->res->code != 200;

    $response = $t->tx->res->json();
    like($response->{output}, qr/0 users added/);
    is(scalar(@{$response->{error}}),2);

}

sub _login($t) {
    my $user_name = new_domain_name();

    my $user_db = Ravada::Auth::SQL->new( name => $user_name);
    $user_db->remove();

    my $user = create_user($user_name, $$);
    user_admin->make_admin($user->id);

    mojo_login($t, $user_name, $$);
}

################################################################################

$ENV{MOJO_MODE} = 'development';
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

_login($t);
test_upload_users();

done_testing();
