#!perl

use strict;
use warnings;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use Ravada;

use Data::Dumper;

no warnings "experimental::signatures";
use feature qw(signatures);

##############################################################################

sub test_deny_access($vm) {
    my $user = create_user();
    my $networks = rvd_front->list_networks($vm->id , $user->id);
    is(scalar(@$networks),0);

    $networks = rvd_front->list_networks($vm->id , user_admin->id);
    ok(scalar(@$networks));

}

##############################################################################

init();

for my $vm_name( vm_names() ) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm= undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        diag("Testing rename on $vm_name");

        Ravada::Request->refresh_vms();
        wait_request( debug => 1);
        test_deny_access($vm);
    }

}

end();
done_testing();
