use warnings;
use strict;

use Data::Dumper;
use IPC::Run3 qw(run3);
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');

my $RVD_BACK = rvd_back();
my $RVD_FRONT= rvd_front();

my @VMS = vm_names();
my $USER = create_user("foo","bar", 1);

#############################################################################

sub test_create_domain {
    my ($vm_name, $vm) = @_;

    my $name = new_domain_name();

    my $domain;
    eval { $domain = $vm->create_domain(name => $name
                    , id_owner => $USER->id
                    , disk => 1024 * 1024
                    , arg_create_dom($vm_name))
    };

    ok($domain,"Domain $name created with ".ref($vm)." ".($@ or '')) or exit;
    return $domain;
}

sub test_wrong_args {
    my ($vm_name, $vm) = @_;

    eval { $RVD_BACK->import_domain( vm => 'nonvm', user => $USER->name, name => 'a') };
    like($@,qr/unknown VM/i);

    eval { $RVD_BACK->import_domain( vm => $vm_name,user => 'nobody', name => 'a') };
    like($@,qr/unknown user/i);

}

sub test_already_there {
    my ($vm_name, $vm) = @_;


    my $domain = test_create_domain($vm_name, $vm);
    ok($domain,"Create domain") or return;
    eval {
        my $domain_imported = $RVD_BACK->import_domain(
                                        vm => $vm_name
                                     ,name => $domain->name
                                     ,user => $USER->name
        );
    };
    like($@,qr/already in RVD/i,"Test import fail, expecting error");

    return $domain;
}

sub _delete_domain_db($id_domain) {
    for my $table ('domain_displays' , 'domain_ports', 'volumes', 'domains_void', 'domains_kvm', 'domain_instances', 'bases_vm', 'domain_access', 'base_xml', 'file_base_images', 'iptables', 'domains_network') {
        my $sth = connector->dbh->prepare("DELETE FROM $table WHERE id_domain=?");
        $sth->execute($id_domain);
    }

}

sub test_import {
    my ($vm_name, $vm, $domain) = @_;

    my $dom_name = $domain->name;

    _delete_domain_db($domain->id);
    my $sth = connector->dbh->prepare("DELETE FROM domains WHERE id=?");
    $sth->execute($domain->id);
    $domain = undef;

    $domain = $RVD_BACK->search_domain( $dom_name );
    ok(!$domain,"Expecting domain $dom_name removed") or return;

    eval {
        $domain = $RVD_BACK->import_domain(
                                        vm => $vm_name
                                     ,name => $dom_name
                                     ,user => $USER->name
        );
    };
    diag($@) if $@;
    ok($domain,"Importing domain $dom_name");

    my $domain2 = $RVD_BACK->search_domain($dom_name);
    ok($domain2, "Search domain in Ravada");
}

sub test_import_spinoff {
    my $vm_name = shift;
    return if $vm_name eq 'Void';

    my $vm = rvd_back->search_vm($vm_name);
    my $domain = test_create_domain($vm_name,$vm);
    $domain->is_public(1);
    my $clone = $domain->clone(name => new_domain_name(), user => user_admin );
    ok($clone);
    ok($domain->is_base,"Expecting base") or return;

    $clone->remove( user_admin );

    for my $volume ( $domain->list_disks ) {
        my $info = `qemu-img info $volume`;
        my ($backing) = $info =~ m{(backing file.*)};
        ok($backing,"Expecting volume with backing file") or return;
    }

    my $dom_name = $domain->name;

    _delete_domain_db($domain->id);
    my $sth = connector->dbh->prepare("DELETE FROM domains WHERE id=?");
    $sth->execute($domain->id);
    $domain = undef;

    $domain = $RVD_BACK->search_domain( $dom_name );
    ok(!$domain,"Expecting domain $dom_name removed") or return;

    eval {
        $domain = $RVD_BACK->import_domain(
                                        vm => $vm_name
                                     ,name => $dom_name
                                     ,user => $USER->name
        );
    };
    diag($@) if $@;
    ok($domain,"Importing domain $dom_name");

    my $domain2 = $RVD_BACK->search_domain($dom_name);
    ok($domain2, "Search domain in Ravada");

    for my $volume ( $domain2->list_disks ) {
        my $info = `qemu-img info $volume`;
        my ($backing) = $info =~ m{(backing file.*)};
        ok(!$backing,"Expecting volume without backing file");
    }


}

