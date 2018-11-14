How to add a KVM template
==========================

ISO images are required to create KVM virtual machines. They can be
placed or downloaded at run time.

Placing your own ISO image
--------------------------

Copy the .iso file to the KVM storage, it is /var/lib/libvirt/images by
default. Make sure everybody can read it

.. prompt:: bash #

    chmod 755 file.iso

Get the md5 for the ISO file, you will need it for the next step:

.. prompt:: bash #

    md5sum file.iso

Add an entry to the SQL table:

.. prompt:: bash $,(env)...$ auto

    mysql -u rvd_user -p ravada
    mysql> INSERT INTO iso_images (name, description, arch, xml, xml_volume, md5, sha256, device)
            VALUES ('name','the description', 'i386', 'name.xml' ,'name-vol.xml','bbblamd5sumjustgenerated','mysha256sum','/var/lib/libvirt/images/file.iso');

XML file
--------

A XML template file is required if you want to create machines from this
ISO. In the directory /var/lib/ravada/xml there are examples. You can
make new ones creating a new machine from another tool like
virt-manager. Once it is down dump the xml with

.. prompt:: bash #

    virsh dumpxml machine > name.xml

XML Volume file
---------------

Create a new xml volume file based in another one from
/var/lib/ravada/xml.

URL based ISO (simplified)
--------------------------

For most Linux based distributions, you won't need to manually download the ISO. Here we're assuming that there are a valid VM definition XML and a volume XML files (based on Ubuntu 16.04 Xenial Xerus).

.. prompt:: bash $,(env)...$ auto

    mysql -u rvd_user -p ravada
    mysql> INSERT INTO iso_images (name, description, arch, xml, xml_volume, url, sha256_url)
            VALUES ('Mint 18.2 BETA Mate 64 bits','Mint Serena 18.2 BETA with Mate Desktop based on Ubuntu Xenial 64 bits', 'amd64', 'xenial64-amd64.xml' ,'xenial64-volume.xml','http://ftp.cixug.es/mint/linuxmint.com/testing/linuxmint-18.2-cinnamon-64bit-beta.iso', 'https://ftp.heanet.ie/mirrors/linuxmint.com/testing/sha256sum.txt');

Windows specifics
-----------------

For Windows you will need the virtio ISO that can be downloaded from
https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

Save it to /var/lib/libvirt/images and change the owner as you did for
the Windows ISO.

.. prompt:: bash #

    chmod 755 /var/lib/libvirt/images/virtio-win-0.1.126.iso

Then edit your Windows xml file and point the second CD drive to that
ISO. For the current stable virtio version, it looks like this: virsh
edit machinename

::

    <disk type='file' device='cdrom'>
        <driver name='qemu' type='raw'/>
        <source file='/var/lib/libvirt/images/virtio-win-0.1.126.iso'/>
        <target dev='hdc' bus='ide'/>
        <readonly/>
        <address type='drive' controller='0' bus='1' target='0' unit='0'/>
    </disk>

You should also ensure that the system disk cache is set to
'directsync':

::

    <driver name='qemu' type='qcow2' cache='directsync' io='native' />

If you're using the NEC xhci USB controller (the default one in our
environment), you'll need to obtain a suitable driver for the µPD720200
chipset. Plugable.com has it here http://plugable.com/drivers/renesas
(2nd entry).
