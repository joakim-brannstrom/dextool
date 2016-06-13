// Scriptlike: Utility to aid in script-like programs.
// Written in the D programming language.

/// Copyright: Copyright (C) 2014-2016 Nick Sabalausky
/// License:   $(LINK2 https://github.com/Abscissa/scriptlike/blob/master/LICENSE.txt, zlib/libpng)
/// Authors:   Nick Sabalausky

module scriptlike.core;

import std.conv;
static import std.file;
static import std.path;
import std.string;

/// If true, all commands will be echoed. By default, they will be
/// echoed to stdout, but you can override this with scriptlikeCustomEcho.
bool scriptlikeEcho = false;

/// Alias for backwards-compatibility. This will be deprecated in the future.
/// You should use scriptlikeEcho insetad.
alias scriptlikeTraceCommands = scriptlikeEcho;

/++
If true, then run, tryRun, file write, file append, and all the echoable
commands that modify the filesystem will be echoed to stdout (regardless
of scriptlikeEcho) and NOT actually executed.

Warning! This is NOT a "set it and forget it" switch. You must still take
care to write your script in a way that's dryrun-safe. Two things to remember:

1. ONLY Scriptlike's functions will obey this setting. Calling Phobos
functions directly will BYPASS this setting.

2. If part of your script relies on a command having ACTUALLY been run, then
that command will fail. You must avoid that situation or work around it.
For example:

---------------------
run(`date > tempfile`);

// The following will FAIL or behave INCORRECTLY in dryrun mode:
auto data = cast(string)read("tempfile");
run("echo "~data);
---------------------

That may be an unrealistic example, but it demonstrates the problem: Normally,
the code above should run fine (at least on posix). But in dryrun mode,
"date" will not actually be run. Therefore, tempfile will neither be created
nor overwritten. Result: Either an exception reading a non-existent file,
or outdated information will be displayed.

Scriptlike cannot anticipate or handle such situations. So it's up to you to
make sure your script is dryrun-safe.
+/
bool scriptlikeDryRun = false;

/++
By default, scriptlikeEcho and scriptlikeDryRun echo to stdout.
You can override this behavior by setting scriptlikeCustomEcho to your own
sink delegate. Since this is used for logging, don't forget to flush your output.

Reset this to null to go back to Scriptlike's default of "echo to stdout" again.

Note, setting this does not automatically enable echoing. You still need to
set either scriptlikeEcho or scriptlikeDryRun to true.
+/
void delegate(string) scriptlikeCustomEcho;

/++
Output text lazily through scriptlike's echo logger.
Does nothing if scriptlikeEcho and scriptlikeDryRun are both false.

The yapFunc version automatically prepends the output with the
name of the calling function. Ex:

----------------
void foo(int i = 42) {
	// Outputs:
	// foo: i = 42
	yapFunc("i = ", i);
}
----------------
+/
void yap(T...)(lazy T args)
{
	import std.stdio;
	
	if(scriptlikeEcho || scriptlikeDryRun)
	{
		if(scriptlikeCustomEcho)
			scriptlikeCustomEcho(text(args));
		else
		{
			writeln(args);
			stdout.flush();
		}
	}
}

///ditto
void yapFunc(string funcName=__FUNCTION__, T...)(lazy T args)
{
	static assert(funcName != "");
	
	auto funcNameSimple = funcName.split(".")[$-1];
	yap(funcNameSimple, ": ", args);
}

/// Maintained for backwards-compatibility. Will be deprecated.
/// Use 'yap' instead.
void echoCommand(lazy string msg)
{
	yap(msg);
}

/++
Interpolated string (ie, variable expansion).

Any D expression can be placed inside ${ and }. Everything between the curly
braces will be evaluated inside your current scope, and passed as a parameter
(or parameters) to std.conv.text.

The curly braces do NOT nest, so variable expansion will end at the first
closing brace. If the closing brace is missing, an Exception will be thrown
at compile-time.

