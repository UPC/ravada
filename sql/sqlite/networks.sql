CREATE TABLE `networks` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` varchar(32) NOT NULL
,  `address` varchar(32) NOT NULL
,  `description` varchar(140) DEFAULT NULL
,  `all_domains` integer DEFAULT '0'
,  `no_domains` integer DEFAULT '0'
,  `n_order` integer DEFAULT '0'
);
