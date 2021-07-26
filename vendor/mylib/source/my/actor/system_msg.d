/**
Copyright: Copyright (c) 2021, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module my.actor.system_msg;

import my.actor.common : SystemError, ExitReason;
import my.actor.mailbox : Address;

/// Sent to all links when an actor is terminated.
struct ExitMsg {
    /// The source of this message, i.e., the terminated actor.
    Address* source;

    /// The exit reason of the terminated actor.
    SystemError reason;
}

/// The system signals the actor to shutdown.
struct SystemExitMsg {
    /// The systems exit reason of the terminated actor.
    ExitReason reason;
}

/// Sent to all actors monitoring an actor that is terminated.
struct DownMsg {
    /// The source of this message, i.e., the terminated actor.
    Address* source;

    /// The exit reason of the terminated actor.
    SystemError reason;
}

struct ErrorMsg {
    /// The source of this message, i.e., the terminated actor.
    Address* source;

    /// The exit reason of the terminated actor.
    SystemError reason;
}

// Incoming requests to link to the actor using this address.
struct MonitorRequest {
    Address* addr;
}

// Request to remove `addr` as a monitor.
struct DemonitorRequest {
    Address* addr;
}

// Incoming requests to link to the actor using this address.
struct LinkRequest {
    Address* addr;
}

// Request to remove `addr` as a link.
struct UnlinkRequest {
    Address* addr;
}
