#ifndef FUNCTIONS_BODY_HPP
#define FUNCTIONS_BODY_HPP

void empty() {
}

void single_stack_variable() {
    int x;
}

void call() {
    empty();
}

void if_() {
    if (true) {
    }
}

void if_else(int x) {
    if (x) {
        x = 2;
    } else {
        x = 4;
    }

    if (x) {
        x = 2;
    } else {
        x = 4;
    }
}

void for_() {
    for (int x = 0; x < 10; ++x) {
        empty();
    }
}

#endif // FUNCTIONS_BODY_HPP
