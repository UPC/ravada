CREATE TABLE `domains_void` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_domain` integer NOT NULL
,  UNIQUE (`id_domain`)
);
