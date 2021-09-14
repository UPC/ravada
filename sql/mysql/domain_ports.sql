CREATE TABLE `domain_ports` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11) NOT NULL references domains(id) on delete cascade,
  `public_port` int(11) DEFAULT NULL,
  `internal_port` int(11) DEFAULT NULL,
  `name` varchar(32) DEFAULT NULL,
  `restricted` int(1) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `domain_port` (`id_domain`,`internal_port`),
  UNIQUE KEY `name` (`id_domain`,`name`)

);
