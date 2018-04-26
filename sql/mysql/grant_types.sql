CREATE TABLE `grant_types` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(32) NOT NULL,
  `description` varchar(255) NOT NULL,
  `enabled` int default NULL,
    UNIQUE(`name`),
    UNIQUE(`description`),
  PRIMARY KEY (`id`)
);
