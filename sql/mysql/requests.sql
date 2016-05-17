CREATE TABLE `requests` (
  `id` integer primary key AUTO_INCREMENT ,
  `command` char(32) DEFAULT NULL,
  `args` char(255) DEFAULT NULL,
  `date_req` datetime DEFAULT NULL,
  `date_changed` timestamp ,
  `status` char(1) DEFAULT NULL,
  `error` varchar(255) DEFAULT NULL,
  `id_domain` int(11) DEFAULT NULL,
  `domain_name` char(80) DEFAULT NULL
);
