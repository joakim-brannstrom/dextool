/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This file contains helpers for creating types.
The general pattern used are builders that can be composed.
*/
module cpptooling.data.type_builder;

import cpptooling.data.kind;
import cpptooling.data.kind_type;

//TODO remove, this is not good. keep it focused on SimleInfo.
TypeKindAttr makeSimple(string txt, TypeAttr attr = TypeAttr.init) pure @safe nothrow {
    import cpptooling.data : SimpleFmt, TypeId;

    TypeKind t;
    t.info = TypeKind.SimpleInfo(SimpleFmt(TypeId(txt)));

    return TypeKindAttr(t, attr);
}
