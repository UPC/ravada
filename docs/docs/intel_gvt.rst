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

Configuration
-------------
Kernel
~~~~~
Make sure that you're booting the kernel with the following arguments:
  GRUB_CMDLINE_LINUX="i915.enable_gvt=1 kvm.ignore_msrs=1 intel_iommu=igfx_off drm.debug=0"

Create a virtual GPU
~~~~~~~
