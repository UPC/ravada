create table vms (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `name` char(64) NOT NULL,
    `vm_type` char(20) NOT NULL,
    `hostname` varchar(128) NOT NULL,
    `default_storage` varchar(64) DEFAULT 'default',
    `security` varchar(20) default null,
    `is_active` int default 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `name` (`name`),
    UNIQUE KEY `hostname_type` (`hostname`,`vm_type`)
);
