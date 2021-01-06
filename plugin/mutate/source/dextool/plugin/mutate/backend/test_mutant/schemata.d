/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant.schemata;

import logger = std.experimental.logger;
import std.algorithm : sort, map, filter;
import std.array : empty, array, appender;
import std.conv : to;
import std.datetime : Duration;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.exception : collectException;
import std.format : format;
import std.typecons : Tuple;

import proc : DrainElement;
import sumtype;
import blob_model;

import my.fsm : Fsm, next, act, get, TypeDataMap;
import my.path;
import my.set;
static import my.fsm;

import dextool.plugin.mutate.backend.database : MutationStatusId, Database,
    spinSql, SchemataId, Schemata;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner, TestResult;
import dextool.plugin.mutate.backend.type : Mutation, TestCase, Checksum;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin, ShellCommand;

@safe:

struct SchemataTestDriver {
    private {
        /// True as long as the schemata driver is running.
        bool isRunning_ = true;
        bool hasFatalError_;

        FilesysIO fio;

        Database* db;

        /// Runs the test commands.
        TestRunner* runner;

        Mutation.Kind[] kinds;

        SchemataId schemataId;

        /// Result of testing the mutants.
        MutationTestResult[] result_;

        /// Time it took to compile the schemata.
        Duration compileTime;
        StopWatch swCompile;

        // Write the instrumented source code to .cov.<ext> for separate
        // inspection.
        const bool log;

        ShellCommand buildCmd;
        Duration buildCmdTimeout;

        /// The full schemata that is used..
        Schemata schemata;

        AbsolutePath[] modifiedFiles;

        Set!AbsolutePath roots;
    }

    static struct None {
    }

    static struct Initialize {
        bool error;
    }

    static struct InitializeRoots {
        bool hasRoot;
    }

    static struct InjectSchema {
        bool error;
    }

    static struct Compile {
        bool error;
    }

    static struct Done {
    }

    static struct Restore {
        bool error;
    }

    static struct NextMutantData {
        /// Mutants to test.
        InjectIdResult mutants;
    }

    static struct NextMutant {
        bool done;
        InjectIdResult.InjectId inject;
    }

    static struct TestMutantData {
        /// If the user has configured that the test cases should be analyzed.
        bool hasTestCaseOutputAnalyzer;
    }

    static struct TestMutant {
        InjectIdResult.InjectId inject;

        MutationTestResult result;
        bool hasTestOutput;
        // if there are mutants status id's related to a file but the mutants
        // have been removed.
        bool mutantIdError;
    }

    static struct TestCaseAnalyzeData {
        TestCaseAnalyzer* testCaseAnalyzer;
        DrainElement[] output;
    }

    static struct TestCaseAnalyze {
        MutationTestResult result;
        bool unstableTests;
    }

    static struct StoreResult {
        MutationTestResult result;
    }

    alias Fsm = my.fsm.Fsm!(None, Initialize, InitializeRoots, Done, NextMutant,
            TestMutant, TestCaseAnalyze, StoreResult, InjectSchema, Compile, Restore);
    alias LocalStateDataT = Tuple!(TestMutantData, TestCaseAnalyzeData, NextMutantData);

    private {
        Fsm fsm;
        TypeDataMap!(LocalStateDataT, TestMutant, TestCaseAnalyze, NextMutant) local;
    }

    this(FilesysIO fio, TestRunner* runner, Database* db, TestCaseAnalyzer* testCaseAnalyzer,
            SchemataId id, Mutation.Kind[] kinds, ShellCommand buildCmd,
            Duration buildCmdTimeout, bool log) {
        this.fio = fio;
        this.runner = runner;
        this.db = db;
        this.schemataId = id;
        this.kinds = kinds;
        this.buildCmd = buildCmd;
        this.buildCmdTimeout = buildCmdTimeout;
        this.log = log;

        this.local.get!TestCaseAnalyze.testCaseAnalyzer = testCaseAnalyzer;
        this.local.get!TestMutant.hasTestCaseOutputAnalyzer = !testCaseAnalyzer.empty;
    }

