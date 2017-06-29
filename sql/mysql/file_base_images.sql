CREATE TABLE `file_base_images` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11),
  `file_base_img` varchar(255) DEFAULT NULL,
  `target` varchar(64) DEFAULT NULL,
  PRIMARY KEY (`id`)
);
