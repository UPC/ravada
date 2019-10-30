create table storage_nodes (
    `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,    `id_node1` integer NOT NULL
,    `id_node2` integer NOT NULL
,    `is_shared` integer NOT NULL DEFAULT 1
,    UNIQUE (`id_node1`,`id_node2`)
);
