#include <iostream>

#include "intercept.hpp"

int intercepted() {
    return custom_prefix_intercepted() + 1;
}

int main(int argc, char** argv) {
    return intercepted() == 667 && normal() == 42 ? 0 : 1;
}
