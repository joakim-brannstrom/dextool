Scriptlike [![Build Status](https://travis-ci.org/Abscissa/scriptlike.svg)](https://travis-ci.org/Abscissa/scriptlike)
==========

Scriptlike is a utility library to help you write script-like programs in the
[D Programming Language](http://dlang.org).

Officially supported compiler versions are shown in
[.travis.yml](https://github.com/Abscissa/scriptlike/blob/master/.travis.yml).

Links:
* [How to Use Scriptlike in Scripts](https://github.com/Abscissa/scriptlike/blob/master/USAGE.md)
* [API Reference](http://semitwist.com/scriptlike)
* [Changelog](http://semitwist.com/scriptlike/changelog.html)
* [DUB](http://code.dlang.org/about) [Package](http://code.dlang.org/packages/scriptlike)
* [Small article explaining the original motivations behind scriptlike](http://semitwist.com/articles/article/view/scriptlike-shell-scripting-in-d-annoyances-and-a-library-solution)

Sections
--------

**[Features](#features)**
* [Automatic Phobos Import](#automatic-phobos-import)
* [User Input Prompts](#user-input-prompts)
* [String Interpolation](#string-interpolation)
* [Filepaths](#filepaths)
* [Try/As Filesystem Operations](#tryas-filesystem-operations)
* [Script-Style Shell Commands](#script-style-shell-commands)
* [Command Echoing](#command-echoing)
* [Dry Run Assistance](#dry-run-assistance)
* [Fail](#fail)

**[Disambiguating write and write](#disambiguating-write-and-write)**

Features
--------

### Automatic Phobos Import

For most typical Phobos modules. Unless you
[don't want to](http://semitwist.com/scriptlike/scriptlike/only.html).
Who needs rows and rows of standard lib imports for a mere script?

```d
import scriptlike;
//import scriptlike.only; // In case you don't want Phobos auto-imported
void main() {
    writeln("Works!");
}
```

See: [```scriptlike```](https://github.com/Abscissa/scriptlike/blob/examples/src/scriptlike/package.d),
[```scriptlike.only```](https://github.com/Abscissa/scriptlike/blob/examples/src/scriptlike/only.d),
[```scriptlike.std```](https://github.com/Abscissa/scriptlike/blob/examples/src/scriptlike/std.d)

### User Input Prompts

Easy prompting for and verifying command-line user input with the
[```interact```](http://semitwist.com/scriptlike/scriptlike/interact.html) module:

```d
auto name = userInput!string("Please enter your name");
auto age = userInput!int("And your age");

if(userInput!bool("Do you want to continue?"))
{
	string outputFolder = pathLocation("Where you do want to place the output?");
	auto color = menu!string("What color would you like to use?", ["Blue", "Green"]);
}

auto num = require!(int, "a > 0 && a <= 10")("Enter a number from 1 to 10");

pause(); // Prompt "Press Enter to continue...";
pause("Hit Enter again, dood!!");
```

See: [```userInput```](http://semitwist.com/scriptlike/scriptlike/interact/userInput.html),
[```pathLocation```](http://semitwist.com/scriptlike/scriptlike/interact/pathLocation.html),
[```menu```](http://semitwist.com/scriptlike/scriptlike/interact/menu.html),
[```require```](http://semitwist.com/scriptlike/scriptlike/interact/require.html),
[```pause```](http://semitwist.com/scriptlike/scriptlike/interact/pause.html)

### String Interpolation

Variable (and expression) expansion inside strings:

```d
// Output: The number 21 doubled is 42!
int num = 21;
writeln( mixin(interp!"The number ${num} doubled is ${num * 2}!") );

// Output: Empty braces output nothing.
writeln( mixin(interp!"Empty ${}braces ${}output nothing.") );

// Output: Multiple params: John Doe.
auto first = "John", last = "Doe";
writeln( mixin(interp!`Multiple params: ${first, " ", last}.`) );
```

See: [```interp```](http://semitwist.com/scriptlike\/scriptlike/core/interp.html)

### Filepaths

Simple, reliable, cross-platform. No more worrying about slashes, paths-with-spaces,
[buildPath](http://dlang.org/phobos/std_path.html#buildPath),
[normalizing](http://dlang.org/phobos/std_path.html#buildNormalizedPath),
or getting paths mixed up with ordinary strings:

```d
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
```

See: [```Path```](http://semitwist.com/scriptlike/scriptlike/path/extras/Path.html),
[```Path.toString```](http://semitwist.com/scriptlike/scriptlike/path/extras/Path.toString.html),
[```Path.toRawString```](http://semitwist.com/scriptlike/scriptlike/path/extras/Path.toRawString.html),
[```Path.up```](http://semitwist.com/scriptlike/scriptlike/path/extras/Path.up.html),
[```Ext```](http://semitwist.com/scriptlike/scriptlike/path/extras/Ext.html),
[```dirName```](http://semitwist.com/scriptlike/scriptlike/path/wrappers/dirName.html),
[```copy```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/copy.html),
[```buildNormalizedPath```](http://dlang.org/phobos/std_path.html#buildNormalizedPath)

### Try/As Filesystem Operations

Less pedantic, when you don't care if there's nothing to do:

```d
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
```

See: [```tryMkdir```](http://semitwist.com/scriptlike/scriptlike/file/extras/tryMkdir.html),
[```mkdir```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/mkdir.html),
[```tryMkdirRecurse```](http://semitwist.com/scriptlike/scriptlike/file/extras/tryMkdirRecurse.html),
[```mkdir```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/mkdir.html),
[```tryRmdir```](http://semitwist.com/scriptlike/scriptlike/file/extras/tryRmdir.html),
[```rmdir```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/rmdir.html),
[```tryRemove```](http://semitwist.com/scriptlike/scriptlike/file/extras/tryRemove.html),
[```tryCopy```](http://semitwist.com/scriptlike/scriptlike/file/extras/tryCopy.html),
[```existsAsDir```](http://semitwist.com/scriptlike/scriptlike/file/extras/existsAsDir.html),
[```removePath```](http://semitwist.com/scriptlike/scriptlike/file/extras/removePath.html),
[```tryRemovePath```](http://semitwist.com/scriptlike/scriptlike/file/extras/tryRemovePath.html),
[```writeFile```](http://semitwist.com/scriptlike/scriptlike/file/extras/writeFile.html)
and [more...](http://semitwist.com/scriptlike/scriptlike/file/extras.html)

### Script-Style Shell Commands

Invoke a command script-style: synchronously with forwarded stdout/in/err
from any working directory. Or capture the output instead. Automatically
throw on non-zero status code if you want.

One simple call, [```run```](http://semitwist.com/scriptlike/scriptlike/process/run.html),
to run a shell command script-style (ie, synchronously with forwarded stdout/in/err)
from any working directory, and automatically throw if it fails. Or
[```runCollect```](http://semitwist.com/scriptlike/scriptlike/process/runCollect.html)
to capture the output instead of displaying it. Or
[```tryRun```](http://semitwist.com/scriptlike/scriptlike/process/tryRun.html)/[```tryRunCollect```](http://semitwist.com/scriptlike/scriptlike/process/tryRunCollect.html)
if you want to receive the status code instead of automatically throwing on non-zero.

```d
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
```

See: [```run```](http://semitwist.com/scriptlike/scriptlike/process/run.html),
[```tryRun```](http://semitwist.com/scriptlike/scriptlike/process/tryRun.html),
[```runCollect```](http://semitwist.com/scriptlike/scriptlike/process/runCollect.html),
[```tryRunCollect```](http://semitwist.com/scriptlike/scriptlike/process/tryRunCollect.html),
[```pause```](http://semitwist.com/scriptlike/scriptlike/interact/pause.html),
[```Path```](http://semitwist.com/scriptlike/scriptlike/path/extras/Path.html),
[```getcwd```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/getcwd.html),
[```ErrorLevelException```](http://semitwist.com/scriptlike/scriptlike/process/ErrorLevelException.html),
[```assertThrown```](http://dlang.org/phobos/std_exception.html#assertThrown),
[```canFind```](http://dlang.org/phobos/std_algorithm_searching.html#.canFind),
[```text```](http://dlang.org/phobos/std_conv.html#text),
[```strip```](http://dlang.org/phobos/std_string.html#.strip)

### Command Echoing

Optionally enable automatic command echoing (including shell commands,
changing/creating directories and deleting/copying/moving/linking/renaming
both directories and files) by setting one simple flag:
[```bool scriptlikeEcho```](http://semitwist.com/scriptlike/scriptlike/core/scriptlikeEcho.html)

Echoing can be customized via
[```scriptlikeCustomEcho```](http://semitwist.com/scriptlike/scriptlike/core/scriptlikeCustomEcho.html).

```d
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
```

See: [```scriptlikeEcho```](http://semitwist.com/scriptlike/scriptlike/core/scriptlikeEcho.html),
[```yap```](http://semitwist.com/scriptlike/scriptlike/core/yap.html),
[```yapFunc```](http://semitwist.com/scriptlike/scriptlike/core/yapFunc.html),
[```run```](http://semitwist.com/scriptlike/scriptlike/process/run.html),
[```Path```](http://semitwist.com/scriptlike/scriptlike/path/extras/Path.html),
[```Path.toRawString```](http://semitwist.com/scriptlike/scriptlike/path/extras/Path.toRawString.html),
[```mkdirRecurse```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/mkdirRecurse.html),
[```copy```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/copy.html)

### Dry Run Assistance

Scriptlike can help you create a dry-run mode, by automatically echoing (even if
[```scriptlikeEcho```](http://semitwist.com/scriptlike/scriptlike/core/scriptlikeEcho.html)
is disabled) and disabling all functions that
[launch external commands](http://semitwist.com/scriptlike/scriptlike/process.html)
or [modify the filesystem](http://semitwist.com/scriptlike/scriptlike/file.html).
Just enable the
[```scriptlikeDryRun```](http://semitwist.com/scriptlike/scriptlike/core/scriptlikeDryRun.html) flag.

Note, if you choose to use this, you still must ensure your program logic
behaves sanely in dry-run mode.

```d
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
```

See: [```scriptlikeDryRun```](http://semitwist.com/scriptlike/scriptlike/core/scriptlikeDryRun.html),
[```copy```](semitwist.com/scriptlike/scriptlike/file/wrappers/copy.html),
[```run```](http://semitwist.com/scriptlike/scriptlike/process/run.html),
[```exists```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/exists.html),
[```read```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/read.html)

### Fail

Single function to bail out with an error message, exception-safe.

```d
/++
Example:
--------
$ test
test: ERROR: Need two args, not 0!
$ test abc 123
test: ERROR: First arg must be 'foobar', not 'abc'!
--------
+/

import scriptlike;

void main(string[] args) {
	helper(args);
}

// Throws a Fail exception on bad args:
void helper(string[] args) {
	// Like std.exception.enforce, but bails with no ugly stack trace,
	// and if uncaught, outputs the program name and "ERROR: "
	failEnforce(args.length == 3, "Need two args, not ", args.length-1, "!");

	if(args[1] != "foobar")
		fail("First arg must be 'foobar', not '", args[1], "'!");
}
```

See: [```fail```](http://semitwist.com/scriptlike/scriptlike/fail/fail.html),
[```failEnforce```](http://semitwist.com/scriptlike/scriptlike/fail/failEnforce.html),
[```Fail```](http://semitwist.com/scriptlike/scriptlike/fail/Fail.html)

Disambiguating write and write
------------------------------

Since they're both imported by default, you may get symbol conflict errors
when trying to use
[```scriptlike.file.wrappers.write```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/write.html)
(which wraps [```std.file.write```](http://dlang.org/phobos/std_file.html#write))
or [```std.stdio.write```](http://dlang.org/phobos/std_stdio.html#.write).
And unfortunately, DMD issue [#11847](https://issues.dlang.org/show_bug.cgi?id=11847)
currently makes it impossible to use a qualified name lookup for
[```scriptlike.file.wrappers.write```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/write.html).

Here's how to easily avoid symbol conflict errors with Scriptlike and ```write```:

```d
// Save file
write("filename.txt", "content");  // Error: Symbols conflict!
// Change line above to...
writeFile("filename.txt", "content"); // Convenience alias included in scriptlike

// Output to stdout with no newline
write("Hello ", "world");  // Error: Symbols conflict!
// Change line above to...
std.stdio.write("Hello ", "world");
// or...
stdout.write("Hello ", "world");
```

See:
[```scriptlike.file.wrappers.writeFile```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/writeFile.html),
[```scriptlike.file.wrappers.readFile```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/readFile.html),
[```scriptlike.file.wrappers.write```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/write.html),
[```std.file.write```](http://dlang.org/phobos/std_file.html#write),
[```std.stdio.write```](http://dlang.org/phobos/std_stdio.html#.write)
