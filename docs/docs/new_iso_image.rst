New ISO image
==========================

In order to use an ISO file when you create a new machine, you must
first place it inside the KVM directory:

::
 
    /var/lib/libvirt/images

After that, Ravada is able to use the ISO when selecting it while creating a machine.
Also, ISOs that were downloaded from Ravada can also be found in this directory.

Ravada may also detect ISOs from ISO directories from your directory /home.

If you want to include a KVM instead of an ISO, use this `guide <http://ravada.readthedocs.io/en/latest/docs/new_kvm_template.html>`_ instead.
