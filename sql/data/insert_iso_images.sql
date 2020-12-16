INSERT INTO iso_images
(name,description,arch,xml,xml_volume,url, file_re, md5_url, min_disk_size)
VALUES('Ubuntu Xenial Xerus 32 bits','Ubuntu 16.04 LTS Xenial Xerus 32 bits'
    ,'i386'
    ,'xenial-i386.xml'
    ,'xenial-volume.xml'
    ,'http://releases.ubuntu.com/16.04/'
    ,'ubuntu-16.04.*desktop-i386.iso'
    ,'$url/MD5SUMS'
    ,'10'
    );

INSERT INTO iso_images
(name,description,arch,xml,xml_volume,url,file_re,md5_url)
VALUES('Debian Jessie 64 bits'
    ,'Debian 8.5.0 Jessie 64 bits (netsinst)'
    ,'amd64'
    ,'jessie-amd64.xml'
    ,'jessie-volume.xml'
    ,'http://cdimage.debian.org/cdimage/archive/8.5.0/amd64/iso-cd/'
    ,'debian-8.5.0-amd64-netinst.iso'
    ,'http://cdimage.debian.org/cdimage/archive/8.5.0/amd64/iso-cd/MD5SUMS'
   );
INSERT INTO iso_images
(name,description,arch,xml,xml_volume,url, file_re, md5_url)
VALUES('Ubuntu Zesty Zapus',' Ubuntu 17.04 Zesty Zapus 64 bits'
    ,'amd64'
    ,'zesty-amd64.xml'
    ,'zesty-volume.xml'
    ,'http://releases.ubuntu.com/17.04/'
    ,'ubuntu-17.04.*desktop-amd64.iso'
    ,'http://releases.ubuntu.com/17.04/MD5SUMS'
    );
