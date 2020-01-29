///
module cachetools.containers.lists;

private import core.memory;

private import std.experimental.allocator;
private import std.experimental.allocator.mallocator : Mallocator;
private import std.experimental.allocator.gc_allocator;
private import std.experimental.logger;
private import std.format;

private import cachetools.internal;

///
/// N-way multilist
struct MultiDList(T, int N, Allocator = Mallocator, bool GCRangesAllowed = true)
{
    static assert(N>0);
    alias allocator = Allocator.instance;
    struct Node {
        T payload;
        private:
        Link[N] links;
        Node* next(size_t i) @safe @nogc
        {
            return links[i].next;
        }
        Node* prev(size_t i) @safe @nogc
        {
            return links[i].prev;
        }
        alias payload this;
    }
    private 
    {
        struct Link
        {
            Node* prev;
            Node* next;
        }
        Node*[N]    _heads;
        Node*[N]    _tails;
        size_t      _length;
        
    }
    ~this() @safe
    {
        clear();
    }
    size_t length() const pure nothrow @safe @nogc {
        return _length;
    }

    Node* insert_last(T v)
    out
    {
        assert(_length>0);
    }
    do
    {
        auto n = make!(Node)(allocator, v);
        static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) )
        {
            () @trusted
            {
                GC.addRange(n, Node.sizeof);
            }();
        }
        static foreach(index;0..N) {
            if ( _heads[index] is null ) {
                _heads[index] = n;
            }
            n.links[index].prev = _tails[index];
            if ( _tails[index] !is null )
            {
                _tails[index].links[index].next = n;
            }
            _tails[index] = n;
        }
        _length++;
        return n;
    }

    void move_to_tail(Node* n, size_t i) @safe @nogc
    in
    {
        assert(i < N);
        assert(_length>0);
    }
    out
    {
        assert(_heads[i] !is null && _tails[i] !is null);
    }
    do
    {
        if ( n == _tails[i] ) {
            return;
        }
        // unlink
        if ( n.links[i].prev is null )
        {
            _heads[i] = n.links[i].next;
        }
        else
        {
            n.links[i].prev.links[i].next = n.links[i].next;
        }
        n.links[i].next.links[i].prev = n.links[i].prev;

        // insert back
        if ( _heads[i] is null ) {
            _heads[i] = n;
        }
        n.links[i].prev = _tails[i];
        if ( _tails[i] !is null )
        {
            _tails[i].links[i].next = n;
        }
        n.links[i].next = null;
        _tails[i] = n;
    }

    void remove(Node* n) nothrow @safe @nogc
    {
        if ( n is null || _length == 0 )
        {
            return;
        }
        static foreach(i;0..N) {
            if ( n.links[i].prev !is null ) {
                n.links[i].prev.links[i].next = n.links[i].next;
            }
            if ( n.links[i].next !is null ) {
                n.links[i].next.links[i].prev = n.links[i].prev;
            }
            if ( n == _tails[i] ) {
                _tails[i] = n.links[i].prev;
            }
            if ( n == _heads[i] ) {
                _heads[i] = n.links[i].next;
            }
        }
        () @trusted {
            static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) )
            {
                GC.removeRange(n);
            }
            dispose(allocator, n);
        }();
        _length--;
    }
    Node* tail(size_t i) pure nothrow @safe @nogc
    {
        return _tails[i];
    }
    Node* head(size_t i) pure nothrow @safe @nogc
    {
        return _heads[i];
    }
    void clear() nothrow @safe @nogc
    {
        while(_length>0)
        {
            auto n = _heads[0];
            remove(n);
        }
    }
}

