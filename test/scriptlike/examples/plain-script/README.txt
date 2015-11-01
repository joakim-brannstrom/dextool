To run this example:

First, ensure you have DMD and DUB installed:
- DMD: http://dlang.org/download.html#dmd
- DUB: http://code.dlang.org/download

Then, make sure Scriptlike is installed through DUB:
$ dub fetch scriptlike --version=0.9.4

And then...

On Windows:
-----------
$ myscript
or
$ myscript Frank

On Linux/OSX:
-------------
$ ln -s myscript.sh myscript
$ ./myscript
or
$ ./myscript Frank

Yes, the link is important (at least on OSX). This is due to a workaround for
OSX's lack of 'readlink -f', which is needed to make the scripts runnable from
ANY directory, not just their own.
