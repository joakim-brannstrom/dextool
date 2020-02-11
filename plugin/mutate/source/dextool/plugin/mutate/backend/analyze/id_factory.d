/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.analyze.id_factory;

import logger = std.experimental.logger;

import dextool.type : Path;

import dextool.plugin.mutate.backend.analyze.extensions;
import dextool.plugin.mutate.backend.analyze.internal;

@safe:

/** Create mutation ID's from source code mutations.
 *
 * Note that the checksum is only based on the content and how it is changed.
 * The filename is not part of the checksum. This mean that the checksum will
 * "detect and reattach" to a file after a rename.
 *
 * The algorithm is a checksum of:
 *  * the content of all relevant tokens, e.g. all except comments
 *  * the token position before and after the mutant.
 *  * the original text
 *  * the mutated text
 */
struct MutationIdFactory {
    import dextool.hash : Checksum128, BuildChecksum128, toBytes, toChecksum128;
    import dextool.plugin.mutate.backend.type : CodeMutant, CodeChecksum, Mutation, Checksum;
    import dextool.type : Path;

    /// An instance is related to a filename.
    Path fileName;

    /// Checksum of the filename containing the mutants.
    Checksum file;
    /// Checksum of all tokens content.
    Checksum content;

    private {
        /// Where in the token stream the preMutant calculation is.
        size_t preIdx;
        Checksum preMutant;
        /// Where in the post tokens the postMutant is.
        size_t postIdx;
        Checksum postMutant;
    }

    /**
     * Params:
     * filename = the file that the factory is for
     * file = checksum of the filename.
     * tokens = all tokens from the file.
     */
    this(Path fileName, Checksum file, Token[] tokens) {
        this.fileName = fileName;
        this.file = file;

        BuildChecksum128 bc;
        foreach (t; tokens) {
            bc.put(cast(const(ubyte)[]) t.spelling);
        }
        this.content = toChecksum128(bc);
    }

    /// Update the number of tokens that are before and after the mutant.
    void updatePosition(const size_t preCnt, const size_t postCnt) {
        // only do it if the position changes
        if (preCnt == preIdx && postCnt == postIdx)
            return;

        preIdx = preCnt;
        postIdx = postCnt;

        {
            BuildChecksum128 bc;
            bc.put(preIdx.toBytes);
            preMutant = toChecksum128(bc);
        }
        {
            BuildChecksum128 bc;
            bc.put(postIdx.toBytes);
            postMutant = toChecksum128(bc);
        }
    }

    /// Calculate the unique ID for a specific mutation at this point.
    Checksum128 makeId(const(ubyte)[] mut) @safe pure nothrow const @nogc scope {
        // # SPC-analyzer-checksum
        BuildChecksum128 h;
        h.put(file.c0.toBytes);
        h.put(file.c1.toBytes);

        h.put(content.c0.toBytes);
        h.put(content.c1.toBytes);

        h.put(preMutant.c0.toBytes);
        h.put(preMutant.c1.toBytes);

        h.put(mut);

        h.put(postMutant.c0.toBytes);
        h.put(postMutant.c1.toBytes);
        return toChecksum128(h);
    }

    /// Create a mutant at this mutation point.
    CodeMutant makeMutant(Mutation m, const(ubyte)[] mut) @safe pure nothrow const @nogc scope {
        auto id = makeId(mut);
        return CodeMutant(CodeChecksum(id), m);
    }
}
