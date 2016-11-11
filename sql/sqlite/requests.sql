CREATE TABLE `requests` (
  `id` integer  PRIMARY KEY AUTOINCREMENT 
,  `command` char(32) DEFAULT NULL
,  `args` char(255) DEFAULT NULL
,  `date_req` datetime DEFAULT NULL
,  `date_changed` timestamp 
,  `status` char(64) DEFAULT NULL
,  `error` text DEFAULT NULL
,  `id_domain` integer DEFAULT NULL
,  `domain_name` char(80) DEFAULT NULL
,  `result` varchar(255) DEFAULT NULL
);
