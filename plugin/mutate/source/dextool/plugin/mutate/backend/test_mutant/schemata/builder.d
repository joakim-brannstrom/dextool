/**
Copyright: Copyright (c) Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.test_mutant.schemata.builder;

import logger = std.experimental.logger;
import std.algorithm : sort, map, filter, among, sum, max;
import std.array : empty, array, appender;
import std.exception : collectException;
import std.sumtype;
import std.typecons : Nullable;

import blob_model;
import colorlog;
import miniorm : spinSql, silentLog;
import my.optional;
import my.container.vector;
import proc : DrainElement;

import my.path;
import my.set;

import dextool.plugin.mutate.backend.analyze.utility;
import dextool.plugin.mutate.backend.analyze.schema_ml : SchemaQ, SchemaSizeQ, SchemaStatus;
import dextool.plugin.mutate.backend.database : MutationStatusId, Database,
    spinSql, SchemataId, Schemata, FileId;
import dextool.plugin.mutate.backend.interface_ : FilesysIO;
import dextool.plugin.mutate.backend.test_mutant.common;
import dextool.plugin.mutate.backend.test_mutant.common_actors : DbSaveActor, StatActor;
import dextool.plugin.mutate.backend.test_mutant.test_cmd_runner : TestRunner, TestResult;
import dextool.plugin.mutate.backend.test_mutant.timeout : TimeoutFsm, TimeoutConfig;
import dextool.plugin.mutate.backend.type : Language, SourceLoc, Offset,
    SourceLocRange, CodeMutant, SchemataChecksum, Mutation, TestCase, Checksum;
import dextool.plugin.mutate.config : ConfigSchema;
import dextool.plugin.mutate.type : TestCaseAnalyzeBuiltin, ShellCommand,
    UserRuntime, SchemaRuntime;

@safe:

/** Build scheman from the fragments.
 *
 * TODO: optimize the implementation. A lot of redundant memory allocations
 * etc.
 *
 * Conservative to only allow up to <user defined> mutants per schemata but it
 * reduces the chance that one failing schemata is "fatal", loosing too many
 * muntats.
 */
struct SchemataBuilder {
    import std.algorithm : any, all;
    import my.container.vector;
    import dextool.plugin.mutate.backend.analyze.schema_ml : SchemaQ;
    import dextool.plugin.mutate.backend.database.type : SchemaFragmentV2;

    static struct SchemataFragment {
        Path file;
        Offset offset;
        const(ubyte)[] text;
    }

    static struct Fragment {
        SchemataFragment fragment;
        CodeMutant[] mutants;
    }

    static struct ET {
        SchemataFragment[] fragments;
        CodeMutant[] mutants;
        SchemataChecksum checksum;
    }

    // TODO: remove SchemataChecksum?

    /// Controls the probability that a mutant is part of the currently generating schema.
    SchemaQ schemaQ;

    /// use probability for if a mutant is injected or not
    bool useProbability;

    /// if the probability should also influence if the scheam is smaller.
    bool useProbablitySmallSize;

    // if fragments that are part of scheman that didn't reach the min
    // threshold should be discarded.
    bool discardMinScheman;

    /// The threshold start at this value.
    double thresholdStartValue = 0.0;

    /// Max mutants per schema.
    long mutantsPerSchema = 1000;

    /// Minimal mutants that a schema must contain for it to be valid.
    long minMutantsPerSchema = 3;

    Vector!Fragment current;
    Vector!Fragment rest;

    /// Size in bytes of the cache of fragments.
    size_t cacheSize;

    /** Merge analyze fragments into larger schemata fragments. If a schemata
     * fragment is large enough it is converted to a schemata. Otherwise kept
     * for pass2.
     *
     * Schematan from this pass only contain one kind and only affect one file.
     */
    void put(Fragment[] fragments) {
        foreach (a; fragments) {
            current.put(a);
            incrCache(a.fragment);
        }
    }

    private void incrCache(ref SchemataFragment a) @safe pure nothrow @nogc {
        cacheSize += a.text.length + (cast(const(ubyte)[]) a.file.toString).length + typeof(a)
            .sizeof;
    }

    bool empty() @safe pure nothrow const @nogc {
        return current.length == 0 && rest.length == 0;
    }

    auto stats() @safe pure nothrow const {
        static struct Stats {
            double cacheSizeMb;
            size_t current;
            size_t rest;
        }

        return Stats(cast(double) cacheSize / (1024 * 1024), current.length, rest.length);
    }

