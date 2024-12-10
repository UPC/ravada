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

my ($USERNAME, $PASSWORD);

my $URL_LOGOUT = '/logout';

$Test::Ravada::BACKGROUND=1;
my $t;

my $BASE_NAME="zz-test-base-alpine";
my $BASE;


###############################################################################

sub _import_base($vm_name) {
    mojo_login($t,$USERNAME, $PASSWORD);
    my $name = new_domain_name()."-".$vm_name."-$$";
    if ($vm_name eq 'KVM') {
        my $base0 = rvd_front->search_domain($BASE_NAME);
        mojo_request_url_post($t,"/machine/copy",{id_base => $base0->id, new_name => $name, copy_ram => 0.128, copy_number => 1});
        for ( 1 .. 90 ) {
            $BASE= rvd_front->search_domain($name);
            last if $BASE;
            wait_request();
        }

    } else {
        $BASE = mojo_create_domain($t, $vm_name);
    }

    Ravada::Request->shutdown_domain(uid => user_admin->id
        ,id_domain => $BASE->id);
    my $req = Ravada::Request->prepare_base(uid => user_admin->id
            ,id_domain => $BASE->id
    );
    wait_request();
    is($req->error,'');

    $BASE->_data('shutdown_disconnected' => 1);

}

sub _list_host_devices($id_vm) {
    $t->get_ok("/list_host_devices/$id_vm")->status_is(200);

    my $body = $t->tx->res->body;
    my $hd0;
    eval { $hd0 = decode_json($body) };
    is($@, '') or return;
    return $hd0;
}

sub create_hd($vm_name) {
    my $id_vm = _id_vm($vm_name);

    my $hd0 = _list_host_devices($id_vm);

    $t->get_ok('/host_devices/templates/list/'.$id_vm)->status_is(200);

    my $body = $t->tx->res->body;
    my $templates;
    eval { $templates = decode_json($body) };
    is($@, '') or return;
    my ($template) = $templates->[0]->{name};

    $t->post_ok("/node/host_device/add",
        json => { id_vm => $id_vm, template => $template ,name => new_domain_name() }
    )->status_is(200);

    like($t->tx->res->code(),qr/^(200|302)$/) or die $t->tx->res->body;

    my $hd1 = _list_host_devices($id_vm);

    my $hd;
    my %hd0;
    for my $curr ( @$hd0 ) {
        $hd0{$curr->{name}}++;
    }
    for my $curr ( @$hd1 ) {
        $hd = $curr if !$hd0{$curr->{name}};
    }

    _rename_hd($hd);

    return $hd;
}

sub _rename_hd($hd) {
    $t->post_ok("/node/host_device/update",
        json => { id => $hd->{id}, name => new_domain_name }
    )->status_is(200);

}

sub _id_vm($vm_name) {
    my $sth = connector->dbh->prepare(
    "SELECT id FROM vms "
    ." WHERE vm_type=?"
    ."   AND hostname='localhost'"
    );
    $sth->execute($vm_name);
    my ($id) = $sth->fetchrow;
    die "Error: no $vm_name found in VMs" if !$id;
    return $id;
}

sub test_base_hd($vm_name, $hd) {
#get('/list_host_devices/'.$id_base);

    my $id_vm = _id_vm($vm_name);

    confess Dumper($hd) if !exists $hd->{id} || !$hd->{id};

    $t->get_ok('/machine/host_device/add/'.$BASE->id
                ."/".$hd->{id})->status_is(200);

    my $res;
    eval { $res = decode_json($t->tx->res->body) };
    is($@, '') or return;
    is($res->{error}, '');
    is($res->{ok}, 1);

    $t->get_ok('/machine/info/'.$BASE->id.".json")->status_is(200);

    my $info;
    eval { $info = decode_json($t->tx->res->body) };
    ok($info->{host_devices}) or die $BASE->name;
    is(scalar(@{$info->{host_devices}}),1) or die $BASE->name;

}

sub clean_hds() {
    my $sth = connector->dbh->prepare(
        "SELECT id FROM host_devices "
        ." WHERE name like ?"
    );
    $sth->execute(base_domain_name().'%');

    while (my ($id) = $sth->fetchrow ) {
        mojo_check_login($t);
        $t->get_ok('/node/host_device/remove/'.$id)->status_is(200);
    }
}

sub test_gpu_inactive($vm_name) {
    my $req = Ravada::Request->check_gpu_status(
        uid => user_admin->id
        ,id_node => _id_vm($vm_name)
    );
    for ( 1 .. 10 ) {
        last if $req->pid || $req->status eq 'done';
        sleep 1;
        diag("Waiting for ".$req->command." started.");
    }
    ok($req->pid);
    is($req->status, 'working');
    is($req->error, '');
    diag($req->status);
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

#remove_old_domains_req(0);


$USERNAME = user_admin->name;
$PASSWORD = "$$ $$";

mojo_login($t,$USERNAME, $PASSWORD);

clean_hds();

for my $vm_name (reverse @{rvd_front->list_vm_types} ) {
    diag("Testing host devices in $vm_name");

    _import_base($vm_name);

    test_gpu_inactive($vm_name);

    my $hd = create_hd($vm_name);
    test_base_hd($vm_name, $hd) if $hd;

}

remove_old_domains_req(0); # 0=do not wait for them
clean_hds();
remove_old_users();

done_testing();
