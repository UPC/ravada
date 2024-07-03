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

my $BASE_NAME="zz-test-base-ubuntu";
my $BASE;
#########################################################

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

sub _remove_clones($time=0) {
    Ravada::Request->remove_clones(
            uid => user_admin->id
            ,id_domain => $BASE->id
            ,at => $time
    );
}

sub _free_memory() {
    open my $mem,"<","/proc/meminfo" or die $!;
    my $mem_avail;
    while (my $line = <$mem> ) {
        ($mem_avail) = $line =~ /^MemAvailable.*?(\d+)/;
        return $mem_avail if $mem_avail;
    }
    die;
}

sub _req_clone($base, $name=new_domain_name(), $memory=2) {
    Ravada::Request->clone(
    uid => user_admin->id
    ,id_domain => $base->id
    ,name => $name
    ,memory => $memory * 1024 * 1024
    );
    return $name;
}

sub _wait_clone($name) {

    my $new;
    for ( 1 .. 90 ) {
        $new = rvd_front->search_domain($name);
        last if $new;
        wait_request(debug => 1);
    }
    return if !$new;

    my $req = Ravada::Request->start_domain( uid => user_admin->id
            ,id_domain => $new->id
    );
    for ( 1 .. 10 ) {
        wait_request();
        last if $req->status eq 'done';
    }

    wait_ip($new);
    return $req;
}

sub test_ram($vm_name,$enable_check) {

    my $free_mem = _free_memory();
    my $limit = int($free_mem/1024/1024)+1 ;
    _remove_clones(time+300+$limit*2);

    _set_min_free($vm_name, $limit*1024*1024);
    _wait_clone(_req_clone($BASE,new_domain_name(),$limit-2));

    my $name;
    for my $n ( 0 .. $limit ) {
        my $free = int(_free_memory()/1024/1024);
        $name = new_domain_name();
        _req_clone($BASE, $name);
        my $req = _wait_clone($name);
        return $name if !$req;
        if ($req->error) {
            diag($req->error);
            last;
        }
        my $free2 = int(_free_memory()/1024/1024);
        redo if $vm_name eq 'KVM' && ($free2>=$free);

    }
    wait_request();
    return $name;
}

sub test_start_another() {
    my $found;
    for my $clone ( $BASE->clones ) {
        $found = $clone if $clone->{status} ne 'active';
    }
    if (!$found) {
        _wait_clone(_req_clone($BASE));
    } else {
        my $req = Ravada::Request->start_domain( uid => user_admin->id
            ,id_domain => $found->{id}
        );
        for ( 1 .. 10 ) {
            wait_request();
            last if $req->status eq 'done';
        }
        is($req->error,'');
    }
}

sub _set_min_free($vm_name,$min_free) {
    my $sth = connector->dbh->prepare(
        "select min_free_memory"
        ." FROM vms "
        ." WHERE vm_type=? AND hostname='localhost'"
    );
    $sth->execute($vm_name);
    my ($old) = $sth->fetchrow;

    $sth = connector->dbh->prepare("UPDATE vms set min_free_memory=?"
        ." WHERE vm_type=?"
    );
    $sth->execute($min_free, $vm_name);

    return $old;
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

remove_old_domains_req();

$USERNAME = user_admin->name;
$PASSWORD = "$$ $$";
for my $vm_name (@{rvd_front->list_vm_types} ) {
    diag("Testing RAM limit in $vm_name");

    _import_base($vm_name);

    rvd_back->setting("/backend/limits/startup_ram" => 1);
    my $min_free=_set_min_free($vm_name,5*1024*1024);
    my $domain_name = test_ram($vm_name,1);
    rvd_back->setting("/backend/limits/startup_ram" => 0);

    test_start_another();

    _set_min_free($vm_name, $min_free);

    _remove_clones();
}

remove_old_domains_req(0); # 0=do not wait for them
remove_old_users();

done_testing();
