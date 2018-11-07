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

When creating virtual machines, Ravada chooses the storage pool with more free space
available. If you want to force another, change the settings updating the table *vms*
in the database like this.

First check the id field of the Virtual Manager in the table *vms*, then
set a default *storage_pool* like this:

::

    $ mysql -u rvd_user -p ravada
    mysql> select * from vms;
    mysql> UPDATE vms set storage_pool='pool2' where id=*id*;

Then restart rvd_back running *systemctl restart rvd_back*.

Chek free memory ( from v0.3 )
------------------------------

Before start the domain, free memory of the Virtual Manager can be checked.
This feature is only available in the development release.

First check the id field of the Virtual Manager in the table *vms*, then
set the minimun of free available memory. In this example we require a
minimun of 2 GB free:

::

    $ mysql -u rvd_user -p ravada
    mysql> select * from vms;
    mysql> update vms set min_free_memory=2000000 where id=*id*;


