create table volumes (
    `id` integer NOT NULL AUTO_INCREMENT,
    `id_domain` integer NOT NULL,
    `name` char(64) NOT NULL,
    `file` varchar(255) NOT NULL,
    `n_order` integer NOT NULL,
    `info` TEXT,
    PRIMARY KEY (`id`),
    UNIQUE (`id_domain`,`name`),
    UNIQUE (`id_domain`,`n_order`)
);
