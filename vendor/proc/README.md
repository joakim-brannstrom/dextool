# proc [![Build Status](https://dev.azure.com/wikodes/wikodes/_apis/build/status/joakim-brannstrom.proc?branchName=master)](https://dev.azure.com/wikodes/wikodes/_build/latest?definitionId=10&branchName=master)

**proc** is a library to run single processes and manage trees of them. It
provides conveniences such as timeouts, output drains and sandboxing for single
processes. The process tree handling map up all running processes on the system
for convenient analyze such as killing a subtree.

# Getting Started

proc depends on the following software packages:

 * [D compiler](https://dlang.org/download.html) (dmd 2.079+, ldc 1.11.0+)

It is recommended to install the D compiler by downloading it from the official distribution page.
```sh
# link https://dlang.org/download.html
curl -fsS https://dlang.org/install.sh | bash -s dmd
```

Download the D compiler of your choice, extract it and add to your PATH shell
variable.
```sh
# example with an extracted DMD
export PATH=/path/to/dmd/linux/bin64/:$PATH
```

Once the dependencies are installed it is time to download the source code to install proc.
```sh
git clone https://github.com/joakim-brannstrom/proc.git
cd proc
dub build -b release
```

Done! Have fun.
Don't be shy to report any issue that you find.

# Examples

This is a couple of examples of how the library can be used.

A sandbox is in this library a way of assuring that any subprocesses that are
spawned have are also killed when the *root* is terminated. This is most
probably used in conjunction with *timeout*.

```d
auto p = pipeProcess([scriptName]).sandbox.scopeKill;
// do stuff. force a kill
p.kill;
```

To kill a process after a timeout.

```d
auto p = pipeProcess(["sleep", "1m"]).timeout(100.dur!"msecs").scopeKill;
// do stuff. the timeout triggers
p.wait; // the exit code of the root process
```

And then to combine both of them.

```d
auto p = pipeProcess([script]).sandbox.timeout(1.dur!"seconds").scopeKill;
// do stuff
p.wait; // the exit code of the root process
```

To drain all output from a process by line. The element returned have an
attribute, `type`, which allow you to see if it is `stdout` or `stderr`. Of
note is that the draining is conservative and thus any non-valid UTF-8 will
result in a large part of the output being discarded. Pull requests to improve
this is welcome.

```d
auto p = pipeProcess(["dd", "if=/dev/zero", "bs=10", "count=3"]).scopeKill;
foreach (l; p.process.drainByLineCopy(100.dur!"msecs").filter!"!a.empty")
    writeln(l);
```

The draining by line do have an overhead. Use the basic drain if you do not
need it to be exactly by line.

```d
auto p = pipeProcess(["dd", "if=/dev/zero", "bs=10", "count=3"]).scopeKill;
foreach (l; p.process.drain(100.dur!"msecs").filter!"!a.empty")
    writeln(l);
```

The final is a combination of all the separate wheels.

```d
auto p = pipeProcess(["proc"]).sandbox.timeout(1.dur!"seconds").scopeKill;
foreach (l; p.process.drain(100.dur!"msecs").filter!"!a.empty")
    writeln(l);
```

The library have functionality to analyze all running processes and present
them in an easily digested format. To create such a map:

```d
auto t = makePidMap();
```

Lets say you want to kill all subtrees of the init process that are owned by the current user:

```d
auto pmap = makePidMap().filterByCurrentUser;
foreach (ref t; pmap.splitToSubMaps) {
    reap(proc.kill(t));
}
```

Or maybe you just want to print the whole tree:

```d
auto pmap = makePidMap().filterByCurrentUser;
foreach (p; pmap.pids) {
    writefln("  pid:%s %s", p.to!string, pmap.getProc(p));
}
```

# Caveat

Depending on the order of the operations the behavior will be different because
an operation **may** traverse from the child up to the root. As an example
lets consider the combination of timeout and sandbox. The `kill` method of the
sandbox will kill all children while the `kill` of the timeout will only kill
the root process. This mean that the combination

```d
auto p = pipeProcess([script]).sandbox.timeout(1.dur!"seconds").scopeKill;
```

will kill the root and all children if `timeout` triggers. Timeout calls `kill`
of the sandox. The reverse though

```d
auto p = pipeProcess([script]).timeout(1.dur!"seconds").sandbox.scopeKill;
```

mean that the timeout will only kill the root process if it triggers.

The library try not to assume too much about the expected use. How it should
behave is left up to the user of the library.
