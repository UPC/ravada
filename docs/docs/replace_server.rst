Replace Server
==============

You have been running Ravada in a server and you just bought a new one.
You want to move all the virtual machines and data to the new server and
retire the old one.

Warning
-------

This document is a work in progress. You should check migration of
the MySQL database and KVM virtual machines.

Very basic procedures are outlined here, please do backups, report
problems to us and ask if some parts are not clear. Also contributions
welcome !

Packages
--------

Install in the new server a Ravada server but do not create the web
admin user. Also you should grant database access using the same
user and password used in /etc/ravada.conf

Data Base
---------

If the data base is locally installed in the server you need to migrate it
to the new one. One way could be to dump all the database information and
load it in the new server. Use mysqldump for that.

First grant access in the new server with the same user and password you
have in /etc/rvd.conf.

.. prompt:: bash $

    mysqldump -u rvd_user -p ravada > ravada.sql
    scp ravada.sql new_server:
    ssh new_server
    mysql -u rvd_user -p ravada < ravada.sql


KVM
----

Storage Pools
~~~~~~~~~~~~~

Virtual machine information is kept in the storage pools. It is easier if
you have the same storage pools in the new and old server, both pointing
to the same directory.

Check it using "sudo virsh pool-list"

Stop all the virtual machines, make sure no one is running typing sudo virsh list

Copy all the data to the new server:

.. prompt:: bash #

    cd /var/lib/libvirt
    rsync -av images new_server:/var/lib/libvirt

Virtual Machine definitions
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Virtual machines definitions are stored in XML files.

.. prompt:: bash #

    cd /etc/libvirt
    rsync -av qemu new_server:/root/

Now all the virtual machines definitions are copied in the new server. You have to
define them. To create a single virtual machine

.. prompt:: bash #

    ssh new_server
    cd /root/qemu/
    virsh define virtual_machine.xml

This is the procedure to re-define all the virtual machines in the new server at once:

.. prompt:: bash #

    ssh new_server
    cd /root/qemu/
    for i in `ls \*xml`; do virsh define $i ; done

Ravada
------

Copy Ravada configuration files from the old server : /etc/ravada.conf and /etc/rvd_front.conf

Start the services and try to run some virtual machines.
