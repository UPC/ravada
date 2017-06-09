CREATE TABLE `domain_ports` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11) DEFAULT NULL,
  `public_port` int(11) DEFAULT NULL,
  `internal_port` int(11) DEFAULT NULL,
  `public_ip` varchar(255) DEFAULT NULL,
  `internal_ip` varchar(255) DEFAULT NULL,
  `name` varchar(32) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `active` int(11) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `domain_port` (`id_domain`,`internal_port`),
  UNIQUE KEY `description` (`id_domain`,`description`),
  UNIQUE KEY `name` (`id_domain`,`name`),
  UNIQUE KEY `internal` (`internal_port`,`internal_ip`),
  UNIQUE KEY `public` (`public_port`,`public_ip`)

);
