/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.report.html.js;

immutable jsSimilarity = import("similarity_graph.js");

immutable jsTableOnClick = import("table_on_click.js");

immutable js_index = import("index.js");

immutable js_source = import("source.js");

immutable jsScoreHistory = import("score_history.js");

immutable jsTreeMap = import("treemap.js");

immutable jsD3Mini = import("d3.min.js");
