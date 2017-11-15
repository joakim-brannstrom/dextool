/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.frontend.frontend;

import logger = std.experimental.logger;

import dextool.compilation_db;
import dextool.type : AbsolutePath, FileName, ExitStatusType;

import dextool.plugin.mutate.frontend.argparser : ArgParser, Mutation;

@safe:

class Frontend {
    import std.typecons : Nullable;

    ExitStatusType run() {
        return runMutate(this);
    }

private:
    string[] cflags;
    AbsolutePath[] inputFiles;
    AbsolutePath outputDirectory;
    Mutation mutation;
    Nullable!size_t mutationPoint;
    CompileCommandDB compileDb;
}

auto buildFrontend(ref ArgParser p) {
    import std.random : uniform;
    import std.array : array;
    import std.algorithm : map;
    import dextool.compilation_db;

    auto r = new Frontend;
    r.cflags = p.cflags;
    r.inputFiles = p.inFiles.map!(a => FileName(a)).map!(a => AbsolutePath(a)).array();
    r.outputDirectory = AbsolutePath(FileName(p.outputDirectory));
    r.mutation = p.mutation;
    r.mutationPoint = p.mutationPoint;

    if (p.compileDb.length != 0) {
        r.compileDb = p.compileDb.fromArgCompileDb;
    }

    return r;
}

private:

ExitStatusType runMutate(Frontend fe) {
    import std.file : exists;
    import dextool.clang : findFlags;
    import dextool.compilation_db : CompileCommandFilter,
        defaultCompilerFlagFilter;
    import dextool.type : AbsolutePath, FileName, makeExists, Exists;
    import dextool.utility : prependDefaultFlags, PreferLang;

    const auto user_cflags = prependDefaultFlags(fe.cflags, PreferLang.none);
    const auto total_files = fe.inputFiles.length;
    const auto abs_outdir = fe.outputDirectory;

    foreach (idx, in_file; fe.inputFiles) {
        logger.infof("File %d/%d ", idx + 1, total_files);

        AbsolutePath abs_input_file;
        string[] cflags;

        if (fe.compileDb.length > 0) {
            // TODO this should come from the user
            auto default_filter = CompileCommandFilter(defaultCompilerFlagFilter, 1);

            auto tmp = fe.compileDb.findFlags(FileName(in_file), user_cflags, default_filter);
            if (tmp.isNull) {
                return ExitStatusType.Errors;
            }
            abs_input_file = tmp.absoluteFile;
            cflags = tmp.cflags;
        } else {
            cflags = user_cflags.dup;
            abs_input_file = AbsolutePath(FileName(in_file));
        }

        Exists!AbsolutePath checked_in_file;
        try {
            checked_in_file = makeExists(abs_input_file);
        }
        catch (Exception e) {
            logger.warning(e.msg);
            continue;
        }

        final switch (fe.mutation) {
        case Mutation.token:
            import dextool.plugin.mutate.backend : tokenMutate;

            tokenMutate(checked_in_file, abs_outdir, cflags, fe.mutationPoint);
            break;
        case Mutation.ror:
            import dextool.plugin.mutate.backend : rorMutate;

            rorMutate(checked_in_file, abs_outdir, cflags, fe.mutationPoint);
            break;
        case Mutation.lcr:
            import dextool.plugin.mutate.backend : lcrMutate;

            lcrMutate(checked_in_file, abs_outdir, cflags, fe.mutationPoint);
            break;
        case Mutation.aor:
            import dextool.plugin.mutate.backend : aorMutate;

            aorMutate(checked_in_file, abs_outdir, cflags, fe.mutationPoint);
            break;
        case Mutation.uoi:
            import dextool.plugin.mutate.backend : uoiMutate;

            uoiMutate(checked_in_file, abs_outdir, cflags, fe.mutationPoint);
            break;
        case Mutation.abs:
            import dextool.plugin.mutate.backend : absMutate;

            absMutate(checked_in_file, abs_outdir, cflags, fe.mutationPoint);
            break;
        }
    }

    return ExitStatusType.Ok;
}
