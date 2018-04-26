CREATE TABLE `grant_types` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(32) NOT NULL,
  `description` varchar(255) NOT NULL,
  `enabled` int not null default 1,
    UNIQUE(`name`),
    UNIQUE(`description`),
  PRIMARY KEY (`id`)
);
