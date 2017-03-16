CREATE TABLE `domains_network` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11) NOT NULL,
  `id_network` int(11) NOT NULL,
  `anonymous` int(11) NOT NULL DEFAULT '0',
  `allowed` int(11) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`)
);