    static void execute_(ref SchemataTestDriver self) @trusted {
        self.fsm.next!((None a) => fsm(Initialize.init), (Initialize a) {
            if (a.error)
                return fsm(Done.init);
            return fsm(InitializeRoots.init);
        }, (InitializeRoots a) {
            if (a.hasRoot)
                return fsm(InjectSchema.init);
            return fsm(Done.init);
        }, (InjectSchema a) {
            if (a.error)
                return fsm(Restore.init);
            return fsm(Compile.init);
        }, (Compile a) {
            if (a.error)
                return fsm(Restore.init);
            return fsm(NextMutant.init);
        }, (NextMutant a) {
            if (a.done)
                return fsm(Restore.init);
            return fsm(TestMutant(a.inject));
        }, (TestMutant a) {
            if (a.mutantIdError)
                return fsm(NextMutant.init);
            if (a.result.status == Mutation.Status.killed
                && self.local.get!TestMutant.hasTestCaseOutputAnalyzer && a.hasTestOutput) {
                return fsm(TestCaseAnalyze(a.result));
            }
            return fsm(StoreResult(a.result));
        }, (TestCaseAnalyze a) {
            if (a.unstableTests)
                return fsm(NextMutant.init);
            return fsm(StoreResult(a.result));
        }, (StoreResult a) => fsm(NextMutant.init), (Restore a) => Done.init, (Done a) => a);

        debug logger.trace("state: ", self.fsm.logNext);
        self.fsm.act!(self);
    }

nothrow:

    MutationTestResult[] result() {
        return result_;
    }

