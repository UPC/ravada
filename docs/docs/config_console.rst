How to enable KVM virsh console access
======================================

From Debian / Ubuntu guest
--------------------------

::
    
    $ sudo systemctl enable serial-getty@ttyS0.service
    $ sudo systemctl start serial-getty@ttyS0.service

From KVM server
---------------

::

    $ virsh list
    Id    Name                           State
    ----------------------------------------------------
    1     freebsd                        running
    2     ubuntu-box1                    running
    3     ubuntu-box2                    running

Type the following command from KVM host to login to the guest named ubuntu-box1
    
::
    
    $ virsh console ubuntu-box1

OR

::

    $ virsh console 2

Use ``CTRL + 5`` to exit the console.
