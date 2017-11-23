import scriptlike;

void main()
{
	// Setup and cleanup
	chdir(thisExePath.dirName);
	scope(exit)
		tryRmdirRecurse("my");
	mkdirRecurse("my/proj/dir/src");
	import scriptlike.file.wrappers : write;
	write("my/proj/dir/src/main.d", `import std.stdio; void main() { writeln("Hello"); }`);

	run("dmd --help"); // Display DMD help screen
	pause(); // Wait for user to hit Enter

	// Automatically throws ErrorLevelException(1, "dmd --bad-flag")
	assertThrown!ErrorLevelException( run("dmd --bad-flag") );

	// Automatically throws ErrorLevelException(-1, "this-cmd-does-not-exist")
	assertThrown!ErrorLevelException( run("this-cmd-does-not-exist") );

	// Don't bail on error
	int statusCode = tryRun("dmd --bad-flag");

	// Collect output instead of showing it
	string dmdHelp = runCollect("dmd --help");
	auto isDMD_2_068_1 = dmdHelp.canFind("D Compiler v2.068.1");

	// Don't bail on error
	auto result = tryRunCollect("dmd --help");
	if(result.status == 0 && result.output.canFind("D Compiler v2.068.1"))
		writeln("Found DMD v2.068.1!");

	// Use any working directory:
	auto myProjectDir = Path("my/proj/dir");
	auto mainFile = Path("src/main.d");
	myProjectDir.run(text("dmd ", mainFile, " -O")); // mainFile is properly escaped!

	// Verify it actually IS running from a different working directory:
	version(Posix)        enum pwd = "pwd";
	else version(Windows) enum pwd = "cd";
	else static assert(0);
	auto output = myProjectDir.runCollect(pwd);
	auto expected = getcwd() ~ myProjectDir;
	assert( Path(output.strip()) == expected );
}
