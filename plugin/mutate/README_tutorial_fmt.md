# TMutation Testing of fmtlib

This tutorial demonstrate how to run dextool mutate on fmtlib. fmtlib uses
cmake as the build system and Googletest for the tests. Both these factors
makes it a perfect candidate for running dextool on.

First of all you need to get the source:

```sh
$ git clone https://github.com/fmtlib/fmt.git
$ cd fmt
```

We now need to configure dextool such that it knows about the tests, what type
of tests there are, what source code to mutate and the operators to use. Use
the admin command to initialize a default configuration:
```sh
$ dextool mutate admin --init
info: Using /home/foo/fmt/dextool_mutate.sqlite3
info: Wrote configuration to /home/foo/fmt/.dextool_mutate.toml
```

Open the configuration file `.dextool_mutate.toml`. See
[options](RADME_config.md) for an in depth explanation of them. Change the
following configuration parameters to this:

```toml
# we only want to mutate the source code in these two directories
restrict = ["src", "include"]

# this is where we will configure cmake to both build the lib and generate the
# compile_commands.json
search_paths = ["./build/compile_commands.json"]

# parallel build makes it faster
build_cmd = ["cd build && make -j3"]

# the test binaries are found here
test_cmd_dir = ["./build/bin"]

# activate the test output analyzer for googletest
analyze_using_builtin = ["gtest"]

# these are good options to have in case the tests change. It isnt really
# applicable for this tutorial but for your project they should be activated.
detected_new_test_case = "resetAlive"
detected_dropped_test_case = "remove"
oldest_mutants = "test"
oldest_mutants_percentage = 1.0
```

Now that the configuration is done we need to setup the build environment:

```sh
$ mkdir build
$ pushd build
$ cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON ..
$ make
$ popd
```

Dextool mutate first has to analyze the source code for mutants:

```sh
$ dextool mutate analyze --fast-db-store
info: Using /home/foo/fmt/dextool_mutate.sqlite3
info: Upgrading database from 0
info: Reading compilation database:
/home/foo/fmt/build/compile_commands.json
info: Analyze and mutation of files will only be done on those inside this directory root
info:   User input: .
info:   Real path: /home/foo/fmt
info: Restricting mutation to files in the following directory tree(s)
info:   User input: src
info:   Real path: /home/foo/fmt/src
info:   User input: include
info:   Real path: /home/foo/fmt/include
info: Analyzing /home/foo/fmt/src/format.cc
info: Analyzing /home/foo/fmt/src/os.cc
info: Removing metadata
info: Prune database of schemata created by an old version
info: Analyzing /home/foo/fmt/test/assert-test.cc
info: Analyzing /home/foo/fmt/test/ranges-test.cc
info: Analyzing /home/foo/fmt/test/os-test.cc
info: Analyzing /home/foo/fmt/test/chrono-test.cc
info: Analyzing /home/foo/fmt/test/scan-test.cc
info: Analyzing /home/foo/fmt/test/core-test.cc
info: Updating files
info: Analyzing /home/foo/fmt/test/header-only-test.cc
info: Saving /home/foo/fmt/include/fmt/core.h
info: Saving /home/foo/fmt/src/os.cc
info: Saving /home/foo/fmt/include/fmt/format.h
info: Saving /home/foo/fmt/include/fmt/os.h
info: Analyzing /home/foo/fmt/test/header-only-test2.cc
info: Analyzing /home/foo/fmt/test/test-main.cc
info: Analyzing /home/foo/fmt/test/format-impl-test.cc
info: Saving /home/foo/fmt/src/format.cc
info: Saving /home/foo/fmt/include/fmt/format-inl.h
info: Analyzing /home/foo/fmt/test/gtest-extra-test.cc
info: Analyzing /home/foo/fmt/test/gmock-gtest-all.cc
info: Saving /home/foo/fmt/include/fmt/ranges.h
info: Analyzing /home/foo/fmt/test/gtest-extra.cc
info: Analyzing /home/foo/fmt/test/util.cc
info: Analyzing /home/foo/fmt/test/locale-test.cc
info: Analyzing /home/foo/fmt/test/compile-test.cc
info: Saving /home/foo/fmt/include/fmt/args.h
info: Analyzing /home/foo/fmt/test/color-test.cc
info: Saving /home/foo/fmt/include/fmt/chrono.h
info: Saving /home/foo/fmt/include/fmt/locale.h
info: Analyzing /home/foo/fmt/test/ostream-test.cc
info: Analyzing /home/foo/fmt/test/posix-mock-test.cc
info: Analyzing /home/foo/fmt/test/format-test.cc
info: Analyzing /home/foo/fmt/test/printf-test.cc
info: Saving /home/foo/fmt/include/fmt/ostream.h
info: Saving /home/foo/fmt/include/fmt/printf.h
info: Saving /home/foo/fmt/include/fmt/compile.h
info: Saving /home/foo/fmt/include/fmt/color.h
info: Resetting timeout context
info: Updating metadata
info: Pruning the database of dropped files
info: Removing orphaned mutants
info: Prune the database of unused schemas
info: Updating manually marked mutants
info: Committing changes
info: Ok
```

