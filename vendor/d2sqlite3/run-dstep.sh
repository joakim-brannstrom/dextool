dstep --package "d2sqlite3" --skip SQLITE_STDCALL --global-attribute={nothrow,@nogc} --space-after-function-name=false -o source/d2sqlite3/sqlite3.d c/sqlite3.h
sed -i '' '1i\
/++ Auto-generated C API bindings. +/\
' source/d2sqlite3/sqlite3.d
