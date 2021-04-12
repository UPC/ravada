CREATE TABLE `users` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` char(255) NOT NULL,
  `password` char(255) DEFAULT NULL,
  `change_password` integer DEFAULT 0,
  `is_admin` integer DEFAULT 0,
  `is_temporary` integer DEFAULT 0,
  `is_external` integer DEFAULT 0,
  `language` char(3) DEFAULT NULL,
  `date_created` timestamp DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
)
  CHARACTER SET 'utf8';

