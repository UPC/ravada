INSERT INTO iso_images
(name,description,arch,xml,xml_volume,url)
VALUES('Debian Jessie 32 bits netinst'
    ,'Debian 8.4.0 Jessie 32 bits (netsinst)'
    ,'i386'
    ,'jessie-i386.xml'
    ,'jessie-volume.xml'
    ,'http://cdimage.debian.org/debian-cd/8.4.0/i386/iso-cd/debian-8.4.0-i386-netinst.iso');
INSERT INTO iso_images
(name,description,arch,xml,xml_volume,url)
VALUES('Ubuntu Trusty 32 bits','Ubuntu 14.04 LTS Trusty 32 bits'
    ,'i386'
    ,'trusty-i386.xml'
    ,'trusty-volume.xml'
    ,'http://releases.ubuntu.com/16.04/ubuntu-16.04-desktop-i386.iso');

INSERT INTO iso_images
(name,description,arch,xml,xml_volume,url)
VALUES('Ubuntu Xenial Xerus 32 bits','Ubuntu 16.04 LTS Xenial Xerus 32 bits'
    ,'i386'
    ,'xenial-i386.xml'
    ,'xenial-volume.xml'
    ,'http://releases.ubuntu.com/16.04/ubuntu-16.04-desktop-i386.iso');

INSERT INTO iso_images
(name,description,arch,url)
VALUES('Ubuntu Xenial Xerus 64 bits','Ubuntu 16.04 LTS Xenial Xerus 64 bits'
        ,'amd64'
        ,'http://releases.ubuntu.com/16.04/ubuntu-16.04-desktop-amd64.iso');