@safe unittest {
    import std.algorithm;
    import std.stdio;
    import std.range;
    struct Person
    {
        string name;
        int    age;
    }
    MultiDList!(Person*, 2) mdlist;
    Person[3] persons = [{"Alice", 11}, {"Bob", 9}, {"Carl", 10}];
    foreach(i; 0..persons.length)
    {
        mdlist.insert_last(&persons[i]);
    }
    enum NameIndex = 0;
    enum AgeIndex  = 1;
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

/// Double linked list
struct DList(T, Allocator = Mallocator, bool GCRangesAllowed = true) {
    this(this) @disable;

    ///
    struct Node(T) {
        /// Node content.
        T payload;
        private Node!T* prev;
        private Node!T* next;
        alias payload this;
    }
    private {
        alias allocator = Allocator.instance;
        Node!T* _head;
        Node!T* _tail;
        ulong   _length;
        
        Node!T* _freelist;
        uint    _freelist_len;
        enum    _freelist_len_max = 100;
    }

    private struct Range {
        Node!T* _current;
        T front() @safe {
            return _current.payload;
        }
        void popFront() @safe {
            _current = _current.next;
        }
        bool empty() @safe {
            return _current is null;
        }
    }

    invariant {
        assert
        (
            ( _length > 0 && _head !is null && _tail !is null) ||
            ( _length == 0 && _tail is null && _tail is null) ||
            ( _length == 1 && _tail == _head && _head !is null ),
            "length: %s, head: %s, tail: %s".format(_length, _head, _tail)
        );
    }

    ~this() {
        clear();
    }

    /// Iterator over items
    Range range() @safe {
        return Range(_head);
    }

    /// Number of items in list
    ulong length() const pure nothrow @safe @nogc {
        return _length;
    }

    private void move_to_feelist(Node!T* n) @safe {
        if ( _freelist_len < _freelist_len_max )
        {
            n.next = _freelist;
            _freelist = n;
            ++_freelist_len;
        }
        else
        {
            () @trusted {
                static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) ) {
                    GC.removeRange(&n.payload);
                }
                dispose(allocator, n);
            }();
        }
    }

    private Node!T* peek_from_freelist(ref T v) 
    {
        if ( _freelist_len )
        {
            _freelist_len--;
            auto r = _freelist;
            _freelist = r.next;
            r.next = r.prev = null;
            r.payload = v;
            return r;
        }
        else
        {
            auto n = make!(Node!T)(allocator, v);
            static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) ) {
                () @trusted {
                    GC.addRange(&n.payload, T.sizeof);
                }();
            }
            return n;
        }
    }

    /// insert item at list back.
    alias insertBack = insert_last;
    /// ditto
    Node!T* insert_last(T v)
    out {
        assert(_length>0);
        assert(_head !is null && _tail !is null);
    }
    do {
        Node!T* n = peek_from_freelist(v);
        if ( _head is null ) {
            _head = n;
        }
        n.prev = _tail;
        if ( _tail !is null )
        {
            _tail.next = n;
        }
        _tail = n;
        _length++;
        return n;
    }

    /// insert item at list front
    alias insertFront = insert_first;
    /// ditto
    Node!T* insert_first(T v)
    out {
        assert(_length>0);
        assert(_head !is null && _tail !is null);
    }
    do {
        Node!T* n = peek_from_freelist(v);
        if ( _tail is null ) {
            _tail = n;
        }
        n.next = _head;
        if ( _head !is null )
        {
            _head.prev = n;
        }
        _head = n;
        _length++;
        return n;
    }

    /// remove all items from list
    void clear() @safe {
        Node!T* n = _head, next;
        while(n)
        {
            next = n.next;
            () @trusted {
                static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) ) {
                    GC.removeRange(&n.payload);
                }
                dispose(allocator, n);
            }();
            n = next;
        }
        n = _freelist;
        while(n)
        {
            next = n.next;
            () @trusted {
                static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) ) {
                    GC.removeRange(&n.payload);
                }
                dispose(allocator, n);
            }();
            n = next;
        }
        _length = 0;
        _freelist_len = 0;
        _head = _tail = _freelist = null;
    }

    /** 
        pop front item.
        Returns: true if list was not empty
    **/
    bool popFront() @safe {
        if ( _length == 0 )
        {
            return false;
        }
        return remove(_head);
    }

    /** 
        pop last item.
        Returns: true if list was not empty
    **/
    bool popBack() @safe {
        if ( _length == 0 )
        {
            return false;
        }
        return remove(_tail);
    }

    /// remove node by pointer. (safe until pointer is correct)
    bool remove(Node!T* n) @safe @nogc
    in {assert(_length>0);}
    do {
        if ( n.prev ) {
            n.prev.next = n.next;
        }
        if ( n.next ) {
            n.next.prev = n.prev;
        }
        if ( n == _tail ) {
            _tail = n.prev;
        }
        if ( n == _head ) {
            _head = n.next;
        }
        _length--;
        move_to_feelist(n);
        return true;
    }

    /// move node to tail
    void move_to_tail(Node!T* n) @safe @nogc
    in {
        assert(_length > 0);
        assert(_head !is null && _tail !is null);
    }
    out {
        assert(_tail == n && n.next is null);
    }
    do {
        if ( n == _tail ) {
            return;
        }
        // unlink
        if ( n.prev is null )
        {
            _head = n.next;
        }
        else
        {
            n.prev.next = n.next;
        }
        n.next.prev = n.prev;
        // insert back
        n.prev = _tail;
        if ( _tail !is null )
        {
            _tail.next = n;
        }
        n.next = null;
        _tail = n;

    }

    /// move to head
    void move_to_head(Node!T* n) @safe @nogc
    in {
        assert(_length > 0);
        assert(_head !is null && _tail !is null);
    }
    out {
        assert(_head == n && n.prev is null);
    }
    do {
        if ( n == _head ) {
            return;
        }
        // unlink
        n.prev.next = n.next;
        if ( n.next is null )
        {
            _tail = n.prev;
        }
        else
        {
            n.next.prev = n.prev;
        }

        // insert front
        n.next = _head;
        if ( _head !is null )
        {
            _head.prev = n;
        }
        n.prev = null;
        _head = n;

    }

    alias front = head;
    /** 
        head node
        Returns: pointer to head node
    **/
    Node!T* head() @safe @nogc nothrow {
        return _head;
    }

    alias back = tail;
    /** Tail node
        Returns: pointer to tail node.
    */
    Node!T* tail() @safe @nogc nothrow {
        return _tail;
    }
}

