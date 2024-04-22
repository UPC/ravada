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

sub _remove_clones($time) {
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

sub test_ram($vm_name,$enable_check, $expected=undef) {

    my $free_mem = _free_memory();
    my $limit = int($free_mem/1024/1024)+1 ;
    _remove_clones(time+300+$limit*2);
    my $count = 0;
    for my $n ( 0 .. $limit*3 ) {
        my $free = int(_free_memory()/1024/1024);
        my $name = new_domain_name();
        my $req=Ravada::Request->clone(
                    uid => user_admin->id
                    ,id_domain => $BASE->id
                    ,name => $name
                    ,memory => 3 * 1024 * 1024
                );
        my $new;
        for ( 1 .. 90 ) {
            $new = rvd_front->search_domain($name);
            last if $new;
            wait_request();
        }
        last if !$new;
        $req = Ravada::Request->start_domain( uid => user_admin->id
            ,id_domain => $new->id
        );
        for ( 1 .. 10 ) {
            wait_request();
            last if $req->status eq 'done';
        }
        if ($req->error) {
            diag($req->error);
            last;
        }
        $count++;
        last if defined $expected && $count > $expected;
        my $free2 = int(_free_memory()/1024/1024);
        sleep $n if $vm_name eq 'KVM';
        redo if $vm_name eq 'KVM' && ($free2>=$free);

    }
    _remove_clones(0);
    wait_request();
    return $count;
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
<<<<<<< HEAD
my $old_value = rvd_back->setting("/backend/limits/startup_ram");
=======
>>>>>>> main
for my $vm_name (reverse @{rvd_front->list_vm_types} ) {
    diag("Testing RAM limit in $vm_name");

    _import_base($vm_name);

    rvd_back->setting("/backend/limits/startup_ram" => 1);
    my $started_limit =test_ram($vm_name,1);
    rvd_back->setting("/backend/limits/startup_ram" => 0);
    my $started_no_limit =test_ram($vm_name,0, $started_limit);
    ok($started_no_limit > $started_limit);
}

<<<<<<< HEAD
rvd_back->setting("/backend/limits/startup_ram" => $old_value);

=======
>>>>>>> main
remove_old_domains_req(0); # 0=do not wait for them

end();
done_testing();
