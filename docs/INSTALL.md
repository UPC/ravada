#Install Ravada

Clone the sources:

    $ git clone https://github.com/frankiejol/ravada.git

#Packages

##Debian

- mysql-server
- libdbd-mysql-perl
- libdbi-perl
- libdbix-connector-perl
- libipc-run3-perl
- libnet-ldap-perl
- libproc-pid-file-perl
- libvirt-bin
- libsys-virt-perl
- libxml-libxml-perl

##Old debian

In old debians and ubuntus Mojolicious is too outdated. Remove libmojolicious-perl and install the cpan release:

    $ sudo apt-get purge libmojolicious-perl
    $ sudo apt-get install cpanminus
    $ sudo cpanm Mojolicious

#Mysql Database

Create a database named "ravada". 

Grant all permissions to your user:

    $ mysql -u root -p
    mysql> grant all on ravada.* to frankie@'localhost' identified by 'figure a password';

Review and run the sql files from the sql dir.

    $ mysqladmin create ravada
    $ cd sql
    $ cat *.sql | mysql -p ravada

#KVM backend

Install KVM and virt-manager. Create new virtual machines (called domains) there.
See docs/operation.md

#Next

Read docs/operation.md
