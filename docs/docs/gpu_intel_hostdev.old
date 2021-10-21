Intel GPU Virtualisation (GVT-g)
===========================

Status
------
At the time of writing, there is no explicit support for GVT-g in Ravada.
On the other hand, a Ravada VM can be configured using libvirt.

Please note that this is a very active topic and the instructions outlined here
might not work in your environment
You may want to read the official `Intel GVT Wiki <https://github.com/intel/gvt-linux/wiki/>`_ first.

This guide will focus on GVT-g using the dmabuf approach.

Requirements
------------
* An Intel desktop CPU with an iGPU that supports GVT-g. Check the `setup guide <https://github.com/intel/gvt-linux/wiki/GVTg_Setup_Guide#2-system-requirements>`_.
* A properly configured kernel along with a recent version of qemu. We were successful with Ubuntu 19.10.

Outline
-------
This approach creates a unique PCIe device that cannot be shared between VM instances.
It is then assigned as managed device to a virtual machine (similarly to a passthrough GPU).
The virtual machine **must** have a primary video device (qxl or cirrus) with a **lower** PCIe ID than the managed device (the supplied sample XML configuration already satisfies this).

During the first boot, 2 displays will be available through SPICE (remote-viewer), one for each video device where the second one is likely a black screen. Once the OS is loaded, the second one should start displaying something. It then time to check that Intel drivers are properly installed and disable the first display in the OS and power off.

The final step is to change the first video device from *qxl* (or *cirrus*) to *none*, using *virt-manager* or *virsh-edit*. A sample XML configuration is also provided for this.

Please note that Intel GPUs do not support automatic display resizing, unlike *QXL*.

Configuration
-------------

Kernel
~~~~~

Make sure that you're booting the kernel with the following parameters:
  GRUB_CMDLINE_LINUX="i915.enable_gvt=1 kvm.ignore_msrs=1 intel_iommu=igfx_off drm.debug=0"

Create a virtual GPU
~~~~~~~
You need to generate a unique identifier for each virtual GPU. Note that we were only able to create a single GPU, although in the `official tutorial <https://github.com/intel/gvt-linux/wiki/GVTg_Setup_Guide#51-check-mdev-module-kvmgt-only>`_ 3 are created.

Mind that you may have to alter the following command depending on your hardware.

.. prompt:: bash #

  uuid
  fff6f017-3417-4ad3-b05e-17ae3e1a4615

  echo "fff6f017-3417-4ad3-b05e-17ae3e1a4615" > "/sys/bus/pci/devices/0000:00:02.0/mdev_supported_types/i915-GVTg_V5_4/create"
    
Assign the GPU to a VM
~~~~~~~
The following XML configuration can be used to install and configure the guest OS.

