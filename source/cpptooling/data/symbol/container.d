/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.data.symbol.container;

import std.typecons : Flag, Yes, No;

import logger = std.experimental.logger;

//TODO move TypeKind to .data
import cpptooling.analyzer.type : TypeKind;

import cpptooling.data.representation : CppClass;
import cpptooling.data.symbol.types;
import cpptooling.data.type : LocationTag;

version (unittest) {
    import unit_threaded : Name;
    import unit_threaded : shouldEqual;
} else {
    private struct Name {
        string name_;
    }
}

/** Wrapper for the results from the find-methods in Container.
 *
 * payload is never null.
 */
@safe pure nothrow @nogc struct FindResult(T) {
    private T* payload;

    ///
    ref T get() @trusted
    out (result) {
        assert(payload !is null);
    }
    body {
        return *payload;
    }

    alias get this;
}

/* The design is such that the memory location of a stored value do not
 * change after storage.
 * Therefor storing both the ptr and a fast lookup into the stored
 * instances.
 *
 * TODO change to using the experimental allocators instead of the GC.
 * TODO Probably ensure that K is an integer to lower the memory pressure.
 * TODO bad name, change to something else more telling. Ok for now because the
 * type isn't exposed.
 */
private struct FastLookup(T, K) {
    T*[] instances;
    T*[K] lookup;

    invariant() {
        assert(instances.length == lookup.length);
    }

    /** The instance and corresponding key must be unique.
     *
     * The callers responsiblity to ensure uniqueness.  If broken, assert.
     */
    ref T put(T instance, in K key)
    in {
        assert((key in lookup) is null);
    }
    body {
        auto heap = new T;
        *heap = instance;

        instances ~= heap;
        lookup[key] = heap;

        return *heap;
    }

    auto find(in K key) const {
        import std.range : only, dropOne;

        auto item = key in lookup;
        if (item is null) {
            return only(FindResult!(const(T))(null)).dropOne;
        }

        return only(FindResult!(const(T))(*item));
    }

    auto lookupRange() @trusted const {
        return lookup.byKeyValue();
    }

    auto opSlice() @safe pure nothrow {
        import std.algorithm : map;

        return instances.map!(a => *a);
    }

    auto opSlice() @safe pure nothrow const {
        import std.algorithm : map;

        return instances.map!(a => *a);
    }
}

@Name("Should be a zero-length range")
unittest {
    auto inst = FastLookup!(int, int)();
    auto result = inst.find(0);

    result.length.shouldEqual(0);
}

/** Location of all declarations.
 *
 * Assuming that there can only be one definition but multiple declarations.
 *
 * A location of kind "noloc" do NOT mean that there exist a
 * definition/declaration. See the hasXXX-methods.
 *
 * Only the first declaration is saved to be used as a fallback for those
 * occasions when a definition isn't found.
 *
 * Remember that for those users of DeclLocation that do not have a
 * cache/delaying the decision until all files have been analyzed base may base
 * their decision on the first occurens. Therefor to be less surprising to the
 * user the first one is saved and the rest discarded.
 *
 * TODO save all declarations? Remember that it may take a lot of memory.
 *
 * Hint, the name DeclLocation was chosen because a definition is a declaration
 * so it encapsulates both.
 */
private @safe struct DeclLocation {
    import std.range : only, dropOne;
    import std.typecons : Nullable;

    this(DeclLocation other) @safe {
        this = other;
    }

    // TODO change name to anyOfDeclaratoinOrDefinition to be self explaining
    /** A range of one location if any is set.
     *
     * Priority is definition -> declaration.
     */
    auto any() pure nothrow const @nogc {
        auto rval = only(const(LocationTag).init).dropOne;

        if (hasDefinition) {
            rval = only(definition_.get);
        } else if (hasDeclaration) {
            rval = only(first_decl.get);
        }

        return rval;
    }

    @property ref const(LocationTag) definition() pure nothrow const @nogc {
        return definition_.get;
    }

    @property ref const(LocationTag) definition(inout LocationTag d) {
        // It is NOT this functions responsiblity to detect multiple
        // definitions. Detecting involves logic, error reporting etc that is
        // not suitable to put here.

        definition_ = d;
        return definition_.get;
    }

    @property ref const(LocationTag) declaration() pure nothrow const @nogc {
        return first_decl.get;
    }

    @property ref const(LocationTag) declaration(inout LocationTag d) {
        if (first_decl.isNull) {
            first_decl = d;
        }

        return first_decl.get;
    }

    bool hasDefinition() pure nothrow const @nogc {
        return !definition_.isNull && definition_.kind != LocationTag.Kind.noloc;
    }

    bool hasDeclaration() pure nothrow const @nogc {
        return !first_decl.isNull && first_decl.kind != LocationTag.Kind.noloc;
    }

private:
    Nullable!LocationTag definition_;
    Nullable!LocationTag first_decl;
}

