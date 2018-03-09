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
,  `description` text
,  `start_time` integer not null default 0
,  `status` varchar(32) default 'shutdown'
,  `display` varchar(128) default NULL
,  `info` varchar(255) default NULL
,  `internal_id` varchar(64) DEFAULT NULL
,  UNIQUE (`id_base`,`name`)
,  UNIQUE (`name`)
);
