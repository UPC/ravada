CREATE TABLE `messages` (
  `id` integer primary key AUTOINCREMENT,
  `id_user` int(11) NOT NULL,
  `id_request` int,
  `subject` varchar(120) DEFAULT NULL,
  `message` text DEFAULT '',
  `date_send` datetime default now,
  `date_read` datetime
);
