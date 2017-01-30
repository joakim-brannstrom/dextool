#ifndef FUNCTIONS_BODY_GLOBALS_HPP
#define FUNCTIONS_BODY_GLOBALS_HPP

int global;

typedef int myInt;

void read_access() {
    int x = global;
}

void assign_access() {
    global = 2;
}

void relate_to_type() {
    myInt x;
}

#endif // FUNCTIONS_BODY_GLOBALS_HPP
