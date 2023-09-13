Virtual Machine Manual Migration
================================

If you have several Ravada servers you may want to copy a virtual
machine from one to another.

.. warning:: The easiest way to migrate Virtual Machines is using the new :ref:`Backup` tool added in release 1.5.

In this example we use the old manual procedure to copy the base for a virtual machine called *Lubuntu-1704*.


Check the storage pools directories
-----------------------------------

If the filesystem layout of both servers is different, the migration
can be complicated. You have to bear in mind the disk volumes may
have backing files in a different location and you need to rebase it.

Check first the directory where the volumes are stored, if you can't
have them in both servers you have to create a clone, spin if off and
migrate it to the new server.

In this example we inspect first the full path of the volumes.
::

  root@origin:~# virsh dumpxml Lubuntu1704 | grep "source file"

      <source file='/var/lib/libvirt/images/lubuntu-vda-k1dj.qcow2'/>

For each source file, check its backing  file:

::

  root@origin:~# qemu-img info /var/lib/libvirt/images/lubuntu-vda-k1dj.qcow2 | grep "backing file"

    backing file: /var/lib/libvirt/images.2/lubuntu-vda.ro.qcow2

So we now know we have to move one file to _/var/lib/libvirt/images/_
and another one to  _/var/lib/libvirt/images.2/_ . Check if the
new server has these directories in storage pools.

::

  root@destionation:~# virsh pool-list

    Name          State    Autostart
    -----------------------------------

    default active yes

::

  root@destination:~# virsh pool-dumpxml default | grep path
    <path>/var/lib/libvirt/images</path>

In this case migrate the virtual machine as it is will be difficult.
We have to rebase the volumes. The easiest way would be to create a
clone, spin off the volumes from the web frontend administration and
migrate it then.

Import the Base
---------------

Copy the Base definition
~~~~~~~~~~~~~~~~~~~~~~~~

First copy the base definition file from server origin to destination. You need an user
in the destination machine and ssh connection from each other.

::

    root@origin:~# virsh dumpxml Lubuntu1704 > Lubuntu1704.xml
    root@origin:~# scp Lubuntu1704.xml root@dst.domain:

Copy the volumes
~~~~~~~~~~~~~~~~

The volumes have a backing file, you must find out what it is so you can copy
to destination.

::

    root@origin:~# grep source Lubuntu1704.xml
    <source file='/var/lib/libvirt/images/Lubuntu1704-vda-X18J.img'/>
    root@origin:~# qemu-img info /var/lib/libvirt/images/base-vda-X18J.img | grep -i backing
    backing file: /var/lib/libvirt/images/Lubuntu1704-vda-X18J.ro.qcow2
    root@origin:~# rsync -avPS /var/lib/libvirt/images/base-vda-X18J.ro.qcow2 root@dst.domain:/var/lib/libvirt/images
    root@origin:~# rsync -avPS /var/lib/libvirt/images/Lubuntu1704-vda-X18J.img root@dst.domain:/var/lib/libvirt/images


Define the base on destination
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Go to the destination server and define the virtual machine base with the XML
config you copied before

::

    root@dst:~# virsh define Lubuntu1704.xml
    Domain base defined from Lubuntu1704.xml

Import the base to Ravada on destination
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Run this command and you should see the base on the Ravada web admin page.

::

    root@dst:~# rvd_back --import-domain Lubuntu1704
    This virtual machine has 3 backing files. Do you want to import it as a base ? Please answer y/n [yes]:

Importing clones
----------------

Now if you want to import a clone too, first you have to ask the clone owner to
start and stop the machine on destination. Then you have to copy the volumes from origin
and overwrite what has just been created on destination.


Create a clone
~~~~~~~~~~~~~~

The owner of the original clone must create a clone in destination using Ravada.
That will create a basic virtual machine with the same name
owned by the correct user. Stop the domain on destination:

::

    root@dst:~# virsh shutdown Lubuntu1704-juan-ramon

Make sure it is stopped

::

    root@dst:~# virsh dominfo Lubuntu1704-juan-ramon

Copy the clone volumes
~~~~~~~~~~~~~~~~~~~~~~

Find out what are the clone volume files, and copy them to the temporary space
in destination:

::

    root@origin:~# virsh dumpxml Lubuntu1704-juan-ramon | grep "source file" | grep -v ".ro."
    <source file='/var/lib/libvirt/images/Lubuntu1704-juan-ramon-vda-kg.qcow2'/>
    root@origin:~# rsync -av /var/lib/libvirt/images/Lubuntu1704-juan-ramon-vda-kg.qcow2 root@dst:/var/lib/libvirt/images

Start the clone on destination
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

First move the volumes to the right place, notice in destination the volumes
have different names. Check the XML configuration matches the place where you
stored the qcow files.

Hopefully then you can start the clone. It is a delicate procedure that must be
followed carefully, please consider helping with this document if you have any
suggestions.

Importing Standalone Machine
----------------------------

Dumping data
~~~~~~~~~~~~

To export the necessary data you need the XML file and the volume files.

XML file
~~~~~~~~

::

    root@src:# virsh dumpxml Lubuntu1704 > Lubuntu1704.xml

Volume Files
~~~~~~~~~~~~

Find out the volume files searching for "source file" in the XML. Copy these
files to the destination server.

::

    root@origin:~# virsh dumpxml Lubuntu1704 | grep "source file" | grep -v ".ro."
    <source file='/var/lib/libvirt/images/Lubuntu1704-vda-kg.qcow2'/>
    root@origin:~# rsync -av /var/lib/libvirt/images/Lubuntu1704-vda-kg.qcow2 root@dst:/var/lib/libvirt/images/

Importing data
~~~~~~~~~~~~~~

First of all you need to check the storage directory in the destination server matches
the source. Check for "source file" lines in the XML and change it if you will place
the qcow files elsewhere.

Then define the virtual machine base with that XML config file.

::

    root@dst:~# virsh define Lubuntu1704.xml
    Domain base defined from Lubuntu1704.xml

Then try to start the virtual machine:

::

    root@dst~# virsh start Lubuntu1704

Once you have verified the machine is running, import it into Ravada:

::

    root@dst~# rvd_back --import-domain Lubuntu1704
