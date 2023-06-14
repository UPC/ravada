Install Ravada on Rocky Linux 9 or RHEL9
========================

Add Pre-Requisite Software
------------
.. prompt:: bash $
    sudo dnf install mariadb-server
.. prompt:: bash $

Securing mariadb-server
To strengthen the security of mariadb-server we need to run a script, but before we do, we need to enable and start mariadb:
~~~~~~
.. prompt:: bash $
    systemctl enable mariadb
.. prompt:: bash $

And then:
.. prompt:: bash $
    systemctl start mariadb
.. prompt:: bash $

Next, run this command:
.. prompt:: bash $
    mysql_secure_installation
.. prompt:: bash $

Requirements
------------

.. prompt:: bash $
    sudo dnf install qemu-kvm libvirt virt-manager virt-install iptables-services httpd mysql-server perl

.. prompt:: bash $


OS
--

Ravada works in any Linux distribution.

.. note:: RPM packages are kindly built by a third party. Please check the release available. If you want the latest verstion it is adviced to install it on top of Ubuntu or Debian.

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

Fedora and EPEL7
----------------

You can install ravada using the 'dnf' package manager.

.. prompt:: bash $

    sudo dnf install ravada
    
Add link to kvm-spice
~~~~~~~~~~~~~~~~~~~~~
This may change in the future but actually a link to kvm-spice is required. Create it this way:

.. prompt:: bash $

    ln -s /usr/bin/qemu-kvm /usr/bin/kvm-spice

MySQL server
~~~~~~~~~~~~
It is required a MySQL server, in Fedora we use MariaDB server. It can be
installed in another host or in the same as the ravada package.

.. prompt:: bash $

    sudo dnf install mariadb mariadb-server

And don't forget to enable and start the server process:

.. prompt:: bash $

    sudo systemctl enable --now mariadb.service
    sudo systemctl start mariadb.service

MySQL database and user
~~~~~~~~~~~~~~~~~~~~~~~

It is required a database for internal use. In this examples we call it *ravada*.
We also need an user and a password to connect to the database. It is customary to call it *rvd_user*.
In this stage the system wants you to set a password for the sql connection.

.. Warning:: If installing ravada on Ubuntu 18 or newer you should enter your user's password instead of mysql's root password.

Create the database:

.. prompt:: bash $

    sudo mysqladmin -u root -p create ravada

Grant all permissions on this database to the *rvd_user*:

.. prompt:: bash $

    sudo mysql -u root -p ravada -e "grant all on ravada.* to rvd_user@'localhost' identified by 'Pword12345*'"
    
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

Firewall (Optional)
-------------------

The server must be able to send *DHCP* packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains. Look what is the address range and add it to your *iptables* configuration.

First we try to find out what is the new internal network:

.. prompt:: bash $,(env)...$ auto

    sudo route -n
    ...
    192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0

So it is 192.168.122.0 , netmask 24. Add it to your iptables configuration:

.. prompt:: bash $

    sudo iptables -A INPUT -s 192.168.122.0/24 -p udp --dport 67:68 --sport 67:68 -j ACCEPT

To confirm that the configuration was updated, check it with:

.. prompt:: bash $

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
