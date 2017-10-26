CREATE TABLE `bases_vm` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11) NOT NULL,
  `id_vm` int(11),
  `enabled` int(4) DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `id_domain` (`id_domain`),
  KEY `id_vm` (`id_vm`),
  UNIQUE (`id_domain`,`id_vm`)
);

