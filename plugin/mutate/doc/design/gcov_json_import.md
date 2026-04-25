# gcov JSON Import

This is a temporary development note for the gcov JSON import work. Its
purpose is to capture the problem, the chosen implementation, and what was
verified while the feature is being developed and reviewed.

It may be removed later, merged into longer-lived design documentation, or
rewritten once the feature and its final documentation have settled.

## Summary

This note records the full gcov JSON coverage import feature for
`mutate test`.

The goal of the feature is to let mutate use coverage that has already been
produced by a GCC/gcov-based build instead of always gathering coverage through
dextool's built-in source instrumentation.

At a high level the feature adds:

- an optional gcov JSON import path in `mutate test`
- CLI and TOML configuration for that import path
- translation from gcov line counts to dextool coverage data in SQLite
- fallback to the built-in instrumentation flow when gcov import is not used or
  cannot provide usable coverage
- precise line-based behavior for HTML/source reporting and `noCoverage`
  propagation when gcov import is used

## User-Facing Behavior

The gcov import path is optional.

If no gcov JSON input is configured:

- mutate behaves as before and gathers coverage with built-in instrumentation

If gcov JSON input is configured:

- mutate tries to import coverage from gcov `--json-format` output
- coverage use is enabled for `mutate test`, even when `[coverage].use` is not
  set explicitly
- if import succeeds, built-in instrumentation is skipped
- if import does not produce usable coverage, mutate warns and falls back to
  the built-in coverage flow when possible

The supported user-facing input forms are:

- `--gcov-json <path>` on the command line, repeatable for multiple inputs
- `[coverage].gcov_json` in TOML, as either a string or an array of strings
- a single gcov JSON file
- multiple gcov JSON files
- a directory containing `.gcov.json` and/or `.gcov.json.gz` files

## Overall Design

The feature fits into the existing coverage flow in `mutate test`.

Before the built-in coverage runtime is injected or otherwise prepared:

- if gcov JSON input is configured, the coverage FSM tries `ImportGcovJson`
- if gcov import succeeds, coverage collection is done
- otherwise the FSM continues into the existing built-in instrumentation path

This keeps gcov import as an additive feature rather than changing the default
coverage behavior.

## Database And Storage Model

The feature uses two representations of coverage:

1. region coverage in the existing coverage tables
2. imported line coverage in a separate table when gcov import is used

The existing region coverage tables are kept because they are already used by
the built-in instrumentation flow and by older coverage consumers.

A new table stores imported line coverage:

- table: `src_cov_imported_line`
- key shape: unique `(file_id, line)`
- status: boolean

This table is created for new databases and added for existing databases by a
schema migration.

## Import Behavior

When gcov JSON is imported:

- the importer accepts GCC `gcov --json-format` output
- relative paths, absolute paths, and `current_working_directory` are handled
  when resolving gcov source paths
- relative source paths without `current_working_directory` are resolved from
  the gcov JSON input file's directory
- the importer resolves gcov file entries to analyzed source files
- one imported line status is stored for each gcov line present in the input
- repeated line counts from multiple gcov JSON inputs are summed before
  coverage status is calculated
- `count > 0` becomes covered
- `count == 0` becomes non-covered
- missing gcov lines remain unknown
- region coverage is still derived from the imported line counts and written to
  the existing region coverage tables

Re-import clears old imported line coverage first, so the latest import wins.

The built-in instrumentation save path also clears imported line coverage, so a
later non-gcov run cannot accidentally reuse stale gcov line data.

## Validation And Fallback

The gcov import path is intentionally forgiving because it is optional and the
built-in instrumentation flow still exists.

When possible, malformed or unusable gcov input produces warnings and mutate
falls back to built-in coverage instead of terminating the whole run.

This includes cases such as:

- bad JSON
- missing `files`
- `files` that is not an array
- malformed individual file entries
- nonexistent inputs
- empty directories
- unsupported filenames
- no analyzed coverage regions
- no matching analyzed source files

## Precision Work

The first version of gcov import stored imported coverage only in the existing
region-based coverage tables. That was enough to guide mutation testing in
coarse regions, but it lost line precision.

In practice this meant that if a large analyzed region contained both covered
and uncovered lines, the HTML report could show the whole region as covered and
`noCoverage` propagation could treat uncovered lines as covered.

The motivating case was a small C++ sample where gcov reported an uncovered
line inside a function that otherwise had covered lines, but the HTML report
still showed that uncovered line as covered because the whole function region
had been reduced to a single covered status.

The precision fix keeps compatibility with the built-in instrumentation flow
while allowing gcov import consumers to prefer exact imported line data.

## Consumers Updated To Prefer Imported Line Coverage

### HTML Source Report

The HTML file report now checks for imported line coverage first.

If imported line coverage exists for a file:

- line classes come directly from imported line coverage

Otherwise:

- the old region-to-line projection is used

This keeps the built-in instrumentation path unchanged while making gcov import
precise in source views.

### No-Coverage Propagation

`noCoverage` propagation now prefers imported line coverage for files that have
it.

For a mutant range:

- if any known imported line in the range is covered, the mutant is not marked
  `noCoverage` by propagation
- if at least one known imported line exists in the range and none are
  covered, the mutant is `noCoverage`
- if no imported line exists in the range, coverage remains unknown

Files without imported line coverage still use the old region-based logic.

## Verification Performed

The implementation was verified with mutate integration tests over C++ sample
inputs.

Added or extended integration coverage includes:

- built-in instrumentation is still used when `--gcov-json` is not configured
- gcov import bypasses built-in instrumentation when configured
- gcov JSON configuration enables coverage use from both CLI and TOML
- CLI and TOML configuration both work
- `.gcov.json`, `.gcov.json.gz`, and directory inputs work
- relative paths, absolute paths, and `current_working_directory` work
- numeric line/count fields may be JSON numbers or strings
- duplicate line counts across inputs are merged
- `count > 0`, `count == 0`, and missing lines map to covered, non-covered, and
  unknown
- re-import replaces old imported coverage instead of accumulating stale data
- failure cases warn and fall back when possible
- HTML reporting uses imported line precision
- `noCoverage` propagation uses imported line precision

## Commands Used For Verification

Unit tests may be run in parallel:

```sh
cmake --build build-test --target mutate_unittest__run --parallel
```

Integration tests should be run sequentially to avoid excessive memory use:

```sh
cmake --build build-test --target dextool_debug-mutate_integration__run -j1
```

If the build tree has been interrupted and the linker reports stale or invalid
objects, a clean sequential rebuild of the mutate binary has been enough:

```sh
cmake --build build-test --target dextool_debug-mutate --clean-first -j1
```

## Optional Manual Checks

The automated tests cover the core behavior with generated gcov JSON. Optional
extra manual checking can still be useful with a real GCC/gcov-producing C++
sample:

- generate gcov JSON with both covered and uncovered lines inside the same
  analyzed function
- run analyze + mutate test with `--gcov-json`
- generate the HTML report
- confirm that covered and uncovered lines inside the same analyzed function are
  shown with different coverage classes

## Scope

This note covers the full gcov JSON import feature in the branch, including the
later precision work for reporting and `noCoverage`.

The built-in instrumentation coverage path remains region-based and unchanged in
behavior, except that it now clears any previously imported gcov line coverage
before saving fresh built-in coverage results.
