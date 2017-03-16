create table vms (
    id integer NOT NULL PRIMARY KEY AUTOINCREMENT
,    name char(64) NOT NULL
,    vm_type char(20) NOT NULL
,    hostname varchar(128) NOT NULL
,    default_storage varchar(64) DEFAULT 'default'
,    UNIQUE (`name`)
);
