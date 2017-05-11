CREATE TABLE `grant_types` (
  `id` integer NOT NULL primary key AUTOINCREMENT,
  `name` char(32) NOT NULL,
  `description` varchar(255) NOT NULL,
  UNIQUE (`name`),
  UNIQUE (`description`)
);
