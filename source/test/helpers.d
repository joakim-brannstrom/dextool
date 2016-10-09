/**
Date: 2015-2016, Joakim Brännström
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module test.helpers;

import cpptooling.utility.virtualfilesystem;

void openAndWrite(ref VirtualFileSystem vfs, FileName fname, Content content) {
    vfs.openInMemory(fname);
    vfs.write(fname, content);
}
