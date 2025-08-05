use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use IPC::Run3 qw(run3);
use Test::More;
use Mojo::JSON qw( encode_json decode_json );
use Storable qw(dclone);
use YAML qw(Load Dump  LoadFile DumpFile);

use Ravada::HostDevice::Templates;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

my $BASE;
my $N_TIMERS;

$Ravada::Domain::TTL_REMOVE_VOLATILE=3;

#########################################################################################
#

sub _create_grid($vm) {
    my $templates = Ravada::HostDevice::Templates::list_templates($vm->id);
    my ($mdev) = grep { $_->{name} =~ /vGPU VFIO/ } @$templates;
    warn Dumper([ map { $_->{name} } @$templates]);
    ok($mdev,"Expecting Nvidia Grid template in ".$vm->name) or return;

    my $id = $vm->add_host_device(template => $mdev->{name});
    my $hd = Ravada::HostDevice->search_by_id($id);

    return $hd;
}

sub test_grid($vm) {

    my $hd = _create_grid($vm);

    warn Dumper([$hd->list_available_devices()]);
}

#########################################################################################

clean();

for my $vm_name ('KVM', 'Void' ) {
    my $vm;
    eval {
        $vm = rvd_back->search_vm($vm_name)
        unless $vm_name eq 'KVM' && $<;
    };

    SKIP: {

        my $msg = "SKIPPED: $vm_name virtual manager not found ".($@ or '');

        diag($msg)      if !$vm;
        skip($msg,10)   if !$vm;

        diag("Testing host devices in $vm_name");

        if ($vm_name eq 'Void') {
            $BASE = create_domain($vm);
        } else {
            $BASE = import_domain($vm);
        }
        my ($domain, $host_device) = test_grid($vm);
    }
}

end();
done_testing();

