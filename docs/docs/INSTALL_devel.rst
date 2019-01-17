Development release
===================

.. note ::
    If you are not sure, you probably want to install the stable release. 
    Follow this `guide <http://ravada.readthedocs.io/en/latest/docs/INSTALL.html>`__.

You can get the development release cloning the sources. 

.. Warning:: Don't do this if you install a packaged release.

.. prompt:: bash $

    git clone https://github.com/UPC/ravada.git
    
Possible development scenarios where to deploy
----------------------------------------------

Obviously if you can deploy on a physical machine will be better but it is not always possible. 
In that case you can test on a nested KVM, that is, a KVM inside another KVM.

.. note:: KVM requires `VT-X / AMD-V <http://www.linux-kvm.org/page/FAQ#What_do_I_need_to_use_KVM.3F>`_.

.. prompt:: bash $

    sudo kvm-ok

.. warning:: Do not consider `VirtualBox <https://www.virtualbox.org/>`_ in this situation, because it doesn't pass VT-X / AMD-V to the guest operating system.



Ubuntu required packages
------------------------

Check this  `file <https://github.com/UPC/ravada/blob/master/debian/control>`_ at the line *depends* for a list of required packages. You must install it running:

.. prompt:: bash $

    sudo apt-get install perl libmojolicious-perl mysql-common libauthen-passphrase-perl \
    libdbd-mysql-perl libdbi-perl libdbix-connector-perl libipc-run3-perl libnet-ldap-perl \
    libproc-pid-file-perl libvirt-bin libsys-virt-perl libxml-libxml-perl libconfig-yaml-perl \
    libmoose-perl libjson-xs-perl qemu-utils perlmagick libmoosex-types-netaddr-ip-perl \
    libsys-statistics-linux-perl libio-interface-perl libiptables-chainmgr-perl libnet-dns-perl \
    wget liblocale-maketext-lexicon-perl libmojolicious-plugin-i18n-perl libdbd-sqlite3-perl \
    debconf adduser libdigest-sha-perl qemu-kvm libnet-ssh2-perl libfile-rsync-perl \
    libdate-calc-perl libparallel-forkmanager-perl
    
In addition you need one package that it still may not be in Ubuntu repository, download from our own server at the `UPC ETSETB
repository <http://infoteleco.upc.edu/img/debian/>`__ and install it this way:

.. prompt:: bash $

    wget http://infoteleco.upc.edu/img/debian/libmojolicious-plugin-renderfile-perl_0.10-1_all.deb
    sudo dpkg -i libmojolicious-plugin-renderfile-perl_0.10-1_all.deb


Mysql Database
--------------

MySQL server is required to run ravada. You can use one from another server you already have or you can install it in the
same host as Ravada.

MySQL user
~~~~~~~~~~

Create a database named "ravada". in this stage the system wants you to identify a password for your sql.

.. prompt:: bash $

    mysqladmin -u root -p create ravada

Grant all permissions to your user:

.. prompt:: bash $,(env)... auto

    mysql -u root -p
    mysql> grant all on ravada.* to rvd_user@'localhost' identified by 'choose a password';
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

.. prompt:: bash $

    sudo chmod o-rx /etc/ravada.conf
    sudo chown your_username /etc/ravada.conf
    
Ravada web user
---------------

Add a new user for the ravada web. Use ``rvd_back`` to create it.

.. prompt:: bash $

    cd ravada
    sudo ./bin/rvd_back.pl --add-user user.name


Firewall(Optional)
------------------

The server must be able to send DHCP packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains. Look what is the address range and add it to your iptables configuration.

First we try to find out what is the new internal network:

.. prompt:: bash $,(env)... auto

    sudo route -n
    ...
    192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0

So it is 192.168.122.0 , netmask 24. Add it to your iptables configuration:

::

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

.. prompt:: bash $ 

    morbo ./rvd_front.pl
    sudo ./bin/rvd_back.pl

Now you must be able to reach ravada at the location http://your.ip:3000/

If you wish to create a script to automatize the start and shutdown of the ravada server, you can use these two bash scripts:

start_ravada.sh:

::

    #!/bin/bash
    #script to initialize ravada server
    
    display_usage()
    {
	echo "./start_ravada 1 (messages not prompting to terminal)
	echo "./start_ravada 0 (prompts enables to this terminal)
    }

    if [ $# -eq 0 ]
    then
	display_usage
    	exit 1
    else
	SHOW_MESSAGES=$1
	if [ $SHOW_MESSAGES -eq 1 ]
	then
	    morbo ./rvd_front.pl > /dev/null 2>&1 &
	    sudo ./bin/rvd_back.pl > /dev/null 2>&1 &
	else
	    morbo ./rvd_front.pl &
	    sudo ./bin/rvd_back.pl &
	fi
	echo "Server initialized succesfully."
    fi

shutdown_ravada.sh:

::

    #!/bin/bash
    #script to shutdown the ravada server

    sudo kill -15 $(pidof './rvd_front.pl')
    sudo kill -15 $(pidof -x 'rvd_back.pl')
    echo "Server closed succesfully"
    
