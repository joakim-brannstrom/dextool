/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.process;

import std.process : spawnProcess, Config;

/** Spawn `args` as a daemon.
 *
 * stdin and stdout is set to `/dev/null`.
 */
auto spawnDaemon(scope const(char[])[] args, scope const char[] workDir = null) {
    import std.stdio : File;

    auto devNullIn = File("/dev/null");
    auto devNullOut = File("/dev/null", "w");
    return spawnProcess(args, devNullIn, devNullOut, devNullOut, null, Config.detached, workDir);
}
