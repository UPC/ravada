CREATE TABLE `domains_req` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `start` char(1) DEFAULT NULL,
  `stop` char(1) DEFAULT NULL,
  `pause` char(1) DEFAULT NULL,
  `date_req` datetime DEFAULT NULL,
  `date_changed` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `done` char(1) DEFAULT NULL,
  `error` varchar(255) DEFAULT NULL,
  `id_domain` int(11) NOT NULL,
  PRIMARY KEY (`id`)
);
