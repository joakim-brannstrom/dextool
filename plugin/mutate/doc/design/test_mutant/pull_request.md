# <a name="uc-pull_request"></a> Pull Request

The user wants to work with mutation testing integrated in a pull request
workflow.

In such a workflow time is **critical**. It is not acceptable that an
integration with the plugin lead to a *significant* slowdown thus the plugin must be
designed in such a way that it can give enough, relevant feedback on the pull
request *fast*.

The user also wants to be able to work with improving the mutation score of a
pull request. It is thus important that the user can identify alive mutants and
add/change test cases to kill them and this is reflected in an update of the
score for the pull request.

## <a name="req-test_subset_of_mutants"></a> Test Subset of Mutants

The user wants to integrate mutation testing in a pull request workflow where
time is crucial. The plugin need to give feedback to the user within a short time
frame such as 10-30 minutes.

For this to work a number of features need to be provided to the user.

 * a report of only a diff which contains some of the alive mutants.
 * The reported alive mutants should only be from the diff.
 * the plugin should only test a subset of the unknown mutants. Which ones are
   either specified manually by the user or read from a diff.

### <a name="design-test_mutants_on_specified_lines"></a> Test Mutants on Lines

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

## <a name="req-improve_pull_request_mutation_score"></a> Improve Mutation Score

The user wants to improve the mutation score of a pull request by killing alive
mutants. It is most probably so that it is specific mutants that have been
identified during a code review that the user or the team deem as "important"
to kill. It is thus important that the plugin allow a user to add test cases
that *may* kill the mutants and be able to check an updated mutation testing
report to see if they managed to kill them. The plugin must thus over a
timespan test the same mutants over and over in the pull request. In other
words deterministically choose the mutants for that pull request the same way.

This use case is in a way a contradiction to the need of a random sampling of
mutants in a pull request. A design to handle this must thus be *stable enough*
over a *period of time* such that the user can improve the pull request/handle
the feedback but change over time such that the sampling is *changed*.

A common practice is that a pull request should be active for at most a couple
of days. A user is expected to be working on the weekdays. Thus it can be
presumed that the stable period can, to begin with, set to a week. The seed for
the random sampling is changed each week. It is also not a catastrophe if the
mutants change. It is more an annoyance. But this "week long" stability should
mean that the annoyance is at most irritating. This can be alleviated in the
future by allowing the user to configure how long the stable period is.

It is important that the random sampling changes over time because otherwise
the tool would always choose the same mutants from a sorted array of mutants.

It is important that the user can manually specify a seed and "repeat" the same
sequence of mutants as e.g. a Jenkins server does.

### <a name="design-random_sampling_of_pull_request"></a> Stable Random Sampling of Pull Request

The plugin shall use the `pull_request_seed` when choosing the random sample of
mutants to test in a pull request.

The plugin shall use 42 + year + ISO week as the default value for
`pull_request_seed`.

The plugin shall use the seed as-is when the user specify it via the command
line interface.

The plugin shall print what seed is being used.
