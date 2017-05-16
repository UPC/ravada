create table vms (
    `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,    `name` char(64) NOT NULL
,    `vm_type` char(20) NOT NULL DEFAULT 'KVM'
,    `hostname` varchar(128) NOT NULL
,    `default_storage` varchar(64) DEFAULT 'default'
,    `connection_args` text DEFAULT NULL
,    UNIQUE (`name`)
);
