/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
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
module cpptooling.utility.stack;

/// Keep track of the depth in the AST.
struct VisitNodeDepth {
public:
    /// Increment the AST depth.
    void incr() {
        level++;
    }

    /// Pop the stack if depth matches depth of top element of stack.
    void decr() {
        level--;
    }

    /// Return: AST depth when traversing.
    @property auto depth() {
        return level;
    }

private:
    int level;
}

/** Stack useful when visiting the AST.
 * Could be used to know what node to attach code in.
 * Params:
 *  Tmodule = object type to build the stack of
 * Example:
 * ---
 * mixin VisitNodeModule!CppModule;
 * CppModule node;
 * push(node);
 * current.sep();
 * ---
 */
struct VisitNodeModule(Tmodule) {
public:
    /// Increment the AST depth.
    void incr() {
        level++;
    }

    /// Pop the stack if depth matches depth of top element of stack.
    void decr() {
        stack.pop(level);
        level--;
    }

    /// Return: AST depth when traversing.
    @property auto depth() {
        return level;
    }

    @property auto current() {
        return stack.top;
    }

    /** Push an element to the stack together with current AST depth.
     * Params:
     *  c = Element to push
     *
     * Return: Pushed element.
     */
    auto push(T)(T c) {
        return stack.push(level, cast(Tmodule) c);
    }

private:
    alias StackType = IdStack!(int, Tmodule);
    StackType stack;
    int level;
}

/** Stack with a discrete id that is only popped when the id matches top of stack.
 * If the stack is empty then Tvalue.init is returned from current.
 *
 * TODO add a contract that invariant stack_id.length == stack_value.length
 *
 * Keeping two stacks and in sync for easier access to the full stack of values.
 * Useful when the stack of values is transformed to other data structures.
 * Example
 * ---
 * import std.array : join;
 * IdStack!(int, string) ns;
 * ns.push(0, "std");
 * ns.push(1, "BaseClass");
 * writeln(join(ns.values, "::"));
 * ---
 * output: std::BaseClass
 *
 * Example:
 * ---
 * IdStack!(int, int) s;
 * s.push(2, 0);
 * s.push(5, 1);
 * s.push(7, 5);
 * for (int i = 8; i != 0; --i) {
 *    s.pop(i);
 *    write(s.current, " ");
 * }
 * ---
 * output: 7 7 7 5 5 5 5 2 0
 */
struct IdStack(Tid, Tvalue) {
    import std.typecons : NullableRef;

    ref auto push(Tid id, Tvalue c) {
        stack_id ~= id;
        stack_value ~= c;
        return stack_value[$ - 1];
    }

    /** Pop from stack all items that have a matching id.
     */
    void pop(Tid id) {
        while (stack_value.length > 0 && stack_id[$ - 1] == id) {
            stack_value.length = stack_value.length - 1;
            stack_id.length = stack_id.length - 1;
        }
    }

    @property auto top() {
        NullableRef!Tvalue r;
        if (stack_value.length > 0)
            r.bind(&stack_value[$ - 1]);
        return r;
    }

    @property auto size() {
        return stack_value.length;
    }

    @property const ref auto values() {
        return stack_value;
    }

private:
    Tid[] stack_id;
    Tvalue[] stack_value;
}
