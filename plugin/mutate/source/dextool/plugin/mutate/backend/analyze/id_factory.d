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

import dextool.type : Path;

import dextool.plugin.mutate.backend.analyze.extensions;
import dextool.plugin.mutate.backend.analyze.internal;

import my.hash : Checksum64, BuildChecksum64, toBytes, toChecksum64;
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

    /** Create a mutant at this mutation point.
      *
      * It is extremly important that the mutated text representation `mut` is
      * used and not the kind of mutation because there are many different
      * kinds of mutations that result in the same textual change. By using the
      * text and not kind as part of the checksum it results in a
      * deduplication/merge of mutants that actually are "the same".
     */
    CodeMutant make(Mutation m, scope const(ubyte)[] mut) @safe pure nothrow scope;
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
        bool newFile = true;

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
        newFile = true;
        file = () {
            BuildChecksum64 bc;
            bc.put(cast(const(ubyte)[]) fileName.toString);
            return toChecksum64(bc);
        }();

        content = () {
            BuildChecksum64 bc;
            foreach (t; tokens) {
                bc.put(cast(const(ubyte)[]) t.spelling);
            }
            return toChecksum64(bc);
        }();
    }

    override void update(const Offset content, const Offset mutant, scope Token[] tokens) {
        // only do it if the position changes
        if (!newFile && mutant == mutantLoc)
            return;
        mutantLoc = mutant;

        auto split = splice(tokens, mutant);

        {
            BuildChecksum64 bc;
            bc.put(split.begin.toBytes);
            preMutant = toChecksum64(bc);
        }
        {
            BuildChecksum64 bc;
            bc.put(split.end.toBytes);
            postMutant = toChecksum64(bc);
        }

        newFile = false;
    }

    override CodeMutant make(Mutation m, scope const(ubyte)[] mut) @safe pure nothrow scope {
        return CodeMutant(CodeChecksum(makeId(mut)), m);
    }

    /// Calculate the unique ID for a specific mutation at this point.
    private Checksum64 makeId(scope const(ubyte)[] mut) @safe pure nothrow scope {
        BuildChecksum64 h;

        h.put(file.c0.toBytes);

        h.put(content.c0.toBytes);

        h.put(preMutant.c0.toBytes);

        h.put(mut);

        h.put(postMutant.c0.toBytes);
        return toChecksum64(h);
    }
}

/** Relaxed mutant IDs that are guaranteed to be unique for a while.
 *
 * The position in the file can be reset make it possible to relocate a mutant
 * inside a file.
 *
 * The algorithm is a checksum of:
 *  * the content of all relevant tokens in the current scope, e.g. all except comments
 *  * the token position before and after the mutant.
 *  * the original text
 *  * the mutated text
 */
class RelaxedImpl : MutantIdFactory {
    private {
        /// Checksum of the filename containing the mutants.
        Checksum file;
        bool newFile = true;

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
        BuildChecksum64 bc;
        bc.put(cast(const(ubyte)[]) fileName.toString);
        file = toChecksum64(bc);
        newFile = true;

        content = Window.init;
        contentLoc = Offset.init;
        mutantLoc = Offset.init;
    }

    override void update(const Offset content, const Offset mutant, scope Token[] tokens) {
        // only do it if the position changes
        if (newFile || contentLoc != content) {
            contentLoc = content;
            auto s = splice(tokens, content);
            this.content.update(s, tokens);
        }

        if (newFile || mutant != mutantLoc) {
            mutantLoc = mutant;
            auto s = this.content.toInside(splice(tokens, mutant));

            {
                BuildChecksum64 bc;
                bc.put(s.begin.toBytes);
                preMutant = toChecksum64(bc);
            }
            {
                BuildChecksum64 bc;
                bc.put(s.end.toBytes);
                postMutant = toChecksum64(bc);
            }
        }

        newFile = false;
    }

    override CodeMutant make(Mutation m, scope const(ubyte)[] mut) @safe pure nothrow scope {
        return CodeMutant(CodeChecksum(makeId(mut)), m);
    }

    /// Calculate the unique ID for a specific mutation at this point.
    private Checksum64 makeId(scope const(ubyte)[] mut) @safe pure nothrow scope {
        BuildChecksum64 h;

        h.put(file.c0.toBytes);

        h.put(content.cs.c0.toBytes);

        h.put(preMutant.c0.toBytes);

        h.put(mut);

        h.put(postMutant.c0.toBytes);

        return toChecksum64(h);
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

        BuildChecksum64 bc;
        foreach (t; tokens[win.begin .. win.end]) {
            bc.put(cast(const(ubyte)[]) t.spelling);
        }
        cs = toChecksum64(bc);
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
