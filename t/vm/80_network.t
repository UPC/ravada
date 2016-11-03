use warnings;
use strict;

use Data::Dumper;
use Test::More;
use Test::SQL::Data;
use XML::LibXML;

use lib 't/lib';
use Test::Ravada;

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

use_ok('Ravada');

my $FILE_CONFIG = 't/etc/ravada.conf';

my $RVD_BACK = rvd_back($test->connector, $FILE_CONFIG);
my $RVD_FRONT= rvd_front($test->connector, $FILE_CONFIG);

my %ARG_CREATE_DOM = (
      KVM => [ id_iso => 1 ]
    ,Void => [ ]
);

my @ARG_RVD = ( config => $FILE_CONFIG,  connector => $test->connector);

my @VMS = reverse keys %ARG_CREATE_DOM;
my $USER = create_user("foo","bar");

my %SUB_CHECK_NET =(
    'KVM' => \&check_net_kvm
);
###############################################################################

sub test_vm {
    my ($vm_name) = @_;

    for my $rvd ($RVD_FRONT,$RVD_BACK) {
        my $vm = $rvd->open_vm($vm_name);
        ok($vm,"Expecting $vm_name VM");
        my @networks =  $vm->list_networks();
        ok(scalar @networks
            , "[$vm_name] Expecting at least 1 network, got ".scalar @networks);
        ok(scalar @networks > 1
            , "[$vm_name] Expecting at least 2 networks, got ".scalar @networks)
                if $vm_name !~ /Void/i;

        for my $net (@networks) {
            ok($net->type =~ /\w/,"Expecting type , got '".$net->type."'");
            ok($net->xml_source =~ /<source/,"Expecting source, got '".$net->xml_source."'");
            test_create_domain($vm_name, $vm, $net);
        }
    }

}

sub test_create_domain {
    my ($vm_name, $vm, $net) = @_;

    my $domain_name = new_domain_name();

    my @args_create = (
            vm => $vm_name
         ,name => $domain_name
       ,id_iso => 1
      ,network => $net
     ,id_owner => $USER->id
    );

    if ($vm->readonly) {
        my $req = $RVD_FRONT->create_domain(@args_create);
        $RVD_BACK->process_requests();
        wait_request($req);
        ok($req->status eq 'done',"Expecting req 'done', got '".$req->status."'") or return;
        ok(!$req->error ,"Expecting no req error , got '".$req->error."'") or return;

    } else {
        my $domain0 = $vm->create_domain(@args_create);
    }

    my $domain = $vm->search_domain($domain_name);
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
        ,"[$vm_name - macVTap] Expecting mode='$exp_mode', got '".($mode or '<UNDEF>'));



}

###############################################################################
remove_old_domains();
remove_old_disks();

for my $vm_name (@VMS) {
    test_vm($vm_name);
}

remove_old_domains();
remove_old_disks();

done_testing();
