CREATE TABLE `domain_settings_options` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `id_setting_type` integer DEFAULT NULL
,  `name` char(64) NOT NULL
,  `value` varchar(255) NOT NULL
);
