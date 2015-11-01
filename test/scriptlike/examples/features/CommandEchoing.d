import scriptlike;

void main()
{
	// Setup and cleanup
	chdir(thisExePath.dirName);
	scope(exit)
	{
		scriptlikeEcho = false;
		tryRemove("file.txt");
		tryRmdirRecurse("some");
	}

	/++
	Output:
	--------
	run: echo Hello > file.txt
	mkdirRecurse: some/new/dir
	copy: file.txt -> 'some/new/dir/target name.txt'
	Gonna run foo() now...
	foo: i = 42
	--------
	+/

	scriptlikeEcho = true; // Enable automatic echoing

	run("echo Hello > file.txt");

	auto newDir = Path("some/new/dir");
	mkdirRecurse(newDir.toRawString()); // Even works with non-Path overloads
	copy("file.txt", newDir ~ "target name.txt");

	void foo(int i = 42) {
		yapFunc("i = ", i); // Evaluated lazily
	}

	// yap and yapFunc ONLY output when echoing is enabled
	yap("Gonna run foo() now...");
	foo();
}
