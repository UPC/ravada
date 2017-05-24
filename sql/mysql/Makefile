SRC = $(wildcard *.sql)

DST = $(patsubst %.sql, ../sqlite/%.sql, $(SRC))

ALL: $(DST)

../sqlite/%.sql: %.sql
	mysql2sqlite $^ | egrep -v "(^PRAGMA|TRANSACTION)" | perl -ne 's/DEFAULT now\(\)/DEFAULT CURRENT_TIME/i; print $_' > $@

clean:
	rm $(SQL)
