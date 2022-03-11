/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Generate unique ID's for used to identify mutants.
*/
module dextool.plugin.mutate.backend.analyze.id_factory;

import logger = std.experimental.logger;

import dextool.type : Path;

import dextool.plugin.mutate.backend.analyze.extensions;
import dextool.plugin.mutate.backend.analyze.internal;

import my.hash : Checksum128, BuildChecksum128, toBytes, toChecksum128;
import dextool.plugin.mutate.backend.type : CodeMutant, CodeChecksum, Mutation, Checksum, Offset;

@safe:

interface MutantIdFactory {
    import dextool.plugin.mutate.backend.type : CodeMutant, Mutation;

    /** Change the current file.
     *
     * Params:
     * filename = the file that the factory is for
     * tokens = all tokens from the file.
     */
    void changeFile(Path fileName, scope Token[] tokens);

    /** Update the number of tokens that are before and after the mutant.
     *
     * Params:
     *  content = offset of the tokens to use for content calculation
     *  mutant = offset of the mutant
     */
    void update(const Offset content, const Offset mutant, scope Token[] tokens);

    /// Create a mutant at this mutation point.
    CodeMutant make(Mutation m, const(ubyte)[] mut) @safe pure nothrow scope;
}

/** Strict and whole file content sensitive unique mutant IDs.
 *
 * ID's are *strict* because any change to tokens besides comments will result
 * in new ID's for all mutants in the file.
 *
 * The algorithm is a checksum of:
 *  * the content of all relevant tokens, e.g. all except comments
 *  * the token position before and after the mutant.
 *  * the original text
 *  * the mutated text
 */
class StrictImpl : MutantIdFactory {
    private {
        /// Checksum of the filename containing the mutants.
        Checksum file;
        /// Checksum of all tokens content.
        Checksum content;

        /// The offset location of the mutant in the file.
        Offset mutantLoc;

        /// Checksum of the token indexes before and after the mutant.
        Checksum preMutant;
        Checksum postMutant;
    }

    this() {
    }

    override void changeFile(Path fileName, scope Token[] tokens) {
        file = () {
            BuildChecksum128 bc;
            bc.put(cast(const(ubyte)[]) fileName.toString);
            return toChecksum128(bc);
        }();

        content = () {
            BuildChecksum128 bc;
            foreach (t; tokens) {
                bc.put(cast(const(ubyte)[]) t.spelling);
            }
            return toChecksum128(bc);
        }();
    }

    override void update(const Offset content, const Offset mutant, scope Token[] tokens) {
        // only do it if the position changes
        if (mutant == mutantLoc)
            return;
        mutantLoc = mutant;

        auto split = splice(tokens, mutant);

        {
            BuildChecksum128 bc;
            bc.put(split.begin.toBytes);
            preMutant = toChecksum128(bc);
        }
        {
            BuildChecksum128 bc;
            bc.put(split.end.toBytes);
            postMutant = toChecksum128(bc);
        }
    }

    override CodeMutant make(Mutation m, const(ubyte)[] mut) @safe pure nothrow scope {
        return CodeMutant(CodeChecksum(makeId(mut)), m);
    }

    /// Calculate the unique ID for a specific mutation at this point.
    private Checksum128 makeId(const(ubyte)[] mut) @safe pure nothrow scope {
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
}

/** Relaxed mutant IDs that are guaranteed to be unique for a while.
 *
 * The position in the file can be reset make it possible to relocate a mutant
 * inside a file.
 *
 * The algorithm is a checksum of:
 *  * the content of all relevant tokens, e.g. all except comments
 *  * the token position before and after the mutant.
 *  * the original text
 *  * the mutated text
 */
class RelaxedImpl : MutantIdFactory {
    import my.set;

    private {
        /// Checksum of the filename containing the mutants.
        Checksum file;

        // the offset of the last window
        Offset contentLoc;

        ///
        Window content;

        // The offset location of the mutant in the file which the content and
        // position checksums are calculated for.
        Offset mutantLoc;

        /// Checksum of the token indexes before and after the mutant.
        Checksum preMutant;
        Checksum postMutant;
    }

    this() {
    }

    override void changeFile(Path fileName, scope Token[] tokens) {
        file = () {
            BuildChecksum128 bc;
            bc.put(cast(const(ubyte)[]) fileName.toString);
            return toChecksum128(bc);
        }();
    }

    override void update(const Offset content, const Offset mutant, scope Token[] tokens) {
        // only do it if the position changes
        if (contentLoc != content) {
            contentLoc = content;
            auto s = splice(tokens, content);
            this.content.update(s, tokens);
        }

        if (mutant != mutantLoc) {
            mutantLoc = mutant;
            auto s = this.content.toInside(splice(tokens, mutant));

            {
                BuildChecksum128 bc;
                bc.put(s.begin.toBytes);
                preMutant = toChecksum128(bc);
            }
            {
                BuildChecksum128 bc;
                bc.put(s.end.toBytes);
                postMutant = toChecksum128(bc);
            }
        }
    }

    override CodeMutant make(Mutation m, const(ubyte)[] mut) @safe pure nothrow scope {
        return CodeMutant(CodeChecksum(makeId(mut)), m);
    }

    /// Calculate the unique ID for a specific mutation at this point.
    private Checksum128 makeId(const(ubyte)[] mut) @safe pure nothrow scope {
        BuildChecksum128 h;

        h.put(file.c0.toBytes);
        h.put(file.c1.toBytes);

        h.put(content.cs.c0.toBytes);
        h.put(content.cs.c1.toBytes);

        h.put(preMutant.c0.toBytes);
        h.put(preMutant.c1.toBytes);

        h.put(mut);

        h.put(postMutant.c0.toBytes);
        h.put(postMutant.c1.toBytes);

        return toChecksum128(h);
    }
}

private:

struct WindowIndex {
    size_t begin;
    size_t end;

    invariant {
        assert(begin <= end);
    }
}

/// Checksum is calculated over the window.
struct Window {
    WindowIndex win;
    Checksum cs;

    void update(const WindowIndex window, scope Token[] tokens) {
        win = window;

        if (win.end > tokens.length || win.begin == win.end)
            win = WindowIndex(0, tokens.length);

        BuildChecksum128 bc;
        foreach (t; tokens[win.begin .. win.end]) {
            bc.put(cast(const(ubyte)[]) t.spelling);
        }
        cs = toChecksum128(bc);
    }

    WindowIndex toInside(const WindowIndex x) {
        const pre = () {
            if (x.begin >= win.begin)
                return x.begin - win.begin;
            return x.begin;
        }();
        const post = () {
            if (x.end <= win.end)
                return x.end - win.begin;
            return x.end;
        }();
        if (pre != post)
            return WindowIndex(pre, post);
        // not possible to use the window thus use the global
        return x;
    }
}

/// Returns: The indexes in `toks` before and after `offset`.
auto splice(scope Token[] toks, const Offset offset) {
    import std.algorithm : countUntil;

    const preIdx = toks.countUntil!((a, b) => a.offset.begin > b.begin)(offset);
    if (preIdx <= -1) {
        return WindowIndex(0, toks.length);
    }

    const postIdx = () {
        auto idx = toks[preIdx .. $].countUntil!((a, b) => a.offset.end > b.end)(offset);
        if (idx == -1)
            return toks.length;
        return preIdx + idx;
    }();

    return WindowIndex(preIdx, postIdx);
}
