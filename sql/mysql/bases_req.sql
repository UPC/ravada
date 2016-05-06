CREATE TABLE `bases_req` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(128) NOT NULL,
  `date_req` datetime DEFAULT NULL,
  `date_changed` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `created` char(1) DEFAULT NULL,
  `error` varchar(255) DEFAULT NULL,
  `id_iso` int(11) NOT NULL,
  `uri` varchar(255),
  PRIMARY KEY (`id`)
);
