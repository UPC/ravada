CREATE TABLE `base_xml` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_domain` integer NOT NULL
,  `xml` varchar(8092) DEFAULT NULL
,  UNIQUE (`id_domain`)
);
