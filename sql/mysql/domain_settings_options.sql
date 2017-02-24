CREATE TABLE `domain_settings_options` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_setting_type` int(11) DEFAULT NULL,
  `name` char(64) NOT NULL,
  `value` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
);
