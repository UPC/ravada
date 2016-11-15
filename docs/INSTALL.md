#Install Ravada

Clone the sources:

    $ git clone https://github.com/frankiejol/ravada.git

#Packages

##Debian

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

##Old debian

In old debians and ubuntus Mojolicious is too outdated. Remove libmojolicious-perl and install the cpan release:

    $ sudo apt-get purge libmojolicious-perl
    $ sudo apt-get install cpanminus
    $ sudo cpanm Mojolicious

#Mysql Database

Create a database named "ravada". 

Grant all permissions to your user:

    $ mysql -u root -p
    mysql> grant all on ravada.* to ravada@'localhost' identified by 'figure a password';
    exit

Review and run the sql files from the sql dir.

    $ mysqladmin -p create -u root ravada
    $ cd ravada/sql/mysql
    $ cat *.sql | mysql -p -u ravada ravada
    $ cd ..
    $ cd data
    $ cat *.sql | mysql -p -u ravada ravada

#Config file

Create a config file at /etc/ravada.conf with:
    
    db:
      user: ravada
      password: *****

#KVM backend

Install KVM 

    $ sudo apt-get install qemu-kvm qemu-utils
    $ sudo virsh pool-define-as default dir - - - - "/var/lib/libvirt/images"

#Ravada user

Add a new user for the ravada web. This command will create a new user (not admin) in the database:

    $ cd ravada
    $ ./bin/rvd_back.pl --add-user user.name

#Screenshots directory

Create a directory to store virtual machines screenshots:

    $ sudo mkdir -p /var/www/img/screenshots/

#Next

Read docs/production.md or devel-docs/development.md to learn how to start it.
