Install Ravada - Ubuntu Xenial
==============================

It is advisable to install Ravada in one of the supported
platforms: Ubuntu Bionic ( 18.04 ) or Fedora.
But if you want to install
in another distribution it can be done.

Packages
--------

Install those packages:

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


These packages are required to build some dependencies from source:

.. prompt:: bash $

    sudo apt-get install gcc gcc-4.8 make libssh2-1-dev libnet-ssh2-perl libssh2-1 libdate-calc-perl zlib1g-dev libpcre3-dev zlib1g-dev libpcre3-dev

Perl Modules
------------

Some Perl modules must be compiled from source:

.. prompt:: bash $

    sudo perl -MCPAN -we 'install "Net::SSH2"'

Database and configuration
--------------------------

From now on you can follow the instructions for Ubuntu 18.04. Skip to
the MySQL installation step.

`Install Ravada in Ubuntu 18.04 <https://ravada.readthedocs.io/en/latest/docs/INSTALL.html>`__ .
