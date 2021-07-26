# Notes

# Messages

# Actor Instantiation

The actor is open and accepts messages when it is being constructed. This mean
that an actor can in its spawn-function send messages to itself. These messages
are guaranteed to be the first to arrive to the actor. This behavior is thus a
convenient way to asynchronous initialize parts of an actor such as "opening" a
database which may take multiple ms.

# TODO

Add ability to detect "dead" actors. That is an actor that have empty queues
and nobody have an address to it. Thus it can never be activated. It just sits
there and takes up memory and a little bit of CPU. It would be very nice to
automatically detect and remove them. It would also mean that user
implementation of actors do not have to care about always shutting down actors.
The "system" will take care of it for them sooner or later.

