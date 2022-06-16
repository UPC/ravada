VirtioFS
========

Virtiofs is a shared file system that lets virtual machines access a directory tree on the host. It will be available with Ravada v1.6.

Requirements
-------------

VirtioFS works only with libvirt 6.2. It is installed in these Linux
Distributions:

* Ubuntu 22.04
* Debian 11
* Alpine 3.16

( TODO : Please contribute if you are aware of more , thank you ! )

Virtual Machine Configuration
-----------------------------

In the hardware section of the virtual machine, add a new *filesystem* item.
You have to pass the full path you want to share with the virtual machine.

.. image:: images/new_virtiofs.jpg

Linux
-----

Using virtiofs from Linux virtual machines is pretty straightforward
and the drivers come already with any latest kernel.

Mount
~~~~~

To mount the partition add a line in the fstab with the source name
and the directory you want to mount it. In this example we mount
the directory exported from */home/shared*, that will be called
*home_shared*. It will be mounted in the path */mnt/shared* inside
the virtual machine.

.. ::

  home_shared /mnt/shared virtiofs rw,relatime 0 0

Create the mount path */mnt/shared* and type `mount -a` to try it.

Mount read-only
~~~~~~~~~~~~~~~

In the first example we accessed the directory with read and write options.
If you want to access it read only, mount it this way:

.. ::

  home_software /mnt/software virtiofs ro,relatime 0 0


Mount in Windows
----------------

`See this manual to use VirtioFS from Windows <https://virtio-fs.gitlab.io/howto-windows.html>`_.

Read More
---------

`More information about VirtioFS <https://virtio-fs.gitlab.io/>`_.
