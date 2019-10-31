CREATE TABLE `settings` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` char(32) NOT NULL
,  `enabled` integer default NULL
);
