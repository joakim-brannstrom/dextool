# REQ-test_subset_of_mutants
partof: REQ-test_mutant
###

The user wants to integrate mutation testing in a pull request workflow where
time is crucial. The tool need to give feedback to the user within a short time
frame such as 10-30 minutes.

For this to work a number of tools need to be provided to the user.

 * a report of only a diff which contains some of the alive mutants.
 * The reported alive mutants should only be from the diff.
 * the plugin should only test a subset of the unknown mutants. Which ones are
   either specified manually by the user or read from a diff.

# SPC-test_mutants_on_specified_lines
partof: REQ-test_subset_of_mutants
###

The plugin shall only test the mutants on the `file:lines` that the user has
specified when running in test mode.

The plugin shall handle multiple `file:lines` at the same time via the CLI.

## Design Notes

The following is an excerp from git blame:
```
-L <start>,<end>, -L :<funcname>
    Annotate only the given line range. May be specified multiple times.
    Overlapping ranges are allowed.

    <start> and <end> are optional. “-L <start>” or “-L <start>,” spans from
    <start> to end of file. “-L ,<end>” spans from start of file to <end>.

    <start> and <end> can take one of these forms:

    *   number
        If <start> or <end> is a number, it specifies an absolute line number
        (lines count from 1).

    *   /regex/
        This form will use the first line matching the given POSIX regex. If
        <start> is a regex, it will search from the end of the previous -L
        range, if any, otherwise from the start of file. If <start> is
        “^/regex/”, it will search from the start of file. If <end> is a regex,
        it will search starting at the line given by <start>.

    *   +offset or -offset
        This is only valid for <end> and will specify a number of lines before
        or after the line given by <start>.

    If “:<funcname>” is given in place of <start> and <end>, it is a regular
    expression that denotes the range from the first funcname line that matches
    <funcname>, up to the next funcname line. “:<funcname>” searches from the
    end of the previous -L range, if any, otherwise from the start of file.
    “^:<funcname>” searches from the start of file.
```

The dextool mutate test CLI could be something like this to begin with.
```
-L <file>:<start>-<end>
    Annotate only the given line range. May be specified multiple times.
    Overlapping ranges are allowed.

    <file>, <start> and <end> are required.

    <start> and <end> can take one of these forms:

    *   number
        If <start> or <end> is a number, it specifies an absolute line number
        (lines count from 1).
```