sub _create_vol($vm, $name) {
    my $sp = $vm->vm->get_storage_pool_by_name('default');

    my $old_vol = $sp->get_volume_by_name($name);
    $old_vol->delete() if $old_vol;

    my $xml = <<EOT;
<volume type='file'>
  <name>$name</name>
  <key>/var/lib/libvirt/images/$name</key>
  <capacity unit='bytes'>21474836480</capacity>
  <allocation unit='bytes'>3485696</allocation>
  <physical unit='bytes'>21478375424</physical>
  <target>
    <path>/var/lib/libvirt/images/$name</path>
    <format type='qcow2'/>
    <permissions>
      <mode>0644</mode>
      <owner>0</owner>
      <group>0</group>
    </permissions>
    <timestamps>
      <atime>1538407038.168298505</atime>
      <mtime>1538406915.308849295</mtime>
      <ctime>1538407050.036621775</ctime>
    </timestamps>
    <compat>1.1</compat>
    <features>
      <lazy_refcounts/>
    </features>
  </target>
</volume>
EOT

    $sp->create_volume($xml);
}

sub test_volume($vm) {

    return if $vm->type ne 'KVM';
    my $dom_name = new_domain_name();
    my $vol_name = new_domain_name();
    _create_vol($vm, $vol_name);
    $vm->refresh_storage_pools();
    return if $vm->type ne 'KVM';
my $xml =<<EOT;
<domain type='kvm'>
  <name>$dom_name</name>
  <uuid>6f6c9b78-3ce4-4a4e-a025-b1c7ae1965e0</uuid>
  <metadata>
    <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
      <libosinfo:os id="http://microsoft.com/win/2k8r2"/>
    </libosinfo:libosinfo>
  </metadata>
  <memory unit='KiB'>1273856</memory>
  <currentMemory unit='KiB'>1273856</currentMemory>
  <vcpu placement='static'>1</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-6.2'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='custom' match='exact' check='none'>
    <model fallback='forbid'>qemu64</model>
  </cpu>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='volume' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source pool='default' volume='$vol_name'/>
      <target dev='sda' bus='sata'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
    <controller type='usb' index='0' model='qemu-xhci'>
      <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
    </controller>
    <controller type='sata' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x1f' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pcie-root'/>
    <controller type='pci' index='1' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='1' port='0x10'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0' multifunction='on'/>
    </controller>
    <controller type='pci' index='2' model='pcie-to-pci-bridge'>
      <model name='pcie-pci-bridge'/>
      <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
    </controller>
    <controller type='pci' index='3' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='3' port='0x11'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x1'/>
    </controller>
    <controller type='pci' index='4' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='4' port='0x12'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x2'/>
    </controller>
    <interface type='network'>
      <mac address='52:54:00:71:50:60'/>
      <source network='default'/>
      <model type='rtl8139'/>
      <address type='pci' domain='0x0000' bus='0x02' slot='0x01' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='tablet' bus='usb'>
      <address type='usb' bus='0' port='1'/>
    </input>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes'>
      <listen type='address'/>
    </graphics>
    <audio id='1' type='none'/>
    <video>
      <model type='cirrus' vram='16384' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0'/>
    </video>
    <memballoon model='none'/>
  </devices>
</domain>
EOT

    $vm->vm->define_domain($xml);

    my $domain;
    eval {
        $domain = $RVD_BACK->import_domain(
                                        vm => $vm->type
                                     ,name => $dom_name
                                     ,user => $USER->name
        );
    };
    diag($@) if $@;
    is(''.$@,'') or exit;
    ok($domain,"Importing domain $dom_name") or exit;

    my $domain_f = Ravada::Front::Domain->open($domain->id);
    $domain_f->info(user_admin);

    $domain->remove(user_admin);

}

############################################################################

clean();

for my $vm_name (@VMS) {
    my $vm = $RVD_BACK->search_vm($vm_name);
    SKIP : {
        my $msg = "SKIPPED test: No $vm_name VM found ";
        if ($vm_name eq 'KVM' && $>) {
            $msg = "SKIPPED test: $vm_name must be tested from root user";
            $vm = undef;
        }
        diag($msg)      if !$vm;
        skip $msg,10    if !$vm;

        diag("Testing import in $vm_name");
        test_wrong_args($vm_name, $vm);

        test_volume($vm);

        my $domain = test_already_there($vm_name, $vm);
        test_import($vm_name, $vm, $domain) if $domain;

        test_import_spinoff($vm_name);
    }
}

end();
done_testing();

