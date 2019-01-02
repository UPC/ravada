create table volumes (
    `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,    `id_domain` integer NOT NULL
,    `name` char(64) NOT NULL
,    `file` varchar(255) NOT NULL
,    `info` TEXT
,    UNIQUE (`id_domain`,`name`)
);
