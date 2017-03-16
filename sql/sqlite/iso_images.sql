CREATE TABLE `iso_images` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` char(64) NOT NULL
,  `description` varchar(255)
,  `arch` char(8)
,  `xml`  varchar(64)
,  `xml_volume` varchar(64)
,  `url` varchar(255)
,  `md5` char(32)
,  UNIQUE (`name`)
);
