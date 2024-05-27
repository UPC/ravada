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
    my $filter_pci = config_host_devices('pci',0);
    my $hd = Ravada::HostDevice->search_by_id($id);
    $hd->_data('list_filter' => $filter_pci) if $filter_pci;

    my $domain = create_domain_v2(
        vm => $vm
        ,options => { machine => 'q35' }
        ,iso_name => '%bull%64%'
    );
    _check_there_is_address($domain, '0x0000:0x01:0x00.0x0');
    $domain->add_host_device($id);
    $domain->start(user_admin) if $filter_pci;
}

sub _check_there_is_address($domain, $address) {
    my $xml = XML::LibXML->load_xml( string => $domain->xml_description );
    for my $node ( $xml->findnodes("/domain/devices/*/address") ) {
        my $d = $node->getAttribute('domain');
        next if !defined $d;
        my $b = $node->getAttribute('bus');
        my $s = $node->getAttribute('slot');
        my $f = $node->getAttribute('function');
        next if !defined $f;
        my $found = "$d:$b:$s.$f";
        if ($found eq $address ) {
            return;
        }
    }
    die "Error: address '$address' not found";
}

########################################################################

init();
clean();

for my $vm_name ( 'KVM' ) {

    SKIP: {
        my $vm;
        $vm = rvd_back->search_vm($vm_name) if !$<;

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

