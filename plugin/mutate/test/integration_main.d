/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/

int main(string[] args) {
    import unit_threaded.runner;
    import std.stdio;

    // dfmt off
    return args.runTests!(
                          "dextool_test.generate_mutant",
                          "dextool_test.mutate_abs",
                          "dextool_test.mutate_aor",
                          "dextool_test.mutate_cor",
                          "dextool_test.mutate_dcr",
                          "dextool_test.mutate_lcr",
                          "dextool_test.mutate_lcrb",
                          "dextool_test.mutate_ror",
                          "dextool_test.mutate_stmt_deletion",
                          "dextool_test.mutate_uoi",
                          "dextool_test.test_admin",
                          "dextool_test.test_analyzer",
                          "dextool_test.test_config",
                          "dextool_test.test_coverage",
                          "dextool_test.test_d2sqlite3_cleanup_bug",
                          "dextool_test.test_mutant_tester",
                          "dextool_test.test_report",
                          "dextool_test.test_schemata",
                          );
    // dfmt on
}
