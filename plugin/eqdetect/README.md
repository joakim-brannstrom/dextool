# Plugin eqdetect

This is the *eqdetect* plugin that detects equivalence mutants.
The plugin is limited to be run directly after the plugin *mutate* has
been used in order to utilize the generated database. *eqdetect* searches
the database for alive mutants and extracts the code needed in order to
run symbolic execution and constraint solving with KLEE.

## Dependencies

- KLEE symbolic execution and constraint solving (How to run
    [KLEE docker](http://klee.github.io/docker/))
- dextool mutate analyze and mutation testing.

*eqdetect* is currently only tested on ubuntu. The following scripts
and commands is therefore written for that purpose.

# Equivalence detection on a project

This is an example of how to detect equivalence mutants in a project.
It assumes the current directory is _build_ and that the generated
dextool_mutation.sqlite3 database is located in the same _build_ directory.

In order for *eqdetect* to run KLEE in a docker, a bashscript is needed that
*eqdetect* will execute. Create and place the following script inside the
_build_ directory and name it _klee.sh_. *eqdetect* will then mount and execute
the script inside the docker, which will start the symbolic execution of
the current mutation.

_klee.sh_:
```
#!/bin/bash

pwd=$(pwd)
cd mounted/eqdetect_generated_files

for file_to_compile in *_klee_*;
do
    clang -I $pwd/klee_src/include/ -emit-llvm -c -g $file_to_compile
    file_to_run=$(ls | grep ".bc")
    klee -max-time=10 $file_to_run

    cd klee-out-0
    klee_fail_run=$(ls | grep ".err")

    if [[ $klee_fail_run = *".abort."* ]]
    then
        klee_fail_run=${klee_fail_run%%.*}
        klee_fail_out=$(ktest-tool --write-ints $klee_fail_run.ktest)

        echo "Abort:"$klee_fail_out >> ../../result.txt

    elif [[ $klee_fail_run = *".assert."* ]]
    then
        klee_fail_run=${klee_fail_run%%.*}
        klee_fail_out=$(ktest-tool --write-ints $klee_fail_run.ktest)

        echo "Assert:"$klee_fail_out >> ../../result.txt
    else
        klee_fail_run=$(ls | grep ".early")

        if [ $klee_fail_run ]
        then
            echo "Halt:"$file_to_compile >> ../../result.txt
        else
            echo "Eq:"$file_to_compile >> ../../result.txt
        fi

    fi

    cd ..
    rm $file_to_run
done

# remove the previously created temporary directory
rm -rf klee-out-* klee-last
```

Make _klee.sh_ executable:
```sh
chmod 755 klee.sh
```

Run *eqdetect*:
```sh
sudo dextool eqdetect --in=dextool_mutation.sqlite3
```

## Flags

If the plugin is run on a project with several sourcefiles and subfolders,
the plugin needs the specific include libraries in order to compile and
traverse the code through the AST.

Example on usage with the include-flag:
```sh
sudo dextool eqdetect --in=dextool_mutation.sqlite3 -- -I/path/to/include/library1/ -I/path/to/include/library2/
```

# Output

The plugin creates separate files for the mutant and the original source code
in order to later include them in the generated file prepared for KLEE execution.

The files generated follow the following pattern:
- KLEE-files: *filename_klee_mutantID_mutantKind.cpp*
- Source-files: *filename_source_mutantID_mutantKind.cpp*
- Mutant-files: *filename_mutant_mutantID_mutantKind.cpp*

These files will be created in a temporary directory called
*eqdetect_generated_files*. The files will be removed after every mutant along
with the directory.

# ! Disclaimer !

This plugin is under development and only works for specific functions that
have been mutated in a specific way. The aim is to be able to conduct symbolic
execution and constraint solving on every mutation generated in order to
detect equivalence mutants.
