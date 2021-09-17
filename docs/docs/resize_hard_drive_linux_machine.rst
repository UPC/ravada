How to extend a Ravada Linux guest's disk space
=================================================

Extending a Linux disk drive in a virtual machine is a straightforward
process. Follow this guide carefully.

The process requires a change in the Ravada frontend and
then use the command line in the host to resize the partition.

Shutdown
--------

The virtual machine must be down to resize the volumes. Press *Shutdown* button
in the *Admin Tools*.

Backup
------

Make a backup of the disk volumes. The easiest way is to
`compact <http://ravada.readthedocs.io/en/latest/docs/compact.html>`_
the virtual machine. After that you should have a copy of all the volumes
in the images directory. Usually located at /var/lib/libvirt/images.

Expand the volume
-----------------

Go to the *Hardware* tab in the virtual machine settings. Select the
disk drive you want to extend and type the desired size of the volume.

.. figure:: images/resize_volume.jpg

Remove and create the partition again
-------------------------------------

This part of the process must be down in the command line. Connect to the
server console and go to the images directory:

.. prompt:: bash

  sudo bash


Connect the disk volume as a device
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. prompt:: bash root@telecos:~#

  modprobe nbd
  qemu-nbd -c /dev/nbd1 /var/lib/libvirt/images/linux-user-vda.qcow2

Now the volume appears as an nbd device in the host system. You can use fdisk and other
tools to change the partitions.

Remove and create the partition
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

First let's check what are the partitions with *fdisk*:

.. prompt:: bash root@telecos:~#

  fdisk /dev/nbd1


::

  p
  Disk /dev/nbd1: 110 GiB, 118111600640 bytes, 230686720 sectors
  Units: sectors of 1 * 512 = 512 bytes
  Sector size (logical/physical): 512 bytes / 512 bytes
  I/O size (minimum/optimal): 512 bytes / 512 bytes
  Disklabel type: dos
  Disk identifier: 0x88e082d8
  
  Device      Boot   Start      End  Sectors  Size Id Type
  /dev/nbd1p1 *       2048   1050623 1048576  512M  b W95 FAT32
  /dev/nbd1p2         2048  1126399  1124352   10G 83 Linux
  

The partition we want to change is the second one (nbd1p2). From fdisk:

::

  # fdisk /dev/nbd1
  Command (m for help): d
  Partition number (1,2, default 2):
  Partition 2 has been deleted.

Now we create the partition again but using all the space we just added.
*Warning*: when asked about remove the signature, answer N.

::

  Command (m for help): n
  Partition type
     p   primary (1 primary, 0 extended, 3 free)
     e   extended (container for logical partitions)
  Select (default p): p
  Partition number (2-4, default 2):
  First sector (1126400-230686719, default 1126400):
  Last sector, +/-sectors or +/-size{K,M,G,T,P} (1126400-230686719, default 230686719):
  Created a new partition 2 of type 'Linux' and of size 109,5 GiB.
  Partition #2 contains an ext4 signature.
  Do you want to remove the signature? [Y]es/[N]o: N

Then save an exit fdisk:

::

  Command (m for help): w
  The partition table has been altered.
  Calling ioctl() to re-read partition table.
  Syncing disks.

Fix the new partition
---------------------

The new partition must be checked and fixed before resize.

Fix it first in the host:

.. prompt:: bash #

  e2fsck /dev/nbd1p2
  resize2fs /dev/nbd1p2


Start
-----

Disconnect the nbd and start the virtual machine.

.. prompt:: bash #

  qemu-nbd -d /dev/nbd1
  rmmod nbd

Start the virtual machine from the Ravada frontend as usual.

Check the new size
------------------

Boot the virtual machine again, in a terminal type df, it should show the new size.
