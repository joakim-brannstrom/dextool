/**
Copyright: Copyright (c) 2019, Niklas Pettersson. All rights reserved.
License: MPL-2
Author: Niklas Pettersson (nikpe353@student.liu.se)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Meant to function as an api for schemata using and providing schemata with a db
*/
module mutantschemata.api;

import mutantschemata.d_string : cppToD, dToCpp;
import mutantschemata.externals;
import mutantschemata.utility : findInclude, sanitize, convertToFs;
import mutantschemata.db_handler;
import mutantschemata.type;
import mutantschemata.execute;

import dextool.type : AbsolutePath, Path, ExitStatusType;
import dextool.compilation_db : CompileCommandDB;
import dextool.plugin.mutate.config : ConfigMutationTest;
import dextool.plugin.mutate.backend.watchdog : StaticTime, ProgressivWatchdog;

import std.array : Appender, join;
import std.conv : to;
import std.datetime.stopwatch : StopWatch;
import core.time : dur;

import logger = std.experimental.logger;

const string STATUS_UNKNOWN = "status = 0";

// Halt execution of mutants
ExitStatusType stopSchemata(string msg) {
    logger.error(msg);
    logger.error("Stopping execution of mutants");
    return ExitStatusType.Errors;
}
// Entry point for Dextool mutate
SchemataApi makeSchemataApi(SchemataInformation si) @trusted {
    SchemataApi sa = new SchemataApi(si);
    sa.apiBuildMutant(); // Create table if it does not exist, do nothing otherwise
    return sa;
}

// D class, connection to C++ code in /cpp_source
extern (C++) class SchemataApi : SchemataApiCpp {
    private DBHandler handler;
    private CompileCommandDB ccdb;
    private AbsolutePath ccdbPath;
    private AbsolutePath mainFile;
    private Appender!(Path[]) files_appender;

    this(SchemataInformation si) {
        handler = DBHandler(si.databasePath);
        ccdb = si.compileCommand;
        ccdbPath = si.compileCommandPath;
    }

    // Override of functions in external interface
    void apiInsertSchemataMutant(SchemataMutant sm) {
        handler.insertInDB(sm);
    }

    SchemataMutant apiSelectSchemataMutant(CppStr cs) {
        return sanitize(handler.selectFromDB(cppToD!CppStr(cs)));
    }

    void apiBuildMutant() {
        handler.buildSchemaDB();
    }

    void apiDeleteMutant(CppStr cs) {
        handler.deleteInDB(cppToD!CppStr(cs));
    }

    void apiClose() @trusted {
        handler.closeDB();
    }

    // Functions not callable from the Cpp-side
    SchemataMutant[] selectUnknownMutants() {
        return handler.selectFromDB(STATUS_UNKNOWN);
    }

    void updateMutant(SchemataMutant sm) {
        handler.insertOrReplaceInDB(sm);
    }

    void addFileToMutate(Path file) @trusted {
        files_appender.put(file);
    }

    void runSchemataAnalyzer(AbsolutePath restrictedPath) @trusted {
        logger.info("Mutating the following file and all of it's includes: ");
        runSchemataCpp(this, dToCpp(files_appender.data.join(",")),
                dToCpp(ccdbPath), dToCpp(restrictedPath));
    }
}

bool initEnvironmentVariable() {
    return setEnvironmentVariable(dToCpp(MUTANT_NR), dToCpp("0")) == 0;
}

ExitStatusType runSchemataTester(SchemataApi sa, ConfigMutationTest config) @trusted {
    // Initialize
    if (!initEnvironmentVariable())
        return stopSchemata("Initializing environment variable MUTANT_NR failed");
    logger.info("Preparing for mutation testing by checking that the program and tests compile without any errors (all mutants injected)");

    // Compile
    auto compile = preCompileSut(config);
    if (compile.status != 0)
        return stopSchemata("Compiler command failed");
    logger.info("Compiled successfully");

    // Measure test suite
    auto test = measureTestDuration(config.mutationTester);
    if (test.status != ExitStatusType.Ok)
        return stopSchemata("Measuring testsuite failed");
    logger.info("Test execution successfull");

    // Set stopWatch and fetch unknown Mutants
    long timeout = 10 * test.runtime.total!"msecs";
    auto stopWatch = StaticTime!StopWatch(timeout.dur!"msecs");
    auto mutants = sa.selectUnknownMutants();

    // Set environment variable, run the tests again and update the mutant
    foreach (m; mutants) {
        auto envRes = setEnvironmentVariable(dToCpp(MUTANT_NR), dToCpp(to!string(m.mut_id)));
        if (envRes != 0)
            return stopSchemata("Setting environment variable MUTANT_NR failed");

        m.status = schemataTester(config, stopWatch);
        sa.updateMutant(m);
    }

    logger.info("All unknown mutants tested!");
    return ExitStatusType.Ok;
}
