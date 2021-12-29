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

sub test_bridge($vm) {
    for my $net ( $vm->vm->list_all_networks ) {
        my $xml = XML::LibXML->load_xml(string
            => $net->get_xml_description());
        my ($xml_ip) = $xml->findnodes("/network/ip");
        my $address = $xml_ip->getAttribute('address');
        $address =~ s/\.\d+$/.4/;
        is($vm->_is_ip_bridged($address),1);
    }
    is($vm->_is_ip_bridged("127.0.0.1"),0);
}

########################################################################
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

        test_bridge($vm);
    }
}

end();

done_testing();
