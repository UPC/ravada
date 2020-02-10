CREATE TABLE `domain_access` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11),
  `type` varchar(64),
  `attribute` varchar(64),
  `value` varchar(254),
  `allowed` int not null default 1,
  `n_order` int not null default 1,
  `last` int not null default 1,
  PRIMARY KEY (`id`)
);

