/**
Copyright: Copyright (c) 2015-2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Basic support structure for enabling semantic representation in D of languages.
Assuming that submodules need:
 - indentation.
 - key/value store.
 - recursing rendering.
*/
module dsrcgen.base;

@safe:

private struct KV {
    string k;
    string v;

    this(T)(string k, T v) {
        import std.conv : to;

        this.k = k;
        this.v = to!string(v);
    }
}

package struct AttrSetter {
    template opDispatch(string name) {
        @property auto opDispatch(T)(T v) {
            static if (name.length > 1 && name[$ - 1] == '_') {
                return KV(name[0 .. $ - 1], v);
            } else {
                return KV(name, v);
            }
        }
    }
}

public:

/// Methods for setting attributes inside slice operator via $.x.
mixin template Attrs() {
    import std.string;

    public string[string] attrs;

    auto opIndex(T...)(T kvs) {
        foreach (kv; kvs) {
            attrs[kv.k] = kv.v;
        }
        return this;
    }

    auto opDollar(int dim)() {
        return AttrSetter();
    }
}

/** Interface for rendering functionality.
 *
 * After the semantic representation is finished the BaseElement interface is
 * used to recursively render the representation.
 */
interface BaseElement {
    /// Recursively render the modules.
    string render();

    /// Query the module for an indented string representation.
    string renderIndent(int parent_level, int level);

    /// Query the module for a concatenated string of the childrens representation.
    string renderRecursive(int parent_level, int level);

    /// Query the module for post recursive data.
    string renderPostRecursive(int parent_level, int level);
}

/// Raw text representation without indentation.
class Text(T) : T {
    private string contents;

    /// Use content as is.
    this(string contents) {
        this.contents = contents;
    }

    /// Render content without indentation.
    override string renderIndent(int parent_level, int level) {
        return contents;
    }
}

/** Common functionality for modules.
 *
 * Support indentation.
 * Children structure.
 * Recursive rendering of content + children.
 * Line separation independent of accidental sep().
 *
 * TODO refactor, lessen the coupling by moving functionality to pure, free functions.
 * TODO refactor, use a GC-less allocator like Array.
 * TODO refactor, toString to support the range versions with a sink.
 */
class BaseModule : BaseElement {
    /// Empty with defaults.
    this() {
    }

    /** Module with a indent different fro default
     * Params:
     *  indent_width = number of whitespaces to use as indent for each level
     */
    this(int indent_width) {
        this.indent_width = indent_width;
    }

    /** Set indent suppression from this point and all children.
     *
     * Number of levels to suppress indent of children.
     * Propagated to leafs.
     *
     * It can't suppress indent to lower than parent.
     * To suppress further use suppressThisIndent.
     *
     * Params:
     *  levels = nr of indentation levels to suppress
     */
    void suppressIndent(int levels) {
        this.suppress_child_indent = levels;
    }

    /** Suppress indentation by also affecting the level propagated from the parent.
     *
     * Params:
     *  levels = nr of indentation levels to suppress
     */
    void suppressThisIndent(int levels) {
        this.suppress_indent = levels;
    }

    /// Sets the width of the indentation
    void setIndentation(int ind) {
        this.indent_width = ind;
    }

    /// Clear the node of childrens.
    auto reset() {
        children.length = 0;
        return this;
    }

    /// Separate with at most count empty lines.
    void sep(int count = 1) {
        import std.ascii : newline;

        count -= sep_lines;
        if (count <= 0)
            return;
        foreach (i; 0 .. count) {
            children ~= new Text!(typeof(this))(newline);
        }

        sep_lines += count;
    }

    /** Insert element at the front.
     *
     * Resets line separation.
     *
     * TODO change to insertFront to be consistent with std.container API.
     */
    void prepend(BaseElement e) {
        children = e ~ children;
        sep_lines = 0;
    }

    /** Insert element at the back.
     *
     * Resets line separation.
     *
     * TODO change to insertBack to be consistent with std.container API.
     */
    void append(BaseElement e) {
        children ~= e;
        sep_lines = 0;
    }

    /** Remove all children and clear line separation.
     *
     * Resets line separation.
     * Why?
     * Conceptually restarts the container so no children then nothing to
     * separate with empty lines.
     */
    void clearChildren() {
        children.length = 0;
        sep_lines = 0;
    }

    /** Render content with an indentation that takes the parent in
     * consideration.
     */
    string indent(string s, int parent_level, int level) const {
        import std.algorithm : max;

        level = max(0, parent_level, level);
        char[] indent;
        indent.length = indent_width * level;
        indent[] = ' ';

        return indent.idup ~ s;
    }

    override string renderIndent(int parent_level, int level) {
        return "";
    }

    override string renderRecursive(int parent_level, int level) {
        import std.algorithm : max;

        level -= suppress_indent;
        string s = renderIndent(parent_level, level);

        // suppressing is intented to affects children. The current leaf is
        // intented according to the parent or propagated level.
        int child_level = level - suppress_child_indent;
        foreach (e; children) {
            // lock indent to the level of the parent. it allows a suppression of many levels of children.
            s ~= e.renderRecursive(max(parent_level, level), child_level + 1);
        }
        s ~= renderPostRecursive(parent_level, level);

        return s;
    }

    override string renderPostRecursive(int parent_level, int level) {
        return "";
    }

    override string render() {
        return renderRecursive(0 - suppress_child_indent, 0 - suppress_child_indent);
    }

private:
    int indent_width = 4;
    int suppress_indent;
    int suppress_child_indent;

    BaseElement[] children;
    int sep_lines;
}
