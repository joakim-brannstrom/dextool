/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <vector>

// a for each loop
int a_for(int x) {
    std::vector<int> a;
    a.push_back(x);
    int r{0};
    for (auto& e : a) {
        r = e;
    }
    return r;
}

int main(int argc, char** argv) { return 0; }
