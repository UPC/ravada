use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);
########################################################################

sub test_usb_many($vm) {
    my $domain = create_domain_v2(vm => $vm);
    my $info = $domain->info(user_admin);
    my $usb = [];
    $usb = $info->{hardware}->{usb} if exists $info->{hardware}->{usb};

    for my $n ( 1 .. 4 ) {
        my $req = Ravada::Request->add_hardware(
                name => 'usb'
                ,uid => user_admin->id
                ,id_domain => $domain->id
                );
        wait_request(debug => 0);
        $domain = Ravada::Domain->open($domain->id);
        my $info2 = $domain->info(user_admin);
        my $usb2 = [];
        $usb2 = $info2->{hardware}->{usb} if exists $info2->{hardware}->{usb};
        is(scalar(@$usb2),scalar(@$usb)+$n) or die $domain->name;

    }

    my $usb_controller = $info->{hardware}->{usb_controller};
    ok($usb_controller) && do {
        is(scalar(@$usb_controller),1) or die $domain->name;
    };
    $domain->remove(user_admin);
}

########################################################################

init();
clean();

for my $vm_name ( 'KVM' ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $vm_name eq 'KVM' && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_usb_many($vm);
    }
}

end();

done_testing();
