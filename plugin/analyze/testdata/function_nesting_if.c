int a(int x) {
    if (x > 0) {
        return 1;
    }
    return 2;
}

int b(int x) {
    if (x > 0)
        if (x > 5) {
            return 1;
        } else {
            return 3;
        }
    return 3;
}
