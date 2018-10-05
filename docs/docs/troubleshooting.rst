Troubleshooting frequent problems
=================================

Could not access KVM kernel module:
-----------------------------------

The system shows this message on trying to start a virtual Machine:

::

    Could not access KVM kernel module: Permission denied failed to initialize KVM: Permission denied

That means the host has no virtual capabilities or are disabled. Try
running:

::

    $ sudo tail -f /var/log/syslog
    $ sudo modprobe kvm-intel

If it shows a message like this it means the BIOS Virt feature must be
enabled:

::

    kvm: disabled by bios
    
or try: kvm-ok command

::

    # kvm-ok
    INFO: /dev/kvm does not exist
    HINT:   sudo modprobe kvm_intel
    INFO: Your CPU supports KVM extensions
    INFO: KVM (vmx) is disabled by your BIOS
    HINT: Enter your BIOS setup and enable Virtualization Technology (VT),
      and then hard poweroff/poweron your system
    KVM acceleration can NOT be used


Dealing with permissions
------------------------

The system may deny access to some directories.

On Screnshots ( requires review )
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

That problem showed up in Vanilla Linux 4.10.

When running the screenshot command it returns:

::

    failed to open file '/var/cache/libvirt/qemu/qemu.screendump.31DvW9': Permission denied

Apparmor
^^^^^^^^

At the file : ``/etc/apparmor.d/usr.lib.libvirt.virt-aa-helper``

::

    /var/cache/libvirt/qemu/ rw,
    /var/cache/libvirt/qemu/** rw,

Error with MySQL version < 5.6
------------------------------

For example the following message:

:: 
    
    DBD::mysql::db do failed: Invalid default value for 'date_send' at /usr/share/perl5/Ravada.pm line 276.
    
DEFAULT CURRENT_TIMESTAMP support for a DATETIME (datatype) was added in MySQL 5.6.

Upgrade your MySQL server or change:  ``datetime`` for ``timestamp``

::

    date_send datetime default now(),
    
More information `about <https://stackoverflow.com/questions/36882149/error-1067-42000-invalid-default-value-for-created-at>`_.

Spice-Warning Error in certificate chain verification
-----------------------------------------------------

(/usr/bin/remote-viewer:2657): Spice-Warning **: ssl_verify.c:429:openssl_verify: Error in certificate chain verification: self signed certificate in certificate chain (num=19:depth1:/C=IL/L=Raanana/O=Red Hat/CN=my CA)


spicec looks for %APPDATA%\spicec\spice_truststore.pem / $HOME/.spicec/spice_truststore.pem. This needs to be identical to the ca-cert.pem on the server, i.e. the ca used to sign the server certificate. The client will use this to authenticate the server.

Network is already in use
-------------------------

If running VMs crash with that message:

    libvirt error code: 1, message: internal error: Network is already in use by interface

You are probably running Ravada inside a virtual machine or you are using the private network that KVM uses for another interface.
This is likely to happen when running Ravad in a Nested Virtual environment.

**Solution:** Change the KVM network definition. Edit the file `/etc/libvirt/qemu/networks/default.xml` and replace all the
 192.168.122 network instances by another one, ie: 192.168.123.
 
 ::
 
     $ sudo virsh net-edit default
     <ip address='192.168.122.1' netmask='255.255.255.0'>
        <dhcp>
          <range start='192.168.122.2' end='192.168.122.254'/>
        </dhcp>
      </ip>
      
 Then reboot the whole system.

Copy & paste integration does not work
--------------------------------------

Make sure that the VM has a Spice communication channel (com.redhat.spice.0) and that the guest additions have been installed.

The Spice channel can be added through virt-manager's Add Hardware wizard or editing the XML:
::
    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>

Linux guests must install the spice-vdagent package, while Windows guests require `this installer <https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe>`_ (`source <https://wiki.archlinux.org/index.php/QEMU#Copy_and_paste>`_)


Resizing the viewer window does not change the guest display resolution
-----------------------------------------------------------------------
This feature requires the Spice communication channel and the guest additions. See above for instructions.

Windows 10 perfomance issues
----------------------------

*thanks to @rlunardo*

* Windows10 Enterprise ISO image (Home/Professional/Enterprise) before April 2017: if you install Enterprise version, it does not reach the end of installation. Issue posted on 30/10/2017. The Professional version does complete the installation.  Recent Enterprise ISO image release completes the installation also.

* Windows 10 tuning after installation: There are several web site where we can find informations and solutions to solve CPU, RAM, Disk overload on Windows 10. Here some links:

  - https://www.drivethelife.com/windows-10/fix-high-ram-cpu-memory-usage-after-windows-10-update.html

  - https://fossbytes.com/how-to-fix-high-ram-and-cpu-usage-of-windows-10-system-ntoskrnl-exe-process/

  - https://youtu.be/iHzEp8a8w10


Problems with the time of the VM guest
--------------------------------------
You create a VM and you set the time correctly. After this VM becomes base and the time appears altered (-2h, +2h,...)

This is due to the parameter:
::
    <clock offset='utc'>  vs    <clock offset='localtime'>

You can modify XML file from the command:  
::
    virsh edit <machine_name>
