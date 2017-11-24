/++
$(H2 Scriptlike $(SCRIPTLIKE_VERSION))

Extra Scriptlike-only functionality to complement and wrap $(MODULE_STD_FILE),
providing extra functionality, such as no-fail "try*" alternatives, and support
for Scriptlike's $(API_PATH_EXTR Path), command echoing and dry-run features.

Modules:
$(UL
	$(LI $(MODULE_FILE_EXTR) )
	$(LI $(MODULE_FILE_WRAP) )
)

Copyright: Copyright (C) 2014-2017 Nick Sabalausky
License:   zlib/libpng
Authors:   Nick Sabalausky
+/
module scriptlike.file;

public import scriptlike.file.extras;
public import scriptlike.file.wrappers;

version(unittest_scriptlike_d)
unittest
{
	import std.algorithm : equal;
	import std.conv;
	import std.datetime : SysTime;
	static import std.file;
	static import std.path;
	import std.string;
	import std.traits;
	import std.typecons;

	import scriptlike.path;
	import scriptlike.core : tmpName;
	
	import std.stdio : writeln;
	import std.process : thisProcessID;
	alias copy = scriptlike.file.wrappers.copy;

	writeln("Running Scriptlike unittests: std.file wrappers");
	
	immutable tempname1 = tmpName("1");
	immutable tempname2 = tmpName("2");
	immutable tempname3 = tmpName("3", "somefile");
	auto tempPath  = Path(tempname1);
	auto tempPath2 = Path(tempname2);
	auto tempPath3 = Path(tempname3);
	
	void testA(T)(T tempPath)
	{
		scope(exit)
		{
			if(std.file.exists(tempname1)) std.file.remove(tempname1);
		}

		tempPath.write("stuff");

		tempPath.append(" more");
		assert(tempPath.read(3) == "stu");
		assert(tempPath.read() == "stuff more");
		assert(tempPath.readText() == "stuff more");
		assert(tempPath.getSize() == 10);

		auto parsed = tempPath.slurp!(string, string)("%s %s");
		assert(equal(parsed, [tuple("stuff", "more")]));
		
		SysTime timeA, timeB, timeC;
		tempPath.getTimes(timeA, timeB);
		version(Windows)
			tempPath.getTimesWin(timeA, timeB, timeC);
		tempPath.setTimes(timeA, timeB);
		timeA = tempPath.timeLastModified();
		timeA = tempPath.timeLastModified(timeB);
		
		uint attr;
		attr = tempPath.getAttributes();
		attr = tempPath.getLinkAttributes();
		
		assert(tempPath.exists());
		assert(tempPath.isFile());
		assert(tempPath.existsAsFile());
		assert(!tempPath.isDir());
		assert(!tempPath.existsAsDir());
		assert(!tempPath.isSymlink());
		assert(!tempPath.existsAsSymlink());
		tempPath.remove();
		assert(!tempPath.exists());
		assert(!tempPath.existsAsFile());
		assert(!tempPath.existsAsDir());
		assert(!tempPath.existsAsSymlink());
	}

	import std.stdio : stdout;
	writeln("    testA with string"); stdout.flush();
	testA(tempPath.raw); // Test with string

	writeln("    testA with Path"); stdout.flush();
	testA(tempPath); // Test with Path

	writeln("    more..."); stdout.flush();
	{
		assert(!tempPath.exists());
		assert(!tempPath2.exists());

		scope(exit)
		{
			if(std.file.exists(tempname1)) std.file.remove(tempname1);
			if(std.file.exists(tempname2)) std.file.remove(tempname2);
		}
		tempPath.write("ABC");
		
		assert(tempPath.existsAsFile());
		assert(!tempPath2.exists());

		tempPath.rename(tempPath2);
		
		assert(!tempPath.exists());
		assert(tempPath2.existsAsFile());
		
		tempPath2.copy(tempPath);
		
		assert(tempPath.existsAsFile());
		assert(tempPath2.existsAsFile());
	}
	
	{
		scope(exit)
		{
			if(std.file.exists(tempname1)) std.file.rmdir(tempname1);
			if(std.file.exists(tempname3)) std.file.rmdir(tempname3);
			if(std.file.exists( std.path.dirName(tempname3) )) std.file.rmdir( std.path.dirName(tempname3) );
		}
		
		assert(!tempPath.exists());
		assert(!tempPath3.exists());
		
		tempPath.mkdir();
		assert(tempPath.exists());
		assert(!tempPath.isFile());
		assert(!tempPath.existsAsFile());
		assert(tempPath.isDir());
		assert(tempPath.existsAsDir());
		assert(!tempPath.isSymlink());
		assert(!tempPath.existsAsSymlink());

		tempPath3.mkdirRecurse();
		assert(tempPath3.exists());
		assert(!tempPath3.isFile());
		assert(!tempPath3.existsAsFile());
		assert(tempPath3.isDir());
		assert(tempPath3.existsAsDir());
		assert(!tempPath3.isSymlink());
		assert(!tempPath3.existsAsSymlink());
		
		auto saveDirName = std.file.getcwd();
		auto saveDir = Path(saveDirName);
		scope(exit) chdir(saveDirName);

		tempPath.chdir();
		assert(getcwd() == tempname1);
		saveDir.chdir();
		assert(getcwd() == saveDirName);
		
		auto entries1 = (tempPath3~"..").dirEntries(SpanMode.shallow);
		assert(!entries1.empty);
		auto entries2 = (tempPath3~"..").dirEntries("*", SpanMode.shallow);
		assert(!entries2.empty);
		auto entries3 = (tempPath3~"..").dirEntries("TUNA TUNA THIS DOES NOT EXIST TUNA WHEE", SpanMode.shallow);
		assert(entries3.empty);
		
		tempPath.rmdir();
		assert(!tempPath.exists());
		assert(!tempPath.existsAsFile());
		assert(!tempPath.existsAsDir());
		assert(!tempPath.existsAsSymlink());

		tempPath3.rmdirRecurse();
		assert(!tempPath.exists());
		assert(!tempPath.existsAsFile());
		assert(!tempPath.existsAsDir());
		assert(!tempPath.existsAsSymlink());
	}
	
	{
		version(Posix)
		{
			assert(!tempPath.exists());
			assert(!tempPath2.exists());

			scope(exit)
			{
				if(std.file.exists(tempname2)) std.file.remove(tempname2);
				if(std.file.exists(tempname1)) std.file.remove(tempname1);
			}
			tempPath.write("DEF");
			
			tempPath.symlink(tempPath2);
			assert(tempPath2.exists());
			assert(tempPath2.isFile());
			assert(tempPath2.existsAsFile());
			assert(!tempPath2.isDir());
			assert(!tempPath2.existsAsDir());
			assert(tempPath2.isSymlink());
			assert(tempPath2.existsAsSymlink());
			
			auto linkTarget = tempPath2.readLink();
			assert(linkTarget.raw == tempname1);
		}
	}
	
	{
		assert(!tempPath.exists());

		scope(exit)
		{
			if(std.file.exists(tempname1)) std.file.remove(tempname1);
		}

		import scriptlike.process;
		run(`echo TestScriptStuff > `~tempPath.to!string());
		assert(tempPath.exists());
		assert(tempPath.isFile());
		assert((cast(string)tempPath.read()).strip() == "TestScriptStuff");
		tempPath.remove();
		assert(!tempPath.exists());

		auto errlevel = tryRun(`echo TestScriptStuff > `~tempPath.to!string());
		assert(tempPath.exists());
		assert(tempPath.isFile());
		assert((cast(string)tempPath.read()).strip() == "TestScriptStuff");
		assert(errlevel == 0);
		tempPath.remove();
		assert(!tempPath.exists());

		import scriptlike.process;
		getcwd().run(`echo TestScriptStuff > `~tempPath.to!string());
		getcwd().tryRun(`echo TestScriptStuff > `~tempPath.to!string());
	}
	
	{
		assert(!tempPath3.exists());
		assert(!tempPath3.up.exists());

		scope(exit)
		{
			if(std.file.exists(tempname3)) std.file.remove(tempname3);
			if(std.file.exists( std.path.dirName(tempname3) )) std.file.rmdir( std.path.dirName(tempname3) );
		}
		
		tempPath3.up.mkdir();
		assert(tempPath3.up.exists());
		assert(tempPath3.up.isDir());
				
		import scriptlike.process;
		tempPath3.up.run(`echo MoreTestStuff > `~tempPath3.baseName().to!string());
		assert(tempPath3.exists());
		assert(tempPath3.isFile());
		assert((cast(string)tempPath3.read()).strip() == "MoreTestStuff");
	}

	{
		scope(exit)
		{
			if(std.file.exists(tempname1)) std.file.rmdir(tempname1);
			if(std.file.exists(tempname3)) std.file.rmdir(tempname3);
			if(std.file.exists( std.path.dirName(tempname3) )) std.file.rmdir( std.path.dirName(tempname3) );
		}
		
		assert(!tempPath.exists());
		assert(!tempPath3.exists());
		
		assert(!tempPath.tryRmdir());
		assert(!tempPath.tryRmdirRecurse());
		assert(!tempPath.tryRemove());
		assert(!tempPath.tryRename(tempPath3));
		version(Posix) assert(!tempPath.trySymlink(tempPath3));
		assert(!tempPath.tryCopy(tempPath3));

		assert(tempPath.tryMkdir());
		assert(tempPath.exists());
		assert(!tempPath.tryMkdir());
		assert(!tempPath.tryMkdirRecurse());

		assert(tempPath.tryRmdir());
		assert(!tempPath.exists());

		assert(tempPath.tryMkdirRecurse());
		assert(tempPath.exists());
		assert(!tempPath.tryMkdirRecurse());
	}
}
