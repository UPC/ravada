Development release
===================

.. note ::
    If you are not sure, you probably want to install the stable release. 
    Follow this `guide <http://ravada.readthedocs.io/en/latest/docs/INSTALL.html>`__.

You can get the development release cloning the sources. 

.. Warning:: Don't do this if you install a packaged release.

::

    $ git clone https://github.com/frankiejol/ravada.git
    
Possible development scenarios where to deploy
----------------------------------------------

Obviously if you can deploy on a physical machine will be better but it is not always possible. 

In that case you can test on a nested KVM, that is, a KVM inside another KVM.

.. note:: KVM requires VT-X / AMD-V. 

.. warning:: Do not consider VirtualBox because it does not pass VT-X / AMD-V to the guest operating system.



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

Read :ref:`dev-docs` to learn how to start it.
