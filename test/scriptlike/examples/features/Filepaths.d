import scriptlike;

void main()
{
	// Setup and cleanup
	chdir(thisExePath.dirName);
	scope(exit)
	{
		tryRmdirRecurse("path");
		tryRmdirRecurse("target");
	}
	mkdirRecurse("path/to");
	mkdirRecurse("target/path");
	import scriptlike.file.wrappers : write;
	write("path/to/file.txt", "abc");

	// This is AUTOMATICALLY kept normalized (via std.path.buildNormalizedPath)
	auto dir = Path("foo/bar");
	dir ~= "subdir"; // Append a subdirectory

	// No worries about trailing slashes!
	assert(Path("foo/bar") == Path("foo/bar/"));
	assert(Path("foo/bar/") == Path("foo/bar//"));
	

	// No worries about forward/backslashes!
	assert(dir == Path("foo/bar/subdir"));
	assert(dir == Path("foo\\bar\\subdir"));

	// No worries about spaces!
	auto file = dir.up ~ "different subdir\\Filename with spaces.txt";
	assert(file == Path("foo/bar/different subdir/Filename with spaces.txt"));
	writeln(file); // Path.toString() always properly escapes for current platform!
	writeln(file.toRawString()); // Don't escape!

	// Even file extentions are type-safe!
	Ext ext = file.extension;
	auto anotherFile = Path("path/to/file") ~ ext;
	assert(anotherFile.baseName == Path("file.txt"));

	// std.path and std.file are wrapped to offer Path/Ext support
	assert(dirName(anotherFile) == Path("path/to"));
	copy(anotherFile, Path("target/path/new file.txt"));
}
