# Requirements

## OS

Ravada has been tested only on Ubuntu Xenial. It should also work in recent RedHat based
systems. Debian jessie has been tried but kvm spice wasn't available there, so it won't
work.

## Hardware

It depends on the number and the type of the virtual machines. For most places 

### Memory
RAM is
the main issue. Multiply the number of concurrent workstations by the amount of memory
each one requires and that is the RAM that must have the server.

### Disks
The faster the disks, the better. Ravada uses incremental files for the disks images, so
clones won't require many space.


# Install Ravada

## Ubuntu

We provide _deb_ Ubuntu packages. Download it from *TODO*.

## Development release

You can get the development release cloning the sources. Don't do this if you install
a packaged release.

    $ git clone https://github.com/frankiejol/ravada.git

### Ubuntu required packages

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

# Mysql Database

## MySQL user
Create a database named "ravada". in this stage the system wants you to identify a password for your sql.

    $ mysqladmin -u root -p create ravada

Grant all permissions to your user:

    $ mysql -u root -p
    mysql> grant all on ravada.* to rvd_user@'localhost' identified by 'figure a password';
    exit

## Config file

Create a config file at /etc/ravada.conf with:

    db:
      user: rvd_user
      password: *****

Protect the config file from others:

    $ sudo chmod o-rx /etc/ravada.conf

## Create tables

Review and run the sql files from the sql dir. If you are using a packaged
release you can find these files at _/usr/share/doc/ravada/doc_. For development,
the files are at the _sql_ directory inside the sources.

    $ cd /usr/share/doc/ravada/sql/mysql
    $ cat *.sql | mysql -p -u rvd_user ravada
    $ cd ../data
    $ cat *.sql | mysql -p -u rvd_user ravada


# Ravada web user

Add a new user for the ravada web. Use rvd\_back to create it.

    $ cd ravada
    $ sudo ./bin/rvd_back.pl --add-user user.name


# Firewall

The server must be able to send _DHCP_ packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains. Look what is the address range
and add it to your _iptables_ configuration.

First we try to find out what is the new internal network:

    $  sudo route -n
    ...
    192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0

So it is 192.168.122.0 , netmask 24. Add it to your iptables configuration:

    -A INPUT -s 192.168.122.0/24 -p udp --dport 67:68 --sport 67:68 -j ACCEPT

# Client

The client must have a spice viewer such as virt-viewer. There is a package for
linux and it can also be downloaded for windows.

# Next

Read [docs/production.md](https://github.com/frankiejol/ravada/blob/master/docs/production.md) or [devel-docs/](https://github.com/frankiejol/ravada/blob/master/devel-docs/) to learn how to start it.