    /** Merge schemata fragments to schemas. A schemata from this pass may may
     * contain multiple mutation kinds and span over multiple files.
     */
    Optional!ET next() {
        Index!Path index;
        auto app = appender!(Fragment[])();
        Set!CodeMutant local;
        auto threshold() {
            return max(thresholdStartValue, cast(double) local.length / cast(double) mutantsPerSchema);
        }

        auto mutantsPerSchemaSmall = mutantsPerSchema;
        auto thresholdSmall() {
            return max(thresholdStartValue,
                    cast(double) local.length / cast(double) mutantsPerSchemaSmall);
        }

        bool loopCond() {
            if (current.empty || local.length >= mutantsPerSchema)
                return false;

            if (!useProbablitySmallSize)
                return true;
            if (local.length >= mutantsPerSchemaSmall)
                return false;

            mutantsPerSchemaSmall = max(mutantsPerSchemaSmall - minMutantsPerSchema,
                    minMutantsPerSchema);
            return true;
        }

        while (loopCond) {
            auto a = current.front;
            current.popFront;

            if (a.mutants.empty)
                continue;

            if (index.intersect(a.fragment.file, a.fragment.offset)) {
                rest.put(a);
                continue;
            }

            // if any of the mutants in the schema has already been included.
            if (any!(a => a in local)(a.mutants)) {
                rest.put(a);
                continue;
            }

            // if any of the mutants fail the probability to be included
            if (useProbability && any!(b => !schemaQ.use(a.fragment.file,
                    b.mut.kind, threshold()))(a.mutants)) {
                // TODO: remove this line of code in the future. used for now,
                // ugly, to see that it behavies as expected.
                //log.tracef("probability postpone fragment with mutants %s %s",
                //        a.mutants.length, a.mutants.map!(a => a.mut.kind));
                rest.put(a);
                continue;
            }

            // no use in using a mutant that has zero probability because then, it will always fail.
            if (any!(b => schemaQ.isZero(a.fragment.file, b.mut.kind))(a.mutants)) {
                continue;
            }

            if (useProbablitySmallSize && any!(b => !schemaQ.use(a.fragment.file,
                    b.mut.kind, thresholdSmall()))(a.mutants)) {
                rest.put(a);
                continue;
            }

            app.put(a);
            local.add(a.mutants);
            index.put(a.fragment.file, a.fragment.offset);
        }

        if (local.length == 0 || local.length < minMutantsPerSchema) {
            if (discardMinScheman) {
                logger.tracef("discarding %s fragments with %s mutants",
                        app.data.length, app.data.map!(a => a.mutants.length).sum);
            } else {
                rest.put(app.data);
            }
            return none!ET;
        }

        ET v;
        v.fragments = app.data.map!(a => a.fragment).array;
        v.mutants = local.toArray;
        v.checksum = toSchemataChecksum(v.mutants);

        return some(v);
    }

    bool isDone() @safe pure nothrow const @nogc {
        return current.empty;
    }

    void restart() @safe pure nothrow @nogc {
        current = rest;
        rest.clear;

        cacheSize = 0;
        foreach (a; current[])
            incrCache(a.fragment);
    }
}

/** A schema is uniquely identified by the mutants it contains.
 *
 * The order of the mutants are irrelevant because they are always sorted by
 * their value before the checksum is calculated.
 */
SchemataChecksum toSchemataChecksum(CodeMutant[] mutants) {
    import dextool.plugin.mutate.backend.utility : BuildChecksum, toChecksum, toBytes;

    BuildChecksum h;
    foreach (a; mutants.sort!((a, b) => a.id.value < b.id.value)
            .map!(a => a.id.value)) {
        h.put(a.c0.toBytes);
    }

    return SchemataChecksum(toChecksum(h));
}

/** The total state for building schemas in runtime.
 *
 * The intention isn't to perfectly travers and handle all mutants in the
 * worklist if the worklist is manipulated while the schema generation is
 * running. It is just "good enough" to generate schemas for those mutants when
 * it was started.
 */
struct SchemaBuildState {
    import std.sumtype;
    import my.optional;
    import dextool.plugin.mutate.backend.database.type : FileId, SchemaFragmentV2;

    enum State : ubyte {
        none,
        processFiles,
        prepareReduction,
        reduction,
        prepareFinalize,
        finalize1,
        finalize2,
        done,
    }

    static struct ProcessFiles {
        FileId[] files;
        size_t idx;

        FileId pop() @safe pure nothrow scope {
            if (idx == files.length)
                return FileId.init;
            return files[idx++];
        }

        bool isDone() @safe pure nothrow const @nogc scope {
            return idx == files.length;
        }

        size_t filesLeft() @safe pure nothrow const @nogc scope {
            return files.length - idx;
        }

        void reset() @safe pure nothrow @nogc scope {
            idx = 0;
        }

        void clear() @safe pure nothrow @nogc scope {
            files = null;
            reset;
        }
    }

    // State of the schema building
    State st;
    private int reducedTicks;

    // Files to use when generating schemas.
    ProcessFiles files;

    SchemataBuilder builder;

    // User configuration.
    typeof(ConfigSchema.minMutantsPerSchema) minMutantsPerSchema = 3;
    typeof(ConfigSchema.mutantsPerSchema) mutantsPerSchema = 1000;

    void initFiles(FileId[] files) @safe nothrow {
        import std.random : randomCover;

        try {
            // improve the schemas non-determinism between each `test` run.
            this.files.files = files.randomCover.array;
        } catch (Exception e) {
            this.files.files = files;
        }
    }

