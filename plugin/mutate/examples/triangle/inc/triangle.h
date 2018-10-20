#ifndef TRIANGLE_H
#define TRIANGLE_H

#include <stdint.h>

typedef enum triangle_type { SCA, ISO, EQU, ERR } triangle_type_t;

typedef struct triangle {
    uint64_t s1;
    uint64_t s2;
    uint64_t s3;
} triangle_t;

triangle_t* triangle_new(uint64_t s1, uint64_t s2, uint64_t s3);
void triangle_del(triangle_t* t);
double triangle_area(const triangle_t* t);
triangle_type_t triangle_type(const triangle_t* t);

#endif // TRIANGLE_H
