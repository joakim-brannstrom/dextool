/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.

Abstractions for easier usage of clang with in-memory files.

An user of Clang and especially SourceRanges/SourceLocation shouldn't need to
keep track of which files are from the filesystem, which are from the in-memory
cache.

The VFS provides an agnostic access to both in-memory and filesystem with
helper functions for SourceRange/SourceLocation.
*/
module cpptooling.utility.vfs;

import clang.SourceLocation : SourceLocation;
import clang.SourceRange : SourceRange;

import deimos.clang.index : CXUnsavedFile;

version (unittest) {
    import unit_threaded : Name, shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

enum FileName : string {
    _init = null};
    enum Source : string {
        _init = null};
        enum AutoLoad {
            No,
            Yes
        };

        /** File layer abstracting the handling of in-memory files and concrete
 * filesystem files.
 *
 * This struct abstracts and contains those differences.
 *
 * A file is only read once.
 * After the first access it is moved to in-memory storage to speed up future
 * access.
 *
 * TODO
 * Is it better to have everything as MMF?
 * It would be possible to have the source code as an anonymous MMF.
 */
        struct VirtualFileSystem {
            import std.mmfile : MmFile;
            import std.traits : isSomeString;

            private {
                struct MmFSize {
                    MmFile file;
                    size_t size;
                }

                ubyte[][FileName] in_memory;
                MmFSize[FileName] filesys;
            }

            /** Add a mapping to a concrete file.
     *
     * Params:
     *   fname = file to map into the VFS
     */
            void put(FileName fname) {
                import std.file : getSize;

                auto sz = getSize(cast(string) fname);
                auto mmf = new MmFile(cast(string) fname, MmFile.Mode.read, sz, null);
                filesys[fname] = MmFSize(mmf, sz);
            }

            /** Add an in-memory file.
     *
     * Params:
     *   fname = simulated in-memory filename
     *   source_code = ?
     */
            void put(FileName fname, Source source_code) @safe pure {
                in_memory[fname] = cast(ubyte[]) source_code.dup;
            }

            /// Returns: range of the filenames in the VFS.
            auto files() pure nothrow const @nogc {
                import std.range : chain;

                return chain(in_memory.byKey, filesys.byKey);
            }

            /**
     * Params:
     *   T = type of the elements of the slice
     *   auto_load = if the file is loaded from the filesystem if it isn't found.
     *
     * Returns: slice of the whole file */
            T slice(T = string, AutoLoad auto_load = AutoLoad.Yes)(FileName fname) {
                ubyte[] data;

                if (auto code = fname in in_memory) {
                    data = (*code)[];
                } else if (auto mmf = fname in filesys) {
                    data = cast(ubyte[])(*mmf).file[0 .. (*mmf).size];
                }

                if (data.length == 0) {
                    // error handling.
                    // Either try to automatically load the file or error out.
                    static if (auto_load == AutoLoad.Yes) {
                        put(fname);
                        return slice!(T, AutoLoad.No)(fname);
                    } else {
                        import std.exception;

                        throw new Exception("File not found in VirtualFileSystem: " ~ fname);
                    }
                }

                import std.utf : validate;

                static auto trustedCast(ubyte[] buf) @trusted {
                    return cast(T) buf;
                }

                auto result = trustedCast(data);

                static if (isSomeString!T) {
                    validate(result);
                }

                return result;
            }
        }

        @Name("Should be an in-memory mapped file")
        unittest {
            VirtualFileSystem vfs;
            string code = "some code";
            auto filename = cast(FileName) "path/to/code.c";

            vfs.put(filename, cast(Source) code);

            vfs.slice(filename).shouldEqual(code);
        }

        @Name("Should be a file from the filesystem")
        unittest {
            import std.path;
            import std.stdio;
            import unit_threaded : Sandbox;

            VirtualFileSystem vfs;
            string code = "content of fun.txt";

            with (immutable Sandbox()) {
                auto filename = cast(FileName) buildPath(testPath, "fun.txt");
                File(filename, "w").write(code);

                vfs.put(filename);

                vfs.slice(filename).shouldEqual(code);
            }
        }

        // keep the clang specifics together in one place

        ///** Returns: a slice starting at the offset of the SourceLocation. */
        T slice(T = string)(VirtualFileSystem vfs, SourceLocation sloc) {
            auto spell = sloc.spelling;
            auto s = vfs.slice!(T, AutoLoad.Yes)(cast(FileName) spell.file.name);
            return s[spell.offset .. $];
        }

        /** Returns: a slice of the text the SourceRanges refers to. */
        T slice(T = string)(VirtualFileSystem vfs, SourceRange srange) {
            // sanity check
            if (!srange.isValid) {
                throw new Exception("Invalid SourceRange");
            }

            auto begin = srange.begin.spelling;
            auto end = srange.end.spelling;

            if (begin.file.name != end.file.name) {
                throw new Exception("Strange SourceRange, begin and end references different files: "
                        ~ begin.file.name ~ " " ~ end.file.name);
            }

            auto s = vfs.slice!(T, AutoLoad.Yes)(cast(FileName) spell.file.name);
            return s[begin.offset .. end.offset];
        }

        CXUnsavedFile[] toClangFiles(ref VirtualFileSystem vfs) {
            import std.algorithm : map;
            import std.array : array;
            import std.string : toStringz;

            return vfs.files.map!((a) {
                auto s = vfs.slice!(ubyte[], AutoLoad.No)(cast(FileName) a);
                return CXUnsavedFile((cast(string) a).toStringz, cast(char*) s.ptr, s.length);
            }).array();
        }