    void execute() {
        try {
            execute_(this);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    bool hasFatalError() {
        return hasFatalError_;
    }

    bool isRunning() {
        return isRunning_;
    }

    void opCall(None data) {
    }

    void opCall(ref Initialize data) {
        swCompile = StopWatch(AutoStart.yes);

        InjectIdBuilder builder;
        foreach (mutant; spinSql!(() => db.getSchemataMutants(schemataId, kinds))) {
            auto cs = spinSql!(() { return db.getChecksum(mutant); });
            if (!cs.isNull) {
                builder.put(mutant, cs.get);
            }
        }
        debug logger.trace(builder).collectException;

        local.get!NextMutant.mutants = builder.finalize;

        schemata = spinSql!(() => db.getSchemata(schemataId)).get;

        try {
            modifiedFiles = schemata.fragments.map!(a => fio.toAbsoluteRoot(a.file))
                .toSet.toRange.array;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            hasFatalError_ = true;
            data.error = true;
        }
    }

    void opCall(ref InitializeRoots data) {
        auto allRoots = () {
            AbsolutePath[] tmp;
            try {
                tmp = spinSql!(() => db.getRootFiles).map!(a => db.getFile(a).get)
                    .map!(a => fio.toAbsoluteRoot(a))
                    .array;
                if (tmp.empty) {
                    // no root found. Inject the runtime in all files and "hope for
                    // the best". it will be less efficient but the weak symbol
                    // should still mean that it link correctly.
                    tmp = modifiedFiles;
                }
            } catch (Exception e) {
                logger.error(e.msg).collectException;
            }
            return tmp;
        }();

        auto mods = modifiedFiles.toSet;
        foreach (r; allRoots) {
            if (r !in mods) {
                modifiedFiles ~= r;
            }
            roots.add(r);
        }

        data.hasRoot = !roots.empty;

        if (roots.empty) {
            logger.warning("No root file found to inject the schemata runtime in").collectException;
        }
    }

    void opCall(Done data) {
        isRunning_ = false;
    }

    void opCall(ref InjectSchema data) {
        import std.path : extension, stripExtension;
        import dextool.plugin.mutate.backend.database.type : SchemataFragment;

        scope (exit)
            schemata = Schemata.init; // release the memory back to the GC

        Blob makeSchemata(Blob original, SchemataFragment[] fragments, Edit extra) {
            auto edits = appender!(Edit[])();
            edits.put(extra);
            foreach (a; fragments) {
                edits ~= new Edit(Interval(a.offset.begin, a.offset.end), a.text);
            }
            auto m = merge(original, edits.data);
            return change(new Blob(original.uri, original.content), m.edits);
        }

        SchemataFragment[] fragments(Path p) {
            return schemata.fragments.filter!(a => a.file == p).array;
        }

        try {
            foreach (f; modifiedFiles) {
                auto extra = () {
                    if (f in roots) {
                        logger.trace("Injecting schemata runtime in ", f);
                        return makeRootImpl;
                    }
                    return makeHdr;
                }();

                logger.info("Injecting schema in ", f);

                // writing the schemata.
                auto s = makeSchemata(fio.makeInput(f), fragments(fio.toRelativeRoot(f)), extra);
                fio.makeOutput(f).write(s);

                if (log) {
                    const ext = f.toString.extension;
                    fio.makeOutput(AbsolutePath(format!"%s.%s.schema%s"(f.toString.stripExtension,
                            schemataId.get, ext).Path)).write(s);

                    fio.makeOutput(AbsolutePath(format!"%s.%s.kinds.txt"(f,
                            schemataId.get).Path)).write(format("%s", kinds));
                }
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            data.error = true;
        }
    }

    void opCall(ref Compile data) {
        import colorlog;
        import dextool.plugin.mutate.backend.test_mutant.common : compile;

        logger.infof("Compile schema %s", schemataId.get).collectException;

        compile(buildCmd, buildCmdTimeout, log).match!((Mutation.Status a) {
            data.error = true;
        }, (bool success) { data.error = !success; });

        if (data.error) {
            logger.info("Skipping schema because it failed to compile".color(Color.yellow))
                .collectException;
            spinSql!(() { db.markUsed(schemataId); });
            return;
        }

        logger.info("Ok".color(Color.green)).collectException;

        try {
            logger.info("Sanity check of the generated schemata");
            auto res = runner.run;
            data.error = res.status != TestResult.Status.passed;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }

        if (data.error) {
            logger.info("Skipping the schemata because the test suite failed".color(Color.yellow))
                .collectException;
            spinSql!(() { db.markUsed(schemataId); });
        } else {
            logger.info("Ok".color(Color.green)).collectException;
        }

        compileTime = swCompile.peek;
    }

    void opCall(ref NextMutant data) {
        data.done = local.get!NextMutant.mutants.empty;

        if (!data.done) {
            data.inject = local.get!NextMutant.mutants.front;
            local.get!NextMutant.mutants.popFront;
        }
    }

    void opCall(ref TestMutant data) {
        import std.datetime.stopwatch : StopWatch, AutoStart;
        import dextool.plugin.mutate.backend.analyze.pass_schemata : schemataMutantEnvKey,
            checksumToId;
        import dextool.plugin.mutate.backend.generate_mutant : makeMutationText;

        auto sw = StopWatch(AutoStart.yes);

        data.result.id = data.inject.statusId;

        auto id = spinSql!(() { return db.getMutationId(data.inject.statusId); });
        if (id.isNull) {
            data.mutantIdError = true;
            return;
        }
        auto entry_ = spinSql!(() { return db.getMutation(id.get); });
        if (entry_.isNull) {
            data.mutantIdError = true;
            return;
        }
        auto entry = entry_.get;

        try {
            const file = fio.toAbsoluteRoot(entry.file);
            auto txt = makeMutationText(fio.makeInput(file), entry.mp.offset,
                    entry.mp.mutations[0].kind, entry.lang);
            debug logger.trace(entry);
            logger.infof("%s from '%s' to '%s' in %s:%s:%s", data.inject.injectId,
                    txt.original, txt.mutation, file, entry.sloc.line, entry.sloc.column);
        } catch (Exception e) {
            logger.info(e.msg).collectException;
        }

        runner.env[schemataMutantEnvKey] = data.inject.injectId.to!string;
        scope (exit)
            runner.env.remove(schemataMutantEnvKey);

        auto res = runTester(*runner);
        data.result.profile = MutantTimeProfile(compileTime, sw.peek);
        // the first tested mutant also get the compile time of the schema.
        compileTime = Duration.zero;

        data.result.mutId = id;
        data.result.status = res.status;
        data.result.exitStatus = res.exitStatus;
        data.hasTestOutput = !res.output.empty;
        local.get!TestCaseAnalyze.output = res.output;

        logger.infof("%s %s:%s (%s)", data.inject.injectId, data.result.status,
                data.result.exitStatus.get, data.result.profile).collectException;
    }

    void opCall(ref TestCaseAnalyze data) {
        try {
            auto analyze = local.get!TestCaseAnalyze.testCaseAnalyzer.analyze(
                    local.get!TestCaseAnalyze.output);
            local.get!TestCaseAnalyze.output = null;

            analyze.match!((TestCaseAnalyzer.Success a) {
                data.result.testCases = a.failed;
            }, (TestCaseAnalyzer.Unstable a) {
                logger.warningf("Unstable test cases found: [%-(%s, %)]", a.unstable);
                logger.info(
                    "As configured the result is ignored which will force the mutant to be re-tested");
                data.unstableTests = true;
            }, (TestCaseAnalyzer.Failed a) {
                logger.warning("The parser that analyze the output from test case(s) failed");
            });

            logger.infof(!data.result.testCases.empty, `%s killed by [%-(%s, %)]`,
                    data.result.mutId, data.result.testCases.sort.map!"a.name").collectException;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(StoreResult data) {
        result_ ~= data.result;
    }

    void opCall(Restore data) {
        try {
            restoreFiles(modifiedFiles, fio);
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            data.error = true;
            hasFatalError_ = true;
        }
    }
}

/** Generate schemata injection IDs (32bit) from mutant checksums (128bit).
 *
 * There is a possibility that an injection ID result in a collision because
 * they are only 32 bit. If that happens the mutant is discarded as unfeasable
 * to use for schemata.
 *
 * TODO: if this is changed to being order dependent then it can handle all
 * mutants. But I can't see how that can be done easily both because of how the
 * schemas are generated and how the database is setup.
 */
struct InjectIdBuilder {
    private {
        alias InjectId = InjectIdResult.InjectId;

        InjectId[uint] result;
        Set!uint collisions;
    }

    void put(MutationStatusId id, Checksum cs) @safe pure nothrow {
        import dextool.plugin.mutate.backend.analyze.pass_schemata : checksumToId;

        const injectId = checksumToId(cs);
        debug logger.tracef("%s %s %s", id, cs, injectId).collectException;

        if (injectId in collisions) {
        } else if (injectId in result) {
            collisions.add(injectId);
            result.remove(injectId);
        } else {
            result[injectId] = InjectId(id, injectId);
        }
    }

    InjectIdResult finalize() @safe pure nothrow {
        import std.array : array;

        return InjectIdResult(result.byValue.array);
    }
}

struct InjectIdResult {
    alias InjectId = Tuple!(MutationStatusId, "statusId", uint, "injectId");
    InjectId[] ids;

    InjectId front() @safe pure nothrow {
        assert(!empty, "Can't get front of an empty range");
        return ids[0];
    }

    void popFront() @safe pure nothrow {
        assert(!empty, "Can't pop front of an empty range");
        ids = ids[1 .. $];
    }

    bool empty() @safe pure nothrow const @nogc {
        return ids.empty;
    }
}

@("shall detect a collision and make sure it is never part of the result")
unittest {
    InjectIdBuilder builder;
    builder.put(MutationStatusId(1), Checksum(1, 2));
    builder.put(MutationStatusId(2), Checksum(3, 4));
    builder.put(MutationStatusId(3), Checksum(1, 2));
    auto r = builder.finalize;

    assert(r.front.statusId == MutationStatusId(2));
    r.popFront;
    assert(r.empty);
}

Edit makeRootImpl() {
    import dextool.plugin.mutate.backend.resource : schemataImpl;

    return new Edit(Interval(0, 0), cast(const(ubyte)[]) schemataImpl);
}

Edit makeHdr() {
    import dextool.plugin.mutate.backend.resource : schemataHeader;

    return new Edit(Interval(0, 0), cast(const(ubyte)[]) schemataHeader);
}
