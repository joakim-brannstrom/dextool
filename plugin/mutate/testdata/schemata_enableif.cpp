/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#if (__cplusplus >= 201402L)

#include <type_traits>
#include <vector>

template <typename T1, typename T2,
          typename std::enable_if<!std::is_integral<T1>::value ||
                                  !std::is_pointer<T2>::value>::type* = nullptr>
void foo(const T1& lhs, const T2& rhs) {}

typedef int IsContainer;
template <class C, class Iterator = decltype(::std::declval<const C&>().begin()),
          class = decltype(::std::declval<const C&>().end()),
          class = decltype(++::std::declval<Iterator&>()),
          class = decltype(*::std::declval<Iterator>()), class = typename C::const_iterator>
IsContainer IsContainerTest(int /* dummy */) {
    return 0;
}

typedef char IsNotContainer;
template <class C> IsNotContainer IsContainerTest(long /* dummy */) { return '\0'; }

template <typename C, bool = sizeof(IsContainerTest<C>(0)) == sizeof(IsContainer)>
struct IsRecursiveContainerImpl;

template <typename C> struct IsRecursiveContainerImpl<C, false> : public std::false_type {};

template <typename C> struct IsRecursiveContainerImpl<C, true> {
    using value_type = decltype(*std::declval<typename C::const_iterator>());
    using type = std::is_same<
        typename std::remove_const<typename std::remove_reference<value_type>::type>::type, C>;
};

template <typename C> struct IsRecursiveContainer : public IsRecursiveContainerImpl<C>::type {};

struct ContainerPrinter {
    template <typename T, typename = typename std::enable_if<(sizeof(IsContainerTest<T>(0)) ==
                                                              sizeof(IsContainer)) &&
                                                             !IsRecursiveContainer<T>::value>::type>
    void foo() {}
};

enum class type { none_type, custom_type };

template <typename Char, typename OutputIt, typename T>
auto write2(OutputIt out, const T& value) ->
    typename std::enable_if<std::vector<Char>::value == type::custom_type, OutputIt>::type {
    return 42;
}

#endif

int main(int argc, char** argv) {
    int x;
    x = argc + 1;
    x = x + argc + 1;
    x = x + argc + 1;
    x = x + argc + 1;

    return 0;
}
