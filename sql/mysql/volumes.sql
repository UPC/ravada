create table volumes (
    `id` integer NOT NULL AUTO_INCREMENT,
    `id_domain` integer NOT NULL,
    `name` char(64) NOT NULL,
    `file` varchar(255) NOT NULL,
    `info` TEXT,
    PRIMARY KEY (`id`),
    UNIQUE (`id_domain`,`name`)
);
