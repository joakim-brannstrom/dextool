// Scriptlike: Utility to aid in script-like programs.
// Written in the D programming language.

/// Copyright: Copyright (C) 2014-2015 Nick Sabalausky
/// License:   $(LINK2 https://github.com/Abscissa/scriptlike/blob/master/LICENSE.txt, zlib/libpng)
/// Authors:   Nick Sabalausky

module scriptlike.process;

import std.array;
import std.conv;
import std.process;
import std.range;

import scriptlike.core;
import scriptlike.path;
import scriptlike.file;

/// Indicates a command returned a non-zero errorlevel.
class ErrorLevelException : Exception
{
	int errorLevel;
	string command;
	
	/// The command's output is only available if the command was executed with
	/// runCollect. If it was executed with run, then Scriptlike doesn't have
	/// access to the output since it was simply sent straight to stdout/stderr.
	string output;
	
	this(int errorLevel, string command, string output=null, string file=__FILE__, size_t line=__LINE__)
	{
		this.errorLevel = errorLevel;
		this.command = command;
		this.output = output;
		auto msg = text("Command exited with error level ", errorLevel, ": ", command);
		if(output)
			msg ~= text("\nCommand's output:\n------\n", output, "------\n");
		super(msg, file, line);
	}
}

/++
Runs a command, through the system's command shell interpreter,
in typical shell-script style: Synchronously, with the command's
stdout/in/err automatically forwarded through your
program's stdout/in/err.

Optionally takes a working directory to run the command from.

The command is echoed if scriptlikeEcho is true.

ErrorLevelException is thrown if the process returns a non-zero error level.
If you want to handle the error level yourself, use tryRun instead of run.

Example:
---------------------
Args cmd;
cmd ~= Path("some tool");
cmd ~= "-o";
cmd ~= Path(`dir/out file.txt`);
cmd ~= ["--abc", "--def", "-g"];
Path("some working dir").run(cmd.data);
---------------------
+/
void run(string command)
{
	yapFunc(command);
	mixin(gagEcho);

	auto errorLevel = tryRun(command);
	if(errorLevel != 0)
		throw new ErrorLevelException(errorLevel, command);
}

///ditto
void run(Path workingDirectory, string command)
{
	auto saveDir = getcwd();
	workingDirectory.chdir();
	scope(exit) saveDir.chdir();
	
	run(command);
}

version(unittest_scriptlike_d)
unittest
{
	import std.string : strip;

	string scratchDir;
	string targetFile;
	string expectedContent;
	void checkPre()
	{
		assert(!std.file.exists(targetFile));
	}

	void checkPost()
	{
		assert(std.file.exists(targetFile));
		assert(std.file.isFile(targetFile));
		assert(strip(cast(string) std.file.read(targetFile)) == expectedContent);
	}

	testFileOperation!("run", "default dir")(() {
		mixin(useTmpName!"scratchDir");
		mixin(useTmpName!("targetFile", "dummy"));
		auto origDir = std.file.getcwd();
		scope(exit) std.file.chdir(origDir);
		std.file.mkdir(scratchDir);
		std.file.chdir(scratchDir);
		std.file.mkdir(std.path.dirName(targetFile));
		expectedContent = scratchDir;

		checkPre();
		run(text(pwd, " > ", Path(targetFile)));
		mixin(checkResult);
	});

	testFileOperation!("run", "custom dir")(() {
		mixin(useTmpName!"scratchDir");
		mixin(useTmpName!("targetFile", "dummy"));
		auto origDir = std.file.getcwd();
		scope(exit) std.file.chdir(origDir);
		std.file.mkdir(scratchDir);
		std.file.chdir(scratchDir);
		std.file.mkdir(std.path.dirName(targetFile));
		expectedContent = std.path.dirName(targetFile);

		checkPre();
		run(Path(std.path.dirName(targetFile)), text(pwd, " > dummy"));
		mixin(checkResult);
	});

	testFileOperation!("run", "bad command")(() {
		import std.exception : assertThrown;

		void doIt()
		{
			run("cd this-path-does-not-exist-scriptlike"~quiet);
		}

		if(scriptlikeDryRun)
			doIt();
		else
			assertThrown!ErrorLevelException( doIt() );
	});
}

/++
Runs a command, through the system's command shell interpreter,
in typical shell-script style: Synchronously, with the command's
stdout/in/err automatically forwarded through your
program's stdout/in/err.

Optionally takes a working directory to run the command from.

The command is echoed if scriptlikeEcho is true.

Returns: The error level the process exited with. Or -1 upon failure to
start the process.