.. code-block:: xml
  :emphasize-lines: 1,187-209,223-230
  :caption: pre.xml
   
  <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
    <name>win10-gvt</name>
    <uuid>e2ef2c4b-1dee-4a43-b241-a24f7581c6c0</uuid>
    <metadata>
      <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
        <libosinfo:os id="http://microsoft.com/win/10"/>
      </libosinfo:libosinfo>
    </metadata>
    <memory unit='KiB'>4194304</memory>
    <currentMemory unit='KiB'>4194304</currentMemory>
    <memoryBacking>
      <locked/>
    </memoryBacking>
    <vcpu placement='static'>8</vcpu>
    <cputune>
      <vcpupin vcpu='0' cpuset='0'/>
      <vcpupin vcpu='1' cpuset='1'/>
      <vcpupin vcpu='2' cpuset='2'/>
      <vcpupin vcpu='3' cpuset='3'/>
      <vcpupin vcpu='4' cpuset='4'/>
      <vcpupin vcpu='5' cpuset='5'/>
      <vcpupin vcpu='6' cpuset='6'/>
      <vcpupin vcpu='7' cpuset='7'/>
    </cputune>
    <os>
      <type arch='x86_64' machine='pc-q35-3.1'>hvm</type>
      <bootmenu enable='no'/>
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
      <topology sockets='1' cores='4' threads='2'/>
      <cache mode='passthrough'/>
    </cpu>
    <clock offset='localtime'>
      <timer name='rtc' tickpolicy='catchup'/>
      <timer name='pit' tickpolicy='delay'/>
      <timer name='hpet' present='no'/>
      <timer name='hypervclock' present='yes'/>
    </clock>
    <on_poweroff>destroy</on_poweroff>
    <on_reboot>restart</on_reboot>
    <on_crash>destroy</on_crash>
    <pm>
      <suspend-to-mem enabled='no'/>
      <suspend-to-disk enabled='no'/>
    </pm>
    <devices>
      <emulator>/usr/bin/kvm</emulator>
      <disk type='file' device='disk'>
        <driver name='qemu' type='qcow2' cache='directsync' io='native'/>
        <source file='/var/lib/libvirt/images.2/win10-gvt.qcow2'/>
        <target dev='sda' bus='scsi'/>
        <boot order='1'/>
        <address type='drive' controller='0' bus='0' target='0' unit='1'/>
      </disk>
      <disk type='file' device='cdrom'>
        <driver name='qemu' type='raw'/>
        <source file='/var/lib/libvirt/images.2/Win10_Spanish_x64.iso'/>
        <target dev='sdb' bus='scsi'/>
        <readonly/>
        <boot order='2'/>
        <address type='drive' controller='0' bus='0' target='0' unit='2'/>
      </disk>
      <disk type='file' device='cdrom'>
        <driver name='qemu' type='raw'/>
        <source file='/var/lib/libvirt/images.2/virtio-win-0.1.173.iso'/>
        <target dev='sdc' bus='sata'/>
        <readonly/>
        <boot order='3'/>
        <address type='drive' controller='0' bus='0' target='0' unit='2'/>
      </disk>
      <controller type='usb' index='0' model='qemu-xhci' ports='15'>
        <address type='pci' domain='0x0000' bus='0x02' slot='0x00' function='0x0'/>
      </controller>
      <controller type='scsi' index='0' model='virtio-scsi'>
        <driver iommu='on' ats='on'/>
        <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
      </controller>
      <controller type='pci' index='0' model='pcie-root'/>
      <controller type='pci' index='1' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='1' port='0x10'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0' multifunction='on'/>
      </controller>
      <controller type='pci' index='2' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='2' port='0x11'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x1'/>
      </controller>
      <controller type='pci' index='3' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='3' port='0x12'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x2'/>
      </controller>
      <controller type='pci' index='4' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='4' port='0x13'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x3'/>
      </controller>
      <controller type='pci' index='5' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='5' port='0x14'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x4'/>
      </controller>
      <controller type='pci' index='6' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='6' port='0x8'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x0' multifunction='on'/>
      </controller>
      <controller type='pci' index='7' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='7' port='0x9'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
      </controller>
      <controller type='pci' index='8' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='8' port='0xa'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x2'/>
      </controller>
      <controller type='pci' index='9' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='9' port='0xb'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x3'/>
      </controller>
      <controller type='pci' index='10' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='10' port='0xc'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x4'/>
      </controller>
      <controller type='pci' index='11' model='pcie-to-pci-bridge'>
        <model name='pcie-pci-bridge'/>
        <address type='pci' domain='0x0000' bus='0x08' slot='0x00' function='0x0'/>
      </controller>
      <controller type='pci' index='12' model='pcie-root-port'>
        <model name='pcie-root-port'/>
        <target chassis='12' port='0xd'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x5'/>
      </controller>
      <controller type='virtio-serial' index='0'>
        <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
      </controller>
      <controller type='sata' index='0'>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x1f' function='0x2'/>
      </controller>
      <interface type='network'>
        <mac address='52:54:00:9c:ec:40'/>
        <source network='default'/>
        <model type='virtio'/>
        <driver name='vhost' iommu='on' ats='on'/>
        <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
      </interface>
      <channel type='spicevmc'>
        <target type='virtio' name='com.redhat.spice.0'/>
        <address type='virtio-serial' controller='0' bus='0' port='1'/>
      </channel>
      <channel type='spiceport'>
        <source channel='org.spice-space.webdav.0'/>
        <target type='virtio' name='org.spice-space.webdav.0'/>
        <address type='virtio-serial' controller='0' bus='0' port='2'/>
      </channel>
      <channel type='unix'>
        <target type='virtio' name='org.qemu.guest_agent.0'/>
        <address type='virtio-serial' controller='0' bus='0' port='3'/>
      </channel>
      <channel type='unix'>
        <target type='virtio' name='org.libguestfs.channel.0'/>
        <address type='virtio-serial' controller='0' bus='0' port='4'/>
      </channel>
      <input type='mouse' bus='ps2'/>
      <input type='keyboard' bus='ps2'/>
      <input type='tablet' bus='virtio'>
        <address type='pci' domain='0x0000' bus='0x07' slot='0x00' function='0x0'/>
      </input>
      <graphics type='spice' autoport='yes' listen='147.83.68.172'>
        <listen type='address' address='147.83.68.172'/>
        <image compression='auto_glz'/>
        <jpeg compression='auto'/>
        <zlib compression='auto'/>
        <playback compression='on'/>
        <streaming mode='filter'/>
        <gl enable='no' rendernode='/dev/dri/by-path/pci-0000:00:02.0-render'/>
      </graphics>
      <graphics type='egl-headless'/>
      <sound model='ich9'>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x1b' function='0x0'/>
      </sound>
      <video>
        <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
      </video>
      <hostdev mode='subsystem' type='mdev' managed='no' model='vfio-pci' display='off'>
        <source>
          <address uuid='fff6f017-3417-4ad3-b05e-17ae3e1a4615'/>
        </source>
        <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
      </hostdev>
      <redirdev bus='usb' type='spicevmc'>
        <address type='usb' bus='0' port='1'/>
      </redirdev>
      <redirdev bus='usb' type='spicevmc'>
        <address type='usb' bus='0' port='2'/>
      </redirdev>
      <memballoon model='virtio'>
        <address type='pci' domain='0x0000' bus='0x04' slot='0x00' function='0x0'/>
      </memballoon>
      <iommu model='intel'>
        <driver caching_mode='on' iotlb='on'/>
      </iommu>
    </devices>
    <qemu:commandline>
      <qemu:arg value='-set'/>
      <qemu:arg value='device.hostdev0.x-igd-opregion=on'/>
      <qemu:arg value='-set'/>
      <qemu:arg value='device.hostdev0.display=on'/>
      <qemu:arg value='-display'/>
      <qemu:arg value='egl-headless'/>
    </qemu:commandline>
  </domain>

