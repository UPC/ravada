CREATE TABLE `access_ldap_attribute` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_domain` integer
,  `attribute` varchar(64)
,  `value` varchar(64)
,  `allowed` integer not null default 1
,  `n_order` integer not null default 1
,  `last` integer not null default 1
,  UNIQUE (`id_domain`,`attribute`,`value`)
);