To run a test phase and thus get some results:
```sh
$ dextool mutate test
info: Using /home/foo/fmt/dextool_mutate.sqlite3
info: mutation operators: lcr, lcrb, sdl, uoi, dcr
info: Initializing worklist
info: Checking that the file(s) on the filesystem match the database
info: Ok
info: Checking the build command
Scanning dependencies of target fmt
   <cmake build output>
info: Found test commands in ["./build/bin"]:
info: shell command '/home/foo/fmt/build/bin/header-only-test'
info: shell command '/home/foo/fmt/build/bin/posix-mock-test'
info: shell command '/home/foo/fmt/build/bin/assert-test'
info: shell command '/home/foo/fmt/build/bin/ranges-test'
info: shell command '/home/foo/fmt/build/bin/os-test'
info: shell command '/home/foo/fmt/build/bin/scan-test'
info: shell command '/home/foo/fmt/build/bin/format-impl-test'
info: shell command '/home/foo/fmt/build/bin/chrono-test'
info: shell command '/home/foo/fmt/build/bin/gtest-extra-test'
info: shell command '/home/foo/fmt/build/bin/core-test'
info: shell command '/home/foo/fmt/build/bin/locale-test'
info: shell command '/home/foo/fmt/build/bin/color-test'
info: shell command '/home/foo/fmt/build/bin/compile-test'
info: shell command '/home/foo/fmt/build/bin/ostream-test'
info: shell command '/home/foo/fmt/build/bin/format-test'
info: shell command '/home/foo/fmt/build/bin/printf-test'
info: Found new test case(s):
info: FileTest.Size
info: StreamingAssertionsTest.EXPECT_SYSTEM_ERROR
... <a list of all test cases>
info: Adding alive mutants to worklist
info: Measuring the runtime of the test command(s):
shell command '/home/foo/fmt/build/bin/header-only-test'
shell command '/home/foo/fmt/build/bin/posix-mock-test'
shell command '/home/foo/fmt/build/bin/assert-test'
shell command '/home/foo/fmt/build/bin/ranges-test'
shell command '/home/foo/fmt/build/bin/os-test'
shell command '/home/foo/fmt/build/bin/scan-test'
shell command '/home/foo/fmt/build/bin/format-impl-test'
shell command '/home/foo/fmt/build/bin/chrono-test'
shell command '/home/foo/fmt/build/bin/gtest-extra-test'
shell command '/home/foo/fmt/build/bin/core-test'
shell command '/home/foo/fmt/build/bin/locale-test'
shell command '/home/foo/fmt/build/bin/color-test'
shell command '/home/foo/fmt/build/bin/compile-test'
shell command '/home/foo/fmt/build/bin/ostream-test'
shell command '/home/foo/fmt/build/bin/format-test'
shell command '/home/foo/fmt/build/bin/printf-test'
info: 0: Measured test command runtime 8 secs, 977 ms, 760 μs, and 5 hnsecs
info: 1: Measured test command runtime 8 secs, 473 ms, 152 μs, and 7 hnsecs
info: 2: Measured test command runtime 9 secs, 475 ms, 10 μs, and 1 hnsec
info: Test command runtime: 8 secs, 975 ms, 307 μs, and 7 hnsecs
info: Schema -61227195788862402 has 118 mutants (threshold 3)
info: Use schema -61227195788862402 (148 left)
info: Injecting the schemata in:
info: /home/foo/fmt/include/fmt/format.h
info: Compile schema -61227195788862402
info: Skipping schema because it failed to compile
info: Schema -6494101575931241202 has 30 mutants (threshold 3)
info: Use schema -6494101575931241202 (147 left)
info: Injecting the schemata in:
info: /home/foo/fmt/include/fmt/format-inl.h
info: Compile schema -6494101575931241202
info: Ok
info: Sanity check of the generated schemata
info: Ok
info: 2906673553 from '(*c >> 11) == 0x1b' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2629:10
info: 2906673553 alive (604 ms, 795 μs, and 4 hnsecs)
info: 868953272 from '(*c >> 11) == 0x1b' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2629:10
info: 868953272 killed (486 ms, 511 μs, and 8 hnsecs)
info: 2732 killed by [ChronoTest.FormatWide]
info: 687979951 from 'n.exp_ > 0' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2673:9
info: 687979951 killed (685 ms, 549 μs, and 8 hnsecs)
info: 2757 killed by [BigIntTest.DivModAssign, BigIntTest.DivModAssignUnaligned]
info: 417090222 from 's.size() >= block_size' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2697:7
info: 417090222 alive (586 ms, 844 μs, and 9 hnsecs)
info: 3356717402 from '*c > 0x10FFFF' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2630:10
info: 3356717402 alive (634 ms, 310 μs, and 2 hnsecs)
info: 108620617 from 'i > 0' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2664:37
info: 108620617 killed (2 secs, 711 ms, 551 μs, and 4 hnsecs)
info: 2749 killed by [BigIntTest.Construct]
info: 3662328053 from 'sign == '-'' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2577:9
info: 3662328053 killed (522 ms, 453 μs, and 5 hnsecs)
info: 2703 killed by [AssertTest.Fail, FormatterTest.CenterAlign, FormatterTest.Fill, FormatterTest.FormatLongDouble, FormatterTest.HashFlag, FormatterTest.LeftAlign, FormatterTest.MinusSign, FormatterTest.PlusSign, FormatterTest.RightAlign, FormatterTest.SpaceSign, FormatterTest.ZeroFlag]
info: 4118349399 from '*fraction_end == '0'' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2582:14
info: Update test command order: "shell command '/home/foo/fmt/build/bin/format-impl-test':1.80", "shell command '/home/foo/fmt/build/bin/chrono-test':0.90", "shell command '/home/foo/fmt/build/bin/os-test':0.90", "shell command '/home/foo/fmt/build/bin/format-test':0.90", "shell command '/home/joker/src /cpp/fmtlib/build/bin/scan-test':0.00", "shell command '/home/foo/fmt/build/bin/gtest-extra-test':0.00", "shell command '/home/foo/fmt/build/bin/ostream-test':0.00", "shell command '/home/foo/fmt/build/bin/compile-test':0.00", "shell command '/home/foo/fmt/build/bin/header-only-test':0.00", "shell comman
d '/home/foo/fmt/build/bin/printf-test':0.00"
info: 4118349399 timeout (13 secs, 699 ms, 156 μs, and 4 hnsecs)
info: 3730676690 from 'i > 0' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2664:37
info: 3730676690 killed (2 secs, 448 ms, 855 μs, and 7 hnsecs)
info: 2750 killed by [BigIntTest.Construct, BigIntTest.DivModAssign, BigIntTest.DivModAssignUnaligned, BigIntTest.Multiply, BigIntTest.ShiftLeft, BigIntTest.Square]
info: 1020360778 from 's.size() >= block_size' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2697:7
info: 1020360778 killed (926 ms, 946 μs, and 8 hnsecs)
info: 2759 killed by [OStreamTest.BufferSize, UtilTest.UTF8ToUTF16]
info: 1770753976 from 'exp_pos != begin + 1' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2579:9
info: 1770753976 killed (506 ms, 431 μs, and 4 hnsecs)
info: 2706 killed by [BufferedFileTest.Fileno, FormatterTest.CenterAlign, FormatterTest.Fill, FormatterTest.FormatLongDouble, FormatterTest.HashFlag, FormatterTest.LeftAlign, FormatterTest.MinusSign, FormatterTest.PlusSign, FormatterTest.Precision, FormatterTest.RightAlign, FormatterTest.RuntimePrecision, FormatterTest.RuntimeWidth, FormatterTest.SpaceSig n, FormatterTest.Width, FormatterTest.ZeroFlag]
info: 2532087144 from 'format_str.size() == 2' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2744:7
info: 2532087144 alive (1 sec, 288 ms, 963 μs, and 4 hnsecs)
info: 1846365421 from 'result == 0' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2720:11
info: 1846365421 killed (502 ms, 619 μs, and 8 hnsecs)
info: 2773 killed by [BufferedFileTest.Fileno, UtilTest.FormatSystemError, UtilTest.SystemError]
info: 4185625654 from 'sign == '-'' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2577:9
info: 4185625654 alive (663 ms, 535 μs, and 4 hnsecs)
info: 2126232661 from '*fraction_end == '0'' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2582:14
info: 2126232661 killed (502 ms and 817 μs)
info: 2709 killed by [BufferedFileTest.Fileno, FormatterTest.CenterAlign, FormatterTest.Fill, FormatterTest.FormatLongDouble, FormatterTest.HashFlag, FormatterTest.LeftAlign, FormatterTest.MinusSign, FormatterTest.PlusSign, FormatterTest.RightAlign, FormatterTest.RuntimeWidth, FormatterTest.SpaceSign, FormatterTest.Width, FormatterTest.ZeroFlag]
info: 269736007 from 'format_str.size() == 2 && equal2(format_str.data(), "{}")' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2744:7
info: 269736007 killed (502 ms, 739 μs, and 7 hnsecs)
warning: A error encountered when trying to analyze the output from the test suite. Ignoring the offending line.
warning: Attempted to decode past the end of a string (at index 3)
warning: invalid UTF-8 sequence
warning: Unable to parse the buffered data for a newline. Ignoring the rest.
info: 2782 killed by [AssertionSyntaxTest.SystemErrorAssertionBehavesLikeSingleStatement, ChronoTest.Align, ChronoTest.FormatFullSpecs, ChronoTest.FormatFullSpecsQq, ChronoTest.FormatPrecision, ChronoTest.FormatPrecisionQq, ChronoTest.FormatSimpleQq, ChronoTest.FormatSpecs, ChronoTest.InvalidColons, ChronoTest.InvalidSpecs, ChronoTest.InvalidWidthId, Chro noTest.NegativeDurations, ChronoTest.SpecialDurations, ExpectSystemErrorTest.DoesNotGenerateUnreachableCodeWarning, ExpectTest.EXPECT_SYSTEM_ERROR, FormatTest.FormatErrorCode, FormatterTest.ArgErrors, FormatterTest.ArgsInDifferentPositions, FormatterTest.AutoArgIndex, FormatterTest.CenterAlign, FormatterTest.Escape, FormatterTest.Fill, FormatterTest.Forma tInt, FormatterTest.HashFlag, FormatterTest.LeftAlign, FormatterTest.ManyArgs, FormatterTest.MinusSign, FormatterTest.NamedArg, FormatterTest.NoArgs, FormatterTest.PlusSign, FormatterTest.Precision, FormatterTest.RightAlign, FormatterTest.RuntimePrecision, FormatterTest.RuntimeWidth, FormatterTest.SpaceSign, FormatterTest.UnmatchedBraces, FormatterTest.Wi dth, FormatterTest.ZeroFlag, OStreamTest.Format, OStreamTest.FormatSpecs, OutputRedirectTest.ErrorInDtor, OutputRedirectTest.FlushErrorInCtor, OutputRedirectTest.FlushErrorInRestoreAndRead, SingleEvaluationTest.FailedEXPECT_SYSTEM_ERROR, SingleEvaluationTest.SystemErrorTests, StreamingAssertionsTest.EXPECT_SYSTEM_ERROR, TimeTest.Format, TimeTest.TimePoint ]
info: 3747119599 from 'n.exp_ > 0' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2673:9
info: 3747119599 killed (569 ms, 887 μs, and 7 hnsecs)
info: 2756 killed by [BigIntTest.Construct, BigIntTest.DivModAssign, BigIntTest.Multiply, BigIntTest.ShiftLeft, BigIntTest.Square]
info: 1097226499 from '*c > 0x10FFFF' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2630:10
info: Update test command order: "shell command '/home/foo/fmt/build/bin/format-test':5.31", "shell command '/home/foo/fmt/build/bin/os-test':4.41", "shell command '/home/foo/fmt/build/bin/format-impl-test':4.32", "shell command '/home/foo/fmt/build/bin/chrono-test':1.71", "shell command '/home/joker/src /cpp/fmtlib/build/bin/gtest-extra-test':0.90", "shell command '/home/foo/fmt/build/bin/ostream-test':0.90", "shell command '/home/foo/fmt/build/bin/printf-test':0.90", "shell command '/home/foo/fmt/build/bin/scan-test':0.00", "shell command '/home/foo/fmt/build/bin/compile-test':0.00", "shell command '/h ome/foo/fmt/build/bin/header-only-test':0.00"
info: 1097226499 killed (502 ms, 512 μs, and 3 hnsecs)
info: 2735 killed by [BufferedFileTest.Fileno, ChronoTest.FormatWide, UtilTest.UTF8ToUTF16]
info: 604557903 from 'p - buf < num_chars_left' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2706:14
info: 604557903 killed (522 ms, 115 μs, and 4 hnsecs)
info: 2769 killed by [BufferedFileTest.Fileno, ChronoTest.FormatWide, UtilTest.UTF8ToUTF16]
info: 2374469645 from 'p < end' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2698:52
info: 2374469645 killed (693 ms, 983 μs, and 4 hnsecs)
info: 2762 killed by [AssertTest.Fail, UtilTest.UTF8ToUTF16]
info: 2799426689 from 'result == 0' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2720:11
info: 2799426689 alive (664 ms, 941 μs, and 7 hnsecs)
info: 3794231491 from 'p < end' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2698:52
info: 3794231491 killed (478 ms, 848 μs, and 7 hnsecs)
info: 2761 killed by [BufferedFileTest.Fileno, UtilTest.UTF8ToUTF16]
info: 1805951685 from 'exp_pos != begin + 1' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2579:9
info: 1805951685 killed (601 ms, 258 μs, and 3 hnsecs)
info: 2705 killed by [FormatterTest.Precision]
info: 722989516 from '*c < mins[len]' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2628:9
info: 722989516 alive (548 ms, 775 μs, and 1 hnsec)
info: 83950204 from '*c < mins[len]' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2628:9
info: 83950204 killed (484 ms, 308 μs, and 8 hnsecs)
info: 2729 killed by [ChronoTest.FormatWide, OStreamTest.BufferSize, UtilTest.UTF8ToUTF16]
info: 3721803321 from 'format_str.size() == 2' to 'true' in /home/foo/fmt/include/fmt/format-inl.h:2744:7
info: 3721803321 killed (463 ms, 554 μs, and 6 hnsecs)
info: 2780 killed by [FormatTest.Dynamic, FormatTest.JoinArg, FormatTest.UnpackedArgs, FormatTest.Variadic, FormatterTest.AutoArgIndex, FormatterTest.Examples, FormatterTest.NamedArg]
info: 2174711077 from 'format_str.size() == 2 && equal2(format_str.data(), "{}")' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2744:7
info: 2174711077 alive (764 ms, 735 μs, and 6 hnsecs)
info: 3470950578 from 'p - buf < num_chars_left' to 'false' in /home/foo/fmt/include/fmt/format-inl.h:2706:14
info: Update test command order: "shell command '/home/foo/fmt/build/bin/format-test':11.08", "shell command '/home/foo/fmt/build/bin/os-test':6.67", "shell command '/home/foo/fmt/build/bin/chrono-test':4.24", "shell command '/home/foo/fmt/build/bin/format-impl-test':3.89", "shell command '/home/joker/sr c/cpp/fmtlib/build/bin/assert-test':0.90", "shell command '/home/foo/fmt/build/bin/gtest-extra-test':0.81", "shell command '/home/foo/fmt/build/bin/ostream-test':0.81", "shell command '/home/foo/fmt/build/bin/printf-test':0.81", "shell command '/home/foo/fmt/build/bin/scan-test':0.00", "shell command '/h ome/foo/fmt/build/bin/compile-test':0.00"
info: 3470950578 killed (508 ms, 254 μs, and 3 hnsecs)
info: 2770 killed by [AssertTest.Fail, BufferedFileTest.Fileno, ChronoTest.FormatWide, UtilTest.UTF8ToUTF16]
info: 3631 mutants left to test. Estimated mutation score 0.696 (error 0.0196)

    <and more until all mutants are tested>
```

