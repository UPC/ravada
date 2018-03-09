alter table domains add is_base int not null default 0;
alter table domains add is_public int not null default 0;
alter table domains add id_owner int not null default 0;
alter table domains change created created int not null default 0;
alter table domains add `file_screenshot` varchar(255) DEFAULT NULL;
alter table domains add vm char(120) not null;
alter table domains add id_base int;
alter table domains add description text;
update domains set is_public=1 where is_base=1;
