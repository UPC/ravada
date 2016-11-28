CREATE TABLE log_commands(
    id integer PRIMARY KEY AUTOINCREMENT 
,    id_domain int not null
,    id_user int not null
,    command char(32) not null
,    remote_ip char(16) not null
,    timereq datetime not null
,    iptables varchar(255) not null
);
