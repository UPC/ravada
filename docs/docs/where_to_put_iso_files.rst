Where to put ISO files
==========================

In order to use an ISO file when you create a new machine, you must
first place it inside the directory where Ravada reads its XML and ISOs:

::
 
    /var/lib/libvirt/images
    
After you placed the ISO, Ravada is able to use it when selecting an ISO
while creating a machine.
Also, ISOs that were downloaded from Ravada can also be found in this directory.

Ravada may also detect ISOs from ISO directories from your directory /home.
