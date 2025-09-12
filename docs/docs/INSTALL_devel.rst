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

    sudo apt install cpu-checker
    sudo kvm-ok

.. warning:: Do not consider `VirtualBox <https://www.virtualbox.org/>`_ in this situation, because it doesn't pass VT-X / AMD-V to the guest operating system.



Ubuntu required packages
------------------------

Check this  `file <https://github.com/UPC/ravada/blob/master/debian>`_ at the line *depends* for a list of required packages. You must install it running:

.. note:: The libvirt-bin package was dropped since Ubuntu 18.10. The package was split into two parts: **libvirt-daemon-system** and **libvirt-clients**.

.. prompt:: bash $

    sudo apt-get install perl libmojolicious-perl mysql-common libauthen-passphrase-perl \
    libdbd-mysql-perl libdbi-perl libdbix-connector-perl libipc-run3-perl libnet-ldap-perl \
    libproc-pid-file-perl libsys-virt-perl libxml-libxml-perl libconfig-yaml-perl \
    libmoose-perl libjson-xs-perl qemu-utils perlmagick libmoosex-types-netaddr-ip-perl \
    libsys-statistics-linux-perl libio-interface-perl libiptables-chainmgr-perl libnet-dns-perl \
    wget liblocale-maketext-lexicon-perl libmojolicious-plugin-i18n-perl libdbd-sqlite3-perl \
    debconf adduser libdigest-sha-perl qemu-kvm libnet-ssh2-perl libfile-rsync-perl \
    libdate-calc-perl libdatetime-perl libdatetime-format-dateparse-perl libnet-openssh-perl \
    libpbkdf2-tiny-perl libdatetime-perl


.. include:: INSTALL_mysql.rst

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
    sudo PERL5LIB=./lib ./script/rvd_back --add-user admin


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

Ravada has two daemons that must run on the server:

- ``rvd_back`` : must run as root and manages the virtual machines
- ``rvd_front`` : is the web frontend that sends requests to the backend


Run each one of these commands in a separate terminal

Run the backend in a terminal:

.. prompt:: bash $

    sudo PERL5LIB=./lib ./script/rvd_back --debug
    Starting rvd_back v1.2.0

The backend must be stopped and started again when you change a library file.
Stop it pressing CTRL-C

Run the frontend in another terminal:

.. prompt:: bash $

    PERL5LIB=./lib MOJO_REVERSE_PROXY=1 morbo -m development -v ./script/rvd_front
    Server available at http://127.0.0.1:3000

Now you must be able to reach ravada at the location http://your.ip:3000/
or http://127.0.0.1:3000 if you run it in your own workstation.

The frontend will restart itself when it detects a change in the
libraries. There is no need to stop it and start it again.


Start/Shutdown scripts
----------------------

If you wish to create a script to automatize the start and shutdown of the ravada server, you can use these two bash scripts:

.. literalinclude:: start_ravada.sh
   :linenos:

.. literalinclude:: shutdown_ravada.sh
   :linenos:

