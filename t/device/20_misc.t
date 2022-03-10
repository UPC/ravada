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

sub test_remove_hostdev($vm) {

my $path="/domain/devices/hostdev";
my $content =
"<hostdev mode='subsystem' type='pci' managed='yes'>
    <driver name='vfio'/>
    <source>
        <address domain='0x' bus='0x3e' slot='0x' function='0x'/>
    </source>
    <rom bar='on'/>
    <address type='pci' domain='00000' bus='0x01' slot='0x01' function='0x'/>
</hostdev>
            ";
my $config=<<EOT;
<?xml version="1.0"?>
<domain type="kvm">
  <name>ubuntu20-pae02</name>
  <uuid>625dda6f-3371-49eb-9fa4-f8576c3e3afc</uuid>
  <memory unit="KiB">18432000</memory>
  <currentMemory unit="KiB">18432000</currentMemory>
  <vcpu placement="static">6</vcpu>
  <sysinfo type="smbios">
    <oemStrings>
      <entry>hostname: ubuntu20-pae02</entry>
    </oemStrings>
  </sysinfo>
  <os>
    <type arch="x86_64" machine="pc-i440fx-4.2">hvm</type>
    <smbios mode="sysinfo"/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <kvm>
      <hidden state="on"/>
    </kvm>
    <vmport state="off"/>
  </features>
  <cpu mode="host-model" check="partial"/>
  <clock offset="utc">
    <timer name="rtc" tickpolicy="catchup"/>
    <timer name="pit" tickpolicy="delay"/>
    <timer name="hpet" present="no"/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <pm>
    <suspend-to-mem enabled="no"/>
    <suspend-to-disk enabled="no"/>
  </pm>
  <devices>
    <emulator>/usr/bin/kvm-spice</emulator>
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2"/>
      <source file="/var/lib/libvirt/images/ubuntu20-pae02-vda.ubuntu20-hz-vda.qcow2"/>
      <backingStore type="file">
        <format type="qcow2"/>
        <source file="/var/lib/libvirt/images/ubuntu20-hz-vda.ro.qcow2"/>
        <backingStore type="file">
          <format type="qcow2"/>
          <source file="/var/lib/libvirt/images/pae-2-mv-vda.ro.qcow2"/>
          <backingStore type="file">
            <format type="qcow2"/>
            <source file="/var/lib/libvirt/images/pae-vda.ro.qcow2"/>
            <backingStore/>
          </backingStore>
        </backingStore>
      </backingStore>
      <target dev="vda" bus="virtio"/>
      <boot order="1"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x05" function="0x0"/>
    </disk>
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2" cache="none"/>
      <source file="/var/lib/libvirt/images/ubuntu20-pae02-vdb.ubuntu20-by-vdb.SWAP.qcow2"/>
      <backingStore type="file">
        <format type="qcow2"/>
        <source file="/var/lib/libvirt/images/ubuntu20-by-vdb.ro.SWAP.qcow2"/>
        <backingStore type="file">
          <format type="qcow2"/>
          <source file="/var/lib/libvirt/images/pae-2-vx-vdb.ro.SWAP.qcow2"/>
          <backingStore type="file">
            <format type="qcow2"/>
            <source file="/var/lib/libvirt/images/pae-vdb.ro.SWAP.qcow2"/>
            <backingStore/>
          </backingStore>
        </backingStore>
      </backingStore>
      <target dev="vdb" bus="virtio"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x09" function="0x0"/>
    </disk>
    <disk type="file" device="disk">
      <driver name="qemu" type="qcow2"/>
      <source file="/var/lib/libvirt/images/ubuntu20-pae02-vdc.ubuntu20-rz-vdc.DATA.qcow2"/>
      <backingStore type="file">
        <format type="qcow2"/>
        <source file="/var/lib/libvirt/images/ubuntu20-rz-vdc.ro.DATA.qcow2"/>
        <backingStore type="file">
          <format type="qcow2"/>
          <source file="/var/lib/libvirt/images/pae-2-ox-vdc.ro.DATA.qcow2"/>
          <backingStore type="file">
            <format type="qcow2"/>
            <source file="/var/lib/libvirt/images/pae-vdc.ro.DATA.qcow2"/>
            <backingStore/>
          </backingStore>
        </backingStore>
      </backingStore>
      <target dev="vdc" bus="virtio"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x0a" function="0x0"/>
    </disk>
    <disk type="file" device="cdrom">
      <driver name="qemu" type="raw"/>
      <target dev="hdb" bus="ide"/>
      <readonly/>
      <boot order="4"/>
      <address type="drive" controller="0" bus="0" target="0" unit="1"/>
    </disk>
    <controller type="pci" index="0" model="pci-root"/>
    <controller type="pci" index="1" model="pci-bridge">
      <model name="pci-bridge"/>
      <target chassisNr="1"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x0b" function="0x0"/>
    </controller>
    <controller type="ide" index="0">
      <address type="pci" domain="0x0000" bus="0x00" slot="0x01" function="0x1"/>
    </controller>
    <controller type="virtio-serial" index="0">
      <address type="pci" domain="0x0000" bus="0x00" slot="0x06" function="0x0"/>
    </controller>
    <controller type="usb" index="0" model="nec-xhci">
      <address type="pci" domain="0x0000" bus="0x00" slot="0x08" function="0x0"/>
    </controller>
    <interface type="network">
      <mac address="52:54:00:e4:ee:4d"/>
      <source network="default"/>
      <model type="virtio"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x03" function="0x0"/>
    </interface>
    <serial type="pty">
      <target type="isa-serial" port="0">
        <model name="isa-serial"/>
      </target>
    </serial>
    <console type="pty">
      <target type="serial" port="0"/>
    </console>
    <channel type="spicevmc">
      <target type="virtio" name="com.redhat.spice.0"/>
      <address type="virtio-serial" controller="0" bus="0" port="1"/>
    </channel>
    <channel type="unix">
      <target type="virtio" name="org.qemu.guest_agent.0"/>
      <address type="virtio-serial" controller="0" bus="0" port="2"/>
    </channel>
    <input type="mouse" bus="ps2"/>
    <input type="keyboard" bus="ps2"/>
    <graphics type="spice" autoport="yes" listen="147.83.36.253">
      <listen type="address" address="147.83.36.253"/>
      <image compression="auto_glz"/>
      <jpeg compression="auto"/>
      <zlib compression="auto"/>
      <playback compression="on"/>
      <streaming mode="filter"/>
    </graphics>
    <sound model="ich6">
      <address type="pci" domain="0x0000" bus="0x00" slot="0x04" function="0x0"/>
    </sound>
    <video>
      <model type="qxl" ram="65536" vram="65536" vgamem="16384" heads="1" primary="yes"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x02" function="0x0"/>
    </video>
    <hostdev mode="subsystem" type="pci" managed="yes">
      <driver name="vfio"/>
      <source>
        <address domain="0x0000" bus="0x3e" slot="0x00" function="0x0"/>
      </source>
      <rom bar="on"/>
      <address type="pci" domain="0x0000" bus="0x01" slot="0x01" function="0x0"/>
    </hostdev>
    <redirdev bus="usb" type="spicevmc">
      <address type="usb" bus="0" port="1"/>
    </redirdev>
    <redirdev bus="usb" type="spicevmc">
      <address type="usb" bus="0" port="2"/>
    </redirdev>
    <redirdev bus="usb" type="spicevmc">
      <address type="usb" bus="0" port="3"/>
    </redirdev>
    <redirdev bus="usb" type="spicevmc">
      <address type="usb" bus="0" port="4"/>
    </redirdev>
    <memballoon model="virtio">
      <address type="pci" domain="0x0000" bus="0x00" slot="0x07" function="0x0"/>
    </memballoon>
  </devices>
</domain>
EOT

    my $domain = create_domain($vm);
    my $xml_config = XML::LibXML->load_xml(string => $config);
    $domain->reload_config($xml_config);

    $domain->remove_config_node("/domain/devices/hostdev", $content, $xml_config);
    $domain->remove(user_admin);
}

##############################################################3

init();
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

        test_remove_hostdev($vm);
    }
}

end();

done_testing();
