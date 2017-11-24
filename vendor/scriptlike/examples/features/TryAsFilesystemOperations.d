import scriptlike;

void main()
{
	// Setup
	chdir(thisExePath.dirName);

	// Just MAKE SURE this exists! If it's already there, then GREAT!
	tryMkdir("somedir");
	assertThrown( mkdir("somedir") ); // Exception: Already exists!
	tryMkdir("somedir"); // Works fine!

	// Just MAKE SURE this is gone! If it's already gone, then GREAT!
	tryRmdir("somedir");
	assertThrown( rmdir("somedir") ); // Exception: Already gone!
	tryRmdir("somedir"); // Works fine!

	// Just MAKE SURE it doesn't exist. Don't bother me if it doesn't!
	tryRemove("file");

	// Copy if it exists, otherwise don't worry about it.
	tryCopy("file", "file-copy");

	// Is this a directory? If it doesn't even exist,
	// then it's obviously NOT a directory.
	assertThrown( isDir("foo/bar") ); // Exception: Doesn't exist!
	if(existsAsDir("foo/bar")) // Works fine!
		{/+ ...do stuff... +/}

	// Bonus! Single function to delete files OR directories!
	writeFile("file.txt", "abc");
	tryMkdirRecurse("foo/bar/dir");
	writeFile("foo/bar/dir/file.txt", "123");
	// Delete with the same function!
	removePath("file.txt"); // Calls 'remove'
	removePath("foo");      // Calls 'rmdirRecurse'
	tryRemovePath("file.txt"); // Also comes in try flavor!
	tryRemovePath("foo");
}
