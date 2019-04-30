CREATE TABLE `domain_ports` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_domain` integer DEFAULT NULL
,  `public_port` integer DEFAULT NULL
,  `internal_port` integer DEFAULT NULL
,  `public_ip` varchar(255) DEFAULT NULL
,  `internal_ip` varchar(255) DEFAULT NULL
,  `name` varchar(32) DEFAULT NULL
,  `description` varchar(255) DEFAULT NULL
,  `active` integer DEFAULT 0
,  UNIQUE (`id_domain`,`internal_port`)
,  UNIQUE (`id_domain`,`description`)
,  UNIQUE (`id_domain`,`name`)
,  UNIQUE (`internal_port`,`internal_ip`)
,  UNIQUE (`public_port`,`public_ip`)
);
