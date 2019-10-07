use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::Mojo;
use Mojo::File 'path';

use lib 't/lib';
use Test::Ravada;

########################################################################################

sub remove_machines {
    for my $name ( @_ ) {
        my $domain = rvd_front->search_domain($name) or next;
        for my $clone ($domain->clones) {
            my $req = Ravada::Request->remove_domain(
                name => $clone->{name}
                ,uid => user_admin->id
            );
        }
        wait_request(debug => 0, background => 1, check_error => 1);

        my $req = Ravada::Request->remove_domain(
            name => $name
            ,uid => user_admin->id
        );
    }
    wait_request(debug => 0, background => 1);
}

########################################################################################

init('/etc/ravada.conf',0);
my $connector = rvd_back->connector;
like($connector->{driver} , qr/mysql/i) or BAIL_OUT;

my $script = path(__FILE__)->dirname->sibling('../rvd_front.pl');

my $t = Test::Mojo->new($script);
$t->get_ok('/')->status_is(200)->content_like(qr/name="login"/);

my $user_admin = user_admin();
my $pass = "$$ $$";

$t->post_ok('/' => form => {login => $user_admin->name, password => $pass})
  ->status_is(302);

exit if !$t->success;

$t->get_ok('/')->status_is(200)->content_like(qr/choose a machine/i);

my @bases;
my @clones;

for my $vm_name ( vm_names() ) {

    diag("Testing new machine in $vm_name");

    my $name = new_domain_name();
    remove_machines($name,"$name-".user_admin->name);

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

    wait_request(debug => 0, background => 1);
    my $base = rvd_front->search_domain($name);
    ok($base) or next;
    push @bases,($base->name);

    $t->get_ok("/machine/prepare/".$base->id.".json")->status_is(200);
    wait_request(debug => 0, background => 1);
    $base = rvd_front->search_domain($name);
    is($base->is_base,1);

    $t->get_ok("/machine/clone/".$base->id.".json")->status_is(200);
    wait_request(debug => 0, background => 1);
    my $clone = rvd_front->search_domain($name."-".$user_admin->name);
    ok($clone,"Expecting clone created");
    is($clone->is_volatile,0) or exit;

}
ok(@bases,"Expecting some machines created");
remove_machines(@bases);
wait_request(background => 1);

done_testing();
