# Analyze {id="design-analyze"}

[partof](#spc-architecture)

See:
 - figures/analyse.pu : analyse a file for mutation points.

The purpose of this function is to analyze *a* file for mutations points.
It is the command centers that should provide the file to analyze.

## Requirements

The plugin shall analyze all files that have changed and save the result in the database.

## Incremental Mutation {id="spc-incremental_mutation"}

[partof](#req-early_validation)

The plugin shall support incremental mutation.

A change of one statement should only generate mutants for that change.

A change to a file should only generate mutants derived from that file.

#### Mutation Identifier {id="design-mutation_id"}

[partof](#spc-incremental_mutation)

A mutation ID should be deterministic between executions of the tool.
Deterministic mean that the same input irregardless of the order should result
in the same ID for a mutant. This mean that two users that invoke the plugin on
the same input should result in the identical identifiers for all mutants.

The ID is used by other parts of the tool to connect a status to a mutant, know
what file it is derived from and as an identifier for the user.

##### Checksum algorithm

The algorithm is a simple Merkel tree. It is based on [@thesis1, p. 27].
The hash algorithm used is murmurhash3 128-bit.

1. f. checksum of the filename.
2. s. checksum of all **relevant** tokens (e.g. remove comment tokens)
3. o1. checksum of the number of tokens before the first token the mutant modify
4. o2. checksum of the number of tokens after the last token the mutant modify
5. m. source code mutation
6. Final checksum of f+s+o1+o2+m

##### Future Improvements

The compiler flags strongly affects the semantic behavior of the source code.
This is so a change in the compilation flags triggers a retest of the
mutations.

 * add a configuration option for the user to let the flags be part of the
   checksum.

# SPC-analyzer-reanalyze_files

[partof](#spc-analyzer)

The analyzer shall re-analyze _the_ file when it exists in the database but has a different checksum.

How?
 - Remove all mutations points from the old file.
 - Analyze the file anew and thus repopulating the mutation points.
 - Update the checksum of the file.

Why?
This will then trigger the mutation testers to retest all mutation points that exist in this specific file.

# SPC-analyzer-semantic_impact

[partof](#spc-analyzer)

TODO: add req.

## Design

Calculate how much have change in the LLVM IR for a mutant. The bigger the change is the semantic impact the mutant had and thus the more important it is that it is killed.

This probably need to be "weighted" against other mutants so it is *dynamic* for the specific program.

This should make it possible to statically find *semantically high impact mutants* cheaply. No need to even have a test suite.

# SPC-analyzer-junk_tests

[partof](#spc-analyzer)

The plugin shall report test cases that has killed zero mutants when the user requests such a report via the *CLI*.

# SPC-analyzer-understand

[partof](#req-uc_understand_analyze)

The plugin shall print a message containing the root directory and restrictions when beginning analyze for mutants.

# REQ-mutant_analyze_speedup

[partof](#req-purpose)

The user may have source code in its repository that is part of the build
system but that is uninteresting to perform mutation testing on. This code can
be of a significant size that negatively affects the performance of the plugin
when it is analysing the source code for mutants. This has an exceptional
negative impact when the user wants fast feedback from the mutation testing
when it is integrated in a pull request workflow.

It is thus important for the analysis phase to be as fast as possible but to
also provide the user with the needed tools to control what is analyzed.

# SPC-exclude_files_from_analysis

[partof](#req-mutant_analyze_speedup)

The plugin shall exclude files from being analyzed based on a list of
directories/files to ignore when analysing for mutants.
