Checking volume disk differences
================================

It is important to keep the clones as small as possible. Because if the disk
volumes of the virtual machines grow you may run out of disk space.


You can check if some files change unnecessarily, they could be
from unexpected activity like unattended package upgrades or system logs.
To do so create two clones and keep one shut down.
Start the second and do some stuff, check the disk volume grow:

Check volume size
-----------------

.. prompt:: bash #

    qemu-img info /var/lib/libvirt/clone-1-vdb.qcow2 -U
    du -hs /var/lib/libvirt/clone-1-vda.qcow2

If you see the volumes don't grow unnecessarily, you worry no more.

Compare volume changes
----------------------

If you want to check the differences between two clones you can compare
like this:

.. prompt:: bash #

    virt-diff --format=qcow2 -a clone-2-vda.qcow2 -A clone-1-vda.qcow2 -h --times

Temporay disk volumes
---------------------

If you need temporary space or a place to store files that change and then
get removed, use a TMP Ravada disk volume. Add it in the hardware settings
for the virtual machine.
