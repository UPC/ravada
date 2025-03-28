PCI Passthrough Templates
=========================

Host Devices as a GPU or another PCI device is passed to the virtual
machine. Ravada injects XML configuration inside the virtual machine
definition.

This works with XML templates stored in a database. We have some common
examples, but you can tweak it to suit your needs.

nVidia virtual GPUs and Ubuntu 24.04
------------------------------------

Under Ubuntu Server 24.04, with some GPUS as L4, the virtual gpus are no longer
mediated devices, but full blown PCIe devices that must be unmanaged.

In future releases we may add a way to tweak the settings of the host devices.
Currently you can change the managed attribute changing the template in the database.

1. Find out host device id
~~~~~~~~~~~~~~~~~~~~~~~~~~

::

    First check what is the host device id you want to change:
    mysql> select id,name FROM host_devices;
    
    +----+---------------+
    | id | name          |
    +----+---------------+
    |  3 | PCI 1         |

2. Find the HostDev Template
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Then list the templates this host device is using. In this case there should be two:

::

    mysql> select id,template from host_device_templates where id_host_device=3;

One of the templates should contain the managed attribute ( I only show part of the text). The important part of this output is the "id" in the first column:

::

    +----+---------------+
    | id | template
    +----+---------------+
    |  5 | <hostdev mode='subsystem' type='pci' managed='yes'>
                    <driver name='vfio'/>
    ...

3. Change the Template
~~~~~~~~~~~~~~~~~~~~~~

Now we want to turn this to managed='no' , do it like this, knowing this was id=5:

::

    mysql> update host_device_templates set template=REPLACE(template,"managed='yes'","managed='no'") WHERE id=5

Now try to start the virtual machine again. The configuration should have
the change you just fixed.

