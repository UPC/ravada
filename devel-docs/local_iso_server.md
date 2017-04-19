# ISO Web Server

It is pointless and resource consuming download each time the ISO
files from the Internet. Set up a webserver in the main host and
let the development virtual ravadas download them from there.

# Copy the ISO files

Copy the _.iso_ files to the directory _/var/www/html/iso_.

    $ sudo mkdir /var/www/html/iso
    $ sudo cp /var/lib/libvirt/images/*iso /var/www/html/iso

# Apache

## Install Apache

Install apache web server:

    $ sudo apt-get install apache2


## Config apache

Configure it so ISOs are donwloaded from the storage pool, and only
the local virtual network is able to access to it.

Edit _/etc/apache2/sites-enabled/000-default.conf_ and add:

    <Location /iso>
    
        Options FollowSymLinks
        AllowOverride None
    
        Allow from localhost
        Allow from 192.168.122.0/24
        Deny from all
    
        Require all granted
        Options +Indexes
    
    </Location>

## Restart apache

    $ sudo systemctl restart apache2


# Change the ISO locations

In the table iso_images there is an entry that states where are
located original ISO files, change it.

## From localhost

If you want to access to the ISO files from localhost
change the _URL_ field to this:

    $ mysql -u root -p ravada
    mysql> update iso_images set url = 'http://127.0.0.1/iso/';

## From Virtual Machines

If you install ravada in a virtual machine inside the host
you have to change the URLs to the virtual address, it will
probably be _192.168.1.1_, check it is doing

    $ ifconfig virbr0


    $ mysql -u root -p ravada
    mysql> update iso_images set url = 'http://192.168.122.1/iso/';


# Try it

Remove the ISO from the storage and from the table

## Remove from the VM storage pool

    $ sudo rm /var/lib/libvirt/images/*iso

## Remove the device name from the table

First find out the id of the iso image, then remove it.

    $ mysql -u root -p ravada
    mysql> select id,name FROM iso_images;
    mysql> update iso_images set device = null where id=9;

Restart rvd\_back and
reload the admin page and verify Ravada
won't download them from Internet the next time you try to install
a new machine.

    $ sudo ./bin/rvd_back.pl --debug
