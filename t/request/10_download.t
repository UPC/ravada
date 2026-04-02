use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;


$Ravada::DEBUG=0;
$Ravada::SECONDS_WAIT_CHILDREN = 1;

##################################################################

SKIP: {
if ($>)  {
    my $msg = "SKIPPED: Test must run as root";
    skip($msg,10) if $<;
}

init();
$Ravada::CAN_FORK = 1;

for my $vm_name ('KVM') {
    my $rvd_back = rvd_back();
    my $vm = $rvd_back->search_vm($vm_name);
        my $msg = "SKIPPED: No virtual managers found";
        if ($vm && $vm_name =~ /kvm/i && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
        }

        skip($msg,10)   if !$vm;

        ################################################
        #
        # Request for the 1st ISO
        my $id_iso = search_id_iso('Alpine');
        my $iso = $vm->_search_iso($id_iso);

        if (!$iso->{device}) {
            $msg = "ISO for $iso->{filename} not downloaded, I won't do it in the tests";
            diag($msg);
            skip($msg,10);
        }

        my $req1 = Ravada::Request->download(
             id_iso => $id_iso
            , id_vm => $vm->id
            , delay => 4
            , test => 1
        );
        is($req1->status, 'requested');

        $rvd_back->process_all_requests();
        sleep 1;
        is($req1->status, 'working');

        ################################################
        #
        # Request for the 2nd ISO
        $id_iso = search_id_iso('Debian');
        $vm = Ravada::VM->open($vm->id);
        my $iso2 = $vm->_search_iso($id_iso);
        if (!$iso2->{device} || ! -e $iso2->{device}) {
            $msg = "ISO for $iso2->{filename} not downloaded, I won't do it in the tests";
            diag($msg);
            skip($msg,10);
        }


        my $req2 = Ravada::Request->download(
             id_iso => $id_iso
            , id_vm => $vm->id
            , delay => 2
            , test => 1
        );
        is($req2->status, 'requested');

        next;
        #TODO: doing so makes test return:  Non-zero wait status: 13 [issue #194]
        $rvd_back->process_all_requests();
        is($req1->status, 'working');
        is($req2->status, 'waiting');

        wait_request($req1);
        is($req1->status, 'done');

        $rvd_back->process_all_requests();
        is($req2->status, 'working');
        wait_request($req2);
        is($req2->status, 'done');
        diag($req1->error)  if $req1->error;
        diag($req2->error)  if $req2->error;
}
end();

} # of skip
done_testing();
