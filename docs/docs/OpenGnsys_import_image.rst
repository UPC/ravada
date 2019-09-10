.. Ravada VDI documentation 
   How to import a OpenGnsys image
    Dani Sanchez - 28/Nov/2018

How to import a OpenGnsys image
===============================

First of all, copy the .img OpenGnsys image file to your Ravada system.

The .img OpenGnsys files are raw disk dump compressed with lzop. You can see the contents of a img lzop file with:

.. prompt:: bash $

   lzop -l  B5part3dataUbuntu.img 
   method      compressed  uncompr. ratio uncompressed_name
   LZO1X-1     4536669058 7962881402  57.0% B5part3dataUbuntu.img.raw

Now, we will decompress the file. We have to force it because it doesn't have a .lzop extension:

.. prompt:: bash $

   lzop -x -S .img /opt/opengnsys/images/B5part3dataUbuntu.img 
   ls
   4 drwxr-xr-x  2 root      root            4096 Nov 27 12:49 .
   12 drwxrwxr-x 13 root      opengnsys      12288 Nov 27 12:48 ..
   7776256 -rwxrwxr-x  1 opengnsys opengnsys 7962881402 Oct 26 12:51 B5part3dataUbuntu


As you can see, the raw file have no extension.

.. prompt:: bash $

   file B5part3dataUbuntu 
   B5part3dataUbuntu: data


Now, we have the raw content of our image disk. Opengnsys uses partclone to create an image disk. The next step is dump this raw file to a qcow2 disk using partclone. 

.. Tip:: You can get the partclone utilities from opengnsys, you can download from the web: https://partclone.org/download/, or extract from a partclone package for you linux distribution.

You can inspect the raw file with:

.. prompt:: bash $

   ./partclone.info ./B5part3dataUbuntu 
   Partclone v0.2.38 http://partclone.org
   unknow mode
   File system:  EXTFS
   Device size:   69.8 GB
   Space in use:  69.7 GB
   Free Space:    85.1 MB
   Block size:   4096 Byte
   Used block :  17008739


Now, we have to create an empty qcow2 file and dump the raw file inside. First of all, create the qcow2 file. It's important to check the size to ensure that the dump will fit in.

.. prompt:: bash $
   
   qemu-img create -f qcow2 B5part3dataUbuntu.qcow2 70G


Now, we mount the qcow2 file in your system, to dump it. 

.. Tip:: You can follow this guide to do it: `How to mount a qcow2 disk image <https://gist.github.com/shamil/62935d9b456a6f9877b5>`_

.. prompt:: bash $
   
   qemu-nbd --connect=/dev/nbd0 ./B5part3dataUbuntu.qcow2


Now, whe can create the partition structure of your disk. After create it, this is the result: 

.. prompt:: bash $
   fdisk /dev/nbd0 
   Disk /dev/nbd0: 90 GiB, 96636764160 bytes, 188743680 sectors
   Units: sectors of 1 * 512 = 512 bytes
   Sector size (logical/physical): 512 bytes / 512 bytes
   I/O size (minimum/optimal): 512 bytes / 512 bytes
   Disklabel type: dos
   Disk identifier: 0xc0545c3a
   
   Device      Boot     Start       End   Sectors Size Id Type
   /dev/nbd0p1           2048 182454271 182452224  87G 83 Linux
   /dev/nbd0p2      182454272 188743679   6289408   3G 82 Linux swap / Solaris



Now, we have 2 partitions, ``/dev/nbd0p1`` and ``/dev/nbd0p2``. To dump the img disk we have to use the  partclone.ext3 utility:

Command to restore: 

.. prompt:: bash $

   # ./partclone.ext3 -s ./B5part3dataUbuntu  -O /dev/nbd0p1  -r 
   Partclone v0.2.38 http://partclone.org
   Starting to restore image (./B5part3dataUbuntu) to device (/dev/nbd0p1)
   Calculating bitmap... Please wait... done!
   File system:  EXTFS
   Device size:   69.8 GB
   Space in use:  69.7 GB
   Free Space:    85.1 MB
   Block size:   4096 Byte
   Used block :  17008739


The process begin, and you can follow the logs: 

.. prompt:: bash $
   
   00:00:07, Remaining: 00:05:36, Completed:  2.04%, Rate:  12.16GB/min,
   
   Elapsed 00:00:01, Completed: 99.97%, Rate:   1.23GB/min,                                                                                
   Elapsed: 00:56:28, 
   Remaining: 00:00:00, Completed: 99.98%, Rate:   1.23GB/min,                                                                                        
   Elapsed: 00:56:29, 
   Remaining: 00:00:00, Completed:100.00%, Rate:   1.23GB/min,                                                                                
   Elapsed: 00:56:29, Remaining: 00:00:00,
   Completed:100.00%, Rate:   1.23GB/min,
   
  Total Time: 00:56:29, Ave. Rate:    1.2GB/min, 100.00% completed!
   
  Total Time: 00:56:29, Ave. Rate:    1.2GB/min, 100.00% completed!
  Syncing... OK!
  Partclone successfully restored the image (./B5part3dataUbuntu) to the device (/dev/nbd0p1)
  Cloned successfully.
  root@willow: /ssd/estegoxCloneC6root@willow:/ssd/estegoxCloneC6# 


 Now, you can verify the filesystem, mounting it:


.. prompt:: bash $

   mount /dev/nbd0p1 /mnt/suse
   
   ls -als /mnt/suse/
   total 168
   4 drwxr-xr-x  26 root root               4096 Mar  2 12:20 .
   4 drwxr-xr-x   4 root root               4096 Mar  1 13:55 ..
   4 drwxr-xr-x   2 root root               4096 Feb  3  2017 assig
   4 -rw-------   1 root root                199 Mar  2 11:42 .bash_history
   4 drwxr-xr-x   2 root root               4096 Feb  2 11:51 bin
   4 drwxr-xr-x   4 root root               4096 Mar  2 12:30 boot
   4 drwxr-xr-x   3 root root               4096 May 10  2017 mnt
   20 -rw-r--r--   1 root root              19732 Sep 23  2015 ogAdmLnxClient.log
   4 drwxr-xr-x  80 root root               4096 Feb 19 11:33 opt

 ...

Maybe didn't full the entire disk. You can expand it to fit all the disk:

.. prompt:: bash $

   umount /mnt/suse
   e2fsck /dev/nbd0p1 
   e2fsck 1.43.5 (04-Aug-2017)
   /dev/nbd0p1: clean, 1897474/5701632 files, 16969078/22806528 blocks
   resize2fs /dev/nbd0p1


Now, unmount que qcow2 file:

.. prompt:: bash $
   
   qemu-nbd --disconnect /dev/nbd0


And that's all! Now you can create a Ravada vm and attach the disk.

It's possible that the system needs some extra adjustments. One tipical problem is modify the ``/etc/fstab`` to change the ``/dev/sda`` references to ``/dev/vda`` . Another common problem is recreate the grub boot or add support to ``/dev/vda`` devices. 
