CREATE TABLE `grant_types_alias` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(32) NOT NULL,
  `alias` char(32) NOT NULL,
  `enabled` int default NULL,
    UNIQUE(`name`,`alias`),
  PRIMARY KEY (`id`)
);
