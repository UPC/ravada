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

.. note:: We only provide support for Ubuntu 18.04 LTS (bionic).

We provide *deb* Ubuntu packages. Download it from the `UPC ETSETB
repository <http://infoteleco.upc.edu/img/debian/>`__.

Install *libmojolicious-plugin-renderfile-perl* package:

::

     sudo apt-get install libmojolicious-plugin-renderfile-perl

Then install the ravada package, it will show some errors, it is ok, keep reading.

::

     wget http://infoteleco.upc.edu/img/debian/ravada_0.2.17_all.deb
     sudo dpkg -i ravada_0.2.17_all.deb

The last command will show a warning about missing dependencies. Install
them running:

::

     sudo apt-get update
     sudo apt-get -f install

Mysql Database
--------------

MySQL server
~~~~~~~~~~~~
.. Warning::  MySql required minimum version 5.6

It is required a MySQL server, it can be installed in another host or in
the same one as the ravada package.

::

     sudo apt-get install mysql-server
    
After completion of mysql installation, run command:

::

     sudo mysql_secure_installation


MySQL database and user
~~~~~~~~~~~~~~~~~~~~~~~

It is required a database for internal use. In this examples we call it *ravada*.
We also need an user and a password to connect to the database. It is customary to call it *rvd_user*.
In this stage the system wants you to set a password for the sql connection.

.. Warning:: When installing MySQL you wont be asked for a password, you can set a password for the root user in MySQL via *mysql_secure_installation* or type your user's password when it ask's you for a password.

Create the database:

::

     sudo mysqladmin -u root -p create ravada

Grant all permissions on this database to the *rvd_user*:

::

     sudo mysql -u root -p ravada -e "grant all on ravada.* to rvd_user@'localhost' identified by 'changeme'"

Config file
~~~~~~~~~~~

Create a config file at /etc/ravada.conf with the username and password
you just declared at the previous step. Please note that you need to
edit the user and password via an editor. Here, we present Vi as an
example.

::

     sudo vi /etc/ravada.conf
    db:
      user: rvd_user
      password: changeme

Ravada web user
---------------

Add a new user for the ravada web. Use rvd\_back to create it. It will perform some initialization duties in the database the very first time this script is executed.

When asked if this user is admin answer *yes*.

::

     sudo /usr/sbin/rvd_back --add-user user.name

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
