#!perl

use strict;
use warnings;

use Data::Dumper;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

init();


my $DIR_SAVE = "/var/lib/libvirt/qemu/save";

##############################################################################

sub test_crashed($vm, $position) {
    my $domain = create_domain($vm->type);
    $domain->start(user_admin);
    is($domain->is_active,1);
    sleep 2;
    $domain->hibernate(user_admin);

    ok($domain->domain->has_managed_save_image) or return;

    my $file_image =  $DIR_SAVE."/".$domain->name.".save";
    ok ( -e $file_image,"Expecting saved image in file $file_image") or return;

    open my $image, "+<", $file_image or die "$! $file_image";
    seek($image, $position , 0);
    syswrite($image,"garbage");
    close $image;

    for ( 1 .. 2 ) {
        eval { $domain->start(user_admin) };
        last if $domain->is_active;
    }
    is(''.$@,'');

    is($domain->is_active,1);

    $domain->remove(user_admin);
}

##############################################################################

clean();

use_ok('Ravada');

for my $vm_name ( 'KVM' ) {

    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) } if !$<;

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        diag("Testing shutdown on $vm_name");

        for my $position( 128, 1024, 2048, 4096 ) {
            test_crashed($vm, $position);
        }

    }
}

end();
done_testing();

