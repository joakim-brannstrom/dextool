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

struct Values2 {
    int x;
    int value() { return x; }
};

int a_switch(Values2 x) {
    // should not be removed because it has return
    switch (x.value()) {
    case 5:
        return 1;
    case 6:
        return 2;
    }

    int rval;
    switch (x.value()) {
    case 0:
        rval = 1;
        rval = 3;
        break;
    case 1:
        rval = 1;
        rval = 3;
        break;
    default:
        rval = 2;
        rval = 5;
        break;
    }
    return rval;
}

int a_binary_unary_inside_if(int x) {
    int y = x;
    if (x == 2) {
        y++;
    }
    if (x == 3) {
        y = 2;
    }
    if (x == 4) {
        y += 5;
    }
    return y;
}

int main(int argc, char** argv) { return 0; }
