How to Use Scriptlike in Scripts
================================

These examples can be found in the "[examples](https://github.com/Abscissa/scriptlike/blob/master/examples)" directory.

* [In a DUB-based project](#in-a-dub-based-project)
* [In a plain script](#in-a-plain-script)
* [FAQ](#faq)

In a DUB-based project
----------------------
If your project uses [DUB](http://code.dlang.org/getting_started), just include the scriptlike as a dependency in your [dub.json](http://code.dlang.org/package-format?lang=json) or [dub.sdl](http://code.dlang.org/package-format?lang=sdl) file like this:

dub.json:
```json
"dependencies": {
	"scriptlike": "~>0.9.6"
}
```

dub.sdl:
```
dependency "scriptlike" version="~>0.9.6"
```

And then import with one of these:

```d
// Imports all of Scriptlike, plus anything from Phobos likely to
// be useful for scripts:
import scriptlike;

// Or import only Scriptlike and omit the automatic Phobos imports:
import scriptlike.only;
```

Run your project with dub like normal:

```bash
$ dub
```

In a plain script
----------------------

Assuming you have [DMD](http://dlang.org/download.html#dmd) and [DUB](http://code.dlang.org/download) installed:

myscript.d:
```d
import scriptlike;

void main(string[] args) {
	writeln("This script is in directory: ", thisExePath.dirName);

	string name;
	if(args.length > 1)
		name = args[1];
	else
		name = userInput!string("What's your name?");

	writeln("Hello, ", name, "!");
}
```

myscript.sh:
```bash
#!/bin/sh
SCRIPT_DIR="$(dirname "$(dirname "$0")/$(readlink "$0")")"
rdmd -I~/.dub/packages/scriptlike-0.9.6/scriptlike/src/ -of$SCRIPT_DIR/.myscript $SCRIPT_DIR/myscript.d "$@"
```

myscript.bat:
```batch
@echo off
rdmd -I%APPDATA%/dub/packages/scriptlike-0.9.6/scriptlike/src/ -of%~dp0.myscript %~dp0myscript.d %*
```

On Linux/OSX:
```bash
$ chmod +x myscript.sh
$ ln -s myscript.sh myscript
$ dub fetch scriptlike --version=0.9.6
$ ./myscript Frank
Hello, Frank!
```

On Windows:
```batch
> dub fetch scriptlike --version=0.9.6
> myscript Frank
Hello, Frank!
```

FAQ
---

### Why not just use a shebang line instead of the bash helper script?

**Short:** You can, but it won't work work on other people's machines.

**Long:** D does support Posix shebang lines, so you *could* omit the `myscript` file and add the following to the top of `myscript.d`:

```bash
#!/PATH/TO/rdmd --shebang -I~/.dub/packages/scriptlike-0.9.6/scriptlike/src/
```

Problem is, there's no way to make that portable across machines. The rdmd tool isn't always going to be in the same place for everyone. Some people may have it in `/bin`, some may have it in `/opt/dmd2/linux/bin64`, `/opt/dmd2/linux/bin32` or `/opt/dmd2/osx/bin`, some people install via [DVM](https://github.com/jacob-carlborg/dvm) (which I recommend) which puts it in `~/.dvm/compilers/dmd-VERSION/...`, and some people simply unzip the [DMD](http://dlang.org/download.html#dmd) archive and use it directly from there.

What about `/usr/bin/env`? Unfortunately, it can't be used here. It lacks an equivalent to RDMD's `--shebang` command, so it's impossible to use it in a shebang line and still pass the necessary args to RDMD.

Additionally, using the shebang method on Posix would mean that invoking the script would be different even more between Posix and Windows than simply slash-vs-backslash: `myscript.d` vs `myscript`.

### Why the -of?

**Short:** So rdmd doesn't break [```thisExePath```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/thisExePath.html).

**Long:** Without ```-of```, rdmd will create the executable binary in a temporary directory. So if your program uses [```thisExePath```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/thisExePath.html) to find the directory your program is in, it will only get the temporary directory, instead of the directory with your script.

Of course, if your program doesn't use [```thisExePath```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/thisExePath.html), then it doesn't matter and you can omit the ```-of```.

Why even use [```thisExePath```](http://semitwist.com/scriptlike/scriptlike/file/wrappers/thisExePath.html) instead of ```args[0]```? Because ```args[0]``` is notoriously unreliable and for various reasons, will often not give you the *real* path to the *real* executable (this is true in any language, not just D).

### What's with the ```$SCRIPT_DIR``` and ```%~dp0``` stuff?

**Short:** So you can run your script from any directory, not just its own.

**Long:** Those are the ways to get the directory of the currently-running script in Posix/Windows shells. This way, if you run your script from a different working directory, rdmd will look for your D file is the correct place, rather than just assuming it's in whatever directory you happen to be in.

Note that on OSX, you will still need to run the script from it's own directory (unless you run a symlink to the script, then you can still run the symlink from any directory). This is because OSX doesn't implement ```readlink -f``` and plain old ```readlink``` only produces output for symlinks.

### Why bother with the symlink? Why not just rename ```myscript.sh``` to ``myscript```?

**Short:** So you can run your script from any directory, not just its own...*on OSX*.

**Long:** Normally you could use ```"$(dirname "$(readlink -f "$0")")"``` to get ```$SCRIPT_DIR```. But ```readlink -f``` is reported to not work on OSX (and some other BSDs, although it worked for me on OpenBSD 10.2). So plain old ordinary ```readlink``` is needed. But that *only* works on actual links. Hence, the symlink to ```myscript.sh```.

### Why have the Windows executable named ```.myscript.exe```? Why not just name it ```myscript.exe```?

**Short:** Consistency, and to not hijack the .bat file.

**Long:** On Windows, .exe files take precedence over .bat, so the next time you run ```myscript``` it'll *seem* to work, but will run the .exe directly, not the .bat. So it won't recompile when you change ```myscript.d```.

The leading dot also provides consistency with the Posix script, which is helpful when working in out modern cross-platform world.
