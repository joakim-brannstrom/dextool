/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2018
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#ifndef REPORT_NOMUT1_HPP
#define REPORT_NOMUT1_HPP

// no mutation point here so shouldn't be affected
const char* to_be_mutated(int var1_long_text, int var2_long_text); // NOMUT

// should find this one even though it is in a header because there are mutation points here.
void f() { // NOMUT
}

void gun(const char*, const char*, const char*);

class Wun {
public:
    void major(const char*, const char*, const char*);
};

#endif // REPORT_NOMUT1_HPP
