Install Windows 11
==================

These are guidelines to install Windows 11 inside a  Ravada KVM Guest.

Requirements
------------

Windows 11 requires TPM ( Trusted Platform Module ).
Follow `this guide <http://ravada.readthedocs.io/en/latest/docs/install_tpm.html>`_

Base Guest
~~~~~~~~~~

The guest should have more than 4 GB of RAM
You can increase it later if you want to keep it slim.

At least 60GB disk drive are required. A swap partition should also be
added when creating the virtual machine.

Installation sources
~~~~~~~~~~~~~~~~~~~~

Two installation source ISO files are required:

* Windows 11 ISO image
* Virtio drivers. Click `here <https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/>`_ to download.

Download and copy them in the Ravada host server
at the directory */var/lib/libvirt/images* .