Example:
---------------------
Args cmd;
cmd ~= Path("some tool");
cmd ~= "-o";
cmd ~= Path(`dir/out file.txt`);
cmd ~= ["--abc", "--def", "-g"];
auto errLevel = Path("some working dir").run(cmd.data);
---------------------
+/
int tryRun(string command)
{
	yapFunc(command);

	if(scriptlikeDryRun)
		return 0;
	else
	{
		try
			return spawnShell(command).wait();
		catch(Exception e)
			return -1;
	}
}

///ditto
int tryRun(Path workingDirectory, string command)
{
	auto saveDir = getcwd();
	workingDirectory.chdir();
	scope(exit) saveDir.chdir();
	
	return tryRun(command);
}

version(unittest_scriptlike_d)
unittest
{
	import std.string : strip;

	string scratchDir;
	string targetFile;
	string expectedContent;
	void checkPre()
	{
		assert(!std.file.exists(targetFile));
	}

	void checkPost()
	{
		assert(std.file.exists(targetFile));
		assert(std.file.isFile(targetFile));
		assert(strip(cast(string) std.file.read(targetFile)) == expectedContent);
	}

	testFileOperation!("tryRun", "default dir")(() {
		mixin(useTmpName!"scratchDir");
		mixin(useTmpName!("targetFile", "dummy"));
		auto origDir = std.file.getcwd();
		scope(exit) std.file.chdir(origDir);
		std.file.mkdir(scratchDir);
		std.file.chdir(scratchDir);
		std.file.mkdir(std.path.dirName(targetFile));
		expectedContent = scratchDir;

		checkPre();
		tryRun(text(pwd, " > ", Path(targetFile)));
		mixin(checkResult);
	});

	testFileOperation!("tryRun", "custom dir")(() {
		mixin(useTmpName!"scratchDir");
		mixin(useTmpName!("targetFile", "dummy"));
		auto origDir = std.file.getcwd();
		scope(exit) std.file.chdir(origDir);
		std.file.mkdir(scratchDir);
		std.file.chdir(scratchDir);
		std.file.mkdir(std.path.dirName(targetFile));
		expectedContent = std.path.dirName(targetFile);

		checkPre();
		tryRun(Path(std.path.dirName(targetFile)), text(pwd, " > dummy"));
		mixin(checkResult);
	});

	testFileOperation!("tryRun", "bad command")(() {
		import std.exception : assertNotThrown;
		mixin(useTmpName!"scratchDir");
		auto origDir = std.file.getcwd();
		scope(exit) std.file.chdir(origDir);
		std.file.mkdir(scratchDir);
		std.file.chdir(scratchDir);

		assertNotThrown( tryRun("cd this-path-does-not-exist-scriptlike"~quiet) );
	});
}

/// Backwards-compatibility alias. runShell may become deprecated in the
/// future, so you should use tryRun or run insetad.
alias runShell = tryRun;

/// Similar to run(), but (like std.process.executeShell) captures and returns
/// the output instead of displaying it.
string runCollect(string command)
{
	yapFunc(command);
	mixin(gagEcho);
	
	auto result = tryRunCollect(command);
	if(result.status != 0)
		throw new ErrorLevelException(result.status, command, result.output);

	return result.output;
}

///ditto
string runCollect(Path workingDirectory, string command)
{
	auto saveDir = getcwd();
	workingDirectory.chdir();
	scope(exit) saveDir.chdir();
	
	return runCollect(command);
}

version(unittest_scriptlike_d)
unittest
{
	import std.string : strip;
	string dir;
	
	testFileOperation!("runCollect", "default dir")(() {
		auto result = runCollect(pwd);
		
		if(scriptlikeDryRun)
			assert(result == "");
		else
			assert(strip(result) == std.file.getcwd());
	});

	testFileOperation!("runCollect", "custom dir")(() {
		mixin(useTmpName!"dir");
		std.file.mkdir(dir);

		auto result = Path(dir).runCollect(pwd);

		if(scriptlikeDryRun)
			assert(result == "");
		else
			assert(strip(result) == dir);
	});

	testFileOperation!("runCollect", "bad command")(() {
		import std.exception : assertThrown;

		void doIt()
		{
			runCollect("cd this-path-does-not-exist-scriptlike"~quiet);
		}

		if(scriptlikeDryRun)
			doIt();
		else
			assertThrown!ErrorLevelException( doIt() );
	});
}

