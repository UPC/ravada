CREATE TABLE `messages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_user` int(11) NOT NULL,
  `id_request` int(11),
  `subject` varchar(120) DEFAULT NULL,
  `message` text,
  `date_send` datetime default now(),
  `date_shown` datetime,
  `date_read` datetime,
  PRIMARY KEY (`id`),
  KEY `id_user` (`id_user`)
);
