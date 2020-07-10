Server Hardware
===============

So you want to buy a brand new server to run virtual machines on it.
Here are some advices to achieve maximum perfomance and how to save
some money.

Shared Storage
--------------

If you are planning to build a large cluster of Ravada nodes you may
go to an expensive shared storage infraestructure. Be aware this can
be a big deployment that can give access to thousands of users, but
it will be expensive and you may have some perfomance issues.

See this doc about `Clustering Hardware reccommendations <http://ravada.readthedocs.io/en/latest/docs/Cluster_Hardware.html>`_

Ravada is easy to grow, so try first a single server setup and you
can add more later.

Initial Hardware Setup
----------------------

Memory
~~~~~~

RAM is the main issue. Multiply the number of concurrent workstations by
the amount of memory each one requires and that is the total RAM the server
must have. However, recent virtualization improvements allow you to overcommit
the memory.

Network
~~~~~~~

For remote virtual desktops it is enough to have 1 GB ethernet cards. If you
are planning on having many video intensive workstations at the same time
it would be good to have 10 GB network cards on the host.

Disk Drives
~~~~~~~~~~~

You will need to store 3 different kind of data in the server:

* Operative System
* Bases volumes
* Clones volumes

Operative System Disk drives
............................

The Operative System partitions like root, /usr and /var are critical so the
server keeps running. But perfomance is not the main issue. Buy two or three
small hard disk drives. Create RAID1 or RAID5 and define these partitions there.
In our experience RAID1 is more than enough, if you can afford it, buy 3 disk
drives: 2 in the RAID and the third one as a spare.

There is no much space requirement for the operative system. 50 GB should be
than enough. If you buy larger disks you may create a partition to store some
virtual machines volumes.

Bases Volumes
.............

With Ravada virtual machines usually are cloned from a **base**. This base is
prepared in advance with all the sofware the users need. All the machines will
read information from the base volumes so it is a good idea to store this
data in SSD disk drives.

This kind of disks are expensive, so you likely would want to buy only one or
two small disk drives for the base volumes.

RAID5 is usually slow so it is not adviced. If you want to have redundancy
configure a RAID1 with 2 SSD disk drives for the base volumes. It would usually
be mounted at /var/lib/libvirt/images

If you want to save some money do not use RAID for the base volumes.
In our experience, top hardware vendor brand disk drives are reliable. You may get more
space if you buy 2 SSD drives and create two different partitions.
In this case you will have base volumes stored in /var/lib/libvirt/images.1 and
/va/lib/libvirt/images.2 .

Be aware that without RAID there is a downtime risk.
If one of the disk drives fail the information it contains
may be lost and a backup must be restored in a new replacement drive. But it is
uncommon to have both disk drives failed at once, so you can restore the data
in the other volume and carry on while the replacement arrives.

Clones Volumes
..............

Clones volumes are incremental information stored on top of base volumes.
Usually this data doesn't require as much perfomance. So it is not a bad idea
to save some money here and store the clones volumes in large mechanical disk drives.
Anyway if you can afford it buy fast disks for a better user experience.

Configuration Examples
......................

Really cheap server

- Operative System: 2 x Hard Disk Drives 100 GB in RAID1
- Volumes: 1 x Solid State Disk drives

Budget perfomance server

- Operative System: 2 x HDD 100 GB in RAID1
- Bases Volumes: 1 x SSD 500 GB
- Clones Volumes: 1 x HDD 1 TB

From this example you can grow as long as your budget allows it. Having more
drives may give you more space. If you need high availability 24x7 you have
to duplicate the volumes disk drives and set RAID1.

High Availability and performance server

- Operative System: 2 x HDD 100 GB in RAID1
- Bases Volumes: 2 x SSD 500 GB in RAID1
- Clones Volumes: 2 x HDD 1 TB in RAID1

Growing and Scaling
-------------------

Ravada is easy to grow. Start with a tight budget, but try to buy the faster drives
you can afford.

When more users start virtual machines at the same time the server may run out of memory.
Adding more RAM will give you more concurrent users.

If you run out of disk space you can buy more disk drives and add more storage pools.
You can configure some bases go to one storage, others to another. If you buy more
storage it can be defined the new clones will be created in new partitions.

**Ravada does scale**:
A cluster can be created from a main server and nodes can be added to it. You can
use older hardware, even PCs. Ravada will automatically balance virtual machines
and start in the less used nodes. You don't need shared storage in the clusters, but
if you use it start up and clone times will be much faster.

Backup
------

Borg backup is a good free choice, its main advantage is it has good deduplication features.

