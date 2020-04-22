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
The virtual machine _must_ have a primary video device (qxl or cirrus) with a _lower_ PCIe ID than the managed device (the supplied sample XML configuration already satisfies this).

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
You need to generate a unique identifier for each virtual GPU. Note that we were only able to create a single GPU, although in the `official tutorial <https://github.com/intel/gvt-linux/wiki/GVTg_Setup_Guide#51-check-mdev-module-kvmgt-only>` 3 are created.

Mind that you may have to alter the following command depending on your hardware.

    # uuid
    fff6f017-3417-4ad3-b05e-17ae3e1a4615

    # echo "fff6f017-3417-4ad3-b05e-17ae3e1a4615" > "/sys/bus/pci/devices/0000:00:02.0/mdev_supported_types/i915-GVTg_V5_4/create"
    
