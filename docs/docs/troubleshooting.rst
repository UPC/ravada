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

    date_send datetime default now(),  >>>>>>  date_send timestamp default now(),
    
More information `about <https://stackoverflow.com/questions/36882149/error-1067-42000-invalid-default-value-for-created-at>`_.

Spice-Warning Error in certificate chain verification
-----------------------------------------------------

(/usr/bin/remote-viewer:2657): Spice-Warning **: ssl_verify.c:429:openssl_verify: Error in certificate chain verification: self signed certificate in certificate chain (num=19:depth1:/C=IL/L=Raanana/O=Red Hat/CN=my CA)


spicec looks for %APPDATA%\spicec\spice_truststore.pem / $HOME/.spicec/spice_truststore.pem. This needs to be identical to the ca-cert.pem on the server, i.e. the ca used to sign the server certificate. The client will use this to authenticate the server.