There are a few very important elements here:

* The document namespace (xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'). If this attribute is not set, libvirt will probably refuse to understand the XML file.
* A QXL video adapter. Its PCI device (0:0:3:0) is lower than the virtual gpu (mdev, 0:0:4:0), making it the first display adapter.
* The Spice protocol has GL disabled, but a rendernode attribute is set.
* There is an extra graphics node, egl-headless. That will allow us to use GPU acceleration and send it via Spice.
* A hostdev node for the virtual GPU that we created earlier on. 
* Some extra parameters for qemu. These are required because libvirt does not implements these options in the XML definition, at least right now.


You can now import it to libvirt using

.. prompt:: bash #

  virsh define win10_gvt_preinstall.xml

You should now modify the VM definition accordingly to your hardware and preferences (cpus, disk images and so), and boot it. 
Mouse support might be funny and wonky, but Windows can be installed using the keyboard solely.

In Windows it seems you need to disable the non-Intel video adapter and make the second display (Intel) the primary one.

Make sure the guest OS has the required drivers for the Intel GPU before proceeding further.

Disable the non-intel video adapter
~~~~~~~

With the VM powered off, change the video adapter type from *qxl* to *none*. You can use *virt-manager* or virsh-edit. Make sure that the xml definition now looks like:

.. code-block:: xml

  <video>
    <model type='none'/>
  </video>

And that's it!
