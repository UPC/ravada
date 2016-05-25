CREATE TABLE `iso_images` (
  `id` integer primary key autoincrement,
  `name` char(64) NOT NULL,
  `description` varchar(255),
  `arch` char(8),
  `xml`  varchar(64),
  `xml_volume` varchar(64),
  `url` varchar(255)
);

