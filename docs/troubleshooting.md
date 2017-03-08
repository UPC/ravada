#Troubleshooting frequent problems

##Could not access KVM kernel module:

The system shows this message on trying to start a virtual Machine:

    Could not access KVM kernel module: Permission denied failed to initialize KVM: Permission denied

That means the host has no virtual capabilities or are disabled. Try running:

    $ sudo tail -f /var/log/syslog
    $ sudo modprobe kvm-intel

If it shows a message like this it means the BIOS Virt feature must be enabled:

    kvm: disabled by bios


##Dealing with permissions

The system may deny access to some directories.

###On Screnshots ( requires review )

That problem showed up in Vanilla Linux 4.10.

When running the screenshot command it returns:

    failed to open file '/var/cache/libvirt/qemu/qemu.screendump.31DvW9': Permission denied

####Apparmor

At the file : usr.lib.libvirt.virt-aa-helper

    /var/cache/libvirt/qemu/ rw,
    /var/cache/libvirt/qemu/** rw,

