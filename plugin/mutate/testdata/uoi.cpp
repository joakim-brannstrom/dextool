/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class OpOverload {
public:
    OpOverload();

    // UAR
    OpOverload operator++();
    OpOverload operator++(int);
    OpOverload operator--();
    OpOverload operator--(int);
};

void unary_arithmetic_operators() {
    int a;

    a++;
    ++a;
    a--;
    --a;

    OpOverload oa;
    oa++;
    ++oa;
    oa--;
    --oa;
}

void g(int x) {
}

void func() {
    int a;
    int b;

    int c = a + b;
    int d = a + 3;

    if (a > b) {
        return;
    }

    g(a);
}

void case_2() {
    int case_2_a = 1 + 5;
    case_2_a += 3;

    int case_2_b0;
    int case_2_b1 = case_2_b0 + 3;
}
