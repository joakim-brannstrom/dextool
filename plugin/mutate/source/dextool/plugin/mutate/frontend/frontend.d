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

import dextool.type : ExitStatusType;
import dextool.compilation_db;
import dextool.plugin.mutate.frontend.argparser : ArgParser;

ExitStatusType runMutate(ArgParser argp, CompileCommandDB compile_db) {
    import dextool.clang : findFlags, SearchResult;
    import dextool.compilation_db : CompileCommandFilter,
        defaultCompilerFlagFilter;
    import dextool.type : AbsolutePath, FileName;
    import dextool.utility : prependDefaultFlags, PreferLang;
    import dextool.plugin.mutate.backend : tokenMutate;

    const auto user_cflags = prependDefaultFlags(argp.cflags, PreferLang.none);
    const auto total_files = argp.inFiles.length;
    const auto abs_outdir = AbsolutePath(FileName(argp.outputDirectory));

    foreach (idx, in_file; argp.inFiles) {
        logger.infof("File %d/%d ", idx + 1, total_files);
        SearchResult pdata;

        if (compile_db.length > 0) {
            // TODO this should come from the user
            auto default_filter = CompileCommandFilter(defaultCompilerFlagFilter, 1);

            auto tmp = compile_db.findFlags(FileName(in_file), user_cflags, default_filter);
            if (tmp.isNull) {
                return ExitStatusType.Errors;
            }
            pdata = tmp.get;
        } else {
            pdata.cflags = user_cflags.dup;
            pdata.absoluteFile = AbsolutePath(FileName(in_file));
        }

        tokenMutate(pdata.absoluteFile, abs_outdir, pdata.cflags);
    }

    return ExitStatusType.Ok;
}
