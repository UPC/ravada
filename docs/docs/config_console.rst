How to enable KVM virsh console access
======================================

Requirements
------------

The virtual machine must have the pty configured. From the KVM server
edit the domain and make sure there is this section:

From KVM Server
~~~~~~~~~~~~~~~

.. prompt:: bash

    sudo virsh edit virtual-machine

::

    <serial type='pty'>
      <source path='/dev/pts/0'/>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
      <alias name='serial0'/>
    </serial>
    <console type='pty' tty='/dev/pts/0'>
      <source path='/dev/pts/0'/>
      <target type='serial' port='0'/>
      <alias name='serial0'/>
    </console> 


From Debian / Ubuntu guest
--------------------------

You eithar have to enable the serial service or add it to grub.

Option 1: Enable Serial Service
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. prompt:: bash

    sudo systemctl enable --now serial-getty@ttyS0.service

Option 2: Add console to grub
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Search for the grub.cfg configuration file and add this to *GRUB_CMDLINE_LINUX_DEFAULT*:

::

    GRUB_CMDLINE_LINUX_DEFAULT="console=tty0 console=ttyS0,115200n8"

From KVM server
---------------

.. prompt:: bash $,(env)...$ auto

    virsh list
    Id    Name                           State
    ----------------------------------------------------
    1     freebsd                        running
    2     ubuntu-box1                    running
    3     ubuntu-box2                    running

Type the following command from KVM host to login to the guest named ubuntu-box1

.. prompt:: bash

    virsh console ubuntu-box1

OR

.. prompt:: bash

    virsh console 2

Use ``CTRL + 5`` to exit the console.
