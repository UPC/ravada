use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;
use Test::SQL::Data;

use lib 't/lib';
use Test::Ravada;

my $FILE_CONFIG = 't/etc/ravada.conf';

my $test = Test::SQL::Data->new(config => 't/etc/sql.conf');

init($test->connector, $FILE_CONFIG);

my $USER = create_user('foo','bar');

my $FILE_XML = "t/kvm/etc/winxp.xml";

sub test_create_domain_xml {
    my $name = new_domain_name();
    my $file_xml = (shift or $FILE_XML);

    die "Missing '$file_xml'" if !-e $file_xml;
    my $vm = rvd_back->search_vm('kvm');

    my $device_disk = $vm->create_volume(
        name => $name
        ,xml => "etc/xml/dsl-volume.xml");
    ok($device_disk,"Expecting a device disk") or return;
    ok(-e $device_disk);

    my $xml = $vm->_define_xml($name, $file_xml);

    Ravada::VM::KVM::_xml_modify_disk($xml,[$device_disk]);
#    $vm->_xml_modify_usb($xml);
#    $vm->_fix_pci_slots($xml);

    my $dom;
    eval { $dom = $vm->vm->define_domain($xml) };
    ok(!$@,"Expecting error='' , got '".($@ or '')."'") or return
    ok($dom,"Expecting a VM defined from $file_xml") or return;

    eval{ $dom->create };
    ok(!$@,"Expecting error='' , got '".($@ or '')."'");

    my $domain = Ravada::Domain::KVM->new(domain => $dom
                , storage => $vm->storage_pool
                , _vm => $vm
    );

    $domain->_insert_db(name => $name, id_owner => $USER->id);

    return $name;
}

sub test_clone_domain {
    my $name = shift;

    my $vm = rvd_back->search_vm('kvm');
    my $domain = $vm->search_domain($name);

    my $clone_name = new_domain_name();
    my $clone;
    $domain->shutdown_now($USER)    if $domain->is_active;
    eval {$clone = $domain->clone(name => $clone_name, user => $USER) };

    ok(!$@,"Expecting error:'' , got '".($@ or '')."'") or exit;

    open my $fh,'<', $FILE_XML or die "$! $FILE_XML";
    binmode $fh;
    my $xml = XML::LibXML->load_xml( IO => $fh);
    close $fh;

    my $xml_base  = XML::LibXML->load_xml(string => $domain->domain->get_xml_description());
    my $xml_clone = XML::LibXML->load_xml(string => $clone->domain->get_xml_description());

    my @controller = $xml->findnodes('/domain/devices/controller');
    my @controller_base = $xml_base->findnodes('/domain/devices/controller');
    my @controller_clone = $xml_clone->findnodes('/domain/devices/controller');

    is (scalar @controller, scalar @controller_base) or next;
    is (scalar @controller_base, scalar @controller_clone) or next;

    for my $n ( 0 .. scalar @controller_base - 1) {
        ok(defined $controller_base[$n],"Expecting device controller $n") or next;
        ok(defined $controller_clone[$n],"Expecting device controller in clone $n "
            .$controller_base[$n]->toString) or next;
        is($controller_clone[$n]->toString, $controller_base[$n]->toString) or last;
    }

}

################################################################

remove_old_domains();
remove_old_disks();

my $vm;
eval { $vm = rvd_back->search_vm('KVM') };
SKIP: {
    my $msg = "SKIPPED test: No KVM backend found";
    if ($vm && $>) {
        $msg = "SKIPPED: Test must run as root";
        $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    for my $xml (
        't/kvm/etc/kvm_50_double_pci_0.xml'
        ,'t/kvm/etc/wind10_fail.xml') {
        my $name = test_create_domain_xml($xml);
        next if !$name;
        test_clone_domain($name);
    }


};
remove_old_domains();
remove_old_disks();
done_testing();
