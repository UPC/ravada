use Data::Dumper;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';

use lib 't/lib';
use Test::Ravada;


########################################################################################

init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

clean();

my $script = path(__FILE__)->dirname->sibling('../rvd_front.pl');

my $t = Test::Mojo->new($script);
$t->get_ok('/')->status_is(200)->content_like(qr/name="login"/);

my $user_admin = user_admin();
my $pass = "$$ $$";

$t->post_ok('/' => form => {login => $user_admin->name, password => $pass})
  ->status_is(302);

exit if !$t->success;

$t->get_ok('/')->status_is(200)->content_like(qr/choose a machine/i);

for my $vm_name ( @vm_names ) {

    my $name = new_domain_name();

    $t->post_ok('/new_machine.html' => form => {
            backend => 'Void'
            ,id_iso => search_id_iso('Alpine%')
            ,name => $name
            ,disk => 1
            ,ram => 1
            ,swap => 1
            ,submit => 1
        }
    )->status_is(302);

    wait_request(debug => 1);
    my $base = rvd_front->search_domain($name);
    ok($base);
}

clean();
done_testing();