/** Contain symbols found during analyze.
 */
struct Container {
    import std.format : FormatSpec;

    private {
        FastLookup!(CppClass, FullyQualifiedNameType) classes;
        FastLookup!(TypeKind, USRType) types;
        FastLookup!(DeclLocation, USRType) locations;
    }

    // Forbid moving. The container is "heavy" and it results in assert errors
    // when moved. If moving is implemented then duplication of the FastLookup
    // need to be performed.
    @disable this(this);

    /** Find the symbol corresponding to the key.
     *
     * Unified Symbol Resolution (USR).
     *
     * Params:
     *   usr = key to look for.
     */
    auto find(T)(USRType usr) const if (is(T == TypeKind))
    out (result) {
        logger.tracef("Find %susr:%s", result.length == 0 ? "failed, " : "", cast(string) usr);
    }
    body {
        return types.find(usr);
    }

    /** Find the location associated with the key.
     *
     * Unified Symbol Resolution (USR).
     *
     * Params:
     *   usr = key to look for.
     */
    auto find(T)(USRType usr) const if (is(T == LocationTag))
    out (result) {
        logger.tracef("Find %susr:%s", result.length == 0 ? "failed, " : "", cast(string) usr);
    }
    body {
        return locations.find(usr);
    }

    /// Find the class with the fully qualified name as key.
    auto find(T)(FullyQualifiedNameType fqn) if (is(T == CppClass))
    out (result) {
        logger.tracef(result.length == 0, "No symbol found for '%s'", cast(string) fqn);
    }
    body {
        return classes.find(fqn);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.algorithm : map, copy;
        import std.ascii : newline;
        import std.format : formattedWrite, formatValue;
        import std.range.primitives : put;
        import std.conv : to;
        import cpptooling.analyzer.type : internalGetFmt;
        import cpptooling.data.type : LocationTag;

        // avoid allocating

        put(w, "classes [");
        foreach (a; classes[]) {
            put(w, newline);
            put(w, "  ");
            put(w, cast(string) a.fullyQualifiedName);
        }
        put(w, "]\n");
        put(w, "types [");
        foreach (a; types[]) {
            formattedWrite(w, "\n  %s %s -> %s", a.info.kind.to!string(),
                    cast(string) a.usr, a.internalGetFmt);
        }
        put(w, "]\n");
        put(w, "locations [");
        () @trusted{
            foreach (a; locations.lookupRange) {
                formattedWrite(w, "\n  %s ->", cast(string) a.key);
                if (a.value.hasDefinition) {
                    put(w, " ");
                    put(w, a.value.definition.toString);
                }
                if (a.value.hasDeclaration) {
                    formattedWrite(w, "\n    %s", a.value.declaration.toString);
                }
            }
        }();
        put(w, "]");
    }

