/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.fixtures;

import std.file : copy;
import std.stdio : File;
import std.format : format;

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
    string programCode = "program.cpp";
    string programBin = "program";
    string compileScript = "compile.sh";
    string testScript = "test.sh";
    string analyzeScript = "analyze.sh";

    void precondition(ref TestEnv testEnv) {
        compileScript = (testEnv.outdir ~ compileScript).toString;
        testScript = (testEnv.outdir ~ testScript).toString;
        programCode = (testEnv.outdir ~ programCode).toString;
        programBin = (testEnv.outdir ~ programBin).toString;
        analyzeScript = (testEnv.outdir ~ analyzeScript).toString;

        copy(programFile, programCode);

        File(compileScript, "w").write(format(scriptBuild, programCode, programBin));
        makeExecutable(compileScript);

        File(testScript, "w").write(scriptTest);
        makeExecutable(testScript);

        File(analyzeScript, "w").write(scriptAnalyzeTestOutput);
        makeExecutable(analyzeScript);
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
echo 1
exit 1
";
    }

    string scriptAnalyzeTestOutput() {
        // the test -e test that the output file has been created
        return "#!/bin/bash
set -e
test -e $1 && echo 'failed:Failed 42'
";
    }
}

class SimpleAnalyzeFixture : TestCase {
    auto precondition(ref TestEnv testEnv) {
        return makeDextoolAnalyze(testEnv).addInputArg(programFile).run;
    }

    string programFile() {
        return (testData ~ "report_one_ror_mutation_point.cpp").toString;
    }
}

/// Run the mutation analyze + test the mutants.
class MutantFixture : TestCase {
    /// Override with the file to mutate.
    string programFile() {
        return null;
    }

    /// Override with the operator to use.
    string op() {
        return null;
    }

    auto precondition(ref TestEnv testEnv) {
        makeDextoolAnalyze(testEnv).addInputArg(testData ~ programFile).run;

        auto r = makeDextool(testEnv).addArg(["test"]).addArg(["--mutant", op]).run;
        return r;
    }
}

class SchemataFixutre : SimpleFixture {
    override string programFile() {
        return (testData ~ "simple_schemata.cpp").toString;
    }

    override string scriptBuild() {
        return "#!/bin/bash
set -e
g++ %s -o %s
";
    }

    override string scriptTest() {
        return format("#!/bin/bash
set -e
%s
", programBin);
    }

    auto runDextoolTest(ref TestEnv testEnv, string[] args) {
        // dfmt off
        return dextool_test.makeDextool(testEnv)
            .setWorkdir(workDir)
            .args(["mutate"])
            .addArg(["test"])
            .addPostArg(args)
            .addPostArg(["--db", (testEnv.outdir ~ defaultDb).toString])
            .addPostArg(["--build-cmd", compileScript])
            .addPostArg(["--test-cmd", testScript])
            .addPostArg(["--test-timeout", "10000"])
            .addPostArg(["--only-schemata"])
            .addPostArg(["--use-schemata"])
            .addPostArg(["--log-schemata"])
            .run;
        // dfmt on
    }
}
