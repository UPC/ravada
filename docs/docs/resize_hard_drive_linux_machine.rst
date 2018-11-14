How to extend a Ravada Linux guest's disk space
========================================================

Here we will show how to extend the system partition of a Linux host by 10 GB.

1. Shutdown the virtual machine

2. Consult the hard drive name of the Virtual Machine you want resize:

.. prompt:: bash #

    virsh edit VirtualMachineName

Here is our image file:

::

    <source file='/path_to_img_file/VirtualDiskImageName.img'/>


3. Use qemu-resize to increase the image size by 10GB:

.. prompt:: bash #

    qemu-img resize /path_to_img_file/VirtualDiskImageName.img +10G

4. IMPORTANT. Do a backup before continue.

.. prompt:: bash #

    cp VirtualDiskImageName.img ./VirtualDiskImageName.img.backup

5. Now start the Virtual Machine. Open a terminal and type:

.. prompt:: bash

    sudo fdisk /dev/vda

Delete the partition

::
    d

Create a new partition

::
    n

Accept all by default and exit saving

::
    w

6. Restart the Virtual Machine.

7. When it starts in a terminal:

.. prompt:: bash

    sudo resize2fs /dev/vda1

You can check if the disk was increased with the 'df' command.
