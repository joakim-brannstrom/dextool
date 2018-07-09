# Plugin eqdetect

This is the *eqdetect* plugin that detects equivalence mutants. The plugin is limited to be run directly after the plugin *mutate* has been used in order to utilize the generated database. *eqdetect* searches the database for alive mutants and extracts the code needed in order to run symbolic execution and constraint solving with KLEE.

## Dependencies

- KLEE symbolic execution and constraint solving (How to run [KLEE docker](http://klee.github.io/docker/))

# Equivalence detection on a project

This is an example of how to detect equivalence mutants in a project. It assumes the current directory is _build_ and that the generated dextool_mutation.sqlite3 database is located in the same _build_ directory.

Run *eqdetect*:
```sh
dextool eqdetect --in=dextool_mutation.sqlite3
```

## Flags

If the plugin is run on a project with several sourcefiles and subfolders, the plugin needs the specific include libraries in order to compile and traverse the code through the AST.

Example on usage with the include-flag:
```sh
dextool eqdetect --in=dextool_mutation.sqlite3 -- -I/path/to/include/library1/ -I/path/to/include/library2/
```

# Output

The plugin creates separate files for the mutant and the original source code in order to later include them in the generated file prepared for KLEE execution.

The files generated follow the following pattern:
- KLEE-files: *filename_klee_mutantID_mutantKind.cpp*
- Source-files: *filename_source_mutantID_mutantKind.cpp*
- Mutant-files: *filename_mutant_mutantID_mutantKind.cpp*

These files will be created in a directory where the plugin is run and will have the name *eqdetect_generated_files*.

# ! Disclaimer !

This plugin is under development and only works for specific functions that have been mutated in a specific way. The aim is to be able to conduct symbolic execution and constraint solving on every mutation generated in order to detect equivalence mutants.
