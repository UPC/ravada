use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');
init();

$Ravada::DEBUG=0;
$Ravada::SECONDS_WAIT_CHILDREN = 1;

if (!$ENV{TEST_DOWNLOAD}) {
    diag("Set environment variable TEST_DOWNLOAD to run this test.");
    done_testing();
    exit;
}

sub test_download {
    my ($vm, $id_iso) = @_;
    my $iso = $vm->_search_iso($id_iso);
    unlink($iso->{device}) or die "$! $iso->{device}"
        if $iso->{device} && -e $iso->{device};
    my $req1 = Ravada::Request->download(
             id_iso => $id_iso
            , id_vm => $vm->id
            , delay => 4
    );
    is($req1->status, 'requested');

    rvd_back->_process_all_requests_dont_fork();
    is($req1->status, 'done');

}
##################################################################

for my $vm_name ('KVM') {
    my $rvd_back = rvd_back();
    my $vm = $rvd_back->search_vm($vm_name);
    SKIP: {
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        ################################################
        #
        # Request for Debian Streth ISO
        my $id_iso = search_id_iso('Debian Stretch') or die "I can't find id_iso for Stretch";
        test_download($vm, $id_iso);
    }
}
done_testing();
