CREATE TABLE `users` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` char(255) NOT NULL
,  `password` char(255) DEFAULT NULL
,  `change_password` integer DEFAULT 0
,  `is_admin` integer DEFAULT 0
,  `is_temporary` integer DEFAULT 0
,  `is_external` integer DEFAULT 0
,  `language` char(3) DEFAULT NULL
,   `date_created` timestamp default CURRENT_TIMESTAMP
,  UNIQUE (`name`)
);
