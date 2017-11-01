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

Check this  `file <https://github.com/UPC/ravada/blob/master/debian/control>`_ at the line *depends* for a list of required packages. You must install it running:

::

    $ sudo apt-get install package1 package2 ... packagen
    
In addition you need one package that it still may not be in Ubuntu repository, download from our own server at the UPC and install it this way:

::

    $ wget http://infoteleco.upc.edu/img/debian/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb
    $ sudo dpkg -i libmojolicious-plugin-renderfile-perl_0.10-1_all.deb


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


When developping Ravada, your username must be able to read the
configuration file. Protect the config file from others and make it
yours.

::

    $ sudo chmod o-rx /etc/ravada.conf
    $ sudo chown your_username /etc/ravada.conf
    
Ravada web user
---------------

Add a new user for the ravada web. Use ``rvd_back`` to create it.

::

    $ cd ravada
    $ sudo ./bin/rvd_back.pl --add-user user.name


Firewall(Optional)
------------------

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


Run each one of these commands in a separate terminal

:: 

    $ morbo ./rvd_front.pl
    $ sudo ./bin/rvd_back.pl

Now you must be able to reach ravada at the location http://your.ip:3000/
