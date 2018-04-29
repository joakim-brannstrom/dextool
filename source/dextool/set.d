/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
Authors: Jacob Carlborg
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)

Copied from DStep.

Convenient functions for a set.
*/

alias Set(T) = void[0][T];

void add(T)(ref void[0][T] self, T value) {
    self[value] = (void[0]).init;
}

void add(T)(ref void[0][T] self, void[0][T] set) {
    foreach (key; set.byKey) {
        self.add(key);
    }
}

Set!T clone(T)(ref void[0][T] self) {
    Set!T result;
    result.add(self);
    return result;
}

bool contains(T)(inout(void[0][T]) set, T value) {
    return (value in set) !is null;
}

auto setFromList(T)(T[] list) {
    import std.traits;

    Set!(Unqual!T) result;

    foreach (item; list)
        result.add(item);

    return result;
}
