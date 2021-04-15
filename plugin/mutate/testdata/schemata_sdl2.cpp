/// @copyright Boost License 1.0, http://boost.org/LICENSE_1_0.txt
/// @date 2021
/// @author Joakim Brännström (joakim.brannstrom@gmx.com)

#include <cstdint>

typedef enum triangle_type { SCA, ISO, EQU, ERR } triangle_type_t;

typedef struct triangle {
    uint64_t s1;
    uint64_t s2;
    uint64_t s3;
} triangle_t;

triangle_type apa_bar(const triangle_t* t) {
    triangle_type_t ty = ERR;
    uint8_t s = 0;

    if (t->s1 <= 0 || t->s2 <= 0 || t->s3 <= 0) {
        return ERR;
    }

    if (t->s1 == t->s2) {
        s += 1;
    }

    if (t->s1 == t->s3) {
        s += 2;
    }

    if (t->s2 == t->s3) {
        s += 3;
    }

    if (s == 0) {
        if ((t->s1 + t->s2 <= t->s3) || (t->s2 + t->s3 <= t->s1) || (t->s1 + t->s3 <= t->s2)) {
            return ERR;
        } else {
            return SCA;
        }
    } else if (s > 3) {
        return EQU;

    } else if (s == 1 && (t->s1 + t->s2 > t->s3)) {
        return ISO;

    } else if (s == 2 && (t->s1 + t->s3 > t->s2)) {
        return ISO;

    } else if (s == 3 && (t->s2 + t->s3 > t->s1)) {
        return ISO;
    }

    return ERR;
}

int main(int argc, char** argv) { return 0; }