    string toString() @safe const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) { buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    /** Store the TypeKind.
     *
     * The TypeKind's usr is used as key.
     */
    void put(TypeKind value) @safe
    in {
        assert(value.usr.length > 0);
    }
    body {
        if (value.usr in types.lookup) {
            return;
        }

        auto latest = types.put(value, value.usr);

        debug {
            import std.conv : to;
            import cpptooling.analyzer.type : TypeKind, toStringDecl, TypeAttr;
            import cpptooling.data.type : LocationTag, Location;

            logger.tracef("Stored kind:%s usr:%s repr:%s", latest.info.kind.to!string,
                    cast(string) latest.usr, latest.toStringDecl(TypeAttr.init, "x"));
        }
    }

    /** Store the CppClass.
     *
     * Assuming that the fully qualified name is unique throughout the program.
     */
    void put(T)(ref T cl, FullyQualifiedNameType fqn) if (is(T : CppClass)) {
        if (fqn in classes.lookup) {
            return;
        }

        classes.put(cl, fqn);
    }

    void put(LocationTag location, USRType usr, Flag!"isDefinition" is_definition) @safe {
        auto found_decl = usr in locations.lookup;

        // ensure it exists
        if (found_decl is null) {
            DeclLocation dummy;
            locations.put(dummy, usr);
            found_decl = usr in locations.lookup;
        }

        auto decl = *found_decl;

        if (is_definition) {
            if (decl.hasDefinition) {
                debug logger.tracef("Definition already in container, %s (%s)",
                        cast(string) usr, location);
            } else {
                decl.definition = location;
            }
        } else {
            decl.declaration = location;
        }
    }
}

@Name("Should find the value corresponding to the key")
unittest {
    import cpptooling.data.type : Location;

    Container cont;

    auto kind = TypeKind(null, USRType("key"));
    cont.put(kind);
    {
        auto result = cont.find!TypeKind(USRType("key"));
        result.length.shouldEqual(1);
        (cast(string) result.front.usr).shouldEqual("key");
    }

    auto loc = LocationTag(Location("file.h", 1, 2));
    cont.put(loc, USRType("file"), Yes.isDefinition);
    {
        auto result = cont.find!LocationTag(USRType("file"));
        result.length.shouldEqual(1);
        result.front.definition.file.shouldEqual("file.h");
    }
}

@Name("Should skip inserting the value if it already exist in the container")
unittest {
    import cpptooling.data.type : Location;

    Container cont;

    auto kind = TypeKind(null, USRType("key"));
    cont.put(kind);
    cont.put(kind);
    cont.find!TypeKind(USRType("key")).length.shouldEqual(1);

    auto loc = LocationTag(Location("file.h", 1, 2));
    cont.put(loc, USRType("file"), Yes.isDefinition), cont.put(loc,
            USRType("file"), Yes.isDefinition),
        cont.find!LocationTag(USRType("file")).length.shouldEqual(1);
}

@Name("should be able to use the found class")
unittest {
    import cpptooling.data.representation : CppClass, CppClassName;

    auto c = CppClass(CppClassName("Class"));

    Container cont;
    cont.put(c, c.fullyQualifiedName);

    // not really needed test but independent at two places, see the invariant.
    1.shouldEqual(cont.classes[].length);

    // should be able to find a stored class by the FQN
    auto found_class = cont.find!CppClass(FullyQualifiedNameType("Class")).front;

    // should be able to use the found class
    "Class".shouldEqual(cast(string) found_class.name);
}

@Name("should list all contained items")
unittest {
    import std.conv : to;
    import cpptooling.data.representation : CppClass, CppClassName;
    import cpptooling.data.type : Location;
    import test.extra_should : shouldEqualPretty;

    Container cont;

    for (auto i = 0; i < 2; ++i) {
        auto c = CppClass(CppClassName("Class" ~ to!string(i)));
        cont.put(c, c.fullyQualifiedName);

        auto loc = LocationTag(Location("file" ~ to!string(i), 1, 2));
        cont.put(loc, USRType("key" ~ to!string(i)), cast(Flag!"isDefinition")(i % 2 == 0));

        auto kind = TypeKind(null, USRType("key" ~ to!string(i)));
        cont.put(kind);
    }

    cont.toString.shouldEqualPretty("classes [
  Class0
  Class1]
types [
  null_ key0 -> kind is @null@
  null_ key1 -> kind is @null@]
locations [
  key1 ->
    File:file1 Line:1 Column:2
  key0 -> File:file0 Line:1 Column:2]");
}

@Name("Should allow only one definition location but multiple declaration locations")
unittest {
    import cpptooling.data.type : Location;

    Container cont;

    auto loc = LocationTag(Location("file.h", 1, 2));
}
