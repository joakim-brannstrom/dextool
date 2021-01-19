/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.type;

static import my.path;

public import dextool.compilation_db : FilterClangFlag;

@safe:

enum ExitStatusType {
    Ok,
    Errors
}

struct DextoolVersion {
    string payload;
    alias payload this;
}

alias Path = my.path.Path;
alias AbsolutePath = my.path.AbsolutePath;
