CREATE TABLE `iso_images` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `file_re` char(64)
,  `name` char(64) NOT NULL
,  `description` varchar(255)
,  `arch` char(8)
,  `xml`  varchar(64)
,  `xml_volume` varchar(64)
,  `url` varchar(255)
,  `md5` varchar(32)
,  `md5_url` varchar(255)
,  `sha256_url` varchar(255)
,  `device` varchar(255)
,  `min_disk_size` integer
,  UNIQUE (`name`)
);
