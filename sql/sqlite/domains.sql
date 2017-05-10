CREATE TABLE `domains` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_base` integer
,  `name` char(80) NOT NULL
,  `created` integer NOT NULL DEFAULT '0'
,  `error` varchar(200) DEFAULT NULL
,  `uri` varchar(250) DEFAULT NULL
,  `is_base` integer NOT NULL DEFAULT '0'
,  `is_public` integer NOT NULL DEFAULT '0'
,  `file_base_img` varchar(255) DEFAULT NULL
,  `file_screenshot` varchar(255) DEFAULT NULL
,  `port` integer
,  `id_owner` integer
,  `vm` char(120) NOT NULL
,  `spice_password` char(20) DEFAULT NULL
,  UNIQUE (`id_base`,`name`)
,  UNIQUE (`name`)
);
