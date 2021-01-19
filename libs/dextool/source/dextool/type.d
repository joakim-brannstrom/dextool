/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dextool.type;

static import my.path;
import my.named_type;

public import dextool.compilation_db : FilterClangFlag;

@safe:

enum ExitStatusType {
    Ok,
    Errors
}

alias DextoolVersion = NamedType!(string, Tag!"DextoolVersion", string.init,
        TagStringable, Lengthable);

alias Path = my.path.Path;
alias AbsolutePath = my.path.AbsolutePath;
