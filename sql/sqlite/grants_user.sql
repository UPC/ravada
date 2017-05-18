CREATE TABLE `grants_user` (
  `id` integer NOT NULL primary key AUTOINCREMENT,
  `id_grant` integer not null,
  `id_user` integer not null,
  `allowed` integer not null default 0,
  UNIQUE (`id_grant`,`id_user`)
);
