use warnings;
use strict;

use Carp qw(confess);
use Data::Dumper;
use Test::More;

use lib 't/lib';
use Test::Ravada;

no warnings "experimental::signatures";
use feature qw(signatures);

#################################################################

sub test_pcie($vm) {
    my $base = create_domain_v2(vm => $vm, id_iso => search_id_iso('Alpine%64'));
    $base->prepare_base(user_admin);

    my $clone = Ravada::Request->clone(
            id_domain => $base->id
            ,uid => user_admin->id
    );
    wait_request();
}

sub test_pcie_2($vm) {

    my $name = new_domain_name();
    my $device_disk = $vm->create_volume(
        name => $name
        ,size => 1024 * 1024
        ,xml => "etc/xml/dsl-volume.xml");

    my $string=<<EOT;
<domain type='kvm' id='50'>
  <name>$name</name>
  <uuid>55b671a7-77c8-4447-b21e-1771055f8bff</uuid>
  <memory unit='KiB'>135168</memory>
  <currentMemory unit='KiB'>135168</currentMemory>
  <vcpu placement='static'>1</vcpu>
  <resource>
    <partition>/machine</partition>
  </resource>
  <sysinfo type='smbios'>
    <oemStrings>
      <entry>hostname: $name</entry>
    </oemStrings>
  </sysinfo>
  <os>
    <type arch='x86_64' machine='pc-q35-6.2'>hvm</type>
    <loader readonly='yes' type='pflash'>/usr/share/OVMF/OVMF_CODE_4M.fd</loader>
    <nvram template='/usr/share/OVMF/OVMF_VARS_4M.fd'>/var/lib/libvirt/qemu/nvram/$name.fd</nvram>
    <smbios mode='sysinfo'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='custom' match='exact' check='full'>
    <model fallback='forbid'>qemu64</model>
    <feature policy='require' name='x2apic'/>
    <feature policy='require' name='hypervisor'/>
    <feature policy='require' name='lahf_lm'/>
    <feature policy='disable' name='svm'/>
  </cpu>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <pm>
    <suspend-to-mem enabled='no'/>
    <suspend-to-disk enabled='no'/>
  </pm>
  <devices>
    <emulator>/usr/bin/kvm-spice</emulator>
    <controller type='pci' index='0' model='pcie-root'>
      <alias name='pcie.0'/>
    </controller>
    <controller type='pci' index='1' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='1' port='0x8'/>
      <alias name='pci.1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0' multifunction='on'/>
    </controller>
    <controller type='pci' index='2' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='2' port='0x9'/>
      <alias name='pci.2'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
    </controller>
    <controller type='pci' index='3' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='3' port='0xa'/>
      <alias name='pci.3'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x2'/>
    </controller>
    <controller type='pci' index='4' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='4' port='0xb'/>
      <alias name='pci.4'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x3'/>
    </controller>
    <controller type='virtio-serial' index='0'>
      <alias name='virtio-serial0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </controller>
    <controller type='usb' index='0' model='qemu-xhci'>
      <alias name='usb'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </controller>
    <controller type='sata' index='0'>
      <alias name='ide'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x1f' function='0x2'/>
    </controller>
    <interface type='network'>
      <mac address='52:54:00:c2:ca:7a'/>
      <source network='default' portid='6ece46b8-9b93-4ba8-9a5c-771087abbf3c' bridge='virbr0'/>
      <target dev='vnet48'/>
      <model type='rtl8139'/>
      <alias name='net0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <serial type='pty'>
      <source path='/dev/pts/14'/>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
      <alias name='serial0'/>
    </serial>
    <console type='pty' tty='/dev/pts/14'>
      <source path='/dev/pts/14'/>
      <target type='serial' port='0'/>
      <alias name='serial0'/>
    </console>
    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0' state='disconnected'/>
      <alias name='channel0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>
    <channel type='unix'>
      <source mode='bind' path='/var/lib/libvirt/qemu/channel/target/domain-50-tst_pcie/org.qemu.guest_agent.0'/>
      <target type='virtio' name='org.qemu.guest_agent.0' state='disconnected'/>
      <alias name='channel1'/>
      <address type='virtio-serial' controller='0' bus='0' port='2'/>
    </channel>
    <input type='mouse' bus='ps2'>
      <alias name='input0'/>
    </input>
    <input type='keyboard' bus='ps2'>
      <alias name='input1'/>
    </input>
    <graphics type='spice' port='5901' autoport='yes'>
      <listen type='address'/>
      <image compression='auto_glz'/>
      <jpeg compression='auto'/>
      <zlib compression='auto'/>
      <playback compression='on'/>
      <streaming mode='filter'/>
    </graphics>
    <sound model='ich6'>
      <alias name='sound0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </sound>
    <audio id='1' type='spice'/>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <alias name='video0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <redirdev bus='usb' type='spicevmc'>
      <alias name='redir0'/>
      <address type='usb' bus='0' port='1'/>
    </redirdev>
    <redirdev bus='usb' type='spicevmc'>
      <alias name='redir1'/>
      <address type='usb' bus='0' port='2'/>
    </redirdev>
    <redirdev bus='usb' type='spicevmc'>
      <alias name='redir2'/>
      <address type='usb' bus='0' port='3'/>
    </redirdev>
    <redirdev bus='usb' type='spicevmc'>
      <alias name='redir3'/>
      <address type='usb' bus='0' port='4'/>
    </redirdev>
    <memballoon model='virtio'>
      <alias name='balloon0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </memballoon>
  </devices>
  <seclabel type='dynamic' model='apparmor' relabel='yes'>
    <label>libvirt-55b671a7-77c8-4447-b21e-1771055f8bc3</label>
    <imagelabel>libvirt-55b671a7-77c8-4447-b21e-1771055f8bc3</imagelabel>
  </seclabel>
  <seclabel type='dynamic' model='dac' relabel='yes'>
    <label>+64055:+132</label>
    <imagelabel>+64055:+132</imagelabel>
  </seclabel>
</domain>
EOT
    my $xml = XML::LibXML->load_xml(string => $string);
    Ravada::VM::KVM::_xml_modify_disk($xml,[$device_disk]);
    my $dom;
    eval { $dom = $vm->vm->define_domain($xml) };
    ok(!$@,"Expecting error='' , got '".($@ or '')."'") or return
    ok($dom,"Expecting a VM defined from string ") or return;

    eval{ $dom->create };
    ok(!$@,"Expecting error='' , got '".($@ or '')."'");

    my $base = Ravada::Domain::KVM->new(domain => $dom
                , storage => $vm->storage_pool
                , _vm => $vm
    );
    $base->_insert_db(name => $name, id_owner => user_admin->id);

    $base->shutdown_now(user_admin);

    $base->prepare_base(user_admin);

    my $req_clone = Ravada::Request->clone(
            id_domain => $base->id
            ,uid => user_admin->id
    );
    wait_request(debug => 0);
    is($req_clone->status,'done');
    is($req_clone->error,'') or exit;

}

#################################################################

clean();
for my $vm_name ( 'KVM'  ) {

    SKIP: {
    my $vm = rvd_back->search_vm($vm_name);

    my $msg = "SKIPPED test: No $vm_name VM found ";
    if ($vm_name ne 'Void' && $>) {
            $msg = "SKIPPED: Test must run as root";
            $vm = undef;
    }

    diag($msg)      if !$vm;
    skip $msg,10    if !$vm;

    diag("Testing $vm_name bundle");

    test_pcie_2($vm);
    test_pcie($vm);
    }
}

end();
done_testing();
