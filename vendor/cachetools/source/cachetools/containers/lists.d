module cachetools.containers.lists;

private import std.experimental.allocator;
private import std.experimental.allocator.mallocator : Mallocator;
private import std.experimental.logger;
private import std.format;

///
/// N-way multilist
struct MultiDList(T, int N, Allocator = Mallocator) {
    alias allocator = Allocator.instance;
    struct Node {
        T payload;
    private:
        Link[N] links;
        Node* next(size_t i) @safe @nogc {
            return links[i].next;
        }

        Node* prev(size_t i) @safe @nogc {
            return links[i].prev;
        }

        alias payload this;
    }

    private {
        struct Link {
            Node* prev;
            Node* next;
        }

        Node*[N] _heads;
        Node*[N] _tails;
        size_t _length;

    }
    size_t length() const pure nothrow @safe @nogc {
        return _length;
    }

    Node* insert_last(T v) @safe nothrow
    out {
        assert(_length > 0);
    }
    do {
        auto n = make!(Node)(allocator, v);
        static foreach (index; 0 .. N) {
            if (_heads[index] is null) {
                _heads[index] = n;
            }
            n.links[index].prev = _tails[index];
            if (_tails[index]!is null) {
                _tails[index].links[index].next = n;
            }
            _tails[index] = n;
        }
        _length++;
        return n;
    }

    void move_to_tail(Node* n, size_t i) @safe @nogc
    in {
        assert(i < N);
        assert(_length > 0);
    }
    out {
        assert(_heads[i]!is null && _tails[i]!is null);
    }
    do {
        if (n == _tails[i]) {
            return;
        }
        // unlink
        if (n.links[i].prev is null) {
            _heads[i] = n.links[i].next;
        } else {
            n.links[i].prev.links[i].next = n.links[i].next;
        }
        if (n.links[i].next is null) {
            _tails[i] = n.links[i].prev;
        } else {
            n.links[i].next.links[i].prev = n.links[i].prev;
        }
        // insert back
        if (_heads[i] is null) {
            _heads[i] = n;
        }
        n.links[i].prev = _tails[i];
        if (_tails[i]!is null) {
            _tails[i].links[i].next = n;
        }
        n.links[i].next = null;
        _tails[i] = n;
    }

    void remove(Node* n) nothrow @safe @nogc {
        if (n is null || _length == 0) {
            return;
        }
        static foreach (i; 0 .. N) {
            if (n.links[i].prev !is null) {
                n.links[i].prev.links[i].next = n.links[i].next;
            }
            if (n.links[i].next !is null) {
                n.links[i].next.links[i].prev = n.links[i].prev;
            }
            if (n == _tails[i]) {
                _tails[i] = n.links[i].prev;
            }
            if (n == _heads[i]) {
                _heads[i] = n.links[i].next;
            }
        }
        (() @trusted { dispose(allocator, n); })();
        _length--;
    }

    Node* tail(size_t i) pure nothrow @safe @nogc {
        return _tails[i];
    }

    Node* head(size_t i) pure nothrow @safe @nogc {
        return _heads[i];
    }

    void clear() nothrow @safe @nogc {
        while (_length > 0) {
            auto n = _heads[0];
            remove(n);
        }
    }
}

@safe unittest {
    import std.algorithm;
    import std.stdio;
    import std.range;

    struct Person {
        string name;
        int age;
    }

    MultiDList!(Person*, 2) mdlist;
    Person[3] persons = [{"Alice", 11}, {"Bob", 9}, {"Carl", 10}];
    foreach (i; 0 .. persons.length) {
        mdlist.insert_last(&persons[i]);
    }
    enum NameIndex = 0;
    enum AgeIndex = 1;
    assert(mdlist.head(NameIndex).payload.name == "Alice");
    assert(mdlist.head(AgeIndex).payload.age == 11);
    assert(mdlist.tail(NameIndex).payload.name == "Carl");
    assert(mdlist.tail(AgeIndex).payload.age == 10);
    auto alice = mdlist.head(NameIndex);
    auto bob = alice.next(NameIndex);
    auto carl = bob.next(NameIndex);
    mdlist.move_to_tail(alice, AgeIndex);
    assert(mdlist.tail(AgeIndex).payload.age == 11);
    mdlist.remove(alice);
    assert(mdlist.head(NameIndex).payload.name == "Bob");
    assert(mdlist.tail(NameIndex).payload.name == "Carl");
    assert(mdlist.head(AgeIndex).payload.age == 9);
    assert(mdlist.tail(AgeIndex).payload.age == 10);
    mdlist.insert_last(&persons[0]); // B, C, A
    mdlist.remove(carl); // B, A
    alice = mdlist.tail(NameIndex);
    assert(mdlist.length == 2);
    assert(alice.payload.name == "Alice");
    assert(alice.payload.age == 11);
    assert(mdlist.head(NameIndex).payload.name == "Bob");
    assert(mdlist.head(AgeIndex).payload.age == 9);
    assert(alice.prev(AgeIndex) == bob);
    assert(alice.prev(NameIndex) == bob);
    assert(bob.prev(AgeIndex) is null);
    assert(bob.prev(NameIndex) is null);
    assert(bob.next(AgeIndex) == alice);
    assert(bob.next(NameIndex) == alice);
    mdlist.insert_last(&persons[2]); // B, A, C
    carl = mdlist.tail(NameIndex);
    mdlist.move_to_tail(alice, AgeIndex);
    assert(bob.next(AgeIndex) == carl);
    assert(bob.next(NameIndex) == alice);
}

