CREATE TABLE `users` (
  `id` integer primary key AUTOINCREMENT,
  `name` char(255) NOT NULL,
  `password` char(255) DEFAULT NULL,
  `change_password` char(1) DEFAULT 'N',
  UNIQUE (`name`)
);

