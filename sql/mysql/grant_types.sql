CREATE TABLE `grant_types` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(32) NOT NULL,
  `description` varchar(255) NOT NULL,
  `enabled` int default NULL,
  `is_int` int default 0,
  `default_admin` int default 1,
    UNIQUE(`name`),
    UNIQUE(`description`),
  PRIMARY KEY (`id`)
) CHARACTER SET 'utf8';
