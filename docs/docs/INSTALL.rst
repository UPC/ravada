Install Ravada
==============

Requirements
------------

OS
--

Ravada works in any Linux distribution but we only support the package for `Ubuntu <https://www.ubuntu.com/download/>`_ server
and `Fedora <https://getfedora.org/es/>`_ server.

Follow this `guide <http://disbauxes.upc.es/code/installing-and-using-ravadavdi-on-debian-jessie/>`_ if you prefer Debian Jessie.

Hardware
--------

It depends on the number and type of virtual machines. For common scenarios are server memory, storage and network bandwidth the most critical requirements.

Memory
~~~~~~

RAM is the main issue. Multiply the number of concurrent workstations by
the amount of memory each one requires and that is the total RAM the server
must have.

Disks
~~~~~

The faster the disks, the better. Ravada uses incremental files for the
disks images, so clones won't require many space.

Install Ravada
--------------

Follow `this guide <http://ravada.readthedocs.io/en/latest/docs/update.html>`_
if you are only upgrading Ravada from a previous version already installed.

Ubuntu
------

.. note:: Ubuntu 16.04 (xenial) rename the VM doesn't work. This functionality is included in more updated libraries that it does not include this distro. For example 17.10 (artful) or laters. Remember that this month (April 2018) will be available the 18.04 LTS (bionic).

We provide *deb* Ubuntu packages. Download it from the `UPC ETSETB
repository <http://infoteleco.upc.edu/img/debian/>`__.

*libmojolicious-plugin-renderfile-perl* package is available only in recent Ubuntus. Try  this first:

::

    $ sudo apt-get install libmojolicious-plugin-renderfile-perl

.. warning:: **Only if it fails** download our own package:
    
    ::

        $ wget http://infoteleco.upc.edu/img/debian/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb
        $ sudo dpkg -i libmojolicious-plugin-renderfile-perl_0.10-1_all.deb

Then install the ravada package, it will show some errors, it is ok, keep reading.

::

    $ wget http://infoteleco.upc.edu/img/debian/ravada_0.2.14_all.deb
    $ sudo dpkg -i ravada_0.2.14_all.deb

The last command will show a warning about missing dependencies. Install
them running:

::

    $ sudo apt-get update
    $ sudo apt-get -f install

Mysql Database
--------------

MySQL server
~~~~~~~~~~~~
.. Warning::  MySql required minimum version 5.6

It is required a MySQL server, it can be installed in another host or in
the same one as the ravada package.

::

    $ sudo apt-get install mysql-server

MySQL database and user
~~~~~~~~~~~~~~~~~~~~~~~

It is required a database for internal use. In this examples we call it *ravada*.
We also need an user and a password to connect to the database. It is customary to call it *rvd_user*.
In this stage the system wants you to set a password for the sql connection.

.. Warning:: If installing ravada on Ubuntu 18 or newer you should enter your user's password instead of mysql's root password.

Create the database:

::

    $ sudo mysqladmin -u root -p create ravada

Grant all permissions on this database to the *rvd_user*:

::

    $ sudo mysql -u root -p ravada -e "grant all on ravada.* to rvd_user@'localhost' identified by 'changeme'"

Config file
~~~~~~~~~~~

Create a config file at /etc/ravada.conf with the username and password
you just declared at the previous step. Please note that you need to
edit the user and password via an editor. Here, we present Vi as an
example.

::

    $ sudo vi /etc/ravada.conf
    db:
      user: rvd_user
      password: changeme

Ravada web user
---------------

Add a new user for the ravada web. Use rvd\_back to create it. It will perform some initialization duties in the database the very first time this script is executed.

When asked if this user is admin answer *yes*.

::

    $ sudo /usr/sbin/rvd_back --add-user user.name

Firewall (Optional)
-------------------

The server must be able to send *DHCP* packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains. Look what is the address range and add it to your *iptables* configuration.

First we try to find out what is the new internal network:

::

    $  sudo route -n
    ...
    192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0

So it is 192.168.122.0 , netmask 24. Add it to your iptables configuration:

::

    sudo iptables -A INPUT -s 192.168.122.0/24 -p udp --dport 67:68 --sport 67:68 -j ACCEPT

To confirm that the configuration was updated, check it with:

::

    sudo iptables -S

Client
------

The client must have a spice viewer such as virt-viewer. There is a
package for linux and it can also be downloaded for windows.

Run
---

The Ravada server is now installed, learn
`how to run and use it <http://ravada.readthedocs.io/en/latest/docs/production.html>`__.

Help
----

Struggling with the installation procedure ? We tried to make it easy but
let us know if you need `assistance <http://ravada.upc.edu/#help>`__.

There is also a `troubleshooting <troubleshooting.html>`__ page with common problems that
admins may face.
