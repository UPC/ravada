alter table users add is_admin int not null default 0;
alter table users add is_temporary int not null default 0;
alter table users add is_first_time int not null default 1;
alter table users add change_password int not null default 0;

