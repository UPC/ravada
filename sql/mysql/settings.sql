CREATE TABLE `settings` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(32) NOT NULL,
  `enabled` int default NULL,
  PRIMARY KEY (`id`)
);
