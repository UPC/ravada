CREATE TABLE `networks` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(32) NOT NULL,
  `address` varchar(32) NOT NULL,
  `description` varchar(140) DEFAULT NULL,
  `all_domains` int(11) DEFAULT '0',
  `no_domains` int(11) DEFAULT '0',
  `requires_password` int(11) DEFAULT '0',
  `n_order` int(11) DEFAULT '0',
    unique(`address`),
    unique(`name`),
  PRIMARY KEY (`id`)
);