struct DList(T, Allocator = Mallocator) {
    this(this) @disable;
    struct Node(T) {
        T payload;
        private Node!T* prev;
        private Node!T* next;
        alias payload this;
    }

    private {
        alias allocator = Allocator.instance;
        Node!T* _head;
        Node!T* _tail;
        ulong _length;
    }

    invariant {
        assert((_length > 0 && _head !is null && _tail !is null) || (_length == 0
                && _tail is null && _tail is null) || (_length == 1 && _tail == _head && _head !is null),
                "length: %s, head: %s, tail: %s".format(_length, _head, _tail));
    }

    ulong length() const pure nothrow @safe @nogc {
        return _length;
    }

    Node!T* insert_last(T v) @safe nothrow
    out {
        assert(_length > 0);
        assert(_head !is null && _tail !is null);
    }
    do {
        auto n = make!(Node!T)(allocator);
        n.payload = v;
        if (_head is null) {
            _head = n;
        }
        n.prev = _tail;
        if (_tail !is null) {
            _tail.next = n;
        }
        _tail = n;
        _length++;
        return n;
    }

    alias insertFront = insert_first;
    Node!T* insert_first(T v) @safe nothrow
    out {
        assert(_length > 0);
        assert(_head !is null && _tail !is null);
    }
    do {
        auto n = make!(Node!T)(allocator);
        n.payload = v;
        if (_tail is null) {
            _tail = n;
        }
        n.next = _head;
        if (_head !is null) {
            _head.prev = n;
        }
        _head = n;
        _length++;
        return n;
    }

    bool remove(Node!T* n) @safe @nogc
    in {
        assert(_length > 0);
    }
    do {
        if (n.prev) {
            n.prev.next = n.next;
        }
        if (n.next) {
            n.next.prev = n.prev;
        }
        if (n == _tail) {
            _tail = n.prev;
        }
        if (n == _head) {
            _head = n.next;
        }
        (() @trusted { dispose(allocator, n); })();
        _length--;
        return true;
    }

    void move_to_tail(Node!T* n) @safe @nogc
    in {
        assert(_length > 0);
        assert(_head !is null && _tail !is null);
    }
    out {
        assert(_tail == n && n.next is null);
    }
    do {
        if (n == _tail) {
            return;
        }
        // unlink
        if (n.prev is null) {
            _head = n.next;
        } else {
            n.prev.next = n.next;
        }
        if (n.next is null) {
            _tail = n.prev;
        } else {
            n.next.prev = n.prev;
        }
        // insert back
        if (_head is null) {
            _head = n;
        }
        n.prev = _tail;
        if (_tail !is null) {
            _tail.next = n;
        }
        n.next = null;
        _tail = n;

        ////debug(cachetools) tracef("n: %s".format(*n));
        //assert(n.next !is null);
        ////debug tracef("m-t-t: %s, tail: %s", *n, *_tail);
        //assert(n.next, "non-tail entry have no 'next' pointer?");
        //if ( _head == n ) {
        //    assert(n.prev is null);
        //    _head = n.next;
        //} else {
        //    n.prev.next = n.next;
        //}
        //// move this node to end
        //n.next.prev = n.prev;
        //n.next = null;
        //tail.next = n;
        //_tail = n;
    }

    Node!T* head() @safe @nogc nothrow {
        return _head;
    }

    Node!T* tail() @safe @nogc nothrow {
        return _tail;
    }
}

struct SList(T, Allocator = Mallocator) {
    this(this) @safe {
        // copy items
        _Node!T* __newFirst, __newLast;
        auto f = _first;
        while (f) {
            auto v = f.v;
            auto n = make!(_Node!T)(allocator, v);
            if (__newLast !is null) {
                __newLast._next = n;
            } else {
                __newFirst = n;
            }
            __newLast = n;
            f = f._next;
        }
        _first = __newFirst;
        _last = __newLast;
    }

    package {
        struct _Node(T) {
            T v;
            _Node!T* _next;
        }

        alias allocator = Allocator.instance;

        ulong _length;
        _Node!T* _first;
        _Node!T* _last;
    }

    invariant {
        assert((_length > 0 && _first !is null && _last !is null) || (_length == 0
                && _first is null && _last is null));
    }

    ~this() {
        clear();
    }

    ulong length() const pure @nogc @safe nothrow {
        return _length;
    }

