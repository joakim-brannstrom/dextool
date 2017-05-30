# Intro

What I think the user want to be able to do.

# Boilerplate

the user is lazy and want as much as possible of the boilerplate to be generated.

# Overwrite

the user do NOT want the user modified stuff to be overwritten.
Therefore try to integrate user modification into the generated files in some way.

# Behavior

the user want to change the _behavior_ of the wrapper.
Call order of the API, pre/post hook, have their own main function.

# Debug

The user want it to be easy to debug when the AFL finds a bug.

# Endian

Unsure. If the "binary data reader" is replacable by the user then it could be
left to the user to provide a reader that handle endiannessness.

# Wrapper Interference

The user want the wrapper to be performance. Do as little as possible.
    The user has no interest in testing the wrapper so...

The user wants the default wrapper to be light, simple with "no bugs".

# C wrapping

Dextool must fix so C-headers are included with a wrapping _extern "C"_ around
them.

# Binary Data Format

The user wants the binary data format to be "deterministic".
Deterministic mean that if the user, for example, wants to add a test case with
a parameter to a function with a specific value he knows how to modify the
binary format.

# libFuzzer

Integrate with libFuzzer from LLVM.
Be able to use the undefined behavior sanitizers etc.
