# ISO Web Server

It is pointless and resource consuming download each time the ISO
files from the Internet. Set up a webserver in the main host and
let the development virtual ravadas download them from there.

# Copy the ISO files

Copy the _.iso_ files to the directory _/var/www/iso_.

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
    
    </Directory>


# Change the ISO locations

In the table iso_images there is an entry that states where are
located original ISO files, change it.

## From localhost

If you want to access to the ISO files from localhost
change the _URL_ field to this:

    $ mysql -u root -p ravada
    mysql> update iso_images set url = 'http://192.168.122.1/iso';

## From Virtual Machines

If you install ravada in a virtual machine inside the host
you have to change the URLs to the virtual address, it will
probably be _192.168.1.1_, check it is doing

    $ ifconfig virbr0


    $ mysql -u root -p ravada
    mysql> update iso_images set url = 'http://192.168.122.1/iso';


# Try it

Remove the ISO file from _/var/lib/libvirt/images_ and verify Ravada
won't download them from Internet the next time you try to install
a new machine.
