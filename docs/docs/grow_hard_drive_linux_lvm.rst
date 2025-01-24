How to extend a Linux LVM guest disk space
==========================================

Extending a Linux disk drive that is LVM in a virtual machine is a straightforward
process. Follow this guide carefully.

The process requires a change using the command line in the host to resize the partition
and in inside the VM to grow it

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

Running in Ravada host root
---------------------------

In the CLI below, I stopped my VM, I looked up the name of the volume, I resized it (+50G), and verified that the resized "worked"

.. prompt:: bash root@dell3:~# virsh list
::

   Id   Name             State
  --------------------------------
   4    ubuntu22.04180   running
   5    knode2           running


.. prompt:: bash root@dell3:~# virsh shutdown ubuntu22.04180
::

   Domain 'ubuntu22.04180' is being shutdown

.. prompt:: bash root@dell3:~# virsh domblklist ubuntu22.04180
::

   Target   Source
  ------------------------------------------------
   vda      /home/jkozik/StoragePool/ubuntu22.04
   sda      -

.. prompt:: bash root@dell3:~# qemu-img resize /home/jkozik/StoragePool/ubuntu22.04 +50G
.. prompt:: bash root@dell3:~# qemu-img info /home/jkozik/StoragePool/ubuntu22.04
::

  image: /home/jkozik/StoragePool/ubuntu22.04
  file format: qcow2
  virtual size: 150 GiB (161061273600 bytes)
  disk size: 96.3 GiB
  cluster_size: 65536
  Format specific information:
      compat: 1.1
      compression type: zlib
      lazy refcounts: true
      refcount bits: 16
      corrupt: false
      extended l2: false

.. prompt:: bash root@dell3:~# fdisk -l /home/jkozik/StoragePool/ubuntu22.04
::

  Disk /home/jkozik/StoragePool/ubuntu22.04: 97.21 GiB, 104376631296 bytes, 203860608 sectors
  Units: sectors of 1 * 512 = 512 bytes
  Sector size (logical/physical): 512 bytes / 512 bytes
  I/O size (minimum/optimal): 512 bytes / 512 bytes

NOTE: in the qemu-info and the fdisk -l commands above the virtual size is now 150G, but the physical size is still 100G.

Restart VM, resize LVM inside of VM
-----------------------------------

Start
-----

Start the virtual machine from the Ravada frontend as usual.

Connect to VM
-------------

This can be via: SSH or XRDP or SPICE

Verify /dev/vda
---------------

.. prompt:: bash jkozik@u2004:~$ lsblk
::

  NAME                      MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
  loop0                       7:0    0     4K  1 loop /snap/bare/5
  loop1                       7:1    0 269.6M  1 loop /snap/firefox/4136
  loop2                       7:2    0  63.9M  1 loop /snap/core20/2264
  loop3                       7:3    0  74.2M  1 loop /snap/core22/1380
  loop4                       7:4    0 269.6M  1 loop /snap/firefox/4209
  loop5                       7:5    0  63.9M  1 loop /snap/core20/2318
  loop6                       7:6    0  91.7M  1 loop /snap/gtk-common-themes/1535
  loop7                       7:7    0  74.2M  1 loop /snap/core22/1122
  loop8                       7:8    0 505.1M  1 loop /snap/gnome-42-2204/176
  loop9                       7:9    0    87M  1 loop /snap/lxd/27948
  loop10                      7:10   0    87M  1 loop /snap/lxd/28373
  loop11                      7:11   0  39.1M  1 loop /snap/snapd/21184
  loop12                      7:12   0  38.7M  1 loop /snap/snapd/21465
  sr0                        11:0    1  1024M  0 rom
  vda                       252:0    0   150G  0 disk
  ├─vda1                    252:1    0     1M  0 part
  ├─vda2                    252:2    0   1.8G  0 part /boot
  └─vda3                    252:3    0  98.2G  0 part
    └─ubuntu--vg-ubuntu--lv 253:0    0  98.2G  0 lvm  /var/snap/firefox/common/host-hunspell

NOTE: the lsblk shows /dev/vda with 150G. That's good!. But also notice that /dev/vda3, the lvm only shows 98G.

Grow /dev/vda3
--------------