Example:
------------
// Output: The number 21 doubled is 42!
int num = 21;
writeln( mixin(interp!"The number ${num} doubled is ${num * 2}!") );

// Output: Empty braces output nothing.
writeln( mixin(interp!"Empty ${}braces ${}output nothing.") );

// Output: Multiple params: John Doe.
auto first = "John", last = "Doe";
writeln( mixin(interp!`Multiple params: ${first, " ", last}.`) );
------------
+/
string interp(string str)()
{
	enum State
	{
		normal,
		dollar,
		code,
	}

	auto state = State.normal;

	string buf;
	buf ~= '`';

	foreach(char c; str)
	final switch(state)
	{
	case State.normal:
		if(c == '$')
			// Delay copying the $ until we find out whether it's
			// the start of an escape sequence.
			state = State.dollar;
		else if(c == '`')
			buf ~= "`~\"`\"~`";
		else
			buf ~= c;
		break;

	case State.dollar:
		if(c == '{')
		{
			state = State.code;
			buf ~= "`~_interp_text(";
		}
		else if(c == '$')
			buf ~= '$'; // Copy the previous $
		else
		{
			buf ~= '$'; // Copy the previous $
			buf ~= c;
			state = State.normal;
		}
		break;

	case State.code:
		if(c == '}')
		{
			buf ~= ")~`";
			state = State.normal;
		}
		else
			buf ~= c;
		break;
	}
	
	// Finish up
	final switch(state)
	{
	case State.normal:
		buf ~= '`';
		break;

	case State.dollar:
		buf ~= "$`"; // Copy the previous $
		break;

	case State.code:
		throw new Exception(
			"Interpolated string contains an unterminated expansion. "~
			"You're missing a closing curly brace."
		);
	}

	return buf;
}
alias _interp_text = std.conv.text;

version(unittest_scriptlike_d)
unittest
{
	import std.stdio : writeln;
	writeln("Running Scriptlike unittests: interp");

	assert(mixin(interp!"hello") == "hello");
	assert(mixin(interp!"$") == "$");

	int num = 21;
	assert(
		mixin(interp!"The number ${num} doubled is ${num * 2}!") ==
		"The number 21 doubled is 42!"
	);

	assert(
		mixin(interp!"Empty ${}braces ${}output nothing.") ==
		"Empty braces output nothing."
	);

	auto first = "John", last = "Doe";
	assert(
		mixin(interp!`Multiple params: ${first, " ", last}.`) ==
		"Multiple params: John Doe."
	);
}

immutable gagEcho = q{
	auto _gagEcho_saveCustomEcho = scriptlikeCustomEcho;

	scriptlikeCustomEcho = delegate(string str) {};
	scope(exit)
		scriptlikeCustomEcho = _gagEcho_saveCustomEcho;
};

version(unittest_scriptlike_d)
unittest
{
	import std.stdio : writeln;
	writeln("Running Scriptlike unittests: gagecho");
	
	// Test 1
	scriptlikeEcho = true;
	scriptlikeDryRun = true;
	scriptlikeCustomEcho = null;
	{
		mixin(gagEcho);
		assert(scriptlikeEcho == true);
		assert(scriptlikeDryRun == true);
		assert(scriptlikeCustomEcho != null);
	}
	assert(scriptlikeEcho == true);
	assert(scriptlikeDryRun == true);
	assert(scriptlikeCustomEcho == null);
	
	// Test 2
	scriptlikeEcho = false;
	scriptlikeDryRun = false;
	scriptlikeCustomEcho = null;
	{
		mixin(gagEcho);
		assert(scriptlikeEcho == false);
		assert(scriptlikeDryRun == false);
		assert(scriptlikeCustomEcho != null);
	}
	assert(scriptlikeEcho == false);
	assert(scriptlikeDryRun == false);
	assert(scriptlikeCustomEcho == null);
	
	// Test 3
	void testEcho(string str)
	{
		import std.stdio;
		writeln(str);
	}
	scriptlikeEcho = false;
	scriptlikeDryRun = false;
	scriptlikeCustomEcho = &testEcho;
	{
		mixin(gagEcho);
		assert(scriptlikeEcho == false);
		assert(scriptlikeDryRun == false);
		assert(scriptlikeCustomEcho != null);
		assert(scriptlikeCustomEcho != &testEcho);
	}
	assert(scriptlikeEcho == false);
	assert(scriptlikeDryRun == false);
	assert(scriptlikeCustomEcho == &testEcho);
}

