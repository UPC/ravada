Windows Post Install
~~~~~~~~~~~~~~~~~~~~

When the installations it's finished, you need to install:

* qemu-guest agent, see the instructions here: https://pve.proxmox.com/wiki/Qemu-guest-agent#Windows
* Windows guest tools - `spice-guest-tools <https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe>`_ .
* make sure that acpi service it's activated.

If you experience slow response from the mouse or other glitches you may try installing
`VirtIO Drivers <https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers>`_ .

The drivers CDROM should have been automatically located in the
secondary cd drive in your system.
