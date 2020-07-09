bool fun() {
    // do not replace true with true
    bool a = true;
    return true;
}

bool wun() {
    // do not replace false with false
    bool a = false;
    return false;
}

struct Foo {};

struct Bar {
    Foo foo{}; // do not remove {}
    Bar()
        : foo() // do not remove ()
    {}
};
