all: sqlite3.o

sqlite3.o: c/sqlite3.c
	gcc -c -O2 -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_UNLOCK_NOTIFY c/sqlite3.c

clean:
	rm -f *.o