The line "info: Skipping schema because it failed to compile" is nothing to
worry about. There is a possibility that a schemata fail to compile because it
contains invalid code. This can be ignored.

You can check on the progress while it is running both by looking for the line
"... mutants left to test" and/or by generating a summary report.

```sh
$ dextool mutate report --section summary
info: Using /home/foo/fmt/dextool_mutate.sqlite3
Mutation operators: lcr, lcrb, sdl, uoi, dcr
info: Summary
Time spent:         35 secs and 326 ms
Remaining: 1 hour, 16 minutes, 21 secs, 25 ms, 6 μs, and 8 hnsecs (2020-12-24T15:53:18.5567919)

Score:              0.714
Trend Score:        0.676 (error:0.0186)
Total:              28
Untested:           3631
Alive:              8
Killed:             19
Timeout:            1
Killed by compiler: 0
Worklist:           3631
```

To run through all the mutants will take a while. A tip is to run multiple
workers in [parallel](README_parallel.md). When it is finally done you can
generate a HTML report for easier navigation of the mutants:

```sh
$ dextool mutate report --style html --section summary --section tc_stat --section tc_killed_no_mutants --section tc_unique --section score_history
info: Using /home/foo/fmt/dextool_mutate.sqlite3
info: Generating Statistics (stats)
info: Generating Long Term View (long_term_view)
info: Generating Test Case Statistics (test_case_stat)
info: Generating NoMut Details (nomut)
info: Generating Test Case Uniqueness (test_case_unique)
info: Generating Killed No Mutants Test Cases (killed_no_mutants_test_cases)
info: Generating Mutation Score History (score_history)

$ firefox html/index.html
```
