/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.fixtures;

import dextool_test.utility;

/// Fejk database entries
class DatabaseFixture : TestCase {
    import dextool.plugin.mutate.backend.database.standalone : Database;

    string databaseFile;

    Database precondition(ref TestEnv testEnv) {
        makeDextoolAnalyze(testEnv).addInputArg(programFile).run;
        databaseFile = (testEnv.outdir ~ defaultDb).toString;
        return Database.make(databaseFile);
    }

    string programFile() {
        return (testData ~ "report_one_ror_mutation_point.cpp").toString;
    }
}

/// Input is a file with about one mutation point in it.
class SimpleFixture : TestCase {
    string program_cpp;
    string program_bin;
    string compile_script;
    string test_script;
    string analyze_script;

    void precondition(ref TestEnv testEnv) {
        compile_script = (testEnv.outdir ~ "compile.sh").toString;
        test_script = (testEnv.outdir ~ "test.sh").toString;
        program_cpp = (testEnv.outdir ~ "program.cpp").toString;
        program_bin = (testEnv.outdir ~ "program").toString;
        analyze_script = (testEnv.outdir ~ "analyze.sh").toString;

        copy(programFile, program_cpp);

        File(compile_script, "w").write(format(scriptBuild, program_cpp, program_bin));
        makeExecutable(compile_script);

        File(test_script, "w").write(scriptTest);
        makeExecutable(test_script);

        File(analyze_script, "w").write(scriptAnalyzeTestOutput);
        makeExecutable(analyze_script);
    }

    string programFile() {
        return (testData ~ "report_one_ror_mutation_point.cpp").toString;
    }

    string scriptBuild() {
        return "#!/bin/bash
set -e
g++ -fsyntax-only -c %s -o %s
";
    }

    string scriptTest() {
        return "#!/bin/bash
exit 1
";
    }

    string scriptAnalyzeTestOutput() {
        // the test -e test that the output file has been created
        return "#!/bin/bash
set -e
test -e $1 && echo 'Failed 42'
";
    }
}
