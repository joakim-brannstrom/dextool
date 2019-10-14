# Mutant Schemata
This is the Mutant Schemata library for Dextool, used for speeding up mutation testing.

It injects all the mutants in the code, and then is able to dynamically activate a specific mutant when running the tests. This removes the need for compilation every time a mutant is introduced into the code (the traditional way of mutation testing).


## Mutation operators
Currently supported operators:
- Relational Operator Replacement (ROR)
- Arithmetic Operator Replacement (AOR)
- Logical Connector Replacement (LCR)


## Usage
To run Dextool using Mutant Schemata, first setup your project for traditional mutation testing according to [Dextool Mutate README](https://github.com/joakim-brannstrom/dextool/blob/master/plugin/mutate/README.md).

Analyze and generate mutants in the code:
```
dextool mutate analyze --schemata on
```
**Note:** you can change the *on* to pretty much anything, as long as you put something after the --schemata-flag

Test your generated mutants:
```
dextool mutate test --schemata on
```
**Note:** you can change the *on* to pretty much anything, as long as you put something after the --schemata-flag

Even if this library speeds up mutation testing considerably, the steps above will execute your tests *AMOUNT_OF_MUTANTS* number of times. For example, running the tests for Googletest takes about ~19 seconds, meaning that executing ~2500 mutants for Googletest would take ~13 hours (without overhead from db insertions and selections). ~19 seconds is also measured from terminal, but Dextool executes the test suite in a separate process (which usually takes much less time).

It is therefore recommended to restrict Dextool to certain files by using --restrict (either via flag or .toml-file).


## Code

### /source
Contains the .d-files for the api between Dextool and the Mutant Schemata implementation. Handles the database-connection, provides the ability to send Cpp-strings back and forth between D and C++, executes the compile and test execution commands provided by a user of Dextool Mutate, declares external types from cpp_source, declares internal types for the Mutant Schemata library and provides some utility functions for conversion and compilation_database.json-searches.
### /cpp_source
Contains the .cpp-files for the implemenation of Mutant Schemata, and the linkage to the .d-api. Handles the call from the api in order to setup clang and start the generation of mutants, contains the background functionality for the Cpp-string implementation, declares the internal types used by the api and conducts the analysis and generation of mutants itself.


# ! Disclaimer !
This library is an experimental version for the mutation testing plugin in Dextool.
