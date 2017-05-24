Swap Partition
==============

Though installing the Operating System in a Virtual Machine may
be the same as in real machines, carefully planning the swap partition of the virtual machines
will save a lot of disk space. Follow those guidelines.


Swap Volume
-----------
Mark at the creation of the Virtual Machine that swap disk volume.
The desired max size must be declared there. That way a different
disk will be created with that purpose. This volume is different
than regular data disk volumes: it will be created only at the start
of the machine and it will be destroyed at shutdown. Also, this
volume won't keep incremental changes from the base, as data volumes do.

Partitioning
------------
Later on we will address particular considerations for swap space
in different operating systems. By now, keep in mind that the best
practice is to keep a disk volume *only for swap*.

Linux
-----

It is reccommended keep the swapping the less possible. If possible
remove the swap partitions and the swap configuration in _/etc/fstab_.

Some software on Linux requires some swap to run. If so, set the
_swappiness_ to the minimun this way:

    $ sudo sysctl vm.swappiness=1

To make this change permanent add it to the file: _/etc/sysctl.conf_
