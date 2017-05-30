#include "int_param_nested_if.hpp"

bool g[10];

void func(int v) {
    if (v == 1) {
        g[0] = true;
    }
    if (v < 10 || v > 20) {
        g[1] = true;
    }

    if (v > 128) {
        g[2] = true;
        if (v == 129) {
            g[3] = true;
        }
        if (v > 256 && v < 512) {
            g[4] = true;
            if (v == 300) {
                g[5] = true;
            }
            if (v > 400) {
                g[6] = true;
                if (v > 462) {
                    g[7] = true;
                }
            }
        }
    }
}
