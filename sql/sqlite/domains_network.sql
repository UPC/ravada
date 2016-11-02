CREATE TABLE `domains_network` (
  `id` integer primary key AUTOINCREMENT,
  `id_domain` int(11) NOT NULL,
  `id_network` int(11) NOT NULL,
  `anonymous` int(11) NOT NULL DEFAULT '0',
  `allowed` int(11) NOT NULL DEFAULT '1'
);
