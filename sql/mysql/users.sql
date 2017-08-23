CREATE TABLE `users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(255) NOT NULL,
  `password` char(255) DEFAULT NULL,
  `change_password` integer DEFAULT 1,
  `is_admin` integer DEFAULT 0,
  `is_temporary` integer DEFAULT 0,
  `is_external` integer DEFAULT 0,
  `language` char(3) DEFAULT NULL,
  `2fa` int(11) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
);
