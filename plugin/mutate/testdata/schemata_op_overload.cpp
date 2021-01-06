/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

class Overload {
public:
    Overload() = default;

    // test that the body of an operator that has a return type other than void
    // is not deleted.
    bool operator==(const Overload& other) const { return true; }

    Overload operator+(const Overload& other) const { return *this; }
};

int main(int argc, char** argv) {
    Overload a, b;

    {
        bool tmp;
        tmp = a == b;
    }

    {
        Overload tmp;
        tmp = a + b;
    }

    return 0;
}
