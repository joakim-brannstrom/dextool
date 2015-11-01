/++
$(H2 Scriptlike $(SCRIPTLIKE_VERSION))
Utility to aid in script-like programs.

Written in the $(LINK2 http://dlang.org, D programming language).

Automatically pulls in anything from Phobos likely to be useful for scripts.

The public `std.file` and `std.path` imports here are static imports to
avoid name conflicts with the $(API_PATH_EXTR Path)-based wrappers in
`scriptlike.file` and `scriptlike.path`.

curl is omitted here because it involves an extra link dependency.

Copyright: Copyright (C) 2014-2015 Nick Sabalausky
License:   $(LINK2 https://github.com/Abscissa/scriptlike/blob/master/LICENSE.txt, zlib/libpng)
Authors:   Nick Sabalausky
+/

module scriptlike.std;

public import std.algorithm;
public import std.array;
public import std.bigint;
public import std.conv;
public import std.datetime;
public import std.exception;
public import std.getopt;
public import std.math;
public import std.process;
public import std.random;
public import std.range;
public import std.regex;
public import std.stdio;
public import std.string;
public import std.system;
public import std.traits;
public import std.typecons;
public import std.typetuple;
public import std.uni;
public import std.variant;

public static import std.file;
public static import std.path;
