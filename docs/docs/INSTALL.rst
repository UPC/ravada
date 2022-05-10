Install Ravada
==============

Requirements
------------

OS
--

Ravada works in any Linux distribution but we only support the package for `Canonical Ltd. Ubuntu <https://www.ubuntu.com/download/>`_ , Debian
and `Fedora <https://getfedora.org/es/>`_ server.

You can also install Ravada using Docker.

Hardware
--------

It depends on the number and type of virtual machines. For common scenarios server memory, storage and network bandwidth are the most critical requirements.

Memory
~~~~~~

RAM is the main issue. Multiply the number of concurrent workstations by
the amount of memory each one requires and that is the total RAM the server
must have. However, recent virtualization improvements allow you to overcommit
the memory.

Disks
~~~~~

The faster the disks, the better. Ravada uses incremental files for the
disks images, so clones won't require many space.

Read these
`recommendations <http://ravada.readthedocs.io/en/latest/docs/Server_Hardware.html>`_
if you want to buy a new dedicated server.

Install Ravada
--------------

Follow the detailed instructions in this section to install on different operating systems.

Ubuntu and Debian packages are built by the Ravada team:

* `Ubuntu <http://ravada.readthedocs.io/en/latest/docs/INSTALL_Ubuntu.html>`_
* `Debian <http://ravada.readthedocs.io/en/latest/docs/INSTALL_Debian.html>`_

RPMs are kindly provided by *Eclipseo*.

* `RedHat Fedora <http://ravada.readthedocs.io/en/latest/docs/INSTALL_Fedora.html>`_

Ravada can be installed from package or using docker. It is more suitable
for development and testing:

* `Docker <http://ravada.readthedocs.io/en/latest/docs/INSTALLfromDockers.html>`_

Follow `this guide <http://ravada.readthedocs.io/en/latest/docs/update.html>`_
if you are only upgrading Ravada from a previous version already installed.

Client
------

The client must have a spice viewer such as virt-viewer. There is a
package for linux and it can also be downloaded for windows.

Run
---

When Ravada is installed, learn
`how to run and use it <http://ravada.readthedocs.io/en/latest/docs/production.html>`__.

Help
----

Struggling with the installation procedure ? We tried to make it easy but
let us know if you need `assistance <http://ravada.upc.edu/#help>`__.

There is also a `troubleshooting <troubleshooting.html>`__ page with common problems that
admins may face.
