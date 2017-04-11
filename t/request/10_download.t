use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');
init($test->connector);

diag("$$ parent pid");
$Ravada::DEBUG=0;
$Ravada::SECONDS_WAIT_CHILDREN = 1;

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

        my $req1 = Ravada::Request->download(
             id_iso => 1
            , id_vm => $vm->id
            , delay => 4
        );
        is($req1->status, 'requested');

        $rvd_back->process_all_requests();
        is($req1->status, 'working');

        my $req2 = Ravada::Request->download( id_iso => 2, delay => 2 );
        is($req2->status, 'requested');

        $rvd_back->process_all_requests();
        is($req1->status, 'working');
        is($req2->status, 'waiting');

        wait_request($req1);
        is($req1->status, 'done');

        $rvd_back->process_all_requests();
        is($req2->status, 'working');
        wait_request($req2);
        is($req2->status, 'done');
        diag($req1->error);
        diag($req2->error);
    }
}
done_testing();
