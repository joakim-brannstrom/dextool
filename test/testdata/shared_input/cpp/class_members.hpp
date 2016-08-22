#ifndef CLASS_MEMBERS_HPP
#define CLASS_MEMBERS_HPP

// case 1
class Forward_ptr;
class Forward_ref;
class Forward_decl;

class ToForward {
    Forward_ptr* fwd_ptr;
    Forward_ref& fwd_ref;

    Forward_decl* fwd_decl;
    int x;
};

class Forward_decl {
};

// case 2
class Impl {
};

class Impl_ptr {
};

class Impl_ref {
};

class ToImpl {
    Impl impl;
    Impl_ptr* impl_ptr;
    Impl_ref& impl_ref;
};

// case 3
class ToPrimitive {
    // ignoring primitive type
    int x;
};

// case 4, func ptr
class ToFuncPtr {
    void (*__foo)(void*);
};
#endif // CLASS_MEMBERS_HPP
