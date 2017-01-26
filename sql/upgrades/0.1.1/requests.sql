
alter table requests change error error text;
alter table requests change status status char(64);
