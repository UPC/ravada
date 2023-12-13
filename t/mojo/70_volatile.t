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

$ENV{MOJO_MODE} = 'development';
my $SCRIPT = path(__FILE__)->dirname->sibling('../script/rvd_front');

my $URL_LOGOUT = '/logout';

$Test::Ravada::BACKGROUND=1;
my $t;

my $BASE_NAME = "zz-test-base-alpine";
my $RAM = 0.5;

my ($USERNAME, $PASSWORD);
###############################################################

sub _wait_ip($id_domain) {
    my $domain;
    for ( 1 .. 60 ) {
        Ravada::Request->refresh_machine(
            id_domain => $id_domain
            ,uid => user_admin->id
        );

        $domain = Ravada::Front::Domain->open($id_domain);
        my $info = $domain->info(user_admin);
        return $info->{ip} if exists $info->{ip} && $info->{ip};
        diag("Waiting for ".$domain->name. " ip") if !(time % 10);
        sleep 1;
    }
}

sub _init_mojo_client {
    my $user_admin = user_admin();
    my $pass = "$$ $$";

    $USERNAME = $user_admin->name;
    $PASSWORD = $pass;

    login($user_admin->name, $pass);
    $t->get_ok('/')->status_is(200)->content_like(qr/choose a machine/i);
}

sub base($vm_name) {
    mojo_check_login($t);

    my $name = new_domain_name()."-".$vm_name."-$$";

    my $base;
    if ($vm_name eq 'KVM') {
        my $base0 = rvd_front->search_domain($BASE_NAME);
        die "Error: test base $BASE_NAME not found" if !$base0;
        mojo_request_url_post($t,"/machine/copy",{id_base => $base0->id, new_name => $name, copy_ram => $RAM, copy_number => 1});

    } else {

        my $iso_name = 'Alpine%';
        _download_iso($iso_name);
        mojo_check_login($t);
        $t->post_ok('/new_machine.html' => form => {
                backend => $vm_name
                ,id_iso => search_id_iso($iso_name)
                ,name => $name
                ,disk => 1
                ,ram => 1
                ,swap => 1
                ,submit => 1
            }
        )->status_is(302);
        die $t->tx->res->body if $t->tx->res->code() != 302;
    }
    for ( 1 .. 60 ) {
            $base = rvd_front->search_domain($name);
            last if $base;
            wait_request();
    }
    ok($base, "Expecting domain $name created") or exit;
    if ($base->id_base) {
        mojo_request($t,"spinoff",{id_domain => $base->id});
    }

    return $base;
}

sub _set_base_vms($vm_name, $id_base) {
    my $sth = connector->dbh->prepare("SELECT id FROM vms WHERE vm_type=?");
    $sth->execute($vm_name);
    while ( my ($id_vm) = $sth->fetchrow) {
        mojo_request($t,"start_node" , { id_node => $id_vm });
    }

    $sth->execute($vm_name);
    while ( my ($id_vm) = $sth->fetchrow) {
        $t->post_ok("/node/enable/$id_vm.json");
        mojo_request($t,"set_base_vm", { id_vm => $id_vm, id_domain => $id_base, value => 1 });
    }

}

sub _id_vm($vm_name) {
    my $sth = connector->dbh->prepare("SELECT id FROM vms WHERE vm_type=? AND hostname='localhost'");
    $sth->execute($vm_name);
    my ($id) = $sth->fetchrow;
    die "Error: vm_type=$vm_name not found in VMS" if !$id;
    return $id;
}

sub test_clone($vm_name, $n=10) {
    my $id_vm = _id_vm($vm_name);

    my $base = base($vm_name);

    mojo_request($t,"compact", {id_domain => $base->id, keep_backup => 0 });
    mojo_request($t,"prepare_base", {id_domain => $base->id });
    $base->is_public(1);
    _set_base_vms($vm_name, $base->id);
    $base->volatile_clones(1);

    my $times = 1;
    $times = 20 if $ENV{TEST_LONG};

    for my $count0 ( 0 .. $times ) {
        _set_base_vms($vm_name, $base->id);
        is($base->_data('id_vm'), $id_vm) or die $base->name;

        for my $count1 ( 0 .. $n ) {
            my $user = create_user(new_domain_name(),$$);
            my $ip = (0+$count0.$count1) % 255;

            Ravada::Request->clone(
                uid => $user->id
                ,id_domain => $base->id
                ,start => 1
                ,remote_ip => "192.168.122.$ip"
            );
            delete_request('set_time','force_shutdown');
        }
        for ( 1 .. 10 ) {
            wait_request();
            last if $base->clones >= $n;
            diag(scalar($base->clones));
            sleep 1;
        }
        mojo_login($t, $USERNAME, $PASSWORD);
        for my $clone ( $base->clones ) {
            $t->get_ok("/machine/shutdown/".$clone->{id}.".json")->status_is(200);
            delete_request('set_time','force_shutdown');
        }
        wait_request();
    }
    remove_old_domains_req(0); # 0=do not wait for them
}

sub login( $user=$USERNAME, $pass=$PASSWORD ) {
    $t->ua->get($URL_LOGOUT);

    confess "Error: missing user" if !defined $user;

    $t->post_ok('/login' => form => {login => $user, password => $pass});
    like($t->tx->res->code(),qr/^(200|302)$/)
    or die $t->tx->res->body;
    #    ->status_is(302);

    exit if !$t->success;
    mojo_check_login($t, $user, $pass);
}

sub _download_iso($iso_name) {
    my $id_iso = search_id_iso($iso_name);
    my $sth = connector->dbh->prepare("SELECT device FROM iso_images WHERE id=?");
    $sth->execute($id_iso);
    my ($device) = $sth->fetchrow;
    return if $device;
    my $req = Ravada::Request->download(id_iso => $id_iso);
    for ( 1 .. 300 ) {
        last if $req->status eq 'done';
        _wait_request(debug => 1, background => 1, check_error => 1);
    }
    is($req->status,'done');
    is($req->error, '') or exit;

}
#########################################################
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

_init_mojo_client();
login();

remove_old_domains_req(0); # 0=do not wait for them

for my $vm_name (@{rvd_front->list_vm_types} ) {
    diag("Testing new machine in $vm_name");

    test_clone($vm_name);
}

remove_old_domains_req(0); # 0=do not wait for them

end();
done_testing();