// Some tools for Scriptlike's unittests
version(unittest_scriptlike_d)
{
	version(Posix)        enum pwd = "pwd";
	else version(Windows) enum pwd = "cd";
	else static assert(0);

	version(Posix)        enum quiet = " >/dev/null 2>/dev/null";
	else version(Windows) enum quiet = " > NUL 2> NUL";
	else static assert(0);

	immutable initTest(string testName, string msg = null, string module_ = __MODULE__) = `
		import std.stdio: writeln;
		import std.exception;
		import core.exception;
		import scriptlike.core;

		writeln("Testing `~module_~`: `~testName~`");
		scriptlikeEcho = false;
		scriptlikeDryRun = false;
		scriptlikeCustomEcho = null;
	`;
	
	// Generate a temporary filepath unique to the current process and current
	// unittest block. Takes optional id number and path suffix.
	// Guaranteed not to already exist.
	// 
	// Path received can be used as either a file or dir, doesn't matter.
	string tmpName(string id = null, string suffix = null, string func = __FUNCTION__)
	out(result)
	{
		assert(!std.file.exists(result));
	}
	body
	{
		import std.conv : text;
		import std.process : thisProcessID;
		
		// Include some spaces in the path, too:
		auto withoutSuffix = std.path.buildPath(
			std.file.tempDir(),
			text("deleteme.script like.unit test.pid", thisProcessID, ".", func, ".", id)
		);
		unittest_tryRemovePath(withoutSuffix);
		
		// Add suffix
		return std.path.buildPath(withoutSuffix, suffix);
	}
	
	// Get a unique temp pathname (guaranteed not to exist or collide), and
	// clean up at the end up scope, deleting it if it exists.
	// Path received can be used as either a file or dir, doesn't matter.
	immutable useTmpName(string name, string suffix=null) =
		name~" = tmpName(`"~name~"`, `"~suffix~"`);
		scope(exit) unittest_tryRemovePath(tmpName(`"~name~"`));
	";

	// Delete if it already exists, regardless of whether it's a file or directory.
	// Just like `tryRemovePath`, but intentionally ignores echo and dryrun modes.
	void unittest_tryRemovePath(string path)
	out
	{
		assert(!std.file.exists(path));
	}
	body
	{
		if(std.file.exists(path))
		{
			if(std.file.isDir(path))
				std.file.rmdirRecurse(path);
			else
				std.file.remove(path);
		}
	}

	immutable checkResult = q{
		if(scriptlikeDryRun)
			checkPre();
		else
			checkPost();
	};

	// Runs the provided test in both normal and dryrun modes.
	// The provided test can read scriptlikeDryRun and assert appropriately.
	//
	// Automatically ensures the test echoes in the echo and dryrun modes,
	// and doesn't echo otherwise.
	void testFileOperation(string funcName, string msg = null, string module_ = __MODULE__)
		(void delegate() test)
	{
		static import std.stdio;
		import std.stdio : writeln, stdout;
		import std.algorithm : canFind;
		
		string capturedEcho;
		void captureEcho(string str)
		{
			capturedEcho ~= '\n';
			capturedEcho ~= str;
		}
		
		auto originalCurrentDir = std.file.getcwd();
		
		scope(exit)
		{
			scriptlikeEcho = false;
			scriptlikeDryRun = false;
			scriptlikeCustomEcho = null;
		}
		
		// Test normally
		{
			std.stdio.write("Testing ", module_, ".", funcName, (msg? ": " : ""), msg, "\t[normal]");
			stdout.flush();
			scriptlikeEcho = false;
			scriptlikeDryRun = false;
			capturedEcho = null;
			scriptlikeCustomEcho = &captureEcho;

			scope(failure) writeln();
			scope(exit) std.file.chdir(originalCurrentDir);
			test();
			assert(
				capturedEcho == "",
				"Expected the test not to echo, but it echoed this:\n------------\n"~capturedEcho~"------------"
			);
		}
		
		// Test in echo mode
		{
			std.stdio.write(" [echo]");
			stdout.flush();
			scriptlikeEcho = true;
			scriptlikeDryRun = false;
			capturedEcho = null;
			scriptlikeCustomEcho = &captureEcho;

			scope(failure) writeln();
			scope(exit) std.file.chdir(originalCurrentDir);
			test();
			assert(capturedEcho != "", "Expected the test to echo, but it didn't.");
			assert(
				capturedEcho.canFind("\n"~funcName~": "),
				"Couldn't find '"~funcName~": ' in test's echo output:\n------------\n"~capturedEcho~"------------"
			);
		}
		
		// Test in dry run mode
		{
			std.stdio.write(" [dryrun]");
			stdout.flush();
			scriptlikeEcho = false;
			scriptlikeDryRun = true;
			capturedEcho = null;
			scriptlikeCustomEcho = &captureEcho;

			scope(failure) writeln();
			scope(exit) std.file.chdir(originalCurrentDir);
			test();
			assert(capturedEcho != "", "Expected the test to echo, but it didn't.");
			assert(
				capturedEcho.canFind("\n"~funcName~": "),
				"Couldn't find '"~funcName~": ' in the test's echo output:\n------------"~capturedEcho~"------------"
			);
		}

		writeln();
	}

	unittest
	{
		mixin(initTest!"testFileOperation");
		
		testFileOperation!("testFileOperation", "Echo works 1")(() {
			void testFileOperation()
			{
				yapFunc();
			}
			testFileOperation();
		});
		
		testFileOperation!("testFileOperation", "Echo works 2")(() {
			if(scriptlikeEcho)        scriptlikeCustomEcho("testFileOperation: ");
			else if(scriptlikeDryRun) scriptlikeCustomEcho("testFileOperation: ");
			else                      {}
		});
		
		{
			auto countNormal = 0;
			auto countEcho   = 0;
			auto countDryRun = 0;
			testFileOperation!("testFileOperation", "Gets run in each mode")(() {
				if(scriptlikeEcho)
				{
					countEcho++;
					scriptlikeCustomEcho("testFileOperation: ");
				}
				else if(scriptlikeDryRun)
				{
					countDryRun++;
					scriptlikeCustomEcho("testFileOperation: ");
				}
				else
					countNormal++; 
			});
			assert(countNormal == 1);
			assert(countEcho   == 1);
			assert(countDryRun == 1);
		}
		
		assertThrown!AssertError(
			testFileOperation!("testFileOperation", "Echoing even with both echo and dryrun disabled")(() {
				scriptlikeCustomEcho("testFileOperation: ");
			})
		);
		
		assertThrown!AssertError(
			testFileOperation!("testFileOperation", "No echo in echo mode")(() {
				if(scriptlikeEcho)        {}
				else if(scriptlikeDryRun) scriptlikeCustomEcho("testFileOperation: ");
				else                      {}
				})
		);
		
		assertThrown!AssertError(
			testFileOperation!("testFileOperation", "No echo in dryrun mode")(() {
				if(scriptlikeEcho)        scriptlikeCustomEcho("testFileOperation: ");
				else if(scriptlikeDryRun) {}
				else                      {}
				})
		);
	}
}
