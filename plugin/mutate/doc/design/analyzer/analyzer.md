# SPC-plugin_mutate_analyzer
partof: SPC-plugin_mutate_architecture
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

# SPC-plugin_mutate_analyzer-checksum
partof: SPC-plugin_mutate_analyzer
###

The analyzer shall calculate and save two checksum for each file:
 - The compilation flags used to parse the file.
   Why? This is so a change in the compilation flags triggers a retest of the mutations.
   Flags can have a semantic effect on the code such as `#define`.
 - the content of the file.

# SPC-plugin_mutate_analyzer-reanalyze_files
partof: SPC-plugin_mutate_analyzer
###

The analyzer shall re-analyze _the_ file when it exists in the database but has a different checksum.

How?
 - Remove all mutations points from the old file.
 - Analyze the file anew and thus repopulating the mutation points.
 - Update the checksum of the file.

Why?
This will then trigger the mutation testers to retest all mutation points that exist in this specific file.
