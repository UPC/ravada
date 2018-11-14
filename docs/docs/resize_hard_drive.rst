How to extend a Ravada Windows guest's disk space
=================================================

More info: http://libguestfs.org/virt-resize.1.html#expanding-a-virtual-machine-disk

.. Warning:: Use truncate only for raw image files. For qcow2 files, use qemu-img

Expanding a Windows 10 guest
----------------------------
Here we will show how to expand the system partition of a Windows 10 host by 10 GB.

First, retrieve the path to the hard drive file that you want to resize. For a VM named ``Windows10Slim``, we would do the following:

.. prompt:: bash #

  virsh dumpxml Windows10Slim

Here is our image file:

::

  <source file='/var/lib/libvirt/images-celerra1/Windows10Slim-vda-UrQ2.img'/>

As we want to expand a certain partition, the system one, we must find it first

.. prompt:: bash #

  virt-filesystems --long --parts --blkdevs -h -a /var/lib/libvirt/images-celerra1/Windows10Slim-vda-UrQ2.img

The output will look like this:

::

  Name       Type       MBR  Size  Parent
  /dev/sda1  partition  -    500M  /dev/sda
  /dev/sda2  partition  07   20G   /dev/sda
  /dev/sda   device     -    20G   -

And that means we are going to resize ``/dev/sda2`` in this example.

Use qemu-img to create a new qcow2 hard drive file. As we want to add 10 GB, the resulting disk will be a 30 GB file

.. prompt:: bash #

    qemu-img create -f qcow2 -o preallocation=metadata /var/lib/libvirt/images.2/Windows10Slim-vda-UrQ3.img 30G

Now virt-resize will expand the image into the new file

.. prompt:: bash #

    virt-resize --expand /dev/sda2 /var/lib/libvirt/images-celerra1/Windows10Slim-vda-UrQ2.img /var/lib/libvirt/images.2/Windows10Slim-vda-UrQ3.img

With virsh we can point the VM to use the newly created image

.. prompt:: bash #

    virsh edit Windows10Slim


Finally, fix permissions

.. prompt:: bash #

    chown libvirt-qemu:kvm /var/lib/libvirt/images.2/Windows10Slim-vda-UrQ3.img
    chmod 600 /var/lib/libvirt/images.2/Windows10Slim-vda-UrQ3.img
