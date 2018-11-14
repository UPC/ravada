Reduce the image size after cloning a physical PC
=================================================

Things to keep in mind when we have a cloned image of Windows from a physical PC.


.. note ::
    During these tasks, be aware that it affects the performance of the server. Avoid making them on a Ravada server in production.

Check the image format
----------------------

In the following case you can see that it's RAW format. Although the extension of the file is qcow2 this obviously does not affect.

.. prompt:: bash #,(env)... auto

    qemu-img info Win7.qcow2
    image: Win7.qcow2
    file format: raw
    virtual size: 90G (96636764160 bytes)
    disk size: 90G

STEPS TO FOLLOW
---------------

1. Convert from RAW (binary) to QCOW2:

.. prompt:: bash #

    qemu-img convert -p -f raw Win7.qcow2 -O qcow2 Win7-QCOW2.qcow2

Now verify that the image format is QCOW2, and it's 26GB smaller.

.. prompt:: bash #,(env)... auto

    qemu-img info Win7-QCOW2.qcow2
    image: Win7-QCOW2.qcow2
    file format: qcow2
    virtual size: 90G (96636764160 bytes)
    disk size: 64G
    cluster_size: 65536
    Format specific information:
        compat: 1.1
        lazy refcounts: false
        refcount bits: 16
        corrupt: false

2.  The virt-sparsify command-line tool can be used to make a virtual machine disk (or any disk image) sparse. This is also known as thin-provisioning. Free disk space on the disk image is converted to free space on the host.

.. prompt:: bash #

    virt-sparsify -v Win7-QCOW2.qcow2 Win7-QCOW2-sparsi.qcow2

.. note ::
        The virtual machine must be shutdown before using virt-sparsify.
        In a worst case scenario, virt-sparsify may require up to twice the virtual size of the source disk image. One for the temporary copy and one for the destination image.
        If you use the --in-place option, large amounts of temporary space are not needed.

Disk size now is 60G, below you can see that reduce image size in 30GB.

.. prompt:: bash #,(env)... auto

    qemu-img info Win7-QCOW2-sparsi.qcow2
    image: Win7-QCOW2-sparsi.qcow2
    file format: qcow2
    virtual size: 90G (96636764160 bytes)
    disk size: 60G
    cluster_size: 65536
    Format specific information:
        compat: 1.1
        lazy refcounts: false
        refcount bits: 16
        corrupt: false

Now it is advisable to let Windows do a CHKDSK, do not interrupt it.
Finally, you need to install the `Spice guest-tools <https://www.spice-space.org/download/windows/spice-guest-tools/spice-guest-tools-latest.exe>`_.
This improves features of the VM, such as the screen settings, it adjusts automatically, etc.
