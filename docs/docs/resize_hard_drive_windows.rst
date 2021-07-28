How to extend a Ravada Windows guest's disk space
=================================================

Extending a Windows disk drive in a virtual machine is a straightforward
process. Follow this guide carefully.

The process requires execute a hardware change in the Ravada frontend and
then use the command line in the host to resize the partition.

Shutdown
--------

The virtual machine must be down to resize the volumes. Press *Shutdown* button
in the *Admin Tool*.

Backup
------

Make a backup of the disk volumes. The easiest way is to
`compact <http://ravada.readthedocs.io/en/latest/docs/compact.html`_
the virtual machine. After that you should have a copy of all the volumes
in the images directory. Usually located at /var/lib/libvirt/images.

Expand the volume
-----------------

Go to the *Hardware* tab in the virtual machine settings. Select the
disk drive you want to extend and type the desired size of the volume.

.. figure: images/resize_volume.jpg

Remove and create the partition again
-------------------------------------

This part of the process must be down in the command line. Connect to the
server console and go to the images directory:

.. prompt:: bash $

  sudo bash
  cd /var/lib/libvirt/images


Connect the disk volume as a device
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. prompt:: bash root@telecos:/var/lib/libvirt/images#

  modprobe nbd
  qemu-nbd -c /dev/nbd1 /var/lib/libvirt/images/WindowsE10_basic-2-hda.WindowsE10_basic-hp-hda.qcow2

Now the volume appears as an nbd device in the host system. You can use fdisk and other
tools to change the partitions.

Remove and create the partition
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. prompt:: bash root@telecos:/var/lib/libvirt/images#

  fdisk /dev/nbd1
  p


.. ::

  Disk /dev/nbd1: 110 GiB, 118111600640 bytes, 230686720 sectors
  Units: sectors of 1 * 512 = 512 bytes
  Sector size (logical/physical): 512 bytes / 512 bytes
  I/O size (minimum/optimal): 512 bytes / 512 bytes
  Disklabel type: dos
  Disk identifier: 0x88e082d8
  
  Device      Boot   Start      End  Sectors  Size Id Type
  /dev/nbd1p1 *       2048  1126399  1124352  549M  7 HPFS/NTFS/exFAT
  /dev/nbd1p2      1126400 62912511 61786112 29,5G  7 HPFS/NTFS/exFAT
  
