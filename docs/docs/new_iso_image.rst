New ISO image
==========================

In order to use an ISO file when you create a new machine, you must
first place it inside the KVM directory:

::
 
    /var/lib/libvirt/images

Then you have to tell the storage engine that you changed a file manually.

::

    $ sudo virsh pool-list
     Name                 State      Autostart
     -------------------------------------------
     default              active     yes
     pool2                active     yes
    $ sudo virsh pool-refresh default
    $ sudo virsh pool-refresh pool2
 
Reload the *new machine* form so the file you just uploaded shows up in the ISO list.

After that, Ravada is able to use he ISO when selecting it while creating a machine.
Also, ISOs that were downloaded from Ravada can also be found in this directory.



If you want to include a KVM templated instead, use this `guide <http://ravada.readthedocs.io/en/latest/docs/new_kvm_template.html>`_ .


If you need the xml or the volume (for when you wanna add a new template), you can extract them via virsh using the following commands:

::

    $ sudo virsh pool-list #in order to see the list of available pools
    $ sudo virsh vol-list default #in order to see the list of volumes available
    $ sudo virsh vol-dumpxml --pool default name_of_the_existing_machine.qcow2 #obtain the dump of a selected volume
    $ sudo virsh dumpxml name_of_the_existing_machine #obtain the xml of a existing selected machine
