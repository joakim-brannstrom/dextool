/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)
/// Standard range checkers for types types.
#ifndef RANGE_CHECK_HPP
#define RANGE_CHECK_HPP

namespace dextool {

template<typename T0, typename T1>
bool less_than(T0 limit, T1 value) {
    return value < limit;
}

template<typename T0, typename T1>
bool greater_than(T0 limit, T1 value)  {
    return value > limit;
}

template<typename T0, typename T1>
bool equal(T0 limit, T1 value)  {
    return value == limit;
}

template<typename T0, typename T1, typename T2>
bool in_range(T0 lower, T1 upper, T2 value) {
    return value >= lower && value <= upper;
}

} // NS: dextool

#endif // RANGE_CHECK_HPP
