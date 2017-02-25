/++
$(H2 Scriptlike $(SCRIPTLIKE_VERSION))

Extra Scriptlike-only functionality to complement and wrap $(MODULE_STD_PATH),
providing extra functionality, such as no-fail "try*" alternatives, and support
for Scriptlike's $(API_PATH_EXTR Path), command echoing and dry-run features.

Modules:
$(UL
	$(LI $(MODULE_PATH_EXTR) )
	$(LI $(MODULE_PATH_WRAP) )
)

Copyright: Copyright (C) 2014-2016 Nick Sabalausky
License:   zlib/libpng
Authors:   Nick Sabalausky
+/
module scriptlike.path;

public import scriptlike.path.extras;
public import scriptlike.path.wrappers;

// The unittests in this module mainly check that all the templates compile
// correctly and that the appropriate Phobos functions are correctly called.
//
// A completely thorough testing of the behavior of such functions is
// occasionally left to Phobos itself as it is outside the scope of these tests.
version(unittest_scriptlike_d)
unittest
{
	import std.algorithm;
	import std.conv;
	import std.datetime;
	import std.file;
	import std.process;
	import std.range;
	import std.stdio;
	import std.string;
	import std.traits;
	import std.typecons;
	import std.typetuple;

	import std.stdio : writeln;
	writeln("Running Scriptlike unittests: std.path wrappers");
	
	alias dirSep = dirSeparator;

	{
		auto e = Ext(".txt");
		assert(e != Ext(".dat"));
		assert(e == Ext(".txt"));
		version(Windows)
			assert(e == Ext(".TXT"));
		else version(OSX)
			assert(e == Ext(".TXT"));
		else version(Posix)
			assert(e != Ext(".TXT"));
		else
			static assert(0, "This platform not supported.");
		
		// Test the other comparison overloads
		assert(e != Ext(".dat"));
		assert(e == Ext(".txt"));
		assert(Ext(".dat") != e);
		assert(Ext(".txt") == e);
		assert(".dat" != e);
		assert(".txt" == e);

		assert(Ext("foo"));
		assert(Ext(""));
		assert(Ext(null).toString() is null);
		assert(!Ext(null));
	}

	auto p = Path();
	assert(p.raw == ".");
	assert(!p.empty);
	
	assert(Path("").empty);
	
	assert(Path("foo"));
	assert(Path(""));
	assert(Path(null).raw is null);
	assert(!Path(null));
	
	version(Windows)
		auto testStrings = ["/foo/bar", "/foo/bar/", `\foo\bar`, `\foo\bar\`];
	else version(Posix)
		auto testStrings = ["/foo/bar", "/foo/bar/"];
	else
		static assert(0, "This platform not supported.");
	
	foreach(str; testStrings)
	{
		writeln("  testing str: ", str);
		
		p = Path(str);
		assert(!p.empty);
		assert(p.raw == dirSep~"foo"~dirSep~"bar");
		
		p = Path(str);
		assert(p.raw == dirSep~"foo"~dirSep~"bar");
		assert(p.raw == p.raw);
		assert(p.toString()    == p.raw.to!string());
		
		assert(p.up.toString() == dirSep~"foo");
		assert(p.up.up.toString() == dirSep);

		assert((p~"sub").toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"sub");
		assert((p~"sub"~"2").toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"sub"~dirSep~"2");
		assert((p~Path("sub")).toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"sub");
		
		version(Windows)
			assert((p~"sub dir").toString() == `"`~dirSep~"foo"~dirSep~"bar"~dirSep~"sub dir"~`"`);
		else version(Posix)
			assert((p~"sub dir").toString() == `'`~dirSep~"foo"~dirSep~"bar"~dirSep~`sub dir'`);
		else
			static assert(0, "This platform not supported.");

		assert(("dir"~p).toString() == dirSep~"foo"~dirSep~"bar");
		assert(("dir"~Path(str[1..$])).toString() == "dir"~dirSep~"foo"~dirSep~"bar");
		
		p ~= "blah";
		assert(p.toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"blah");
		
		p ~= Path("more");
		assert(p.toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"blah"~dirSep~"more");
		
		p ~= "..";
		assert(p.toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"blah");
		
		p ~= Path("..");
		assert(p.toString() == dirSep~"foo"~dirSep~"bar");
		
		p ~= "sub dir";
		p ~= "..";
		assert(p.toString() == dirSep~"foo"~dirSep~"bar");
		
		p ~= "filename";
		assert((p~Ext(".txt")).toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.txt");
		assert((p~Ext("txt")).toString()  == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.txt");
		assert((p~Ext("")).toString()     == dirSep~"foo"~dirSep~"bar"~dirSep~"filename");

		p ~= Ext(".ext");
		assert(p.toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.ext");
		assert(p.baseName().toString() == "filename.ext");
		assert(p.dirName().toString() == dirSep~"foo"~dirSep~"bar");
		assert(p.rootName().toString() == dirSep);
		assert(p.driveName().toString() == "");
		assert(p.stripDrive().toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.ext");
		version(Windows)
		{
			assert(( Path("C:"~p.raw) ).toString() == "C:"~dirSep~"foo"~dirSep~"bar"~dirSep~"filename.ext");
			assert(( Path("C:"~p.raw) ).stripDrive().toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.ext");
		}
		assert(p.extension().toString() == ".ext");
		assert(p.stripExtension().toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename");
		assert(p.setExtension(".txt").toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.txt");
		assert(p.setExtension("txt").toString()  == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.txt");
		assert(p.setExtension("").toString()     == dirSep~"foo"~dirSep~"bar"~dirSep~"filename");
		assert(p.setExtension(Ext(".txt")).toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.txt");
		assert(p.setExtension(Ext("txt")).toString()  == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.txt");
		assert(p.setExtension(Ext("")).toString()     == dirSep~"foo"~dirSep~"bar"~dirSep~"filename");

		assert(p.defaultExtension(".dat").toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.ext");
		assert(p.stripExtension().defaultExtension(".dat").toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.dat");

		assert(equal(p.pathSplitter(), [dirSep, "foo", "bar", "filename.ext"]));

		assert(p.isRooted());
		version(Windows)
			assert(!p.isAbsolute());
		else version(Posix)
			assert(p.isAbsolute());
		else
			static assert(0, "This platform not supported.");

		assert(!( Path("dir"~p.raw) ).isRooted());
		assert(!( Path("dir"~p.raw) ).isAbsolute());
		
		version(Windows)
		{
			assert(( Path("dir"~p.raw) ).absolutePath("C:/main").toString() == "C:"~dirSep~"main"~dirSep~"dir"~dirSep~"foo"~dirSep~"bar"~dirSep~"filename.ext");
			assert(( Path("C:"~p.raw) ).relativePath("C:/foo").toString() == "bar"~dirSep~"filename.ext");
			assert(( Path("C:"~p.raw) ).relativePath("C:/foo/bar").toString() == "filename.ext");
		}
		else version(Posix)
		{
			assert(( Path("dir"~p.raw) ).absolutePath("/main").toString() == dirSep~"main"~dirSep~"dir"~dirSep~"foo"~dirSep~"bar"~dirSep~"filename.ext");
			assert(p.relativePath("/foo").toString() == "bar"~dirSep~"filename.ext");
			assert(p.relativePath("/foo/bar").toString() == "filename.ext");
		}
		else
			static assert(0, "This platform not supported.");

		assert(p.filenameCmp(dirSep~"foo"~dirSep~"bar"~dirSep~"filename.ext") == 0);
		assert(p.filenameCmp(dirSep~"faa"~dirSep~"bat"~dirSep~"filename.ext") != 0);
		assert(p.globMatch("*foo*name.ext"));
		assert(!p.globMatch("*foo*Bname.ext"));

		assert(!p.isValidFilename());
		assert(p.baseName().isValidFilename());
		assert(p.isValidPath());
		
		assert(p.expandTilde().toString() == dirSep~"foo"~dirSep~"bar"~dirSep~"filename.ext");
		
		assert(p != Path("/dir/subdir/filename.ext"));
		assert(p == Path("/foo/bar/filename.ext"));
		version(Windows)
			assert(p == Path("/FOO/BAR/FILENAME.EXT"));
		else version(OSX)
			assert(p == Path("/FOO/BAR/FILENAME.EXT"));
		else version(Posix)
			assert(p != Path("/FOO/BAR/FILENAME.EXT"));
		else
			static assert(0, "This platform not supported.");
		
		// Test the other comparison overloads
		assert(p != Path("/dir/subdir/filename.ext"));
		assert(p == Path("/foo/bar/filename.ext"));
		assert(Path("/dir/subdir/filename.ext") != p);
		assert(Path("/foo/bar/filename.ext")    == p);
		assert("/dir/subdir/filename.ext" != p);
		assert("/foo/bar/filename.ext"    == p);
	}
}
