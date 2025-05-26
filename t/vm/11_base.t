use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Hash::Util qw(lock_hash);
use IPC::Run3 qw(run3);
use JSON::XS;
use Test::More;

no warnings "experimental::signatures";
use feature qw(signatures);

use lib 't/lib';
use Test::Ravada;

sub test_remove_base($vm) {

    my $base = import_clone($vm);

    my @volumes_base = $base->list_files_base();

    my @volumes= $base->list_volumes();
    for my $vol ($base->list_volumes_info()) {
        my $backing = $vol->backing_file;
        ok($vm->file_exists($backing),$backing);
    }

    $base->remove_base(user_admin);

    for my $vol ($base->list_volumes_info()) {
        my $backing = $vol->backing_file;
        ok(!$backing,"Expecting no backing from file ".$vol->file);
    }

    for my $vol (@volumes_base) {
        ok(!$vm->file_exists($vol),"Expecting base file '$vol' removed");
    }

    $base->start(user_admin);
    my $ip = wait_ip($base);

    ok($ip);

    remove_domain($base);

}

########################################################################

init();
clean();

for my $vm_name ( vm_names() ) {
    my $vm;

    eval { $vm = rvd_back->search_vm($vm_name) };

    SKIP: {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_remove_base($vm);
    }
}

########################################################################
end();
done_testing();
