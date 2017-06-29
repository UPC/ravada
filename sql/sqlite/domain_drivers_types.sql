CREATE TABLE `domain_drivers_types` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` char(32) DEFAULT NULL
,  `description` varchar(200) DEFAULT NULL
,  `vm` char(32)
,  UNIQUE (`name`)
);
