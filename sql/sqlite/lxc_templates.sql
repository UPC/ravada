CREATE TABLE `lxc_templates` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` char(64) NOT NULL
,  `description` varchar(355)
,  `arch` char(8)
,  UNIQUE (`name`)
);
