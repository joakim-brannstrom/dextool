/**
Date: 2015-2016, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.app;

version (unittest) {
} else {
    int main(string[] args) {
        import application.app_main : rmain;

        return rmain(args);
    }
}
