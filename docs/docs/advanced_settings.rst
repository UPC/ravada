Ravada advanced settings
========================

Display IP
-----------

On a server with 2 IPs, the configuration file allows the administrator define
which one is used for the display. Add the entry *display_ip* to /etc/ravada.conf
with the public address of the server.

::

    display_ip: public.display.ip

NAT
---

The Ravada server can be behind a NAT environment.

::

  ____RVD    _______________ NAT ________________ client
      Server 1.1.1.1             2.2.2.2

Configure this option in /etc/ravada.conf

::

    display_ip: 1.1.1.1
    nat_ip: 2.2.2.2

Auto Start
----------

Virtual machines can be configured to start automatically when the physical host boots.

.. image:: images/autostart.png

You can enable the auto start column at the frontend configuration file at
/etc/rvd_front.conf .
Reboot the frontend with systemctl restart rvd_front to display the changes.

::

    /etc/rvd_front.conf

    {
        admin => {
            autostart => 1
        }
    };



Choosing Storage Pool
---------------------

Default Storage Pool
~~~~~~~~~~~~~~~~~~~~

When creating virtual machines, Ravada chooses the storage pool with more free space
available. If you want to force another, change the settings updating the table *vms*
in the database like this.

First check the id field of the Virtual Manager in the table *vms*, then
set a *default_storage* pool this way:

.. prompt:: bash $,(env)...$ auto

    mysql -u rvd_user -p ravada
    mysql> select * from vms;
    +----+---------------+-----------------+
    | id | name          | default_storage |
    +----+---------------+-----------------+
    |  1 | KVM_localhost |                 |
    +----+---------------+-----------------+
    mysql> UPDATE vms set default_storage='pool2' where id=1;

Then restart rvd_back running *systemctl restart rvd_back*.

Specific Storage Pools
~~~~~~~~~~~~~~~~~~~~~~

Specific storages for bases and clones can be defined. This way you can
use small and fast disk drives for bases and big but slower disks for clones.

Add and define the storage pools as described in the
`add kvm storage pool <add_kvm_storage_pool.html>`__ manual. Then change the
values in the database directly.

First check the id field of the Virtual Manager in the table *vms*, then
set a *base_storage* or *clone_storage* pools this way:

.. prompt:: bash $,(env)...$ auto
    root@ravada:~# virsh pool-list
     Name                 State      Autostart
    -------------------------------------------
     pool_ssd              active     yes
     pool_sata             active     yes

.. prompt:: bash $,(env)...$ auto

    mysql -u rvd_user -p ravada
    mysql> select * from vms;
    +----+---------------+-----------------+--------------+---------------+
    | id | name          | default_storage | base_Storage | clone_storage |
    +----+---------------+-----------------+--------------+---------------+
    |  1 | KVM_localhost |                 |              |               |
    +----+---------------+-----------------+--------------+---------------+
    mysql> UPDATE vms set base_storage='pool_ssd' where id=1;
    mysql> UPDATE vms set clone_storage='pool_sata' where id=1;


Chek free memory ( from v0.3 )
------------------------------

Before start the domain, free memory of the Virtual Manager can be checked.
This feature is only available in the development release.

First check the id field of the Virtual Manager in the table *vms*, then
set the minimun of free available memory. In this example we require a
minimun of 2 GB free:

.. prompt:: bash $,(env)...$ auto

    mysql -u rvd_user -p ravada
    mysql> select * from vms;
    mysql> update vms set min_free_memory=2000000 where id=*id*;