    /// Step through the schema building.
    void tick() @safe nothrow {
        logger.tracef("state_pre: %s %s", st, builder.stats).collectException;
        final switch (st) {
        case State.none:
            st = State.processFiles;
            try {
                setIntermediate;
            } catch (Exception e) {
                st = State.done;
            }
            break;
        case State.processFiles:
            if (files.isDone)
                st = State.prepareReduction;
            try {
                setIntermediate;
            } catch (Exception e) {
                st = State.done;
            }
            break;
        case State.prepareReduction:
            st = State.reduction;
            break;
        case State.reduction:
            immutable magic = 10; // reduce the size until it is 1/10 of the original
            immutable magic2 = 5; // if it goes <95% then it is too high probability to fail

            if (builder.empty)
                st = State.prepareFinalize;
            else if (++reducedTicks > (magic * magic2))
                st = State.prepareFinalize;

            try {
                setReducedIntermediate(1 + reducedTicks / magic, reducedTicks % magic2);
            } catch (Exception e) {
                st = State.done;
            }
            break;
        case State.prepareFinalize:
            st = State.finalize1;
            break;
        case State.finalize1:
            st = State.finalize2;
            try {
                finalize;
            } catch (Exception e) {
                st = State.done;
            }
            break;
        case State.finalize2:
            if (builder.isDone)
                st = State.done;
            break;
        case State.done:
            break;
        }
        logger.trace("state_post: ", st).collectException;
    }

    /// Add all fragments from one of the files to process to those to be
    /// incorporated into future schemas.
    /// Returns: number of fragments added.
    size_t updateFiles(ref Set!MutationStatusId whiteList, ref Set!MutationStatusId denyList,
            scope SchemaFragmentV2[]delegate(FileId) @safe fragmentsFn,
            scope Nullable!Path delegate(FileId) @safe fnameFn,
            scope Mutation.Kind delegate(MutationStatusId) @safe kindFn) @safe nothrow {
        import std.algorithm : any;
        import dextool.plugin.mutate.backend.type : CodeChecksum, Mutation;
        import dextool.plugin.mutate.backend.database : toChecksum;

        if (files.isDone)
            return 0;
        auto id = files.pop;
        try {
            const fname = fnameFn(id);
            if (fname.isNull)
                return 0;

            auto app = appender!(SchemataBuilder.Fragment[])();
            auto frags = fragmentsFn(id);
            foreach (a; frags.filter!(a => !any!(b => b in denyList)(a.mutants))) {
                auto cm = a.mutants
                    .filter!(a => a in whiteList)
                    .map!(a => CodeMutant(CodeChecksum(a.toChecksum),
                            Mutation(kindFn(a), Mutation.Status.unknown)))
                    .array;
                if (!cm.empty) {
                    app.put(SchemataBuilder.Fragment(SchemataBuilder.SchemataFragment(fname.get,
                            a.offset, a.text), cm));
                }
            }

            builder.put(app.data);
            return app.data.length;
        } catch (Exception e) {
            logger.trace(e.msg).collectException;
        }
        return 0;
    }

    Optional!(SchemataBuilder.ET) process() {
        auto rval = builder.next;
        builder.restart;
        return rval;
    }

    void setMinMutants(long desiredValue) {
        // seems like 200 Mbyte is large enough to generate scheman with >1000
        // mutants easily when running on LLVM.
        enum MaxCache = 200 * 1024 * 1024;
        if (builder.cacheSize > MaxCache) {
            // panic mode, just empty it as fast as possible.
            logger.infof(
                    "Schema cache is %s bytes (limit %s). Producing as many schemas as possible to flush the cache.",
                    builder.cacheSize, MaxCache);
            builder.minMutantsPerSchema = minMutantsPerSchema.get;
        } else {
            builder.minMutantsPerSchema = desiredValue;
        }
    }

    void setIntermediate() {
        logger.trace("schema generator phase: intermediate");
        builder.discardMinScheman = false;
        builder.useProbability = true;
        builder.useProbablitySmallSize = false;
        builder.mutantsPerSchema = mutantsPerSchema.get;
        builder.thresholdStartValue = 1.0;

        setMinMutants(mutantsPerSchema.get);
    }

    void setReducedIntermediate(long sizeDiv, long threshold) {
        import std.algorithm : max;

        logger.tracef("schema generator phase: reduced size:%s threshold:%s", sizeDiv, threshold);
        builder.discardMinScheman = false;
        builder.useProbability = true;
        builder.useProbablitySmallSize = false;
        builder.mutantsPerSchema = mutantsPerSchema.get;
        // TODO: interresting effect. this need to be studied. I think this
        // is the behavior that is "best".
        builder.thresholdStartValue = 1.0 - (cast(double) threshold / 100.0);

        setMinMutants(max(minMutantsPerSchema.get, mutantsPerSchema.get / sizeDiv));
    }

    /// Consume all fragments or discard.
    void finalize() {
        logger.trace("schema generator phase: finalize");
        builder.discardMinScheman = true;
        builder.useProbability = false;
        builder.useProbablitySmallSize = true;
        builder.mutantsPerSchema = mutantsPerSchema.get;
        builder.minMutantsPerSchema = minMutantsPerSchema.get;
        builder.thresholdStartValue = 0;
    }
}
