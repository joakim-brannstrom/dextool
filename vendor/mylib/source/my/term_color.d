/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Terminal colors. initColors must be called for the colors to be activated.
Colors are automatically toggled off if the output is not an interactive tty.
This can be bypassed by calling initColors with `true`.
*/
module my.term_color;

import std.stdio : writefln, stderr, stdout;
import logger = std.experimental.logger;

@("shall print colors, backgrounds and modes")
unittest {
    import std.stdio;
    import std.traits;
    import std.conv;
    import std.string;

    initColors(true);

    foreach (c; EnumMembers!Color) {
        write(c.to!string.color(c).toString.rightJustify(30));
        foreach (m; EnumMembers!Mode) {
            writef(" %s", m.to!string.color(c).mode(m));
        }
        writeln;
    }
    foreach (c; EnumMembers!Background) {
        write(c.to!string.color.bg(c).toString.rightJustify(30));
        foreach (m; EnumMembers!Mode) {
            writef(" %s", m.to!string.color.bg(c).mode(m));
        }
        writeln;
    }
}

private template BaseColor(int n) {
    enum BaseColor : int {
        none = 39 + n,

        black = 30 + n,
        red = 31 + n,
        green = 32 + n,
        yellow = 33 + n,
        blue = 34 + n,
        magenta = 35 + n,
        cyan = 36 + n,
        white = 37 + n,

        lightBlack = 90 + n,
        lightRed = 91 + n,
        lightGreen = 92 + n,
        lightYellow = 93 + n,
        lightBlue = 94 + n,
        lightMagenta = 95 + n,
        lightCyan = 96 + n,
        lightWhite = 97 + n,
    }
}

alias Color = BaseColor!0;
alias Background = BaseColor!10;

enum Mode {
    none = 0,
    bold = 1,
    underline = 4,
    blink = 5,
    swap = 7,
    hide = 8,
}

struct ColorImpl {
    import std.format : FormatSpec;

    private {
        string text;
        Color fg_;
        Background bg_;
        Mode mode_;
    }

    this(string txt) @safe pure nothrow @nogc {
        text = txt;
    }

    this(string txt, Color c) @safe pure nothrow @nogc {
        text = txt;
        fg_ = c;
    }

    ColorImpl opDispatch(string fn)() {
        import std.conv : to;
        import std.string : toLower;

        static if (fn.length >= 2 && (fn[0 .. 2] == "fg" || fn[0 .. 2] == "bg")) {
            static if (fn[0 .. 2] == "fg") {
                fg_ = fn[2 .. $].toLower.to!Color;
            } else static if (fn[0 .. 2] == "bg") {
                bg_ = fn[2 .. $].toLower.to!Background;
            } else {
                static assert("unable to handle " ~ fn);
            }
        } else {
            mode_ = fn.to!Mode;
        }
        return this;
    }

    ColorImpl fg(Color c_) @safe pure nothrow @nogc {
        this.fg_ = c_;
        return this;
    }

    ColorImpl bg(Background c_) @safe pure nothrow @nogc {
        this.bg_ = c_;
        return this;
    }

    ColorImpl mode(Mode c_) @safe pure nothrow @nogc {
        this.mode_ = c_;
        return this;
    }

    string toString() @safe const {
        import std.exception : assumeUnique;
        import std.format : FormatSpec;

        char[] buf;
        buf.reserve(100);
        auto fmt = FormatSpec!char("%s");
        toString((const(char)[] s) @safe const{ buf ~= s; }, fmt);
        auto trustedUnique(T)(T t) @trusted {
            return assumeUnique(t);
        }

        return trustedUnique(buf);
    }

    void toString(Writer, Char)(scope Writer w, FormatSpec!Char fmt) const {
        import std.format : formattedWrite;
        import std.range.primitives : put;

        if (!_printColors || (fg_ == Color.none && bg_ == Background.none && mode_ == Mode.none))
            put(w, text);
        else
            formattedWrite(w, "\033[%d;%d;%dm%s\033[0m", mode_, fg_, bg_, text);
    }
}

auto color(string s, Color c = Color.none) @safe pure nothrow @nogc {
    return ColorImpl(s, c);
}

@("shall be safe/pure/nothrow/nogc to color a string")
@safe pure nothrow @nogc unittest {
    auto s = "foo".color(Color.red).bg(Background.black).mode(Mode.bold);
}

@("shall be safe to color a string")
@safe unittest {
    initColors(true);
    auto s = "foo".color(Color.red).bg(Background.black).mode(Mode.bold).toString;
}

@("shall use opDispatch for config")
@safe unittest {
    import std.stdio;

    initColors(true);
    writeln("opDispatch".color.fgred);
    writeln("opDispatch".color.bgGreen);
    writeln("opDispatch".color.bold);
    writeln("opDispatch".color.fgred.bggreen.bold);
}

/** It will detect whether or not stdout/stderr are a console/TTY and will
 * consequently disable colored output if needed.
 *
 * Forgetting to call the function will result in ASCII escape sequences in the
 * piped output, probably an undesiderable thing.
 */
void initColors(bool forceOn = false) @trusted {
    if (forceOn) {
        _printColors = true;
        return;
    }

    if (_isColorsInitialized)
        return;
    scope (exit)
        _isColorsInitialized = true;

    version (Windows) {
        _printColors = false;
    } else {
        import my.tty;

        _printColors = isStdoutInteractive && isStderrInteractive;
    }
}

private:

/** Whether to print text with colors or not
 *
 * Defaults to true but will be set to false in initColors() if stdout or
 * stderr are not a TTY (which means the output is probably being piped and we
 * don't want ASCII escape chars in it)
*/
private shared bool _printColors = false;
private shared bool _isColorsInitialized = false;
