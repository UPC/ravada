CREATE TABLE `access_ldap_attribute` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_domain` int(11),
  `attribute` varchar(64),
  `value` varchar(64),
  `allowed` int not null default 1,
  `n_order` int not null default 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `id_base` (`id_domain`,`attribute`,`value`)
);

