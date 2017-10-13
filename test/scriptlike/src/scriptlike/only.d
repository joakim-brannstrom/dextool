/++
$(H2 Scriptlike $(SCRIPTLIKE_VERSION))
Utility to aid in script-like programs.

Written in the $(LINK2 http://dlang.org, D programming language).

Import this `scriptlike.only` module instead of `scriptlike` if you want to
import all of Scriptlike, but DON'T want to automatically import any of Phobos.

Copyright: Copyright (C) 2014-2017 Nick Sabalausky
License:   $(LINK2 https://github.com/Abscissa/scriptlike/blob/master/LICENSE.txt, zlib/libpng)
Authors:   Nick Sabalausky
+/


module scriptlike.only;

public import scriptlike.core;
public import scriptlike.interact;
public import scriptlike.fail;
public import scriptlike.file;
public import scriptlike.path;
public import scriptlike.process;
