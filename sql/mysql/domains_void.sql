CREATE TABLE `domains_void` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `id_domain` (`id_domain`)
);
