How to Use Scriptlike in Scripts
================================

These examples can be found in the
"[examples](https://github.com/Abscissa/scriptlike/blob/master/examples)" directory.

* [A Basic Script in D](#a-basic-script-in-d)
* [In a DUB-based project](#in-a-dub-based-project)

A Basic Script in D
-------------------
Make sure you have [DUB](http://code.dlang.org/download) v1.0.0 or later installed,
as well as a D compiler (DMD, LDC, or GDC). You can check your version of DUB
by running `dub --help`. Then, using Scriptlike in a D script is easy:

myscript.d:
```d
#!/usr/bin/env dub
/+ dub.sdl:
	name "myscript"
	dependency "scriptlike" version="~>0.10.2"
+/
import scriptlike;

void main(string[] args) {
	string name;
	if(args.length > 1)
		name = args[1];
	else
		name = userInput!string("What's your name?");

	writeln("Hello, ", name, "!");
}
```

You don't even need to download or install Scriptlike! That will be done
automatically by DUB, thanks to the `dependency` line in the special
`dub.sdl` comment section. (Learn
[more about this feature of DUB](http://code.dlang.org/getting_started#single-file-packages),
introduced in DUB v1.0.0.)

On Linux/OSX, you can then run that script just like any shell script:

```bash
$ chmod +x myscript.d
$ ./myscript.d Frank
Hello, Frank!
```

As long as you have a D compiler installed (DMD, LDC or GDC), that will
cause DUB to automatically download/install all dependencies (in this case,
just Scriptlike), recompile the script if necessary, and run it.

Or if you're on Windows (this will also work on Linux/OSX, too):
```batch
> dub myscript.d Frank
Hello, Frank!
```

NOTE: Due to [an issue](https://github.com/dlang/dub/issues/907) in DUB,
if you use this single-file approach and you need to use
[`thisExePath`](http://semitwist.com/scriptlike/scriptlike/file/wrappers/thisExePath.html)
(or the [Phobos equivalent](http://dlang.org/phobos/std_file.html#thisExePath)),
then you won't get the expected result. The `thisExePath` function will NOT
return the path to the `myscript.d` script, it will simply return the temporary
path where DUB stored the compiled binary. I'm not aware of any way to work
around this while using DUB's single-file feature, so if your script needs
to obtain its own path (remember, `args[0]` is famously unreliable for this
in any language), then try one of the older approaches below.

In a DUB-based project
----------------------
If your project uses [DUB](http://code.dlang.org/getting_started),
just include the scriptlike as a dependency in your
[dub.json](http://code.dlang.org/package-format?lang=json) or
[dub.sdl](http://code.dlang.org/package-format?lang=sdl) file like this:

dub.json:
```json
"dependencies": {
	"scriptlike": "~>0.10.2"
}
```

dub.sdl:
```
dependency "scriptlike" version="~>0.10.2"
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
