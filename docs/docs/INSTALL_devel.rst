Development release
===================

.. note ::
    If you are not sure, you probably want to install the stable release. 
    Follow this `guide <http://ravada.readthedocs.io/en/latest/docs/INSTALL.html>`__.

You can get the development release cloning the sources. 

.. Warning:: Don't do this if you install a packaged release.

::

    $ git clone https://github.com/UPC/ravada.git
    
Possible development scenarios where to deploy
----------------------------------------------

Obviously if you can deploy on a physical machine will be better but it is not always possible. 
In that case you can test on a nested KVM, that is, a KVM inside another KVM.

.. note:: KVM requires `VT-X / AMD-V <http://www.linux-kvm.org/page/FAQ#What_do_I_need_to_use_KVM.3F>`_.

.. warning:: Do not consider `VirtualBox <https://www.virtualbox.org/>`_ in this situation, because it doesn't pass VT-X / AMD-V to the guest operating system.



Ubuntu required packages
------------------------

These are the Ubuntu required packages. It is is only necessary for the
development release.

::

    $ sudo apt-get install libmojolicious-perl  mysql-server libauthen-passphrase-perl  libdbd-mysql-perl libdbi-perl libdbix-connector-perl libipc-run3-perl libnet-ldap-perl libproc-pid-file-perl libvirt-bin libsys-virt-perl libxml-libxml-perl libconfig-yaml-perl libmoose-perl libjson-xs-perl qemu-utils perlmagick libmoosex-types-netaddr-ip-perl libsys-statistics-linux-perl libio-interface-perl libiptables-chainmgr-perl libnet-dns-perl wget liblocale-maketext-lexicon-perl libmojolicious-plugin-i18n-perl libdbd-sqlite3-perl

-  libmojolicious-perl
-  mysql-server
-  libauthen-passphrase-perl
-  libdbd-mysql-perl
-  libdbi-perl
-  libdbix-connector-perl
-  libipc-run3-perl
-  libnet-ldap-perl
-  libproc-pid-file-perl
-  libvirt-bin
-  libsys-virt-perl
-  libxml-libxml-perl
-  libconfig-yaml-perl
-  libmoose-perl
-  libjson-xs-perl
-  qemu-utils
-  perlmagick
-  libmoosex-types-netaddr-ip-perl
-  libsys-statistics-linux-perl
-  libio-interface-perl
-  libiptables-chainmgr-perl
-  libnet-dns-perl
-  wget
-  liblocale-maketext-lexicon-perl
-  libmojolicious-plugin-i18n-perl

Config file
-----------

When developping Ravada, your username must be able to read the
configuration file. Protect the config file from others and make it
yours.

::

    $ sudo chmod o-rx /etc/ravada.conf
    $ sudo chown your_username /etc/ravada.conf

Mysql Database
--------------

MySQL user
~~~~~~~~~~

Create a database named "ravada". in this stage the system wants you to identify a password for your sql.

::

    $ mysqladmin -u root -p create ravada

Grant all permissions to your user:

:: 

    $ mysql -u root -p
    mysql> grant all on ravada.* to rvd_user@'localhost' identified by 'figure a password';
    exit

Config file
-----------

Create a config file at ``/etc/ravada.conf`` with the ``username`` and ``password`` you just declared at the previous step.

::

    db:
      user: rvd_user
      password: *****

Ravada web user
---------------

Add a new user for the ravada web. Use ``rvd_back`` to create it.

::

    $ cd ravada
    $ sudo /usr/sbin/rvd_back --add-user user.name


Firewall
--------

The server must be able to send DHCP packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains. Look what is the address range and add it to your iptables configuration.

First we try to find out what is the new internal network:

::

    $  sudo route -n
    ...
    192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0

So it is 192.168.122.0 , netmask 24. Add it to your iptables configuration:

    -A INPUT -s 192.168.122.0/24 -p udp --dport 67:68 --sport 67:68 -j ACCEPT

Client
------

The client must have a spice viewer such as virt-viewer. There is a package for linux and it can also be downloaded for windows.

Daemons
-------

Ravada has two daemons that must run on the production server:

- ``rvd_back`` : must run as root and manages the virtual machines
- ``rvd_front`` : is the web frontend that sends requests to the backend

Application directory
---------------------

The ravada application should be installed in ``/var/www/ravada``

Ravada system user
------------------

The frontend daemon must run as a non-privileged user.

::

    # useradd ravada

Allow it to write to some diretories inside ``/var/www/ravada/``

::

    # mkdir /var/www/ravada/log
    # chown ravada /var/www/ravada/log
    # chgrp ravada /etc/ravada.conf
    # chmod g+r /etc/ravada.conf
    # mkdir -p /var/www/img/screenshots/
    # chown ravada /var/www/img/screenshots

Apache
------

It is advised to run an apache server or similar before the frontend.

::

    # apt-get install apache2
    
Systemd
-------

Configuration for boot start

First you have to copy the service scripts to the systemd directory:

::

    $ cd ravada/etc/systemd/
    $ sudo cp *service /lib/systemd/system/

Edit ``/lib/systemd/system/rvd_front.service`` and change ``User=****`` to the ``ravada`` user just created.


Then enable the services to run at startup

:: 

    $ sudo systemctl enable rvd_back
    $ sudo systemctl enable rvd_front

Start or stop
~~~~~~~~~~~~~

:: 

    $ sudo systemctl stop rvd_back
    $ sudo systemctl stop rvd_front

Other systems
~~~~~~~~~~~~~

For production mode you must run the front end with a high perfomance server like hypnotoad:

::

    $ hypnotoad ./rvd_front.pl

And the backend must run from root

::

    # ./bin/rvd_back.pl &


Firewall
--------

Ravada uses `iptables` to restrict the access to the virtual machines. 
Thes iptables rules grants acess to the admin workstation to all the domains and disables the access to everyone else.
When the users access through the web broker they are allowed to the port of their virtual machines. Ravada uses its own iptables chain called 'ravada' to do so:

::

    -A INPUT -p tcp -m tcp -s ip.of.admin.workstation --dport 5900:7000 -j ACCEPT
    -A INPUT -p tcp -m tcp --dport 5900:7000 -j DROP

Read :ref:`dev-docs` to learn how to start it.
