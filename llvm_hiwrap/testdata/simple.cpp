int func(int);

int myFun(int x) {
    int y;
    if (func(x) == 2) {
        y = 1;
    } else {
        y = 7;
    }

    return y;
}
