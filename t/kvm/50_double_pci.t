use warnings;
use strict;

use Data::Dumper;
use IPC::Run3;
use Test::More;

use lib 't/lib';
use Test::Ravada;

init();

my $USER = create_user('foo','bar');

sub create_device {
    my $vol_name = shift;
    my $size = '128';

}

sub test_create_domain_xml {
    my $name = new_domain_name();
    my $file_xml = shift;

    die "Missing '$file_xml'" if !-e $file_xml;
    my $vm = rvd_back->search_vm('KVM');

    my $device_disk = $vm->create_volume(
        name => $name
        ,size => 1024 * 1024
        ,xml => "etc/xml/dsl-volume.xml");
    ok($device_disk,"Expecting a device disk") or return;
    ok(-e $device_disk);

    # oh my god, undocumented internal method -> technical debt
    # but we are trying to test these private subs do its job !
    my $xml = $vm->_define_xml($name, $file_xml);

    Ravada::VM::KVM::_xml_modify_disk($xml,[$device_disk]);
    $vm->_xml_modify_usb($xml);
    $vm->_fix_pci_slots($xml);

    my $dom;
    eval { $dom = $vm->vm->define_domain($xml) };
    ok(!$@,"Expecting error='' , got '".($@ or '')."'\n$xml") or exit;
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

    my $vm = rvd_back->search_vm('KVM');
    my $domain = $vm->search_domain($name);

    my $clone_name = new_domain_name();
    my $domain_clone;
    $domain->shutdown_now($USER)    if $domain->is_active;
    $domain->is_public(1);
    eval {$domain_clone = $domain->clone(name => $clone_name, user => user_admin ) };

    ok(!$@,"Expecting error:'' , got '".($@ or '')."'") or exit;


}

################################################################

remove_old_domains();
remove_old_disks();

my $vm;
eval { $vm = rvd_back->search_vm('KVM') } if !$<;
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
        my $name = test_create_domain_xml(qemu_fix_xml_file($xml));
        next if !$name;
        test_clone_domain($name);
    }


};
end();
done_testing();
