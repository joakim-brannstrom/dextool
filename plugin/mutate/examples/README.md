This directory contains examples of how to use the mutate plugin.

It assumes that dextool has been installed and is available in the PATH.

# Test Code Snippets

This is an example of how to do mutation testing on small code snippets. It assumes that no dedicated build system or testing framework is used.

The root of the examples are [found here](triangle).

It uses makefiles for the integration with dextool thus to run mutation testing you would do:
```sh
make all
```

# Incremental Mutation Testing

This example demonstrate the incremental mutation testing capabilities of dextool.

Note that the initial test suite has full branch coverage and high MC/DC coverage but even though it do have this there are still a critical bug lurking in the shadows.

The scenario is a developer using mutation testing to improve the test suites effectiveness. At the end it finds the bug in the implementation. Although a bit contrived it do show the impact different mutation operators have on the test suite when trying to verify an implementation.

To run the demo:
```
cd algol_test
./run_demo_0.sh
./run_demo_1.sh
./run_demo_2.sh
./run_demo_3.sh
```

Each step in the demo generate a html report at `html/index.html`.

To see the capability of dextool to detect when test cases are removed and then re-verify those mutants that the test cases killed one can run this sequence:
```sh
./run_demo_0.sh
./run_demo_1.sh
./run_demo_0.sh
```

It is a synthetic emulation of adding and removing a test case.
