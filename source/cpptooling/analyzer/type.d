/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com).
///
/// Extracted information of types.
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module cpptooling.analyzer.type;

import std.conv : to;
import std.string : format;
import std.traits;
import logger = std.experimental.logger;

/** Type represenation and information.
 *
 * txt is type, qualifiers and storage class. For example const int *.
 */
pure @safe nothrow @nogc struct TypeKind {
    import std.traits : isSomeString;
    import cpptooling.utility.taggedalgebraic : TaggedAlgebraic;

    /** The type 'int x[2][3]'
     * elementType = int
     * indexes = [2][3]
     * fmt = %s %s%s
     */
    static struct ArrayInfo {
        string elementType;
        string indexes;
        string fmt;
    }

    /** The type 'extern int (*e_g)(int pa)'
     * fmt = int (*%s)(int pa)
     *
     * TODO improve formatting with more separation, f.e return, ptr and args.
     */
    static struct FuncPtrInfo {
        string fmt;
    }

    /** Textual representation of simple types.
     *
     * The type const int x would be:
     *
     * TODO add the following:
     * fmt = const int %s
     */
    static struct SimpleInfo {
        string fmt;
    }

    /// Formatting information needed to reproduce the type and identifier.
    static union InternalInfo {
        typeof(null) null_;
        SimpleInfo simple;
        ArrayInfo array;
        FuncPtrInfo funcPtr;
    }

    alias Info = TaggedAlgebraic!InternalInfo;
    Info info;

    bool isConst;
    bool isRef;
    bool isPointer;
    bool isFuncPtr;
    bool isArray;

    /** The full type with storage classes and operators.
     * Example
     * ---
     * const int&
     * ---
     */
    string toString() @property const {
        return txt_;
    }

    auto txt() const {
        return txt_;
    }

    auto txt(string s) {
        if (txt_ is null)
            txt_ = s;
    }

private:
    string txt_;
}

///TODO change the bools to using the Flag from typecons
TypeKind makeTypeKind(string txt, bool isConst, bool isRef, bool isPointer,
    bool isFuncPtr = false, bool isArray = false) pure @safe nothrow {
    TypeKind t;
    t.info = TypeKind.SimpleInfo(txt ~ " %s");
    t.txt = txt;
    t.isConst = isConst;
    t.isRef = isRef;
    t.isPointer = isPointer;
    t.isFuncPtr = isFuncPtr;
    t.isArray = isArray;

    return t;
}

/// Return a duplicate.
/// Side effect is that the cursor is thrown away.
/// TODO investigate how this can be done with opAssign and postblit.
TypeKind duplicate(T)(T t_in) pure @safe nothrow {
    TypeKind t = makeTypeKind(t_in.txt, t_in.isConst, t_in.isRef,
        t_in.isPointer, t_in.isFuncPtr, t_in.isArray);
    t.info = t_in.info;

    return t;
}
