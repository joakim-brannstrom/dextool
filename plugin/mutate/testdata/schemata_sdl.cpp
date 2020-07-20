/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <vector>

// a for each loop
int a_for1(int x) {
    std::vector<int> a;
    a.push_back(x);
    int r{0};
    for (auto& e : a) {
        r = e;
    }
    return r;
}

struct Values {
    std::vector<int> x;
    std::vector<int>& values() { return x; }
};

int a_for2(int x) {
    Values a;
    a.values().push_back(x);
    int r{0};
    for (auto& e : a.values()) {
        r = e;
    }
    return r;
}

struct Vec {
    double x, y;
};

Vec a_return_in_lambda(double x) {
    auto dir = [&](double x) -> Vec {
        if (x > 1.0)
            return {-1.0};
        return {0.0};
    };
    return dir(x);
}

int a_while(int x) {
    while (x < 10) {
        x++;
    }
    return x;
}

int a_do(int x) {
    do {
        x++;
    } while (x < 10);
    return x;
}

int main(int argc, char** argv) { return 0; }
