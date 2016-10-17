CREATE TABLE `networks` (
  `id` integer primary key AUTOINCREMENT,
  `name` varchar(32) NOT NULL,
  `address` varchar(32) NOT NULL,
  `description` varchar(140) DEFAULT NULL,
  `all_domains` int(11) DEFAULT '0'
  `no_domains` int(11) DEFAULT '0'
);
