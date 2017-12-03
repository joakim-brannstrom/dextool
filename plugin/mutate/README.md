# Admin and other fun stuff

To get the files in the database:
```sh
select * from files
```

To get mutants:
```sh
# tested mutations
sqlite3 dextool_mutate.sqlite3 "select * from mutation where status!=0"
# alive
sqlite3 dextool_mutate.sqlite3 "select * from mutation where status==2"
```

To get the location of alive mutants:
```sh
sqlite3 dextool_mutate.sqlite3 "select mutation.kind,mutation_point.offset_begin,mutation_point.offset_end,files.path from mutation,mutation_point,files where mutation.status==2 and mutation.mp_id==mutation_point.id and mutation_point.file_id=files.id"
```

To get the mutation points for a specific file:
```sh
sqlite3 dextool_mutate.sqlite3 "select mutation_point.id,mutation_point.offset_begin,mutation_point.offset_end from mutation_point,files where mutation_point.file_id==files.id and files.path==$(readlink -f myfile)"
```

Reset all mutations of a kind to unknown which forces them to be tested again:
```sh
sqlite3 dextool_mutate.sqlite3 "update mutation SET status=0 WHERE mutation.kind=FOO"
```

# Mutation testing google test

This is an example of how to mutation test google test itself.
It assumes the current directory is _build_ which is then located the google test repo.


Create a database of all mutation points:
```sh
cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..
dextool mutate --compile-db compile_commands.json --mode analyzer --restrict .. -- -D_POSIX_PATH_MAX=1024
```

Reconfigure and prebuild with the tests activated:
```sh
cmake -Dgtest_build_tests=ON -Dgmock_build_tests=ON ..
make
```

Create a file tester.sh with this content:
```sh
#!/bin/bash
set -e
make test ARGS="-j$(nproc)"
```

Create a file compile.sh with this content:
```sh
#!/bin/bash
set -e
make -j$(nproc)
```

Make them executable so they can be used by dextool:
```sh
chmod 755 tester.sh
chmod 755 compile.sh
```

Start mutation testing!!!!:
```sh
dextool_debug mutate --mode test_mutants --mutant-tester ./tester.sh --mutant-compile ./compile.sh --out .. --restrict ..
```
