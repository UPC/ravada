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

We provide _deb_ Ubuntu packages. Download it from the [UPC ETSETB repository](http://infoteleco.upc.edu/img/debian/). Downlad them and install them:

    $ sudo dpkg -i libmojolicious-plugin-renderfile-perl_0.10-1_all.deb
    $ sudo dpkg -i ravada_0.1.2_all.deb

The last command will show a warning about missing dependencies. Install them
running:

    $ sudo apt-get -f install

## Development Release

Read [docs/INSTALL\_devel.md](https://github.com/UPC/ravada/blob/master/docs/INSTALL_devel.md)  if you want to develop Ravada or install a bleeding
edge, non-packaged, release.

# Mysql Database

## MySQL user
Create a database named "ravada". in this stage the system wants you to identify a password for your sql.

    $ mysqladmin -u root -p create ravada

Grant all permissions to your user:

    $ mysql -u root -p
    mysql> grant all on ravada.* to rvd_user@'localhost' identified by 'CHOOSE A PASSWORD';
    exit

## Config file

Create a config file at /etc/ravada.conf with the username and password you just declared
at the previous step.

    db:
      user: rvd_user
      password: THE PASSWORD CHOSEN BEFORE

## Create tables

Review and run the sql files from the sql dir. If you are using a packaged
release you can find these files at _/usr/share/doc/ravada/doc_. For development,
the files are at the _sql_ directory inside the sources.

    $ cd /usr/share/doc/ravada/sql/mysql
    $ cat *.sql | mysql -p -u root ravada
    $ cd ../data
    $ cat *.sql | mysql -p -u root ravada


# Ravada web user

Add a new user for the ravada web. Use rvd\_back to create it.

    $ sudo /usr/sbin/rvd_back --add-user user.name


# Firewall

The server must be able to send _DHCP_ packets to its own virtual interface.

KVM should be using a virtual interface for the NAT domnains. Look what is the address range
and add it to your _iptables_ configuration.

First we try to find out what is the new internal network:

    $  sudo route -n
    ...
    192.168.122.0   0.0.0.0         255.255.255.0   U     0      0        0 virbr0

So it is 192.168.122.0 , netmask 24. Add it to your iptables configuration:

    sudo iptables -A INPUT -s 192.168.122.0/24 -p udp --dport 67:68 --sport 67:68 -j ACCEPT

To confirm that the configuration was updated, check it with:

    sudo iptables -S

# Client

The client must have a spice viewer such as virt-viewer. There is a package for
linux and it can also be downloaded for windows.

# Next

Read [docs/production.md](https://github.com/UPC/ravada/blob/master/docs/production.md) 
