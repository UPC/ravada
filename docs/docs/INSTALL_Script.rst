Install Ravada with a Script
============================

Requirements
------------

OS
--

This Script only works on Ubuntu and Fedora.

Hardware
--------

It depends on the number and type of virtual machines. For common scenarios are
server memory, storage and network bandwidth the most critical requirements.

Memory
~~~~~~

RAM is the main issue. Multiply the number of concurrent workstations by
the amount of memory each one requires and that is the total RAM the server
must have.

Disks
~~~~~

The faster the disks, the better. Ravada uses incremental files for the
disks images, so clones won't require many space.

Install Ravada
--------------

Only use this script if you are going to install Ravada on a fresh OS.
Download the script :download:`here <res/ravada_install.sh>` .

Instructions
------------

1 - Execute the script:

::

  $ bash /path/to/ravada_install.sh

2 - The script will chack if your OS is compatible with it.

3 - The script will ask for root permisions, insert your password.

4 - The script will download and install ravada.

5 - The script will start installing MySQL server, and will ask you for a password,
it is higly recomended to NOT leave it blank!

6 - The script will create a MySQL user for ravada and will ask you for a password,
don't leave it blanck!

7 - The script will launch the ravada web user creator, and will ask you for the username,
the password and if it is admin.

8 - That's it, you have installed ravada successfully.

Issues
------

If you experiment any unexpected behaviour, don't wait to report it to us `here <https://github.com/UPC/ravada/issues>`_ .
Alternatively, you can `install it manually <http://ravada.readthedocs.io/en/latest/docs/INSTALL.html>`_ .
