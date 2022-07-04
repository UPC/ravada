use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3;
use JSON::XS;
use Test::More;

use Ravada::HostDevice::Templates;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

########################################################################

sub test_pci($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->id);
    my ($pci) = grep { $_->{name} eq 'PCI' } @$templates;
    ok($pci,"Expecting PCI template in ".$vm->name) or return;

    my $id = $vm->add_host_device(template => $pci->{name});

    my $domain = create_domain_v2(
        vm => $vm
        ,options => { machine => 'q35' } );
    $domain->add_host_device($id);
    $domain->start(user_admin);
}

########################################################################

init();
clean();

for my $vm_name ( 'KVM' ) {

    SKIP: {
        my $vm = rvd_back->search_vm($vm_name);

        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm && $>) {
              $msg = "SKIPPED: Test must run as root";
              $vm = undef;
        }

        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        test_pci($vm);
    }
}

end();

done_testing();