.. prompt:: bash jkozik@u2004:~$ sudo su -
::

  [sudo] password for jkozik:

.. prompt:: bash root@u2004:~# growpart -h
::

  growpart disk partition
     rewrite partition table so that partition takes up all the space it can
     options:
      -h | --help       print Usage and exit
           --fudge F    if part could be resized, but change would be
                        less than 'F' bytes, do not resize (default: 1048576)
      -N | --dry-run    only report what would be done, show new 'sfdisk -d'
      -v | --verbose    increase verbosity / debug
      -u | --update  R  update the the kernel partition table info after growing
                        this requires kernel support and 'partx --update'
                        R is one of:
                         - 'auto'  : [default] update partition if possible
                         - 'force' : try despite sanity checks (fail on failure)
                         - 'off'   : do not attempt
                         - 'on'    : fail if sanity checks indicate no support
    
     Example:
      - growpart /dev/sda 1
        Resize partition 1 on /dev/sda

.. prompt:: bash root@u2004:~# growpart /dev/vda 3
::

  CHANGED: partition=3 start=3719168 old: size=205995999 end=209715167 new: size=310853599 end=314572767
  root@u2004:~# lsblk
  NAME                      MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
  loop0                       7:0    0     4K  1 loop /snap/bare/5
  loop1                       7:1    0 269.6M  1 loop /snap/firefox/4136
  loop2                       7:2    0  63.9M  1 loop /snap/core20/2264
  loop3                       7:3    0  74.2M  1 loop /snap/core22/1380
  loop4                       7:4    0 269.6M  1 loop /snap/firefox/4209
  loop5                       7:5    0  63.9M  1 loop /snap/core20/2318
  loop6                       7:6    0  91.7M  1 loop /snap/gtk-common-themes/1535
  loop7                       7:7    0  74.2M  1 loop /snap/core22/1122
  loop8                       7:8    0 505.1M  1 loop /snap/gnome-42-2204/176
  loop9                       7:9    0    87M  1 loop /snap/lxd/27948
  loop10                      7:10   0    87M  1 loop /snap/lxd/28373
  loop11                      7:11   0  39.1M  1 loop /snap/snapd/21184
  loop12                      7:12   0  38.7M  1 loop /snap/snapd/21465
  sr0                        11:0    1  1024M  0 rom
  vda                       252:0    0   150G  0 disk
  ├─vda1                    252:1    0     1M  0 part
  ├─vda2                    252:2    0   1.8G  0 part /boot
  └─vda3                    252:3    0 148.2G  0 part
    └─ubuntu--vg-ubuntu--lv 253:0    0  98.2G  0 lvm  /var/snap/firefox/common/host-hunspell
                                                      /

.. prompt:: bash root@u2004:~# df -h
::

  Filesystem                         Size  Used Avail Use% Mounted on
  tmpfs                              6.2G  1.7M  6.2G   1% /run
  /dev/mapper/ubuntu--vg-ubuntu--lv   97G   93G  486M 100% /
  tmpfs                               31G     0   31G   0% /dev/shm
  tmpfs                              5.0M  4.0K  5.0M   1% /run/lock
  /dev/vda2                          1.8G  264M  1.4G  17% /boot
  tmpfs                              5.4G   72K  5.4G   1% /run/user/131
  overlay                             97G   93G  486M 100% /var/lib/docker/overlay2/83807a2711e3aa56668c41fcbec6a837ac4365e4aa1b23c8e180176d06753f02/merged
  tmpfs                              5.4G   60K  5.4G   1% /run/user/1000

NOTE: After running growpart, above, the lsblk shows /dev/vda3 with 148G. But the lvm is still 98G.

Now run the pvs resize command
------------------------------

.. prompt:: bash root@u2004:~# pvs
::

    PV         VG        Fmt  Attr PSize   PFree
    /dev/vda3  ubuntu-vg lvm2 a--  148.22g 50.00g

.. prompt:: bash root@u2004:~# pvresize /dev/vda3
::

    Physical volume "/dev/vda3" changed
    1 physical volume(s) resized or updated / 0 physical volume(s) not resized

.. prompt:: bash root@u2004:~# pvs
::

    PV         VG        Fmt  Attr PSize   PFree
    /dev/vda3  ubuntu-vg lvm2 a--  148.22g 50.00g

