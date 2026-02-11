CREATE TABLE `grant_types` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` char(32) NOT NULL
,  `description` varchar(255) NOT NULL
,  `enabled` integer default NULL
,  `is_int` integer default 0
,  `default_admin` integer default 1
,  `default_user` integer default 0
,    UNIQUE(`name`)
);
