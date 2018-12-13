/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2017
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

double f1Global;

void f1() { f1Global = 2.2; }

void f2(double& z) { z = 1.2; }

int f2(double w) { return static_cast<int>(w); }

bool bool_f(double w) {
    if (w > 1.0)
        return true;
    return false;
}

class Dummy {
    float method1;
    float method2;
    void delMe() { method1 = 2.2; }
    float notMe() { return method2 + 1.2; }
};

Dummy dummy_f(double w) {
    try {
        if (w > 1)
            return Dummy();
    } catch (Dummy x) {
        f2(2.1);
        return Dummy();
    }
}
