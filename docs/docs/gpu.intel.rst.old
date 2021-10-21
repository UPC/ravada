WIP

GPU passthrough
===============
We will explain how to pass the GPU to a guest virtual machine manually, while it is not implemented in Ravada.
We are going to use Single Root I/O Virtualization (SR-IOV).
To begin we add a second graphic card to the server, as can be seen below. We have Intel embeded and one AMD PCI card
We have an integrated graphic card and an AMD PCI.

.. prompt:: bash $,(env)... auto

	lspci | grep VGA
	00:02.0 VGA compatible controller: Intel Corporation HD Graphics 530 (rev 06)
	01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Oland GL [FirePro W2100]

.. prompt:: bash $,(env)... auto

	lspci -nn | grep 01:00.
	01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Oland GL [FirePro W2100] [1002:6608]
	01:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Cape Verde/Pitcairn HDMI Audio [Radeon HD 7700/7800 Series] [1002:aab0]

So we’ve found the second graphics card. Take a note of those IDs in the square brackets: in this case 1002:6608 (graphics) and 1002:aab0 (sound). Note that we’ll need to send the graphics card’s integrated sound card along for the passthrough because both devices are in the same IOMMU group.

Configuration
-------------

To enable SR-IOV in the kernel add any of these following options for pass-through in ``/etc/default/grub``

::

	GRUB_CMDLINE_LINUX_DEFAULT="splash i915.enable_gvt=1 intel_iommu=on iommu=pt"
	GRUB_CMDLINE_LINUX_DEFAULT="splash intel_iommu=on iommu=pt rd.driver.pre=vfio-pci video=efifb:off"
	GRUB_CMDLINE_LINUX_DEFAULT="radeon.blacklist=1 quiet splash amd_iommu=on pci-stub.ids=1002:6608,1002:aab0"
	GRUB_CMDLINE_LINUX_DEFAULT="radeon.blacklist=1 amdgpu.blacklist=1 quiet splash intel_iommu=on amd_iommu=on iommu=pt rd.driver.pre=vfio-pci video=efifb:off pci-stub.ids=1028:2120,1028:aab0"

Add pci-stubs in ``/etc/initramfs-tools/modules``, just add this line: ``pci-stub ids=1002:6608,1002:aab0;``. 

Then add these additional drivers to ``/etc/modules``:

::

	kvmgt
	vfio
	vfio_iommu_type1
	vfio_pci
	vhost-net

And update ``initramfs``:

.. prompt:: bash

	update-initramfs -u

Verification
------------

Reboot and try:

.. prompt:: bash

	lsmod | grep vfio
	dmesg | grep pci-stub
	dmesg | grep VFIO


Assign the graphic card to VM
-----------------------------

TODO more information about https://wiki.debian.org/VGAPassthrough

00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 530 [8086:1912] (rev 06) (prog-if 00 [VGA controller])
	Subsystem: Lenovo HD Graphics 530 [17aa:30be]
	Flags: bus master, fast devsel, latency 0, IRQ 125
	Memory at de000000 (64-bit, non-prefetchable) [size=16M]
	Memory at c0000000 (64-bit, prefetchable) [size=256M]
	I/O ports at f000 [size=64]
	[virtual] Expansion ROM at 000c0000 [disabled] [size=128K]
	Capabilities: <access denied>
	Kernel driver in use: i915
	Kernel modules: i915


More detail
-----------
Intel

::

	00:02.0 VGA compatible controller: Intel Corporation HD Graphics 530 (rev 06) (prog-if 00 [VGA controller])
		Subsystem: Lenovo HD Graphics 530
		Flags: bus master, fast devsel, latency 0, IRQ 126
		Memory at de000000 (64-bit, non-prefetchable) [size=16M]
		Memory at b0000000 (64-bit, prefetchable) [size=256M]
		I/O ports at f000 [size=64]
		[virtual] Expansion ROM at 000c0000 [disabled] [size=128K]
		Capabilities: [40] Vendor Specific Information: Len=0c <?>
		Capabilities: [70] Express Root Complex Integrated Endpoint, MSI 00
		Capabilities: [ac] MSI: Enable+ Count=1/1 Maskable- 64bit-
		Capabilities: [d0] Power Management version 2
		Capabilities: [100] Process Address Space ID (PASID)
		Capabilities: [200] Address Translation Service (ATS)
		Capabilities: [300] Page Request Interface (PRI)
		Kernel driver in use: i915
		Kernel modules: i915


AMD

::

	01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Oland GL [FirePro W2100] (prog-if 00 [VGA controller])
		Subsystem: Dell Oland GL [FirePro W2100]
		Physical Slot: 3
		Flags: bus master, fast devsel, latency 0, IRQ 127
		Flags: bus master, fast devsel, latency 0, IRQ 127
		Memory at c0000000 (64-bit, prefetchable) [size=256M]
		Memory at df000000 (64-bit, non-prefetchable) [size=256K]
		I/O ports at e000 [size=256]
		Expansion ROM at df040000 [disabled] [size=128K]
		Capabilities: [48] Vendor Specific Information: Len=08 <?>
		Capabilities: [50] Power Management version 3
		Capabilities: [58] Express Legacy Endpoint, MSI 00
		Capabilities: [a0] MSI: Enable+ Count=1/1 Maskable- 64bit+
		Capabilities: [100] Vendor Specific Information: ID=0001 Rev=1 Len=010 <?>
		Capabilities: [150] Advanced Error Reporting
		Capabilities: [200] #15
		Capabilities: [270] #19
		Kernel driver in use: radeon
		Kernel modules: radeon, amdgpu

More information
----------------
https://support.amd.com/en-us/download/workstation?os=KVM#pro-driver
