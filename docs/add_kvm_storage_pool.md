#How to add a Qemu-KVM storage pool

If you run out of disk space you may add a new disk. KVM mush then
be informed about this new space available by creating a new
storage pool.

##Add the drive to the system

Add the drive to the host. Format it.

After booting with the new drive, check dmesg to find out the
name of the new disk. It will probably be called /dev/sdSOMETHING.

Double check this is actually the new disk, if not you may erase
all the contents of the system. Type df to see the old disk partitions.

Create a new partition with fdisk. It should show it as empty. Add only
one primary partition for all the free space.

    $ sudo fdisk /dev/sdb

Format it with large files tunning:

    $ sudo mkfs.ext4 -m 0.001 -T largefiles /dev/sdb1

##Mount the new partition

Add this new partition to the filesystem table:

    $ sudo mkdir /var/lib/libvirt/images.2
    $ sudo vim /etc/fstab
    /dev/sdb1   /var/lib/libvirt/images.2 ext4  auto    0   3

It will mount it next time you boot, but it can be used without rebooting
issuing:

    sudo mount -a

##Add the drive to the Virtual Manager

    $ sudo virsh pool-define-as pool2 dir - - - - /var/lib/libvirt/images.2
    $ sudo virsh pool-autostart pool2
    $ sudo virsh pool-start pool2

And that's it, now Ravada will use the pool that has more empty space the
next time it needs to create a volume.
