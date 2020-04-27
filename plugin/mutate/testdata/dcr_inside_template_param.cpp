#include <cstdint>
#include <type_traits>

using std::size_t;

namespace testing {

struct Test {};

} // namespace testing

template <typename T>
//  Note that SuiteApiResolver inherits from T because
//  SetUpTestSuite()/TearDownTestSuite() could be protected. Ths way
//  SuiteApiResolver can access them.
struct SuiteApiResolver : T {
    // testing::Test is only forward declared at this point. So we make it a
    // dependend class for the compiler to be OK with it.
    using Test = typename std::conditional<sizeof(T) != 0, ::testing::Test, void>::type;
};

// Backport of std::index_sequence.
template <size_t... Is> struct IndexSequence { using type = IndexSequence; };

// Double the IndexSequence, and one if plus_one is true.
template <bool plus_one, typename T, size_t sizeofT> struct DoubleSequence;
template <size_t... I, size_t sizeofT> struct DoubleSequence<true, IndexSequence<I...>, sizeofT> {
    using type = IndexSequence<I..., (sizeofT + I)..., 2 * sizeofT>;
};
template <size_t... I, size_t sizeofT> struct DoubleSequence<false, IndexSequence<I...>, sizeofT> {
    using type = IndexSequence<I..., (sizeofT + I)...>;
};

template <size_t N>
struct MakeIndexSequence
    : DoubleSequence<N % 2 == 1, typename MakeIndexSequence<N / 2>::type, N / 2>::type {};

int main(int argc, char** argv) {
    int x = 2 + argc;
    if (x == 1)
        return 2;
    return 0;
}
