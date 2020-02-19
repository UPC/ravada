CREATE TABLE `domain_access` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_domain` integer
,  `type` varchar(64)
,  `attribute` varchar(64)
,  `value` varchar(254)
,  `allowed` integer not null default 1
,  `n_order` integer not null default 1
,  `last` integer not null default 1
);
