CREATE TABLE iptables (
    id integer PRIMARY KEY AUTOINCREMENT 
,    id_domain int not null
,    id_user int not null
,    remote_ip char(16) not null
,    time_req datetime not null
,    time_deleted datetime 
,    iptables varchar(255) not null
);
