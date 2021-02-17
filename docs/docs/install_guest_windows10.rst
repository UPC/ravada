Install Windows 10
==================

These are guidelines to install Windows 10 inside a  Ravada KVM Guest.


Base Guest
----------

The guest should have more than 3 GB of RAM. If you are planning to run
many services you should create the virtual machine with more memory.
You can increase it later if you want to keep it slim.

At least 30GB disk drive is required. A swap partition should also be
added when creating the virtual machine.

.. figure:: images/create_win10.png
 


When the machine is created start it from *Admin Tools menu*, click on
*Virtual Machines* to see a list. At the right there is a bunch of buttons.
Click on *view* to start and access the virtual machine console.

.. figure:: images/create_win10_view.png

   Start and View Virtual Machine



Setup
-----

Follow the usual procedure to install Windows10.         

When the installations it's finished, you need to install:

* qemu-guest agent, see the instructions here: https://pve.proxmox.com/wiki/Qemu-guest-agent#Windows
* Windows guest tools - `spice-guest-tools <https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe>`_ .
* make sure that acpi service it's activated.

If you experience slow response from the mouse or other glitches you may try installing
`VirtIO Drivers <https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers>`_ .


Use a swap partition for pagefiles
----------------------------------

By default the Windows pagefiles will go to the C: disk drive. That will make the clones partitions
grow up too much and fill your host disk drive.
It should go to the *SWAP* volume, problaby in your D: or E: drive.

In this link you can see how to move pagefiles to another disk:

https://winaero.com/blog/how-to-move-page-file-in-windows-10-to-another-disk/



