/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool_test.component_integration;

import dextool_test.utility;

@(testId ~ "shall not crash when a component have a relation to an excluded component")
unittest {
    mixin(EnvSetup(globalTestdir));
    makeDextool(testEnv).addInputArg(testData ~ "cli/included/b.hpp").addInputArg(
            testData ~ "cli/excluded/bug_component_relating_to_excluded_component.hpp")
        .addArg("--file-exclude=.*/cli/excluded/.*").addIncludeFlag(testData ~ "cli").run;
}
