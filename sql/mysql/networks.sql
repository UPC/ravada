CREATE TABLE `networks` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(32) NOT NULL,
  `ip` varchar(32) NOT NULL,
  `description` varchar(140) DEFAULT NULL,
  `all_domains` int(11) DEFAULT '0',
  PRIMARY KEY (`id`)
);
