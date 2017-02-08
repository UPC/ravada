alter table messages add date_shown datetime;
update messages set date_shown=now();
