/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.plugin.mutate.backend.test_mutant.coverage;

import core.time : Duration;
import logger = std.experimental.logger;
import std.algorithm : map, filter, sort;
import std.array : array, appender, empty;
import std.exception : collectException;
import std.stdio : File;
import std.typecons : tuple, Tuple;

import blob_model;
import miniorm;
import my.fsm : next, act;
import my.optional;
import my.path;
import my.set;
import sumtype;

static import my.fsm;

import dextool.plugin.mutate.backend.database : CovRegion, CoverageRegionId, FileId;
import dextool.plugin.mutate.backend.database : Database;
import dextool.plugin.mutate.backend.interface_ : FilesysIO, Blob;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner, TestResult;
import dextool.plugin.mutate.backend.type : Mutation, Language;
import dextool.plugin.mutate.type : ShellCommand;

@safe:

struct CoverageDriver {
    static struct None {
    }

    static struct Initialize {
    }

    static struct InitializeRoots {
        bool hasRoot;
    }

    static struct SaveOriginal {
    }

    static struct Instrument {
    }

    static struct Compile {
        bool error;
    }

    static struct Run {
        // something happend, throw away the result.
        bool error;

        CovEntry[] covMap;
    }

    static struct SaveToDb {
        CovEntry[] covMap;
    }

    static struct Restore {
    }

    static struct Done {
    }

    alias Fsm = my.fsm.Fsm!(None, Initialize, InitializeRoots, SaveOriginal,
            Instrument, Compile, Run, SaveToDb, Restore, Done);

    private {
        Fsm fsm;
        bool isRunning_ = true;

        // If an error has occurd that should be signaled to the user of the
        // coverage driver.
        bool error_;

        // Write the instrumented source code to .cov.<ext> for separate
        // inspection.
        bool log;

        FilesysIO fio;
        Database* db;

        ShellCommand buildCmd;
        Duration buildCmdTimeout;

        Blob[AbsolutePath] original;
        Language[AbsolutePath] lang;

        /// Runs the test commands.
        TestRunner* runner;

        CovRegion[][AbsolutePath] regions;

        // a map of incrementing numbers from 0 which map to the global, unique
        // ID of the region.
        CoverageRegionId[long] localId;

        // the files to inject the code that setup the coverage map.
        Set!AbsolutePath roots;
    }

    this(FilesysIO fio, Database* db, TestRunner* runner, ShellCommand buildCmd,
            Duration buildCmdTimeout, bool log) {
        this.fio = fio;
        this.db = db;
        this.runner = runner;
        this.buildCmd = buildCmd;
        this.buildCmdTimeout = buildCmdTimeout;
        this.log = log;
        logger.trace("coverage logging ", log).collectException;
    }

    static void execute_(ref CoverageDriver self) @trusted {
        self.fsm.next!((None a) => Initialize.init,
                (Initialize a) => InitializeRoots.init, (InitializeRoots a) {
            if (a.hasRoot)
                return fsm(SaveOriginal.init);
            return fsm(Done.init);
        }, (SaveOriginal a) => Instrument.init, (Instrument a) => Compile.init, (Compile a) {
            if (a.error)
                return fsm(Restore.init);
            return fsm(Run.init);
        }, (Run a) {
            if (a.error)
                return fsm(Restore.init);
            return fsm(SaveToDb(a.covMap));
        }, (SaveToDb a) => Restore.init, (Restore a) => Done.init, (Done a) => a);

        debug logger.trace("state: ", self.fsm.logNext);
        self.fsm.act!self;
    }

nothrow:
    void execute() {
        try {
            execute_(this);
        } catch (Exception e) {
            isRunning_ = false;
            error_ = true;
            logger.warning(e.msg).collectException;
        }
    }

    bool isRunning() {
        return isRunning_;
    }

    bool hasFatalError() {
        return error_;
    }

    void opCall(None data) {
    }

