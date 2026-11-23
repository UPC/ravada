Set Hostname
============

The hostname of a virtual machine can be changed on startup. The name of
the virtual domain is passed in a smbios string and can be used to rename.

It is advisable to change the hostname specially if the Virtual Machine
mounts an NFS directory. The NFS server may see all clones as the same and
constanltly dettaches and attaches the mount points. That impacts the
performance of the virtual machine. Running this script on startup fixes
that issue.

Requirements
------------

This feature is available from release 0.3.4 and requires libvirt-4.6.

Packages
~~~~~~~~
- Ravada: 0.3.4
- libvirt: 4.6

Distributions
~~~~~~~~~~~~~
This feature has been reported to work with these Linux distributions. Any
other distribution with libvirt 4.6 or bigger will work too. Please report
if you successfully tested it.

Supported distributions:

- Ubuntu 18.10

Linux dmidecode
---------------

This is how the hostname dynamic setting works with Ravada. A special DMI
entry is added to all the virtual machines internally.

The virtual machine name can be read with dmidecode

.. prompt:: bash $

    dmidecode | grep hostname


systemd
~~~~~~~~

If your system supports systemd this script will set the virtual machine name
as the hostname on startup. It also updates the machine-id.
Put the service file in */lib/systemd/system/sethostname.service*:


.. literalinclude:: sethostname.service

This is the script that is launched by the service, it should be
in */usr/local/bin/set_hostname.sh* as specified in the previous file.

.. literalinclude:: set_hostname.sh

Type this so the script is executed on startup:

.. prompt:: bash $

   sudo chmod +x /usr/local/bin/set_hostname.sh
   sudo systemctl enable sethostname

Reboot and check if the hostname is applied. You should find a log file
at */var/log/set_hostname.log*.

rc.local
~~~~~~~~

If you Linux system supports rc.local just call the script and the hostname
will be updated on boot:


::

    /usr/local/bin/set_hostname.sh

Windows
-------

SMBios information is available in Windows too. The data is stored in the
registry and also can be shown with a tool called WMI.

Contributed information would be appreciated.
