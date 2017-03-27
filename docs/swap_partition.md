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
