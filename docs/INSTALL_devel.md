# Development release

If you are not sure, you probably want to install the stable release.
Follow this [guide](https://github.com/UPC/ravada/blob/master/docs/INSTALL.md).

You can get the development release cloning the sources. Don't do this if you install
a packaged release.

    $ git clone https://github.com/frankiejol/ravada.git

## Ubuntu required packages

These are the Ubuntu required packages. It is is only necessary for the
development release.

    $ sudo apt-get install libmojolicious-perl  mysql-server libauthen-passphrase-perl  libdbd-mysql-perl libdbi-perl libdbix-connector-perl libipc-run3-perl libnet-ldap-perl libproc-pid-file-perl libvirt-bin libsys-virt-perl libxml-libxml-perl libconfig-yaml-perl libmoose-perl libjson-xs-perl qemu-utils perlmagick libmoosex-types-netaddr-ip-perl libsys-statistics-linux-perl libio-interface-perl libiptables-chainmgr-perl libnet-dns-perl wget liblocale-maketext-lexicon-perl libmojolicious-plugin-i18n-perl libdbd-sqlite3-perl

- libmojolicious-perl
- mysql-server
- libauthen-passphrase-perl
- libdbd-mysql-perl
- libdbi-perl
- libdbix-connector-perl
- libipc-run3-perl
- libnet-ldap-perl
- libproc-pid-file-perl
- libvirt-bin
- libsys-virt-perl
- libxml-libxml-perl
- libconfig-yaml-perl
- libmoose-perl
- libjson-xs-perl
- qemu-utils
- perlmagick
- libmoosex-types-netaddr-ip-perl
- libsys-statistics-linux-perl
- libio-interface-perl
- libiptables-chainmgr-perl
- libnet-dns-perl
- wget
- liblocale-maketext-lexicon-perl
- libmojolicious-plugin-i18n-perl


# Config file
When developping Ravada, your username must be able to read the configuration file. Protect the config file from others and make it yours.

    $ sudo chmod o-rx /etc/ravada.conf
    $ sudo chown your_username /etc/ravada.conf

Read [devel-docs/](https://github.com/UPC/ravada/blob/master/devel-docs/) to learn how to start it.

