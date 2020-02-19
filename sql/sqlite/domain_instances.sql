CREATE TABLE `domain_instances` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_domain` integer NOT NULL
,  `id_vm` integer NOT NULL
,  UNIQUE (`id_domain`,`id_vm`)
);
