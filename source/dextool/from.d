/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

The license of this module is Boost because the code is derived from a pull
request for druntime.

Local imports everywhere.

Example:
---
std_.foo fun(std_.string.Path p)
---
*/
module dextool.from;

template from(string moduleName) {
    mixin("import from = " ~ moduleName ~ ";");
}
