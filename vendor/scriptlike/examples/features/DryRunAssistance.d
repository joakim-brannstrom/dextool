import scriptlike;

void main()
{
	scriptlikeDryRun = true;

	// When dry-run is enabled, this echoes but doesn't actually copy or invoke DMD.
	copy("original.d", "app.d");
	run("dmd app.d -ofbin/app");

	// Works fine in dry-run, since it doesn't modify the filesystem.
	bool isItThere = exists("another-file");

	if(!scriptlikeDryRun)
	{
		// This won't work right if we're running in dry-run mode,
		// since it'll be out-of-date, if it even exists at all.
		auto source = read("app.d");
	}
}
