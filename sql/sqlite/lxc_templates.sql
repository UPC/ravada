CREATE TABLE `lxc_templates` (
  `id` integer primary key AUTOINCREMENT,
  `name` char(64) NOT NULL,
  `description` varchar(355),
  `arch` char(8)
);
