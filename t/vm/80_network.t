use warnings;
use strict;

use Data::Dumper;
use Test::More;
use XML::LibXML;

use lib 't/lib';
use Test::Ravada;

use_ok('Ravada');

$Ravada::DEBUG = 0;
$Ravada::CAN_FORK = 1;

my $FILE_CONFIG = 't/etc/ravada.conf';

init();
my $RVD_BACK = rvd_back();
my $RVD_FRONT= rvd_front();

my @VMS = vm_names();
my $USER = create_user("foo","bar");

my %SUB_CHECK_NET =(
    'KVM' => \&check_net_kvm
);
###############################################################################

sub test_vm_rvd {
    my ($vm_name, $rvd ) = @_;

    my $vm = $rvd->open_vm($vm_name);
    ok($vm,"Expecting $vm_name VM");
    my @networks =  $vm->list_networks();
    ok(scalar @networks
        , "[$vm_name] Expecting at least 1 network, got ".scalar @networks);
    ok(scalar @networks > 1
        , "[$vm_name] Expecting at least 2 networks, got ".scalar @networks)
            if $vm_name !~ /Void/i;

    for my $net (@networks) {
        $rvd->disconnect_vm();
        $vm->disconnect;
        ok($net->type =~ /\w/,"Expecting type , got '".$net->type."'");
        ok($net->xml_source =~ /<source/,"Expecting source, got '".$net->xml_source."'");
        test_create_domain($vm_name, $vm, $net);
    }
}

sub test_vm {
    my $vm_name = shift;

    $RVD_FRONT = undef;
    test_vm_rvd($vm_name, $RVD_BACK);

    $RVD_FRONT= rvd_front( $FILE_CONFIG);
    test_vm_rvd($vm_name, $RVD_FRONT);

    $RVD_FRONT = undef;

}

sub test_create_domain {
    my ($vm_name, $vm, $net) = @_;

    my $domain_name = new_domain_name();

    my @args_create = (
            vm => $vm_name
         ,name => $domain_name
       ,id_iso => search_id_iso('Alpine')
      ,network => $net
     ,id_owner => $USER->id
    );


    if ($vm->readonly) {

        $RVD_BACK->disconnect_vm();
        $RVD_FRONT->disconnect_vm();
        my $req = $RVD_FRONT->create_domain(@args_create);
        $RVD_BACK->process_requests();
        wait_request($req);

        ok($req->status eq 'done',"Expecting req 'done', got '".$req->status."'");
        ok(!$req->error ,"Expecting no req error , got '".($req->error or '<UNDEF>')."'");
        exit if $req->status() ne 'done';

    } else {
        my $domain0 = $vm->create_domain(@args_create);
    }
    $vm = undef;

    my $domain = $RVD_BACK->search_domain($domain_name);
    ok($domain,"Expecting domain '$domain_name' created") or return;

    return if $vm_name =~ /Void/i;

    my $sub = $SUB_CHECK_NET{$vm_name};
    ok($sub,"[$vm_name] Expecting a sub to check network") or return;

    $sub->($vm_name, $domain, $net);

}

sub check_net_kvm {
    my ($vm_name, $domain, $net) = @_;

    my $xml = XML::LibXML->load_xml(string => $domain->domain->get_xml_description);

    my @if = $xml->findnodes('/domain/devices/interface');
    ok(scalar @if == 1,"Expecting 1 interface, got ".scalar @if) or return;

    for my $if ( @if ) {
        if (ref($net) =~ /KVM/) {
            test_interface_kvm($vm_name, $net, $if);
        } elsif(ref($net) =~ /MacVTap/i) {
            test_interface_macvtap($vm_name, $net, $if);
        }
    }
}

sub test_interface_kvm {
    my ($vm_name, $net, $if) = @_;


    my $exp_type = 'network';
    my $type = $if->getAttribute('type');
    ok($type eq $exp_type,"[$vm_name , netKVM] Expecting interface type=\"$exp_type\", got: \"$type\"");

    my ($source) = $if->findnodes('./source');

    my $network = $source->getAttribute('network');
    my ($exp_network) = $net->xml_source =~ /"(\w+)"/;

    ok($network eq $exp_network
                ,"Expecting source=$exp_network , got ".$network);
}

sub test_interface_macvtap {
    my ($vm_name, $net, $if) = @_;

    my $exp_type = 'direct';
    my $type = $if->getAttribute('type');
    ok($type eq $exp_type,"[$vm_name , netKVM] Expecting interface type=\"$exp_type\", got: \"$type\"");

    my ($source) = $if->findnodes('./source');

    my $dev= $source->getAttribute('dev');
    my ($exp_dev) = $net->interface->name;

    ok(defined$dev && $dev eq $exp_dev
        ,"[$vm_name - macVTap] Expecting dev='$exp_dev', got '".($dev or '<UNDEF>'));

    my $mode= $source->getAttribute('mode');
    my ($exp_mode) = $net->mode;

    ok(defined$mode && $mode eq $exp_mode
        ,"[$vm_name - macVTap] Expecting mode='$exp_mode', got '".($mode or '<UNDEF>')."'");



}

###############################################################################
clean();

for my $vm_name (@VMS) {
    my $vm;
    eval { $vm = rvd_back->search_vm($vm_name); };
    SKIP: {
        skip("No $vm_name virtual manager found",3);
        test_vm($vm_name);
    }
}

end();
done_testing();
