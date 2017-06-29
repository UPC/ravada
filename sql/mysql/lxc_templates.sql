CREATE TABLE `lxc_templates` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(64) NOT NULL,
  `description` varchar(355),
  `arch` char(8),
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
);