///
struct SList(T, Allocator = Mallocator, bool GCRangesAllowed = true) {
    this(this)
    {
        // copy items
        _Node!T* __newFirst, __newLast;
        auto f = _first;
        while(f)
        {
            auto v = f.v;
            auto n = make!(_Node!T)(allocator, v);
            static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) )
            {
                () @trusted {
                    GC.addRange(&n.v, T.sizeof);
                }();
            }
            if ( __newLast !is null ) {
                __newLast._next = n;
            } else {
                __newFirst = n;
            }
            __newLast = n;
            f = f._next;
        }
        _first = __newFirst;
        _last = __newLast;
        _freelist = null;
        _freelist_len = 0;
    }

    void opAssign(typeof(this) other)
    {
        // copy items
        debug(cachetools) safe_tracef("opAssign SList");
        _Node!T* __newFirst, __newLast;
        auto f = other._first;
        while(f)
        {
            auto v = f.v;
            auto n = make!(_Node!T)(allocator, v);
            static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) )
            {
                () @trusted {
                    GC.addRange(&n.v, T.sizeof);
                }();
            }
            if ( __newLast !is null ) {
                __newLast._next = n;
            } else {
                __newFirst = n;
            }
            __newLast = n;
            f = f._next;
        }
        _first = __newFirst;
        _last = __newLast;
        _length = other._length;
        _freelist = null;
        _freelist_len = 0;
    }

    ~this() @safe {
        clear();
    }

    package {
        struct _Node(T) {
            T v;
            _Node!T *_next;
        }
        alias allocator = Allocator.instance;

        ulong _length;
        _Node!T *_first;
        _Node!T *_last;
        
        _Node!T* _freelist;
        uint     _freelist_len;
        enum     _freelist_len_max = 100;
    }

    invariant {
        try
        {
            assert (
                ( _length > 0 && _first !is null && _last !is null) ||
                ( _length == 0 && _first is null && _last is null),
                "length: %d, first: %s, last: %s".format(_length, _first, _last)
            );
        }
        catch(Exception e)
        {
        }
    }

    /// number of items in list
    ulong length() const pure @nogc @safe nothrow {
        return _length;
    }
    /// item empty?
    bool empty() @nogc @safe const {
        return _length == 0;
    }
    /// front item
    T front() pure @nogc @safe {
        return _first.v;
    }
    /// back item
    T back() pure @nogc @safe {
        return _last.v;
    }

    private void move_to_feelist(_Node!T* n) @safe
    {
        if ( _freelist_len < _freelist_len_max )
        {
            n._next = _freelist;
            _freelist = n;
            ++_freelist_len;
        }
        else
        {
            (() @trusted {
                static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) )
                {
                    GC.removeRange(&n.v);
                }
                dispose(allocator, n);
            })();
        }
    }
    private _Node!T* peek_from_freelist() @safe
    {
        if ( _freelist_len )
        {
            _freelist_len--;
            auto r = _freelist;
            _freelist = r._next;
            r._next = null;
            return r;
        }
        else
        {
            auto n = make!(_Node!T)(allocator);
            static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) )
            {
                () @trusted
                {
                    GC.addRange(&n.v, T.sizeof);
                }();
            }
            return n;
        }
    }
    /// pop front item
    T popFront() @nogc @safe nothrow
    in { assert(_first !is null); }
    do {
        T v = _first.v;
        auto next = _first._next;
        _length--;
        move_to_feelist(_first);
        _first = next;
        if ( _first is null ) {
            _last = null;
        }
        return v;
    }
    /// clear everything
    void clear() @nogc @safe {
        _Node!T* n = _first;
        while( n !is null ) {
            auto next = n._next;
            (() @trusted {
                static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) )
                {
                    GC.removeRange(&n.v);
                }
                dispose(allocator, n);
            })();
            n = next;
        }
        n = _freelist;
        while( n !is null ) {
            auto next = n._next;
            (() @trusted {
                static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) )
                {
                    GC.removeRange(&n.v);
                }
                dispose(allocator, n);
            })();
            n = next;
        }
        _length = _freelist_len = 0;
        _first = _last = _freelist = null;
    }
    private struct Range(T) {
        private {
            _Node!T *current;
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
    /// return range over list
    Range!T range() {
        return Range!T(_first);
    }
    /// insert item at front
    void insertFront(T v)
    out{ assert(_first !is null && _last !is null);}
    do {
        _Node!T* n = peek_from_freelist();
        n.v = v;
        if ( _first !is null ) {
            n._next = _first;
        }
        _first = n;
        if ( _last is null ) {
            _last = n;
        }
        _length++;
    }
    /// insert item at back
    void insertBack(T v)
    out{ assert(_first !is null && _last !is null);}
    do {
        _Node!T* n = peek_from_freelist();
        n.v = v;
        if ( _last !is null ) {
            _last._next = n;
        } else {
            _first = n;
        }
        _last = n;
        _length++;
    }
    /// remove items by predicate
    bool remove_by_predicate(scope bool delegate(T) @safe @nogc nothrow f) @nogc @trusted nothrow {
        bool removed;
        _Node!T *current = _first;
        _Node!T *prev = null;
        while (current !is null) {
            auto next = current._next;
            if ( !f(current.v) ) {
                prev = current;
                current = next;
                continue;
            }
            // do remove
            _length--;
            removed = true;
            static if ( !is(Allocator == GCAllocator)  && UseGCRanges!T )
            {
                GC.removeRange(current);
            }
            dispose(allocator, current);
            if ( prev is null ) {
                _first = next;                    
            } else {
                prev._next = next;
            }
            if ( next is null ) {
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
    removed = l.remove_by_predicate((n){return n==2;});
    foreach(v; l[]){
        //log("v=%d\n", *v);
    }
    assert(removed);
    assert(l.length()==2);
    //log("---\n");
    removed = l.remove_by_predicate((n){return n==4;});
    foreach(v; l[]){
        //log("v=%d\n", *v);
    }
    assert(removed);
    assert(l.length()==1);
    //log("---\n");
    removed = l.remove_by_predicate((n){return n==3;});
    foreach(v; l[]){
        //log("v=%d\n", *v);
    }
    assert(removed);
    assert(l.length()==0);
    //log("---\n");
    removed = l.remove_by_predicate((n){return n==3;});
    foreach(v; l[]){
        //log("v=%d\n", *v);
    }
    assert(!removed);
    assert(l.length()==0);
    auto l1 = SList!int();
    foreach(i;0..10000) {
        l1.insertBack(i);
    }
    while(l1.length) {
        l1.popFront();
    }
    foreach(i;0..10000) {
        l1.insertFront(i);
    }
    while(l1.length) {
        l1.popFront();
    }
}
@safe unittest
{
    class C
    {
        int c;
        this(int v) {
            c = v;
        }
    }
    SList!C l2;
    foreach(i;0..10000) {
        l2.insertBack(new C(i));
    }
    while(l2.length) {
        l2.popFront();
    }
}

@safe nothrow unittest {
    import std.algorithm.comparison;

    DList!int dlist;
    () @nogc 
    {
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
        dlist.move_to_head(n1);
        assert(dlist.head.payload == 1);
        assert(dlist.tail.payload == 2);
        dlist.clear();
        auto p = dlist.insertBack(1);
        dlist.insertBack(2);
        dlist.insertBack(3);
        dlist.insertFront(0);
        dlist.move_to_tail(p);
        dlist.move_to_tail(p);
        dlist.move_to_head(p);
        dlist.move_to_head(p);
        dlist.remove(p);
    }();
    assert(equal(dlist.range(), [0, 2, 3]));
    dlist.clear();
    class C
    {
        int c;
        this(int v)
        {
            c = v;
        }
    }
    DList!C dlist_c;
    // test freelist ops
    foreach(i;0..1000)
    {
        dlist_c.insertBack(new C(i));
    }
    foreach(i;0..500)
    {
        dlist_c.popFront();
    }
    assert(dlist_c.length() == 500);
    dlist_c.clear();
    dlist_c.popFront();
    dlist_c.popBack();
    assert(dlist_c.length() == 0);
}

private byte useFreePosition(ubyte[] m) @safe @nogc nothrow
{
    import core.bitop: bsf;
    //
    // find free position, mark it as used and return it
    // least significant bit in freeMap[0] means _nodes[0]
    // most significant bit in freeMap[$-1] means nodes[$-1]
    //
    auto l = m.length;
    for(uint i=0; i < l;i++)
    {
        ubyte v = m[i];
        if ( v < 255 )
        {
            auto p = bsf(v ^ 0xff);
            m[i] += 1 << p;
            return cast(byte)((i<<3)+p);
        }
    }
    assert(0);
}
private void markFreePosition(ubyte[] m, size_t position) @safe @nogc nothrow
{
    auto p = position >> 3;
    auto b = position & 0x7;
    m[p] &= (1<<b)^0xff;
}

private bool isFreePosition(ubyte[] m, size_t position) @safe @nogc nothrow
{
    auto p = position >> 3;
    auto b = position & 0x7;
    return (m[p] & (1<<b)) == 0;
}
private ubyte countBusy(ubyte[] m) @safe @nogc nothrow
{
    import core.bitop;
    ubyte s = 0;
    foreach(b; m)
    {
        s+=popcnt(b);
    }
    return s;
}
@safe unittest
{
    import std.experimental.logger;
    globalLogLevel = LogLevel.info;
    import std.algorithm.comparison: equal;
    ubyte[] map = [0,0];
    auto p = useFreePosition(map);
    assert(p == 0, "expected 0, got %s".format(p));
    assert(map[0] == 1);
    assert(!isFreePosition(map, 0));
    assert(isFreePosition(map, 1));

    p = useFreePosition(map);
    assert(p == 1, "expected 1, got %s".format(p));
    map = [255,0];
    p = useFreePosition(map);
    assert(p == 8, "expected 8, got %s".format(p));
    assert(map[1] == 1);
    map = [255,0x01];
    p = useFreePosition(map);
    assert(p == 9, "expected 9, got %s".format(p));
    assert(equal(map, [0xff, 0x03]));
    markFreePosition(map, 8);
    assert(equal(map, [0xff, 0x02]), "got %s".format(map));
    markFreePosition(map, 9);
    assert(equal(map, [0xff, 0x00]), "got %s".format(map));
    markFreePosition(map, 0);
    assert(equal(map, [0xfe, 0x00]), "got %s".format(map));
}

///
/// Unrolled list
///
struct CompressedList(T, Allocator = Mallocator, bool GCRangesAllowed = true)
{
    alias allocator = Allocator.instance;
    alias StoredT = StoredType!T;
    //enum MAGIC = 0x00160162;
    enum PageSize = 512;    // in bytes
    enum NodesPerPage = PageSize/Node.sizeof;
    static assert(NodesPerPage >= 1, "Node is too large to use this List, use DList instead");
    static assert(NodesPerPage <= 255, "Strange, but Node size is too small to use this List, use DList instead");

    enum BitMapLength = NodesPerPage % 8 ? NodesPerPage/8+1 : NodesPerPage/8;

    ///
    /// unrolled list with support only for:
    /// 1. insert/delete front
    /// 2. insert/delete back
    /// 3. keep unstable "pointer" to arbitrary element
    /// 4. remove element by pointer

    struct Page {
        ///
        /// Page is fixed-length array of list Nodes
        /// with batteries
        ///
        //uint                _magic = MAGIC;
        //uint                _epoque;    // increment each time we move to freelist
        ubyte[BitMapLength] _freeMap;
        Page*               _prevPage;
        Page*               _nextPage;
        byte                _firstNode;
        byte                _lastNode;
        ubyte               _count;      // nodes counter
        Node[NodesPerPage]  _nodes;
    }

    struct Node {
        StoredT v;
        byte    p; // prev index
        byte    n; // next index
    }

    struct NodePointer {
        private
        {
            Page*   _page;
            byte    _index;
        }
        this(Page* page, byte index)
        {
            //_epoque = page._epoque;
            _page = page;
            _index = index;
        }
        ///
        /// This is unsafe as you may refer to deleted node.
        /// You are free to wrap it in @trusted code if you know what are you doing.
        ///
        T opUnary(string s)() @system if (s == "*")
        {
            assert(_page !is null);
            //assert(_page._magic == MAGIC, "Pointer resolution to freed or damaged page");
            //assert(_page._epoque == _epoque, "Page were freed");
            assert(!isFreePosition(_page._freeMap, _index), "you tried to access already free list element");
            return _page._nodes[_index].v;
        }
    }

    struct Range {
        private Page* page;
        private byte  index;

        T front() @safe {
            if ( page !is null && index == -1)
            {
                index = page._firstNode;
            }
            return page._nodes[index].v;
        }
        void popFront() @safe {
            if ( page !is null && index == -1)
            {
                index = page._firstNode;
            }
            index = page._nodes[index].n;
            if ( index != -1 )
            {
                return;
            }
            page = page._nextPage;
            if ( page is null )
            {
                return;
            }
            index = page._firstNode;
        }
        bool empty() const @safe {
            return page is null;
        } 
    }
    /// Iterator over items.
    Range range() @safe {
        return Range(_pages_first, -1);
    }
    private
    {
        Page*   _pages_first, _pages_last;
        ulong   _length;

        Page*   _freelist;
        int     _freelist_len;
        enum    _freelist_len_max = 100;
    }
    this(this) {
        auto r = range();
        _pages_first = _pages_last = _freelist = null;
        _length = 0;
        _freelist_len = 0;
        foreach(e; r) {
            insertBack(e);
        }
    }
    private void move_to_freelist(Page* page) @safe @nogc {
        if ( _freelist_len >= _freelist_len_max )
        {
            debug(cachetools) safe_tracef("dispose page");
            () @trusted {
                static if ( UseGCRanges!(Allocator,T, GCRangesAllowed) ) {
                    GC.removeRange(&page._nodes[0]);
                }
                dispose(allocator, page);
            }();
            return;
        }
        debug(cachetools) safe_tracef("put page in freelist");
        //page._epoque++;
        page._nextPage = _freelist;
        _freelist = page;
        _freelist_len++;
    }

    private Page* peek_from_freelist() @safe {
        if ( _freelist is null )
        {
            Page* page = make!Page(allocator);
            static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) ) {
                () @trusted {
                    GC.addRange(&page._nodes[0], Node.sizeof * NodesPerPage);
                }();
            }
            _freelist = page;
            _freelist_len = 1;
        }
        Page* p = _freelist;
        _freelist = p._nextPage;
        _freelist_len--;
        assert(_freelist_len>=0 && _freelist_len < _freelist_len_max);
        p._nextPage = p._prevPage = null;
        p._firstNode = p._lastNode = -1;
        return p;
    }

    ~this() @safe {
        clear();
    }

    /// remove anything from list
    void clear() @safe {
        _length = 0;
        Page* page = _pages_first, next;
        while(page)
        {
            next = page._nextPage;
            () @trusted {
                static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) ) {
                    GC.removeRange(page);
                }
                dispose(allocator, page);
            }();
            page = next;
        }
        page = _freelist;
        while(page)
        {
            next = page._nextPage;
            () @trusted {
                static if ( UseGCRanges!(Allocator, T, GCRangesAllowed) ) {
                    GC.removeRange(page);
                }
                dispose(allocator, page);
            }();
            page = next;
        }
        _length = _freelist_len = 0;
        _pages_first = _pages_last = _freelist = null;
    }

    /// Is list empty?
    bool empty() @safe const {
        return _length == 0;
    }

    /// Items in the list.
    ulong length() @safe const {
        return _length;
    }

    /// remove node (by 'Pointer')
    void remove(ref NodePointer p) @system {
        if ( empty )
        {
            assert(0, "Tried to remove from empty list");
        }
        _length--;
        Page *page = p._page;
        byte index = p._index;
        assert(!isFreePosition(page._freeMap, index), "you tried to remove already free list element");
        with (page)
        {
            assert(_count>0);
            _count--;
            // unlink from list
            auto next = _nodes[index].n;
            auto prev = _nodes[index].p;
            if ( prev >= 0)
            {
                _nodes[prev].n = next;
            }
            else
            {
                _firstNode = next;
            }
            if ( next >= 0)
            {
                _nodes[next].p = prev;
            }
            else
            {
                _lastNode = prev;
            }
            //_nodes[index].n = _nodes[index].p = -1;
            markFreePosition(_freeMap, index);
        }
        if ( page._count == 0 )
        {
            // relase this page
            if ( _pages_first == page )
            {
                assert(page._prevPage is null);
                _pages_first = page._nextPage;
            }
            if ( _pages_last == page )
            {
                assert(page._nextPage is null);
                _pages_last = page._prevPage;
            }
            if ( page._nextPage !is null )
            {
                page._nextPage._prevPage = page._prevPage;
            }
            if ( page._prevPage !is null )
            {
                page._prevPage._nextPage = page._nextPage;
            }
            move_to_freelist(page);
        }
        // at this point page can be disposed
    }

    /// List front item
    T front() @safe {
        if ( empty )
        {
            assert(0, "Tried to access front of empty list");
        }
        Page* p = _pages_first;
        assert( p !is null);
        assert( p._count > 0 );
        with(p)
        {
            return _nodes[_firstNode].v;
        }
    }

    /// Pop front item
    void popFront() @safe {
        if ( empty )
        {
            assert(0, "Tried to popFront from empty list");
        }
        _length--;
        Page* page = _pages_first;
        debug(cachetools) safe_tracef("popfront: page before: %s", *page);
        assert(page !is null);
        with (page) {
            assert(_count>0);
            assert(!isFreePosition(_freeMap, _firstNode));
            auto first = _firstNode;
            auto next = _nodes[first].n;
            markFreePosition(_freeMap, first);
            if ( next >= 0 )
            {
                _nodes[next].p = -1;
            }
            //_nodes[first].n = _nodes[first].p = -1;
            _count--;
            _firstNode = next;
        }
        if ( page._count == 0 )
        {
            // relase this page
            _pages_first = page._nextPage;
            move_to_freelist(page);
            if ( _pages_first is null )
            {
                _pages_last = null;
            }
            else
            {
                _pages_first._prevPage = null;
            }
        }
        debug(cachetools) safe_tracef("popfront: page after: %s", *page);
    }

    /// Insert item at front.
    NodePointer insertFront(T v) {
        _length++;
        Page* page = _pages_first;
        if ( page is null )
        {
            page = peek_from_freelist();
            _pages_first = _pages_last = page;
        }
        if (page._count == NodesPerPage)
        {
            Page* new_page = peek_from_freelist();
            new_page._nextPage = page;
            page._prevPage = new_page;
            _pages_first = new_page;
            page = new_page;
        }
        // there is free space
        auto index = useFreePosition(page._freeMap);
        assert(index < NodesPerPage);
        page._nodes[index].v = v;
        page._nodes[index].p = -1;
        page._nodes[index].n = page._firstNode;
        if (page._count == 0)
        {
            page._firstNode = page._lastNode = cast(ubyte)index;
        }
        else
        {
            assert(page._firstNode >= 0);
            assert(!isFreePosition(page._freeMap, page._firstNode));
            page._nodes[page._firstNode].p = cast(ubyte)index;
            page._firstNode = cast(ubyte)index;
        }
        page._count++;
        assert(page._count == countBusy(page._freeMap));
        debug(cachetools) safe_tracef("page: %s", *page);
        return NodePointer(page, index);
    }

    /// List back item.
    T back() @safe {
        if ( empty )
        {
            assert(0, "Tried to access back of empty list");
        }
        Page* p = _pages_last;
        assert( p !is null);
        assert( p._count > 0 );
        debug(cachetools) safe_tracef("page: %s", *p);
        with(p)
        {
            return _nodes[_lastNode].v;
        }
    }

    /// Pop back item from list.
    void popBack() @safe {
        if ( empty )
        {
            assert(0, "Tried to popBack from empty list");
        }
        _length--;
        Page* page = _pages_last;
        assert(page !is null);
        with (page) {
            assert(_count>0);
            assert(!isFreePosition(_freeMap, _lastNode));
            auto last = _lastNode;
            auto prev = _nodes[last].p;
            markFreePosition(_freeMap, last);
            if ( prev >=0 )
            {
                _nodes[prev].n = -1;
            }
            //_nodes[last].n = _nodes[last].p = -1;
            _count--;
            _lastNode = prev;
        }
        if ( page._count == 0 )
        {
            debug(cachetools) safe_tracef("release page");
            // relase this page
            _pages_last = page._prevPage;
            move_to_freelist(page);
            if ( _pages_last is null )
            {
                _pages_first = null;
            }
            else
            {
                _pages_last._nextPage = null;
            }
        }
    }

    /// Insert item back.
    NodePointer insertBack(T v) {
        _length++;
        Page* page = _pages_last;
        if ( page is null )
        {
            page = peek_from_freelist();
            _pages_first = _pages_last = page;
        }
        if (page._count == NodesPerPage)
        {
            Page* new_page = peek_from_freelist();
            new_page._prevPage = page;
            page._nextPage = new_page;
            _pages_last = new_page;
            page = new_page;
        }
        // there is free space
        auto index = useFreePosition(page._freeMap);
        assert(index < NodesPerPage);
        page._nodes[index].v = v;
        page._nodes[index].n = -1;
        page._nodes[index].p = page._lastNode;
        if (page._count == 0)
        {
            page._firstNode = page._lastNode = cast(ubyte)index;
        }
        else
        {
            assert(page._lastNode >= 0);
            assert(!isFreePosition(page._freeMap, page._lastNode));
            page._nodes[page._lastNode].n = cast(ubyte)index;
            page._lastNode = cast(ubyte)index;
        }
        page._count++;
        assert(page._count == countBusy(page._freeMap));
        debug(cachetools) safe_tracef("page: %s", *page);
        return NodePointer(page, index);
    }
}

