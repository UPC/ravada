CREATE TABLE `iso_images` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(64) NOT NULL,
  `description` varchar(255),
  `arch` char(8),
  `xml`  varchar(64),
  `xml_volume` varchar(64),
  `url` varchar(255),
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
);

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