/// Similar to tryRun(), but (like $(FULL_STD_PROCESS executeShell)) captures
/// and returns the output instead of displaying it.
/// 
/// Returns the same tuple as $(FULL_STD_PROCESS executeShell):
/// `std.typecons.Tuple!(int, "status", string, "output")`
///
/// Returns: The `status` field will be -1 upon failure to
/// start the process.
auto tryRunCollect(string command)
{
    static import std.typecons;

	yapFunc(command);
	auto result = std.typecons.Tuple!(int, "status", string, "output")(0, null);

	if(scriptlikeDryRun)
		return result;
	else
	{
		try
			return executeShell(command);
		catch(Exception e)
		{
			result.status = -1;
			return result;
		}
	}
}

///ditto
auto tryRunCollect(Path workingDirectory, string command)
{
	auto saveDir = getcwd();
	workingDirectory.chdir();
	scope(exit) saveDir.chdir();
	
	return tryRunCollect(command);
}

version(unittest_scriptlike_d)
unittest
{
	import std.string : strip;
	string dir;
	
	testFileOperation!("tryRunCollect", "default dir")(() {
		auto result = tryRunCollect(pwd);
		
		assert(result.status == 0);
		if(scriptlikeDryRun)
			assert(result.output == "");
		else
			assert(strip(result.output) == std.file.getcwd());
	});

	testFileOperation!("tryRunCollect", "custom dir")(() {
		mixin(useTmpName!"dir");
		std.file.mkdir(dir);

		auto result = Path(dir).tryRunCollect(pwd);

		assert(result.status == 0);
		if(scriptlikeDryRun)
			assert(result.output == "");
		else
			assert(strip(result.output) == dir);
	});

	testFileOperation!("tryRunCollect", "bad command")(() {
		import std.exception : assertThrown;

		auto result = tryRunCollect("cd this-path-does-not-exist-scriptlike"~quiet);
		if(scriptlikeDryRun)
			assert(result.status == 0);
		else
			assert(result.status != 0);
		assert(result.output == "");
	});
}

/++
Much like std.array.Appender!string, but specifically geared towards
building a command string out of arguments. String and Path can both
be appended. All elements added will automatically be escaped,
and separated by spaces, as necessary.

Example:
-------------------
Args args;
args ~= Path(`some/big path/here/foobar`);
args ~= "-A";
args ~= "--bcd";
args ~= "Hello World";
args ~= Path("file.ext");

// On windows:
assert(args.data == `"some\big path\here\foobar" -A --bcd "Hello World" file.ext`);
// On linux:
assert(args.data == `'some/big path/here/foobar' -A --bcd 'Hello World' file.ext`);
-------------------
+/
struct Args
{
	// Internal note: For every element the user adds to ArgsT,
	// *two* elements will be added to this internal buf: first a spacer
	// (normally a space, or an empty string in the case of the very first
	// element the user adds) and then the actual element the user added.
	private Appender!(string) buf;
	private size_t _length = 0;
	
	void reserve(size_t newCapacity) @safe pure nothrow
	{
		// "*2" to account for the spacers
		buf.reserve(newCapacity * 2);
	}


	@property size_t capacity() const @safe pure nothrow
	{
		// "/2" to account for the spacers
		return buf.capacity / 2;
	}

	@property string data() inout @trusted pure nothrow
	{
		return buf.data;
	}
	
	@property size_t length()
	{
		return _length;
	}
	
	private void putSpacer()
	{
		buf.put(_length==0? "" : " ");
	}
	
	void put(string item)
	{
		putSpacer();
		buf.put(escapeShellArg(item));
		_length += 2;
	}

	void put(Path item)
	{
		put(item.toRawString());
	}

	void put(Range)(Range items)
		if(
			isInputRange!Range &&
			(is(ElementType!Range == string) || is(ElementType!Range == Path))
		)
	{
		for(; !items.empty; items.popFront())
			put(items.front);
	}

	void opOpAssign(string op)(string item) if(op == "~")
	{
		put(item);
	}

	void opOpAssign(string op)(Path item) if(op == "~")
	{
		put(item);
	}

	void opOpAssign(string op, Range)(Range items)
		if(
			op == "~" &&
			isInputRange!Range &&
			(is(ElementType!Range == string) || is(ElementType!Range == Path))
		)
	{
		put(items);
	}
}

version(unittest_scriptlike_d)
unittest
{
	import std.stdio : writeln;
	writeln("Running Scriptlike unittests: Args");

	Args args;
	args ~= Path(`some/big path/here/foobar`);
	args ~= "-A";
	args ~= "--bcd";
	args ~= "Hello World";
	args ~= Path("file.ext");

	version(Windows)
		assert(args.data == `"some\big path\here\foobar" -A --bcd "Hello World" file.ext`);
	else version(Posix)
		assert(args.data == `'some/big path/here/foobar' -A --bcd 'Hello World' file.ext`);
}
