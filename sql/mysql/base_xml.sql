CREATE TABLE `base_xml` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11) NOT NULL,
  `xml` varchar(8092) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `id_domain` (`id_domain`)
);
