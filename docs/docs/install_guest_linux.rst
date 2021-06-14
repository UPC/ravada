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

For Debian, Ubuntu and similar systems:

.. prompt:: bash $

    sudo dpkg-reconfigure unattended-upgrades

Other Linux flavours may have similar tools. Contributions welcome.

Limit systemd log size
----------------------

*Thanks to Jordi Lino for this tip* .

You can change the systemd configuration to limit the journal log disk usage (100 MB for example).
Edit the /etc/systemd/journald.conf file and un-comment (remove # at the beginning) the line #SystemMaxUse= and change it to SystemMaxUse=100M.

Read `this <https://ubuntuhandbook.org/index.php/2020/12/clear-systemd-journal-logs-ubuntu/>`__ for more information.
