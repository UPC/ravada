CREATE TABLE `grants_user` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `id_user` int(11) NOT NULL,
  `id_grant` int(11) NOT NULL,
  `allowed` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE(`id_grant`,`id_user`)
);
