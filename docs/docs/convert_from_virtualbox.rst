How to import a Virtualbox image
================================

.. note:: In this example we have VirtualBox machine called *EXAMPLE*.

Create an empty Virtual Machine
-------------------------------

From the Ravada admin form, create a new virtual machine with the same
operative system as the one installed in the virtual box machine.

Do not install anything in that machine, keep it off. Check what is the
name of the disk volume and remove the other volumes.

Check the contents *file* attribute with the command ``virsh edit EXAMPLE``, 

::

    source file='/var/lib/libvirt/images/EXAMPLE-vda-id8Q.img'/

Remove the ``swap``, ``cdrom`` and other disk volumes.

This is the SWAP volume, notice its name ends in ``.SWAP.img``.

::

    <disk type='file' device='disk'>
      <driver name='qemu' type='raw' cache='none'/>
      <source file='/var/lib/libvirt/images/EXAMPLE-aGam.SWAP.img'/>
      <target dev='vdb' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </disk>

This is the ``cdrom`` disk drive, remove it too.

.. raw:: html

   <address type='drive' controller='0' bus='1' target='0' unit='0'/>

::

    </disk>

Remove also the SWAP image file:

::

    $ sudo rm /var/lib/libvirt/images-celerra1/EXAMPLE-_G_m.SWAP.img

Convert the image file
----------------------

Make sure the VirtualBox machine is down, then convert the VDI to raw, then to qcow2.

This converted image wil be used by the empty virtual machine that was created before.

DIRECTLY VDI TO QCOW2
~~~~~~~~~~~~~~~~~~~~~

::

    $ qemu-img convert -p -f vdi -O qcow2 EXAMPLE.vdi EXAMPLE.qcow2

OR IN TWO STEPS
~~~~~~~~~~~~~~~

1. Convert to raw
~~~~~~~~~~~~~~~~~

::

    $ VBoxManage clonehd --format RAW EXAMPLE.vdi EXAMPLE.img

2. Convert to qcow2
~~~~~~~~~~~~~~~~~~~

Convert to qcow2 using the name you saw before in the *XML* definition
of the machine:

::

    $ sudo qemu-img convert -p -f raw EXAMPLE.vdi -O qcow2 /var/lib/libvirt/images/EXAMPLE-vda-id8Q.img
