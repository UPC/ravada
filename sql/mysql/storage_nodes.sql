create table storage_nodes (
    `id` integer NOT NULL AUTO_INCREMENT,
    `id_node1` integer NOT NULL,
    `id_node2` integer NOT NULL,
    `dir` varchar(255) NOT NULL,
    `is_shared` integer NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    UNIQUE (`id_node1`,`id_node2`, `dir`)
);


