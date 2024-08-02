use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;
use YAML qw(LoadFile DumpFile);

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');
use_ok('Ravada::Auth::OpenID');

init();

my $user_name = new_domain_name();
my $header = {};

my $user = Ravada::Auth::OpenID::login_external($user_name, $header);
ok($user);

$header = { OIDC_CLAIM_exp => time-10 };

$user = Ravada::Auth::OpenID::login_external($user_name, $header);
ok(!$user);

$header = { OIDC_access_token_expires => time-10 };

$user = Ravada::Auth::OpenID::login_external($user_name, $header);
ok(!$user);

rvd_front->setting('/frontend/auto_create_users' => 0);

$user_name = new_domain_name();
$header = {};

$user = Ravada::Auth::OpenID::login_external($user_name, $header);
ok(!$user);

end();
done_testing();
