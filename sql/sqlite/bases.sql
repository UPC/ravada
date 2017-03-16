CREATE TABLE `bases` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` varchar(80) NOT NULL
,  `image` varchar(255) DEFAULT NULL
,  UNIQUE (`name`)
);
