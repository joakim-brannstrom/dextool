/**
Copyright: Copyright (c) 2020, Sebastiaan de Schaetzen. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Sebastiaan de Schaetzen

Author: Joakim Brännström (joakim.brannstrom@gmx.com) (modifications)

**All** credit goes to Sebastiaan. It is only copied here for convenience.

A simple to use async/await library.

# dawait - A simple to use async/await library

This library provides a very easy-to-use async/await library for D.
It consists of only three functions: `async`, `await`, and `startScheduler`.
The library is build on top of D's fibers and allows for easier cooperative multitasking.

## Functionality

|Function|Description|
|--------|-----------|
|`startScheduler(void delegate() callback)`| Starts the scheduler with an initial task.|
|`async(void delegate() callback)`|Runs the given delegate in a separate fiber.|
|`await(lazy T task)`|Runs the expression in a separate thread. Once the thread has completely, the result is returned.|

## Code Example
```d
import std.stdio;

int calculateTheAnswer() {
    import core.thread : Thread;
    Thread.sleep(5.seconds);
    return 42;
}

void doTask() {
    writeln("Calculating the answer to life, the universe, and everything...");
    int answer = await(calculateTheAnswer());
    writeln("The answer is: ", answer);
}

void main() {
    startScheduler({
        doTask();
    });
}
```
*/
module my.await;

import std.parallelism;
import std.container;
import core.thread.fiber;
import core.sync.semaphore;

private SList!Fiber fibersQueued = SList!Fiber();
private size_t globalWaitingOnThreads = 0;
private shared Semaphore globalSync;

/**
Creates an async task.
An async task is a task that will be running in a separate fiber, independent
from the current fiber.

Params:
    task = The task to run.
*/
void async(void delegate() task) {
    auto fiber = new Fiber(task);
    fibersQueued.insert(fiber);
}

@("async queues task")
unittest {
    scope (exit)
        fibersQueued = SList!Fiber();
    // there should be no queued tasks at first"
    assert(fibersQueued.empty);
    async({});
    // there should be a single task
    assert(!fibersQueued.empty);
}

@("async should not immediately execute its task")
unittest {
    scope (exit)
        fibersQueued = SList!Fiber();
    bool executed = false;
    auto executeIt = { executed = true; };
    async(executeIt);
    // async should not execute its operand
    assert(!executed);
}

/**
Runs the argument in a separate task, waiting for the result.
*/
T await(T)(lazy T task)
in (Fiber.getThis() !is null && globalSync !is null) {
    globalWaitingOnThreads++;
    shared finished = false;

    auto semaphore = globalSync;
    T result;
    scopedTask({
        scope (exit)
            finished = true;
        assert(semaphore !is null);
        result = task;
        (cast(Semaphore) semaphore).notify();
    }).executeInNewThread();

    while (!finished) {
        Fiber.yield();
    }
    globalWaitingOnThreads--;

    return result;
}

@("await can run a quick thread")
unittest {
    scope (exit)
        fibersQueued = SList!Fiber();
    bool executed = false;
    startScheduler({ await(executed = true); });
    // a quick thread should run
    assert(executed);
}

@("await can run a slow thread")
unittest {
    scope (exit)
        fibersQueued = SList!Fiber();
    bool executed = false;

    bool largeTask() {
        import core.thread : Thread;

        Thread.sleep(2.seconds);
        executed = true;
        return true;
    }

    startScheduler({ await(largeTask()); });
    // a slow thread should run
    assert(executed);
}

@("await should return the value that was calculated")
unittest {
    scope (exit)
        fibersQueued = SList!Fiber();
    bool executed = false;

    bool someTask() {
        return true;
    }

    startScheduler({ executed = await(someTask()); });
    // a slow thread should run
    assert(executed);
}

/**
Starts the scheduler.
*/
void startScheduler(void delegate() firstTask) {
    globalSync = cast(shared) new Semaphore;
    async({ firstTask(); });

    while (!fibersQueued.empty) {
        auto fibersRunning = fibersQueued;
        fibersQueued = SList!Fiber();
        foreach (Fiber fiber; fibersRunning) {
            fiber.call();
            if (fiber.state != Fiber.State.TERM)
                fibersQueued.insert(fiber);
        }

        if (globalWaitingOnThreads > 0) {
            (cast(Semaphore) globalSync).wait();
        }
    }
}

@("startScheduler should run initial task")
unittest {
    scope (exit)
        fibersQueued = SList!Fiber();
    bool executed = false;
    startScheduler({ executed = true; });
    // startScheduler should execute the initial task
    assert(executed);
}

@("startScheduler should also run tasks registered before itself")
unittest {
    scope (exit)
        fibersQueued = SList!Fiber();
    bool executed = false;
    async({ executed = true; });
    startScheduler({});
    // startScheduler should execute the task executed before itself
    assert(executed);
}

@("startScheduler should also run tasks registered by the initial task")
unittest {
    scope (exit)
        fibersQueued = SList!Fiber();
    bool executed = false;
    startScheduler({ async({ executed = true; }); });
    // startScheduler should execute the task created during the initial task
    assert(executed);
}
