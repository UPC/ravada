use warnings;
use strict;

use utf8;

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

my $BASE_NAME = "пользователя";
my $N = 0;
########################################################################

sub test_clone_cyrillic_domain($t, $vm_name) {
    test_clone_cyrillic_user($t, $vm_name, 1);
}

sub test_clone_cyrillic_user($t, $vm_name, $cyrillic_base=0) {
    my $user_name = $BASE_NAME."-".$N++;

    my $user_db = Ravada::Auth::SQL->new( name => $user_name);
    $user_db->remove();

    my $user = create_user($user_name, $$);
    user_admin->make_admin($user->id);

    mojo_login($t, $user_name, $$);
    my $base_name;
    if ($cyrillic_base) {
        $base_name = $user_name;
    } else {
        $base_name = new_domain_name();
    }

    my $iso_name = 'Alpine%64 bits';
    my $id_iso = search_id_iso($iso_name);

    $t->post_ok("/new_machine.html",
        form => {
            backend => $vm_name
            ,name => $base_name
            ,disk => 1
            ,memory => 1
            ,id_owner => $user->id
            ,id_iso => $id_iso
            ,submit => 1

        }
    )->status_is(302);
    wait_request(debug => 1);

}


sub _remove_cyrillic_domains() {
    my $machines = rvd_front->list_machines(user_admin);
    for my $machine (@$machines) {
        warn $machine->{name};
        next unless $machine->{name} =~ /^$BASE_NAME/;
        warn "\tremoving\n";
        remove_domain_and_clones_req($machine,0);
    }
    wait_request(debug => 0);

}
########################################################################

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

$t = Test::Mojo->new($SCRIPT);
$t->ua->inactivity_timeout(900);
$t->ua->connect_timeout(60);
remove_old_domains_req(0); # 0=do not wait for them
_remove_cyrillic_domains();

for my $vm_name ( @{rvd_front->list_vm_types} ) {
    test_clone_cyrillic_user($t, $vm_name);
    test_clone_cyrillic_domain($t, $vm_name);
}

_remove_cyrillic_domains();
done_testing();

