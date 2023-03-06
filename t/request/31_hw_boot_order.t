use warnings;
use strict;

use Carp qw(carp confess cluck);
use Data::Dumper;
use Test::More;
use XML::LibXML;

no warnings "experimental::signatures";
use feature qw(signatures);

use_ok('Ravada');
use_ok('Ravada::Request');

use lib 't/lib';
use Test::Ravada;

init();

my $xml =<<EOT;
<domain type='kvm'>
  <name>Windows-10-2021</name>
  <uuid>fa79d9cf-2e6c-4266-a4e6-6a21a7f36c64</uuid>
  <metadata>
    <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
      <libosinfo:os id="http://microsoft.com/win/10"/>
    </libosinfo:libosinfo>
  </metadata>
  <memory unit='KiB'>3194304</memory>
  <currentMemory unit='KiB'>4194304</currentMemory>
  <vcpu placement='static'>2</vcpu>
  <sysinfo type='smbios'/>
  <os>
    <type arch='x86_64' machine='pc-i440fx-2.11'>hvm</type>
    <bootmenu enable='yes'/>
    <smbios mode='sysinfo'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <hyperv>
      <relaxed state='on'/>
      <vapic state='on'/>
      <spinlocks state='on' retries='8191'/>
      <vpindex state='on'/>
      <synic state='on'/>
      <stimer state='on'/>
      <frequencies state='on'/>
    </hyperv>
    <vmport state='off'/>
    <ioapic driver='kvm'/>
  </features>
  <cpu mode='host-passthrough' check='partial'>
    <cache mode='passthrough'/>
  </cpu>
  <clock offset='localtime'>
    <timer name='hypervclock' present='yes'/>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <pm>
    <suspend-to-mem enabled='no'/>
    <suspend-to-disk enabled='no'/>
  </pm>
  <devices>
    <emulator>/usr/bin/kvm-spice</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='directsync' io='native' discard='unmap'/>
      <source file='/var/lib/libvirt/images/Windows-10-2021-fernandosda.Windows-10-2021-sda.qcow2'/>
      <backingStore/>
      <target dev='sda' bus='scsi'/>
      <boot order='1'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <target dev='sdb' bus='scsi'/>
      <readonly/>
      <boot order='2'/>
      <address type='drive' controller='0' bus='0' target='0' unit='1'/>
    </disk>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='directsync' io='native'/>
      <source file='/var/lib/libvirt/images/Windows-10-2021-fernandosdd.Windows-10-2021-sdd.DATA.qcow2'/>
      <backingStore/>
      <target dev='sdd' bus='scsi'/>
      <boot order='4'/>
      <address type='drive' controller='0' bus='0' target='0' unit='3'/>
    </disk>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='directsync' io='native'/>
      <source file='/var/lib/libvirt/images/Windows-10-2021-fernandosde.Windows-10-2021-sde.SWAP.qcow2'/>
      <backingStore/>
      <target dev='sde' bus='scsi'/>
      <address type='drive' controller='0' bus='0' target='0' unit='4'/>
    </disk>
    <controller type='pci' index='0' model='pci-root'/>
    <controller type='ide' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
    </controller>
    <controller type='virtio-serial' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </controller>
    <controller type='usb' index='0' model='qemu-xhci' ports='15'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </controller>
    <controller type='scsi' index='0' model='virtio-scsi'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </controller>
    <controller type='sata' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x09' function='0x0'/>
    </controller>
    <interface type='network'>
      <mac address='52:54:00:3e:f4:e6'/>
      <source network='default'/>
      <model type='virtio'/>
      <boot order='3'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>
    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='2'/>
    </channel>
    <channel type='spiceport'>
      <source channel='org.spice-space.webdav.0'/>
      <target type='virtio' name='org.spice-space.webdav.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='3'/>
    </channel>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <input type='tablet' bus='usb'>
      <address type='usb' bus='0' port='5'/>
    </input>
    <graphics type='spice' autoport='yes' listen='147.83.36.253'>
      <listen type='address' address='147.83.36.253'/>
      <image compression='auto_glz'/>
      <jpeg compression='auto'/>
      <zlib compression='auto'/>
      <playback compression='on'/>
      <streaming mode='filter'/>
      <gl enable='no'/>
    </graphics>
    <sound model='ac97'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </sound>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <redirdev bus='usb' type='spicevmc'>
      <address type='usb' bus='0' port='1'/>
    </redirdev>
    <redirdev bus='usb' type='spicevmc'>
      <address type='usb' bus='0' port='2'/>
    </redirdev>
    <redirdev bus='usb' type='spicevmc'>
      <address type='usb' bus='0' port='3'/>
    </redirdev>
    <redirdev bus='usb' type='spicevmc'>
      <address type='usb' bus='0' port='4'/>
    </redirdev>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </memballoon>
  </devices>
