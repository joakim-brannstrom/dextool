// Scriptlike: Utility to aid in script-like programs.
// Written in the D programming language.

/// Copyright: Copyright (C) 2014-2015 Nick Sabalausky
/// License:   $(LINK2 https://github.com/Abscissa/scriptlike/blob/master/LICENSE.txt, zlib/libpng)
/// Authors:   Nick Sabalausky

module scriptlike.fail;

import std.conv;
import std.file;
import std.path;
import std.traits;

// Throwable.toString(sink) isn't an override on DMD 2.064.2, and druntime
// won't even call any Throwable.toString on DMD 2.064.2 anyway, so use
// a fallback method if Throwable doesn't have toString(sink).
static if( MemberFunctionsTuple!(Throwable, "toString").length > 1 )
	private enum useFallback = false;
else
	private enum useFallback = true;

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
		throw cast(Fail) cast(void*) Fail.classinfo.init;
	}
	
	private static string fullMessage(string msg = Fail.msg)
	{
		auto appName = thisExePath().baseName();

		version(Windows)
			appName = appName.stripExtension();

		return appName~": ERROR: "~msg;
	}
	
	static if(!useFallback)
	{
		override void toString(scope void delegate(in char[]) sink) const
		{
			sink(fullMessage());
		}
	}
}

/++
Call this to end your program with an error message for the user, and no
ugly stack trace. The error message is sent to stderr and the errorlevel is
set to non-zero.

This is exception-safe, all cleanup code gets run.

Your program's name is automatically detected from $(STD_FILE thisExePath).

Note, on DMD 2.064.2, the error message is displayed BEFORE the exception is
thrown. So if you catch the Fail exception, the message will have already been
displayed. This is due to limitations in the older druntime, and is fixed
on DMD 2.065 and up.

Example:
----------------
auto id = 3;
fail("You forgot to provide a destination for id #", id, "!");

// Output on DMD 2.065 and up:
// yourProgramName: ERROR: You forgot to provide a destination for id #3!

// Output on DMD 2.064.2:
// yourProgramName: ERROR: You forgot to provide a destination for id #3!
// scriptlike.fail.Fail
----------------
+/
void fail(T...)(T args)
{
	static if(useFallback)
	{
		import std.stdio;
		stderr.writeln(Fail.fullMessage( text(args) ));
		stderr.flush();
	}
	
	throw Fail( text(args) );
}

/++
Calls fail() if the condition is false.

This is much like $(FULL_STD_EXCEPTION enforce), but for for fail() instead of
arbitrary exceptions.

Example:
----------------
failEnforce(brokenSquareRoot(4)==2, "Reality broke! Expected 2, not ", brokenSquareRoot(4));

// Output on DMD 2.065 and up:
// yourProgramName: ERROR: Reality broke! Expected 2, not 555

// Output on DMD 2.064.2:
// yourProgramName: ERROR: Reality broke! Expected 2, not 555
// scriptlike.fail.Fail
----------------
+/
void failEnforce(T...)(bool cond, T args)
{
	if(!cond)
		fail(args);
}
