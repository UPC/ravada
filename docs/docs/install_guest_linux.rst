Best practices to install Linux Guests in Ravada
================================================


Disk volumes
------------

It is advisable to have at least 2 disk volumes: one for the Operative System
and another one for the SWAP partition. Make sure both are selected in the
new machine form.

The Operative system will go to /dev/vda and the swap drive will be in /dev/vdb.
Configure them properly in the installation process.

Installing software
~~~~~~~~~~~~~~~~~~~~~~~~

You should at least install these applications:


- qemu-guest-agent
- acpi

Energy setup
------------

Configure the system so if the *power off* button is pressed the computer is shut down.

Automatic or unattended upgrades
--------------------------------

Upgrades may cause the disk volumes to grow unexpectedly. They should be disabled.
