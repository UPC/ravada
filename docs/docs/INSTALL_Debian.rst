Install Ravada in Debian
========================

Upgrade Ravada
--------------

Follow `this guide <http://ravada.readthedocs.io/en/latest/docs/update.html>`_
if you are only upgrading Ravada from a previous version already installed.

Debian
------

This is the guide to install Ravada in Debian Bullseye and Buster. It is reccomended you use Buster for better perfomance.

We provide *deb* packages on the `UPC ETSETB
repository <http://infoteleco.upc.edu/img/debian/>`__.

Install the ravada package. It is called *debian-10* but works fine in *debian-11* also.

- ravada_1.8.1_debian-10_all.deb

When you run dpkg now it may show some errors, it is ok, keep reading.

.. prompt:: bash $

     wget http://infoteleco.upc.edu/img/debian/ravada_1.8.1_debian-10_all.deb
     sudo apt update
     sudo apt install ./ravada_1.8.1_debian-10_all.deb

Debian KVM
~~~~~~~~~~

You must enable spice KVM manually:

.. prompt:: bash $

   sudo ln -s /usr/bin/kvm /usr/bin/kvm-spice

Mysql/MariaDB Database
----------------------

MariaDB server
~~~~~~~~~~~~~~

It is required a MySQL or MariaDB server, it can be installed in another host or in
the same one as the ravada package.

.. prompt:: bash $

     sudo apt-get install mariadb-server


MariaDB database and user
~~~~~~~~~~~~~~~~~~~~~~~~~

It is required a database for internal use. In this examples we call it *ravada*.
We also need an user and a password to connect to the database. It is customary to call it *rvd_user*.
In this stage the system wants you to set a password for the sql connection.

.. prompt:: bash $

     sudo mysqladmin -u root -p create ravada

Grant all permissions on this database to the *rvd_user*:

.. prompt:: bash $

     sudo mysql -u root -p ravada -e "create user 'rvd_user'@'localhost' identified by 'Pword12345*'"
     sudo mysql -u root -p ravada -e "grant all on ravada.* to rvd_user@'localhost'"

The password chosen must fulfill the following characteristics:

    - At least 8 characters.
    - At least 1 number.
    - At least 1 special character.

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
      password: Pword12345*

Ravada web user
---------------

Add a new user for the ravada web. Use rvd\_back to create it. It will perform some initialization duties in the database the very first time this script is executed.

When asked if this user is admin answer *yes*.

.. prompt:: bash $

     sudo /usr/sbin/rvd_back --add-user admin

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
