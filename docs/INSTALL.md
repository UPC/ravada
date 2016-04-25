#Packages

##Debian

- mysql-server
- libdbd-mysql-perl
- libdbi-perl
- libdbix-connector-perl
- libnet-ldap-perl
- libproc-pid-file-perl
- libvirt-bin
- libsys-virt-perl
- libxml-libxml-perl
- cpanminus

    $ sudo cpanm Mojolicious

#Mysql Database

Create a database named "ravada". Review and run the sql files from the sql dir.

    $ mysqladmin create ravada
    $ cd sql
    $ cat *.sql | mysql ravada

#KVM backend

Install KVM and virt-manager. Create new virtual machines (called domains) there.
