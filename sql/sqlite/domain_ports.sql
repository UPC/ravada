CREATE TABLE `domain_ports` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_domain` integer DEFAULT NULL
,  `public_port` integer DEFAULT NULL
,  `internal_port` integer DEFAULT NULL
,  `name` varchar(32) DEFAULT NULL
,  `restricted` integer DEFAULT 0
,  UNIQUE (`id_domain`,`internal_port`)
,  UNIQUE (`id_domain`,`name`)
,  UNIQUE (`public_port`)
);
