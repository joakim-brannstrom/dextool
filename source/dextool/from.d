/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

The license of this module is Boost because the code is derived from a pull
request for druntime.
*/

module dextool.from;

/** Local imports everywhere.

Example:
---
void fun(from!"std.string".Path p)
---
*/
template from(string moduleName) {
    mixin("import from = " ~ moduleName ~ ";");
}