    void opCall(Initialize data) {
        foreach (a; spinSql!(() => db.getCoverageMap).byKeyValue
                .map!(a => tuple(spinSql!(() => db.getFile(a.key)), a.value,
                    spinSql!(() => db.getFileIdLanguage(a.key))))
                .filter!(a => !a[0].isNull)
                .map!(a => tuple(a[0].get, a[1], a[2].orElse(Language.cpp)))) {
            try {
                auto p = fio.toAbsoluteRoot(a[0]);
                regions[p] = a[1];
                lang[p] = a[2];
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }

        logger.tracef("%s files to instrument", regions.length).collectException;
    }

    void opCall(ref InitializeRoots data) {
        auto rootIds = () {
            auto tmp = spinSql!(() => db.getRootFiles);
            if (tmp.empty) {
                // no root found, inject instead in all instrumented files and
                // "hope for the best".
                tmp = spinSql!(() => db.getCoverageMap).byKey.array;
            }
            return tmp;
        }();

        foreach (id; rootIds) {
            try {
                auto p = fio.toAbsoluteRoot(spinSql!(() => db.getFile(id)).get);
                if (p !in regions) {
                    // add a dummy such that the instrumentation state do not need
                    // a special case for if no root is being instrumented.
                    regions[p] = (CovRegion[]).init;
                    lang[p] = spinSql!(() => db.getFileIdLanguage(id)).orElse(Language.init);
                }
                roots.add(p);
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }

        data.hasRoot = !roots.empty;

        if (regions.empty) {
            logger.info("No files to gather coverage data from").collectException;
        } else if (roots.empty) {
            logger.warning("No root file for coverage instrumentation found").collectException;
            logger.info("A root file is one in e.g. compile_commands.json").collectException;
        }
    }

    void opCall(SaveOriginal data) {
        try {
            foreach (a; regions.byKey) {
                original[a] = fio.makeInput(a);
            }
        } catch (Exception e) {
            // TODO: should it set error?
            isRunning_ = false;
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(Instrument data) {
        import std.path : extension, stripExtension;

        Blob makeInstrumentation(Blob original, CovRegion[] regions, Language lang, Edit[] extra) {
            auto edits = appender!(Edit[])();
            edits.put(extra);
            foreach (a; regions) {
                long id = cast(long) localId.length;
                localId[id] = a.id;
                edits.put(new Edit(Interval(a.region.begin, a.region.begin),
                        makeInstrCode(id, lang)));
            }
            auto m = merge(original, edits.data);
            return change(new Blob(original.uri, original.content), m.edits);
        }

        try {
            // sort by filename to enforce that the IDs are stable.
            foreach (a; regions.byKeyValue.array.sort!((a, b) => a.key < b.key)) {
                auto extra = () {
                    if (a.key in roots) {
                        logger.info("Injecting coverage runtime in ", a.key);
                        return makeRootImpl;
                    }
                    return makeHdr;
                }();

                logger.infof("Coverage instrumenting %s regions in %s", a.value.length, a.key);
                auto instr = makeInstrumentation(original[a.key], a.value, lang[a.key], [
                        extra
                        ]);
                fio.makeOutput(a.key).write(instr);

                if (log) {
                    const ext = a.key.toString.extension;
                    const l = AbsolutePath(a.key.toString.stripExtension ~ ".cov" ~ ext);
                    fio.makeOutput(l).write(instr);
                }
            }
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
            error_ = true;
        }

        // release back to GC
        regions = null;
    }

    void opCall(ref Compile data) {
        import dextool.plugin.mutate.backend.test_mutant.common : compile;

        try {
            logger.info("Compiling instrumented source code");

            compile(buildCmd, buildCmdTimeout, true).match!((Mutation.Status a) {
                data.error = true;
            }, (bool success) { data.error = !success; });
        } catch (Exception e) {
            data.error = true;
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(ref Run data) @trusted {
        import std.file : remove;
        import std.range : repeat;
        import my.random;
        import my.xdg : makeXdgRuntimeDir;

        try {
            logger.info("Gathering runtime coverage data");

            // TODO: make this a configurable parameter?
            const dir = makeXdgRuntimeDir(AbsolutePath("/dev/shm"));
            const covMapFname = AbsolutePath(dir ~ randomId(20));

            createCovMap(covMapFname, cast(long) localId.length);
            scope (exit)
                () { remove(covMapFname.toString); }();

            runner.env[dextoolCovMapKey] = covMapFname.toString;
            scope (exit)
                runner.env.remove(dextoolCovMapKey);

            auto res = runner.run;
            if (res.status != TestResult.Status.passed) {
                logger.info(
                        "An error occurred when executing instrumented binaries to gather coverage information");
                logger.info("This is not a fatal error. Continuing without coverage information");
                data.error = true;
                return;
            }

            data.covMap = readCovMap(covMapFname, cast(long) localId.length);
        } catch (Exception e) {
            data.error = true;
            logger.warning(e.msg).collectException;
        }
    }

    void opCall(SaveToDb data) {
        logger.info("Saving coverage data to database").collectException;
        void save() @trusted {
            auto trans = db.transaction;
            foreach (a; data.covMap) {
                db.putCoverageInfo(localId[a.id], a.status);
            }
            db.updateCoverageTimeStamp;
            trans.commit;
        }

        spinSql!(save);
    }

    void opCall(Restore data) {
        foreach (a; original.byKeyValue) {
            try {
                fio.makeOutput(a.key).write(a.value);
            } catch (Exception e) {
                isRunning_ = false;
                error_ = true;
                logger.error(e.msg).collectException;
            }
        }
    }

    void opCall(Done data) {
        isRunning_ = false;
    }
}

private:

import dextool.plugin.mutate.backend.resource : coverageMapHdr, coverageMapImpl;

immutable dextoolCovMapKey = "DEXTOOL_COVMAP";

struct CovEntry {
    long id;
    bool status;
}

const(ubyte)[] makeInstrCode(long id, Language l) {
    import std.format : format;

    final switch (l) {
    case Language.assumeCpp:
        goto case;
    case Language.cpp:
        return cast(const(ubyte)[]) format!"::dextool_cov__(%s);"(id + 1);
    case Language.c:
        return cast(const(ubyte)[]) format!"dextool_cov__(%s);"(id + 1);
    }
}

Edit makeRootImpl() {
    return new Edit(Interval(0, 0), cast(const(ubyte)[]) coverageMapImpl);
}

Edit makeHdr() {
    return new Edit(Interval(0, 0), cast(const(ubyte)[]) coverageMapHdr);
}

void createCovMap(const AbsolutePath fname, const long localIdSz) {
    const size_t K = 1024;
    // create a margin of 1K in case something goes awry.
    const allocSz = 1 + localIdSz + K;

    auto covMap = File(fname.toString, "w");

    ubyte[K] zeroes;
    for (size_t i; i < allocSz; i += zeroes.length) {
        covMap.rawWrite(zeroes);
    }
}

// TODO: should check if anything is written to the extra bytes at the end.  if
// there are data there then something is wrong and the coverage map should be
// discarded.
CovEntry[] readCovMap(const AbsolutePath fname, const long localIdSz) {
    auto rval = appender!(CovEntry[])();

    auto covMap = File(fname.toString);

    // TODO: read multiple IDs at a time to speed up.
    ubyte[1] buf;

    // check that at least one test has executed and thus set the first byte.
    auto r = covMap.rawRead(buf);
    if (r[0] == 0) {
        logger.info("No coverage instrumented binaries executed");
        return typeof(return).init;
    }

    foreach (i; 0 .. localIdSz) {
        r = covMap.rawRead(buf);
        // something is wrong.
        if (r.empty)
            return typeof(return).init;

        rval.put(CovEntry(cast(long) i, r[0] == 1));
    }

    return rval.data;
}
