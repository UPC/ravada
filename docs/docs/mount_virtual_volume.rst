Mount Virtual Volumes
=====================

The virtual machine disk volumes can be mounted in the host.

Use cases
---------

You may want to mount the volumes to change information inside the virtual machine
without starting it. You may also want to check the filesystem after it got corrupted
and it won't start.

Mount volume
------------

Identify the virtual machine volume file:

.. prompt:: bash #

    virsh dumpxml virtual_machine | grep "source file"
    <source file='/var/lib/libvirt/images.4/machine-vda-cdtr.qcow2'/>

Now load nbd, create a directory and mount it there. The virtual machine must
be down.

.. prompt:: bash #

    modprobe nbd
    mkdir /mnt/nbd
    qemu-nbd -c /dev/nbd10 /var/lib/libvirt/images.4/machine-vda-cdtr.qcow2 /mnt/

List the partitions. In this case there is only one listed:

.. prompt:: bash #

    fdisk -l /dev/nbd10
    Device       Boot Start      End  Sectors Size Id Type
    /dev/nbd10p1 *     2048 83884031 83881984  40G 83 Linux

We proceed to mount:

.. prompt:: bash #

    mount /dev/nbd10p1 /mnt/nbd

Now we can inspect the contents of the virtual machine inside /mnt/nbd.

Check a filesystem
------------------

A virtual filesystem can be checked from the host. It has to be unmounted and the
virtual machine must be down.

.. prompt:: bash #

    virsh dumpxml virtual_machine | grep "source file"
    <source file='/var/lib/libvirt/images.4/machine-vda-cdtr.qcow2'/>

Now load nbd and connect the volume to a device:

.. prompt:: bash #

    modprobe nbd
    qemu-nbd -c /dev/nbd10 /var/lib/libvirt/images.4/machine-vda-cdtr.qcow2 /mnt/nbd

List the partitions. In this case there is only one listed:

.. prompt:: bash #

    fdisk -l /dev/nbd10
    Device       Boot Start      End  Sectors Size Id Type
    /dev/nbd10p1 *     2048 83884031 83881984  40G 83 Linux

We can check it. If it was a linux partition we can run:

.. prompt:: bash #

    e2fsck /dev/nbd10p1

Restablish the volume
---------------------

It is very important to properly umount the volume, and even unloading nbd. If else
the system may be unstable and require a full reboot of the host server.

Umount volume
~~~~~~~~~~~~~

If we mounted we must umount it:

.. prompt:: bash #

    umount /mnt/nbd

Disconnect NBD
~~~~~~~~~~~~~~

It is a good practice to try to unload the nbd kernel module so if something was
left in use we will see an error message:

.. prompt:: bash #

    qemu-nbd -d /dev/nbd10
    rmmod nbd

