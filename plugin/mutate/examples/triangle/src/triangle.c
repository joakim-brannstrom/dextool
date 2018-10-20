#include <assert.h> //assert()
#include <math.h>   //sqrt()
#include <stdlib.h> //malloc()

#include "triangle.h"

triangle_t* triangle_new(uint64_t s1, uint64_t s2, uint64_t s3) {
    triangle_t* t = malloc(sizeof(triangle_t));
    assert(t);

    t->s1 = s1;
    t->s2 = s2;
    t->s3 = s3;

    return t;
}

void triangle_del(triangle_t* t) { free(t); }

double triangle_area(const triangle_t* t) {
    double p = t->s1 + t->s2 + t->s3;
    double k = p / 2;
    return sqrt(k * (k - t->s1) * (k - t->s2) * (k - t->s3));
}

triangle_type_t triangle_type(const triangle_t* t) {
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