///
@safe unittest
{
    import std.experimental.logger;
    import std.algorithm;
    import std.range;

    globalLogLevel = LogLevel.info;
    CompressedList!int list;
    foreach(i;0..66)
    {
        list.insertFront(i);
        assert(list.front == i);
    }
    assert(list.length == 66);
    assert(list.back == 0);
    list.popFront();
    assert(list.length == 65);
    assert(list.front == 64);
    list.popFront();
    assert(list.length == 64);
    assert(list.front == 63);
    while( !list.empty )
    {
        list.popFront();
    }
    foreach(i;1..19)
    {
        list.insertFront(i);
        assert(list.front == i);
    }
    foreach(i;1..19)
    {
        assert(list.back == i);
        assert(list.length == 19-i);
        list.popBack();
    }
    assert(list.empty);
    auto p99 = list.insertBack(99);
    assert(list.front == 99);
    assert(list.back == 99);
    auto p100 = list.insertBack(100);
    assert(list.front == 99);
    assert(list.back == 100);
    auto p98 = list.insertFront(98);
    auto p101 = list.insertBack(101);
    () @trusted // * and remove for poiners is unsafe
    {
        assert(*p98 == 98);
        assert(list.length == 4);
        list.remove(p98);
        assert(list.length == 3);
        assert(list.front == 99);
        list.remove(p100);
        assert(list.length == 2);
        assert(list.front == 99);
        assert(list.back == 101);
        list.remove(p99);
        assert(list.length == 1);
        list.clear();

        foreach(i;0..1000)
        {
            list.insertBack(i);
        }
        assert(equal(list.range(), iota(0,1000)));
        list.clear();

        iota(0, 1000).
            map!(i => list.insertBack(i)).
            array.
            each!(p => list.remove(p));
        assert(list.empty);
        iota(0, 1000).map!(i => list.insertBack(i));
        auto r = list.range();
        while(!r.empty)
        {
            int v = r.front;
            r.popFront();
        }
        assert(list.empty);
    }();

    () @nogc
    {
        struct S {}
        CompressedList!(immutable S) islist;
        immutable S s = S();
        islist.insertFront(s);
    }();
    class C
    {
        int c;
        this(int v) {
            c = v;
        }
    }
    CompressedList!C clist;
    foreach(i;0..5000)
    {
        clist.insertBack(new C(i));
    }
    foreach(i;0..4500)
    {
        clist.popBack();
    }
    assert(clist.length == 500);
    clist.clear();
}

// unittest for unsafe types
unittest {
    import std.variant;
    alias T = Algebraic!(int, string);
    auto v = T(1);
    CompressedList!T cl;
    DList!T dl;
    SList!T sl;
    cl.insertFront(v);
    dl.insertFront(v);
    sl.insertFront(v);
    assert(cl.front == v);
    assert(dl.front.payload == v);
    assert(sl.front == v);
    cl.insertBack(v);
    dl.insertBack(v);
    sl.insertBack(v);
    cl.popFront;
    cl.popBack;
    dl.popFront;
    dl.popBack;
    sl.popFront;
    auto a = cl.insertFront(v);
    cl.remove(a);
    auto b = dl.insertFront(v);
    dl.remove(b);
}

@safe @nogc unittest {
    import std.range, std.algorithm;
    CompressedList!int a, b;
    iota(0,100).each!(e => a.insertBack(e));
    a.popFront();
    b = a;
    assert(equal(a, b));
}