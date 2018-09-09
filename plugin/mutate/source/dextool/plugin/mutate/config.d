/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.config;

import dextool.plugin.mutate.type;

/// Config of the report.
struct ReportConfig {
    ReportKind reportKind;
    ReportLevel reportLevel;
    ReportSection[] reportSection;

    /// Controls how to sort test cases by their kill statistics.
    ReportKillSortOrder tcKillSortOrder;
    int tcKillSortNum = 20;
}
