CREATE TABLE `domains_network` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_domain` integer NOT NULL
,  `id_network` integer NOT NULL
,  `anonymous` integer NOT NULL DEFAULT '0'
,  `allowed` integer NOT NULL DEFAULT '1'
);
