use warnings;
use strict;

use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;
use XML::LibXML;


use_ok('Ravada');
use_ok('Ravada::Request');

init();
my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);
our $TIMEOUT_SHUTDOWN = 10;

#TODO use config file for DIR_XML
our $DIR_XML = "etc/xml";
$DIR_XML = "/var/lib/ravada/xml/" if $0 =~ m{^/usr/sbin};

our $XML = XML::LibXML->new();
my $RAVADA;
my $BACKEND = 'KVM';

################################################################
sub test_create_domain {
    my $vm_name = shift;
    my $vm = rvd_back->search_vm($vm_name);
    ok($vm,"I can't find VM $vm_name") or return;

    my $name = new_domain_name();

    my $domain;
    $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , arg_create_dom($vm_name));

	my $req = Ravada::Request->add_hardware(name => 'network', id_domain => $domain->id, uid => user_admin->id);
	wait_request();

	ok($domain,"No domain $name created with ".ref($vm)." ".($@ or '')) or return;
    ok($domain->name
        && $domain->name eq $name,"Expecting domain name '$name' , got "
        .($domain->name or '<UNDEF>')
        ." for VM $vm_name"
    );

    return $domain;
}

sub test_req_prepare_base{
    my $name = shift;

    my $domain0 = $RAVADA->search_domain($name);
    ok(!$domain0->is_base,"Domain $name should not be base");

	my $req = Ravada::Request->prepare_base(id_domain => $domain0->id, uid => user_admin->id);
    wait_request();

    ok($req->status('done'),"Request should be done, it is".$req->status);
    ok(!$req->error(),"Request error ".$req->error);

    my $domain = $RAVADA->search_domain($name);
    ok($domain->is_base,"Domain $name should be base");
    ok(scalar $domain->list_files_base," Domain $name should have files_base, got ".
        scalar $domain->list_files_base);

    $domain->is_public(1);
}

#Read xml
sub read_mac{
        my $domain = shift;
        my $xml = XML::LibXML->load_xml(string => $domain->get_xml_base());
        my @mac;
        my (@if_mac) = $xml->findnodes('/domain/devices/interface/mac');
        for my $if_mac (@if_mac) {
            my $mac = $if_mac->getAttribute('address');
            push @mac, $mac;
        }
        return(@mac);
}

sub test_add_nic {
    my $vm_name = shift;

#    diag("Testing add description $vm_name");
    my $vm = rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name);
    my $domain_other = test_create_domain($vm_name);

    #Prepare base
	test_req_prepare_base($domain->name);

	#Clone domain
    my $name = new_domain_name();
    my $domain_father = $domain;
    my $req2 = Ravada::Request->create_domain(
        name => $name
        ,id_base => $domain_father->id
       ,id_owner => user_admin->id
        ,vm => $BACKEND
    );
    wait_request();
    is($req2->error,"");
    is($req2->status,"done");

    my $domain_clon = $RAVADA->search_domain($name);

    my @mac = read_mac($domain);
    my @mac_other = read_mac($domain_other);
    my @mac2 = read_mac($domain_clon);
    isnt($mac[0],$mac2[0], "1st MAC from 1st NIC cloned are the same");
    isnt($mac[1],$mac2[1], "2nd MAC from 2nd NIC cloned are the same");

    my %dupe_mac = ();
    for my $mac (@mac, @mac_other, @mac2) {
        ok(!$dupe_mac{$mac}++,"MAC $mac duplicated");
    }
}


#######################################################

#######################################################

clean();
eval { $RAVADA = rvd_back() };
ok($RAVADA,"I can't launch a new Ravada");# or exit;

my $vm_name = 'KVM';
my $vm;
eval { $vm = rvd_back->search_vm($vm_name) } if !$<;

SKIP: {

    my $msg = "SKIPPED: No virtual managers found";
    if ($vm && $vm_name =~ /kvm/i && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }
    skip($msg,10)   if !$vm;

    test_add_nic($vm_name);
}

end();

done_testing();
