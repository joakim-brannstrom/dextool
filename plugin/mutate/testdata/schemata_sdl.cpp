/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2020
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <string>
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

int a_switch_with_return(Values2 x) {
    // should not be removed because it has return
    switch (x.value()) {
    case 5:
        return 1;
    case 6:
        return 2;
    }
    return 0;
}

int a_switch_with_assign(Values2 x) {
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

void dummy(const char c) {}

void a_switch_with_calls(const char ch) {
    switch (ch) {
    case '\t':
        dummy(ch);
        break;
    case '\n':
    case '\r':
        dummy(ch);
        break;
    default:
        break;
    }
}

enum class MobType { Unknown, Rabbit, RabbitWere, Snake, OrcWeak, OrcStrong, Player };

inline std::string to_string(MobType type) {
    // using namespace std::string_literals;

    switch (type) {
    default:
    case MobType::Unknown:
        return std::string("MobType::Unknown");
    }
    // case MobType::Rabbit:
    //     return "MobType::Rabbit"s;
    // case MobType::RabbitWere:
    //     return "MobType::RabbitWere"s;
    // case MobType::Snake:
    //     return "MobType::Snake"s;
    // case MobType::OrcWeak:
    //     return "MobType::OrcWeak"s;
    // case MobType::OrcStrong:
    //     return "MobType::OrcStrong"s;
    // case MobType::Player:
    //     return "MobType::Player"s;
    // }
}

class MobInfo {};

class Component {};

class Mob : public Component {
public:
    Mob() = default;
    Mob(const MobInfo* info) : info{info} {}
    const MobInfo* info{&sMobInfo};

private:
    static MobInfo sMobInfo;
};

int main(int argc, char** argv) { return 0; }
