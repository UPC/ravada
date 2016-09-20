use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use_ok('Ravada');
use_ok('Ravada::Domain::KVM');

my $test = Test::SQL::Data->new( config => 't/etc/sql.conf');
my $RAVADA;
my $VMM;

eval { $RAVADA = Ravada->new( connector => $test->connector) };
my $REMOTE_VIEWER = `which remote-viewer`;
chomp $REMOTE_VIEWER;

##############################################################
#

sub test_remove_domain {
    my $name = shift;

    my $domain;
    $domain = $RAVADA->search_domain($name,1);

    if ($domain) {
        diag("Removing domain $name");
        $domain->remove();
    }
    $domain = $RAVADA->search_domain($name,1);
    die "I can't remove old domain $name"
        if $domain;

}

sub remove_old_disks {
    my ($name) = $0 =~ m{.*/(.*)\.t};

    my $vm = $RAVADA->search_vm('kvm');
    ok($vm,"I can't find a KVM virtual manager") or return;

    my $dir_img = $vm->dir_img();
    ok($dir_img," I cant find a dir_img in the KVM virtual manager") or return;

    for my $count ( 0 .. 10 ) {
        my $disk = $dir_img."/$name"."_$count.img";
        if ( -e $disk ) {
            unlink $disk or die "I can't remove $disk";
        }
    }
    $vm->storage_pool->refresh();
}


##############################################################

eval { $VMM = $RAVADA->search_vm('kvm') } if $RAVADA;
SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    diag($msg)      if !$VMM;
    skip $msg,10    if !$VMM;


remove_old_disks();
my ($name) = $0 =~ m{.*/(.*)\.t};
$name .= "_0";

test_remove_domain($name);

my $domain = $VMM->create_domain(name => $name, id_iso => 1 , active => 0, id_owner => 1);


ok($domain,"Domain not created") and do {
    $domain->shutdown(timeout => 5) if !$domain->is_active;

    for ( 1 .. 10 ){
        last if !$domain->is_active;
        diag("Waiting for domain $name to shut down");
        sleep 1;
    }
    if ( $domain->domain->is_active() ) {
        $domain->domain->destroy;
        sleep 2;
    }

    ok(! $domain->is_active, "I can't shut down the domain") and do {
        $domain->start();
        ok($domain->is_active,"I don't see the domain active");

        if ($domain->is_active) {
            $domain->shutdown(timeout => 3);
        }
        ok(!$domain->is_active."Domain won't shut down") and do {
            test_remove_domain($name);
        };
    };
};
}

done_testing();