</domain>
EOT

sub _fix_domain_config($domain) {

    my $old_doc = XML::LibXML->load_xml( string => $domain->xml_description() );
    my ($old_uuid) = $old_doc->findnodes('/domain/uuid/text()');

    my $doc = XML::LibXML->load_xml(string => $xml );
    my ($node_name) = $doc->findnodes('/domain/name/text()');
    $node_name->setData($domain->name);

    my ($uuid) = $doc->findnodes('/domain/uuid/text()');
    $uuid->setData($old_uuid);

    for my $volume ( $doc->findnodes("/domain/devices/disk/source") ) {
        my $old_file = $volume->getAttribute('file');
        my ($path,$ext) = $old_file =~ m{(.*)/.*(-sd.*)};
        my $new_drive = $path."/".new_domain_name().$ext;
        $volume->setAttribute(file => $new_drive);
    }

    $domain->reload_config($doc);
}

sub test_change_capacity($vm, $new_boot_order = undef) {
    my $domain = create_domain($vm);
    _fix_domain_config($domain);

    my $doc = XML::LibXML->load_xml(string => $domain->xml_description );
    my $index = 0;
    my @old_boot;
    for my $disk ($doc->findnodes("/domain/devices/disk")) {
        my ($boot_node) = $disk->findnodes('boot');
        my $old_boot_order;
        $old_boot_order = $boot_node->getAttribute('order') if $boot_node;
        $old_boot[$index++] = $old_boot_order;

        my $boot;
        $boot = $new_boot_order if defined $new_boot_order;

        next if $disk->getAttribute('device') eq 'cdrom';

        my ($source) = $disk->findnodes('source');
        die $disk->toString() unless $source;
        my $file = $source->getAttribute('file');
        $vm->run_command("qemu-img","create","-f","qcow2",$file,"10M");
        my ($target) = $disk->findnodes('target');
        my $driver = $target->getAttribute('bus');
        my $new_capacity = '444M';

        my $req = Ravada::Request->change_hardware(
            uid => user_admin->id
            ,id_domain => $domain->id
            ,index => $index-1
            ,hardware => 'disk'
            ,data => { bus => $driver , boot => $boot, file => $file
                , capacity => $new_capacity }
        );
        wait_request( debug => 0 );
        is($req->status,'done');
        is($req->error, '');

        test_boot_order($domain, $index-1, $boot) if $new_boot_order;

    }
    test_all_boot_order($domain,\@old_boot) if !$new_boot_order;

    $domain->start(user => user_admin , remote_ip => '192.0.9.1');
    $domain->remove(user_admin);
}

sub test_boot_order($domain, $index, $boot) {
    my $domain2 = Ravada::Domain->open($domain->id);
    is($domain2->_get_boot_order($index), $boot,"Expecting boot order for $index") or exit;
}

sub test_all_boot_order($domain, $old_boot) {

    my $doc = XML::LibXML->load_xml(string => $domain->xml_description );
    my $index = 0;
    for my $disk ($doc->findnodes("/domain/devices/disk")) {
        my ($boot_node) = $disk->findnodes('boot');
        my $boot;
        $boot = $boot_node->getAttribute('order') if $boot_node;
        is($boot,$old_boot->[$index],"boot order for disk $index");
        $index++;
    }
}

SKIP: {
    skip("This test must run as root",56) if $<;
my $vm = rvd_back->search_vm('KVM');
test_change_capacity($vm);
for my $n ( 1 .. 4 ) {
    test_change_capacity($vm,$n);
}
}
done_testing();