.. prompt:: bash root@u2004:~# df -h
::

  Filesystem                         Size  Used Avail Use% Mounted on
  tmpfs                              6.2G  1.7M  6.2G   1% /run
  /dev/mapper/ubuntu--vg-ubuntu--lv   97G   93G  486M 100% /
  tmpfs                               31G     0   31G   0% /dev/shm
  tmpfs                              5.0M  4.0K  5.0M   1% /run/lock
  /dev/vda2                          1.8G  264M  1.4G  17% /boot
  tmpfs                              5.4G   72K  5.4G   1% /run/user/131
  overlay                             97G   93G  486M 100% /var/lib/docker/overlay2/83807a2711e3aa56668c41fcbec6a837ac4365e4aa1b23c8e180176d06753f02/merged
  tmpfs                              5.4G   60K  5.4G   1% /run/user/1000

Run the lvextend and resize2fs commands on /dev/mapper/ubuntu--vg-ubuntu--lv
----------------------------------------------------------------------------

.. prompt:: bash root@u2004:~# vgs
::

    VG        #PV #LV #SN Attr   VSize   VFree
    ubuntu-vg   1   1   0 wz--n- 148.22g 50.00g

.. prompt:: bash root@u2004:~# lvextend -f -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
::

  Size of logical volume ubuntu-vg/ubuntu-lv changed from 98.22 GiB (25145 extents) to 148.22 GiB (37945 extents).
  Logical volume ubuntu-vg/ubuntu-lv successfully resized.

.. prompt:: bash root@u2004:~# df -h
::

  Filesystem                         Size  Used Avail Use% Mounted on
  tmpfs                              6.2G  1.7M  6.2G   1% /run
  /dev/mapper/ubuntu--vg-ubuntu--lv   97G   93G  486M 100% /
  tmpfs                               31G     0   31G   0% /dev/shm
  tmpfs                              5.0M  4.0K  5.0M   1% /run/lock
  /dev/vda2                          1.8G  264M  1.4G  17% /boot
  tmpfs                              5.4G   72K  5.4G   1% /run/user/131
  overlay                             97G   93G  486M 100% /var/lib/docker/overlay2/83807a2711e3aa56668c41fcbec6a837ac4365e4aa1b23c8e180176d06753f02/merged
  tmpfs                              5.4G   60K  5.4G   1% /run/user/1000

.. prompt:: bash root@u2004:~# resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
::

  resize2fs 1.46.5 (30-Dec-2021)
  Filesystem at /dev/mapper/ubuntu--vg-ubuntu--lv is mounted on /; on-line resizing required
  old_desc_blocks = 13, new_desc_blocks = 19
  The filesystem on /dev/mapper/ubuntu--vg-ubuntu--lv is now 38855680 (4k) blocks long.

Verify that the LVM is now running at 150G
------------------------------------------

.. prompt:: bash root@u2004:~# df -h
::

  Filesystem                         Size  Used Avail Use% Mounted on
  tmpfs                              6.2G  1.7M  6.2G   1% /run
  /dev/mapper/ubuntu--vg-ubuntu--lv  146G   93G   48G  66% /
  tmpfs                               31G     0   31G   0% /dev/shm
  tmpfs                              5.0M  4.0K  5.0M   1% /run/lock
  /dev/vda2                          1.8G  264M  1.4G  17% /boot
  tmpfs                              5.4G   72K  5.4G   1% /run/user/131
  overlay                            146G   93G   48G  66% /var/lib/docker/overlay2/83807a2711e3aa56668c41fcbec6a837ac4365e4aa1b23c8e180176d06753f02/merged
  tmpfs                              5.4G   60K  5.4G   1% /run/user/1000


.. prompt:: bash root@u2004:~# pvs
::

    PV         VG        Fmt  Attr PSize   PFree
    /dev/vda3  ubuntu-vg lvm2 a--  148.22g    0

.. prompt:: bash root@u2004:~# vgs
::

  VG        #PV #LV #SN Attr   VSize   VFree
  ubuntu-vg   1   1   0 wz--n- 148.22g    0

Now, you can begin using the VM with the new expanded size. 
