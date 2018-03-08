INSERT INTO iso_images
(name,description,arch,xml,xml_volume,url,file_re,md5_url, min_disk_size)
VALUES('Ubuntu Trusty 32 bits','Ubuntu 14.04 LTS Trusty 32 bits'
    ,'i386'
    ,'trusty-i386.xml'
    ,'trusty-volume.xml'
    ,'http://releases.ubuntu.com/14.04/'
    ,'ubuntu-14.04.*-desktop-i386.iso'
    ,'$url/MD5SUMS'
    ,'10'
	);

INSERT INTO iso_images
(name,description,arch,xml,xml_volume,url, file_re, md5_url, min_disk_size)
VALUES('Ubuntu Trusty 64 bits','Ubuntu 14.04.1 LTS Trusty 64 bits'
    ,'amd64'
    ,'trusty-amd64.xml'
    ,'trusty-amd64-volume.xml'
    ,'http://releases.ubuntu.com/14.04/'
    ,'ubuntu-14.04.*-desktop-amd64.iso'
    ,'http://releases.ubuntu.com/14.04/MD5SUMS'
    ,'10'
	);

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
(name,description,arch,xml,xml_volume,url, file_re, md5_url, min_disk_size)
VALUES('Ubuntu Xenial Xerus 64 bits','Ubuntu 16.04 LTS Xenial Xerus 64 bits'
    ,'amd64'
    ,'xenial64-amd64.xml'
    ,'xenial64-volume.xml'
    ,'http://releases.ubuntu.com/16.04/'
    ,'ubuntu-16.04.*-desktop-amd64.iso'
    ,'$url/MD5SUMS'
    ,'10'
    );

INSERT INTO iso_images
(name,description,arch,xml,xml_volume,url, file_re, md5_url)
VALUES('Ubuntu Yakkety Yak 64 bits',' Ubuntu 16.10 Yakkety Yak 64 bits'
    ,'amd64'
    ,'yakkety64-amd64.xml'
    ,'yakkety64-volume.xml'
    ,'http://old-releases.ubuntu.com/releases/16.10/'
    ,'ubuntu-16.10.*desktop-amd64.iso'
    ,'http://old-releases.ubuntu.com/releases/16.10/MD5SUMS'
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
