// Scriptlike: Utility to aid in script-like programs.
// Written in the D programming language.

/// Copyright: Copyright (C) 2014-2016 Nick Sabalausky
/// License:   $(LINK2 https://github.com/Abscissa/scriptlike/blob/master/LICENSE.txt, zlib/libpng)
/// Authors:   Nick Sabalausky

module scriptlike.fail;

import std.conv;
import std.file;
import std.path;
import std.traits;

/// This is the exception thrown by fail(). There's no need to create or throw
/// this directly, but it's public in case you have reason to catch it.
class Fail : Exception
{
	private this()
	{
		super(null);
	}
	
	private static string msg;
	private static Fail opCall(string msg, string file=__FILE__, int line=__LINE__)
	{
		Fail.msg = msg;
		static if(__traits(compiles, Fail.classinfo.initializer))
			// DMD 2.072 or 2.073 deprecates 'classinfo.init'
			throw cast(Fail) cast(void*) Fail.classinfo.initializer;
		else
			// DMD 2.069.2 and below lack 'classinfo.initializer'
			throw cast(Fail) cast(void*) Fail.classinfo.init;
	}
	
	private static string fullMessage(string msg = Fail.msg)
	{
		auto appName = thisExePath().baseName();

		version(Windows)
			appName = appName.stripExtension();

		return appName~": ERROR: "~msg;
	}
	
	override void toString(scope void delegate(in char[]) sink) const
	{
		sink(fullMessage());
	}
}

/++
Call this to end your program with an error message for the user, and no
ugly stack trace. The error message is sent to stderr and the errorlevel is
set to non-zero.

This is exception-safe, all cleanup code gets run.

Your program's name is automatically detected from $(STD_FILE thisExePath).

Example:
----------------
auto id = 3;
fail("You forgot to provide a destination for id #", id, "!");

// Output:
// yourProgramName: ERROR: You forgot to provide a destination for id #3!
----------------
+/
void fail(T...)(T args)
{
	throw Fail( text(args) );
}

/++
Calls fail() if the condition is false.

This is much like $(FULL_STD_EXCEPTION enforce), but for for fail() instead of
arbitrary exceptions.

Example:
----------------
failEnforce(brokenSquareRoot(4)==2, "Reality broke! Expected 2, not ", brokenSquareRoot(4));

// Output:
// yourProgramName: ERROR: Reality broke! Expected 2, not 555
----------------
+/
void failEnforce(T...)(bool cond, T args)
{
	if(!cond)
		fail(args);
}
