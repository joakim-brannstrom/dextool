// Written in the D programming language.
/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module cpptooling.utility.nullvoid;

/// Based on phobos Nullable but always initialize the value to void.
///TODO further research if it is possible to do this with Nullable.
struct NullableVoid(T) {
    private bool _isNull = true;
    private T _value = void;

    /// Stored value is initialized to value.
    this(inout T value) inout {
        _value = value;
        _isNull = false;
    }

    /** Check if `this` is in the null state.
     * Returns: true $(B iff) `this` is in the null state, otherwise false.
     */
    @property bool isNull() const @safe pure nothrow {
        return _isNull;
    }

    /** Assigns $(D value) to the internally-held state. If the assignment
     * succeeds, $(D this) becomes non-null.
     *
     * Params:
     *  value = A value of type `T` to assign to this `Nullable`.
     */
    void opAssign()(T value) {
        import std.conv : emplace;

        emplace!T(&_value, value);
        _isNull = false;
    }

    /** Gets the value. $(D this) must not be in the null state.
     * This function is also called for the implicit conversion to $(D T).
     *
     * Returns: The value held internally by this `Nullable`.
     */
    @property ref inout(T) get() inout @safe pure nothrow {
        enum message = "Called `get' on null Nullable!" ~ T.stringof ~ ".";
        assert(!isNull, message);
        return _value;
    }
}
