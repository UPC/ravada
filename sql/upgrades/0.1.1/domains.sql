alter table domains add is_public int not null default 0;
update domains set is_public=1 where is_base=1;
