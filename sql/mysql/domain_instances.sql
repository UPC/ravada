CREATE TABLE `domain_instances` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11) NOT NULL,
  `id_vm` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `id2` (`id_domain`,`id_vm`)
);