    bool empty() @nogc @safe const {
        return _length == 0;
    }

    T front() pure @nogc @safe {
        return _first.v;
    }

    T back() pure @nogc @safe {
        return _last.v;
    }

    T popFront() @nogc @safe nothrow
    in {
        assert(_first !is null);
    }
    do {
        T v = _first.v;
        auto next = _first._next;
        (() @trusted { dispose(allocator, _first); })();
        _first = next;
        if (_first is null) {
            _last = null;
        }
        _length--;
        return v;
    }

    void clear() @nogc @safe {
        _Node!T* n = _first;
        while (n !is null) {
            auto next = n._next;
            (() @trusted { dispose(allocator, n); })();
            n = next;
        }
    }

    private struct Range(T) {
        private {
            _Node!T* current;
        }
        auto front() pure nothrow @safe @nogc @property {
            return &current.v;
        }

        void popFront() @safe @nogc nothrow {
            current = current._next;
        }

        bool empty() pure const nothrow @safe @nogc @property {
            return current is null;
        }
    }

    alias opSlice = range;
    auto range() {
        return Range!T(_first);
    }

    void insertFront(T v) @safe nothrow
    out {
        assert(_first !is null && _last !is null);
    }
    do {
        auto n = make!(_Node!T)(allocator, v);
        if (_first !is null) {
            n._next = _first;
        }
        _first = n;
        if (_last is null) {
            _last = n;
        }
        _length++;
    }

    void insertBack(T v) @safe nothrow
    out {
        assert(_first !is null && _last !is null);
    }
    do {
        auto n = make!(_Node!T)(allocator, v);
        if (_last !is null) {
            _last._next = n;
        } else {
            _first = n;
        }
        _last = n;
        _length++;
    }

    bool remove_by_predicate(scope bool delegate(T) @safe @nogc nothrow f) @nogc @trusted nothrow {
        bool removed;
        _Node!T* current = _first;
        _Node!T* prev = null;
        while (current !is null) {
            auto next = current._next;
            if (!f(current.v)) {
                prev = current;
                current = next;
                continue;
            }
            // do remove
            _length--;
            removed = true;
            dispose(allocator, current);
            if (prev is null) {
                _first = next;
            } else {
                prev._next = next;
            }
            if (next is null) {
                _last = prev;
            }
        }
        return removed;
    }
}

@safe @nogc nothrow unittest {
    SList!int l;
    assert(l.length() == 0);
    l.insertFront(0);
    assert(l.front() == 0);
    l.popFront();
    l.insertBack(1);
    assert(l.front() == 1);
    assert(l.length() == 1);
    l.insertBack(2);
    assert(l.front() == 1);
    assert(l.back() == 2);
    assert(l.length() == 2);
    //log(l.range());
    l.popFront();
    assert(l.front() == 2);
    assert(l.back() == 2);
    assert(l.length() == 1);
    l.insertBack(3);
    l.insertBack(4);
    //foreach(v; l[]){
    //    log("v=%d\n", *v);
    //}
    //log("---\n");
    bool removed;
    removed = l.remove_by_predicate((n) { return n == 2; });
    foreach (v; l[]) {
        //log("v=%d\n", *v);
    }
    assert(removed);
    assert(l.length() == 2);
    //log("---\n");
    removed = l.remove_by_predicate((n) { return n == 4; });
    foreach (v; l[]) {
        //log("v=%d\n", *v);
    }
    assert(removed);
    assert(l.length() == 1);
    //log("---\n");
    removed = l.remove_by_predicate((n) { return n == 3; });
    foreach (v; l[]) {
        //log("v=%d\n", *v);
    }
    assert(removed);
    assert(l.length() == 0);
    //log("---\n");
    removed = l.remove_by_predicate((n) { return n == 3; });
    foreach (v; l[]) {
        //log("v=%d\n", *v);
    }
    assert(!removed);
    assert(l.length() == 0);
    auto l1 = SList!int();
    foreach (i; 0 .. 100) {
        l1.insertBack(i);
    }
    while (l1.length) {
        l1.popFront();
    }
    foreach (i; 0 .. 100) {
        l1.insertFront(i);
    }
    while (l1.length) {
        l1.popFront();
    }
}

@safe @nogc nothrow unittest {
    DList!int dlist;
    auto n0 = dlist.insertFront(0);
    assert(dlist.head.payload == 0);
    dlist.remove(n0);
    auto n1 = dlist.insert_last(1);
    assert(dlist.length == 1);
    dlist.remove(n1);
    assert(dlist.length == 0);

    n1 = dlist.insert_first(1);
    assert(dlist.length == 1);
    dlist.remove(n1);
    assert(dlist.length == 0);

    n1 = dlist.insert_first(1);
    auto n2 = dlist.insert_last(2);
    assert(dlist.length == 2);
    dlist.move_to_tail(n1);
    assert(dlist.head.payload == 2);
    assert(dlist.tail.payload == 1);
}
