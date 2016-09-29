#How to add a new ISO image

ISO images are required to create KVM virtual machines. They can be placed or downloaded at run time.

##Placing your own ISO image

Copy the .iso file to the KVM storage, it is /var/lib/libvirt/images by default. Make sure everybody can read it

   # chown 07500 file.iso
  
Add an entry to the SQL table:

    mysql> INSERT INTO iso_images (name, description, arch, xml, xml_volume, md5)
            VALUES ('name','the description', 'i386', 'name.xml' ,'name-vol.xml','bbbla');
  
##XML file

A XML template file is required if you want to create machines from this ISO. In the directory etc/xml there are examples. You can make new ones creating a new machine from another tool like virt-manager. Once it is down dump the xml with

    # virsh dumpxml machine name.xml

##XML Volume file

Create a new xml volume file based in another one from etc/xml.
