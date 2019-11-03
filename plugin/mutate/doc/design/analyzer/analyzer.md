# SPC-analyzer
partof: SPC-architecture
###
*Note: functional design*

See:
 - figures/analyse.pu : analyse a file for mutation points.

The purpose of this function is to analyze *a* file for mutations points.
It is the command centers that should provide the file to analyze.

## Requirements
The analyzer shall save the mutation points to the database when analyzing the provided file.

The analyzer shall save all *new* mutation point with status unknown.

### Incremental Mutation
The analyzer shall skip analysis of the provided file+compiler flags when the checksum exists in the database.

*Rationale: The purpose is to speed up analysis of source code that has already been analyzed and tested, incremental mutation*

# SPC-analyzer-checksum
partof: SPC-analyzer
###

The analyzer shall calculate and save two checksum for each file:
 - The compilation flags used to parse the file.
   Why? This is so a change in the compilation flags triggers a retest of the mutations.
   Flags can have a semantic effect on the code such as `#define`.
 - the content of the file.

## Style Stable Mutation Checksum

Change how the checksums are calculated to make it possible to format a file
without requiring a re-analyze -> test.

Current checksum structure:

 * file path
 * file content checksum
 * offset begin
 * offset end
 * source code mutation

Change to this:

 * checksum of the relative file path
 * checksum of all **relevant** tokens (e.g. remove comment tokens)
 * checksum of the number of tokens before the first token the mutant modify
 * source code mutation
 * checksum of the number of tokens after the last token the mutant modify

By removing the offset in the file the mutant become stable to style changes in
the source code. It is still guaranteed to be unique because the stream of
tokens are modified depending on what is changed in the file. This *encodes*
the offset via the injection of the source code mutant in the stream of tokens
when calculating the checksum.

**Note**: The path should be relative to make it possible to easier reuse the
database between parties. Such a reuse could be to download it from a CI server
to use locally by a user.

### TODO

Include the compiler flags in the checksum. Be wary of absolute paths. They may
make it hard to reuse databases between environments. Such as downloading the
database from the CI server to analyze and use locally.

# SPC-analyzer-reanalyze_files
partof: SPC-analyzer
###

The analyzer shall re-analyze _the_ file when it exists in the database but has a different checksum.

How?
 - Remove all mutations points from the old file.
 - Analyze the file anew and thus repopulating the mutation points.
 - Update the checksum of the file.

Why?
This will then trigger the mutation testers to retest all mutation points that exist in this specific file.

# SPC-analyzer-semantic_impact
partof: SPC-analyzer
###

TODO: add req.

## Design

Calculate how much have change in the LLVM IR for a mutant. The bigger the change is the semantic impact the mutant had and thus the more important it is that it is killed.

This probably need to be "weighted" against other mutants so it is *dynamic* for the specific program.

This should make it possible to statically find *semantically high impact mutants* cheaply. No need to even have a test suite.

# SPC-analyzer-junk_tests
partof: SPC-analyzer
###

The plugin shall report test cases that has killed zero mutants when the user requests such a report via the *CLI*.

# SPC-analyzer-understand
partof: REQ-uc_understand_analyze
###

The plugin shall print a message containing the root directory and restrictions when beginning analyze for mutants.

# REQ-mutant_analyze_speedup
partof: REQ-purpose
###

The user may have source code in its repository that is part of the build
system but that is uninteresting to perform mutation testing on. This code can
be of a significant size that negatively affects the performance of the plugin
when it is analysing the source code for mutants. This has an exceptional
negative impact when the user wants fast feedback from the mutation testing
when it is integrated in a pull request workflow.

It is thus important for the analysis phase to be as fast as possible but to
also provide the user with the needed tools to control what is analyzed.

# SPC-exclude_files_from_analysis
partof: REQ-mutant_analyze_speedup
###

The plugin shall exclude files from being analyzed based on a list of
directories/files to ignore when analysing for mutants.
