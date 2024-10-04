use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use HTML::Lint;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';
use Mojo::JSON qw(decode_json);
use Storable qw(dclone);

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $SECONDS_TIMEOUT = 15;

my $t;

my $URL_LOGOUT = '/logout';
my ($USERNAME, $PASSWORD) = (user_admin->name, "$$ $$");
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

$ENV{MOJO_MODE} = 'devel';
init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

$Test::Ravada::BACKGROUND=1;

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);

mojo_login($t, $USERNAME, $PASSWORD);

my $sth = rvd_front->_dbh->prepare("UPDATE settings set value='' WHERE id_parent=?");

$t->get_ok("/settings_global.json")->status_is(200);
my $body = $t->tx->res->body();
my $settings = decode_json($body);

$sth->execute($settings->{frontend}->{content_security_policy}->{id});

my $new = dclone($settings);
my $exp_default = "foodefault.example.com";
my $exp_all = "fooall.example.com";
$new->{frontend}->{content_security_policy}->{'default-src'}->{value} = $exp_default;
$new->{frontend}->{content_security_policy}->{'all'}->{value} = $exp_all;
delete $new->{backend};

my $reload=0;
rvd_front->update_settings_global($new,user_admin,$reload);

$t->post_ok("/settings_global", json => $new );

$t->get_ok("/settings_global.json")->status_is(200);
$body = $t->tx->res->body();
my $settings2 = decode_json($body);
is($settings2->{frontend}->{content_security_policy}->{'all'}->{value} , $exp_all) or exit;
is($settings2->{frontend}->{content_security_policy}->{'default-src'}->{value} , $exp_default) or exit;

my $config_csp = rvd_front->_settings_by_parent("/frontend/content_security_policy");
is($config_csp->{all}, $exp_all);
is($config_csp->{'default-src'}, $exp_default);

my $header = $t->tx->res->headers->content_security_policy();
my %csp;
for my $entry (split /;/,$header) {
    my ($key,$value) = $entry =~ /\s*(.*?)\s+(.*)/;
    $csp{$key}=$value;
}

like($csp{'default-src'},qr/$exp_all/);
like($csp{'default-src'},qr/$exp_default/);

$sth->execute($settings->{frontend}->{content_security_policy}->{id});

$new->{frontend}->{content_security_policy}->{'default-src'}->{value} = '';
$new->{frontend}->{content_security_policy}->{'all'}->{value} = '';
$t->post_ok("/settings_global", json => $new );
end();
done_testing();
