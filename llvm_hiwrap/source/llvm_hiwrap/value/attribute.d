/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module llvm_hiwrap.value.attribute;

import std.typecons : Nullable;

import llvm_hiwrap.types;
import llvm_hiwrap.value.value;

struct Attribute {
    import llvm;

    LxAttribute lx;
    alias lx this;

    /**
     * Return an unique id given the name of a enum attribute,
     * or 0 if no attribute by that name exists.
     *
     * See http://llvm.org/docs/LangRef.html#parameter-attributes
     * and http://llvm.org/docs/LangRef.html#function-attributes
     * for the list of available attributes.
     *
     * NB: Attribute names and/or id are subject to change without
     * going through the C API deprecation cycle.
     */
    //unsigned LLVMGetEnumAttributeKindForName(const char *Name, size_t SLen);
    //unsigned LLVMGetLastEnumAttributeKind(void);

    /**
     * Create an enum attribute.
     */
    //LLVMAttributeRef LLVMCreateEnumAttribute(LLVMContextRef C, unsigned KindID,
    //                                         uint64_t Val);
    //
    /**
     * Get the unique id corresponding to the enum attribute
     * passed as argument.
     */
    //unsigned LLVMGetEnumAttributeKind(LLVMAttributeRef A);

    /**
     * Get the enum attribute's value. 0 is returned if none exists.
     */
    //uint64_t LLVMGetEnumAttributeValue(LLVMAttributeRef A);

    /**
     * Create a string attribute.
     */
    //LLVMAttributeRef LLVMCreateStringAttribute(LLVMContextRef C,
    //                                           const char *K, unsigned KLength,
    //                                           const char *V, unsigned VLength);
    //
    /**
     * Get the string attribute's kind.
     */
    //const char *LLVMGetStringAttributeKind(LLVMAttributeRef A, unsigned *Length);

    /**
     * Get the string attribute's value.
     */
    //const char *LLVMGetStringAttributeValue(LLVMAttributeRef A, unsigned *Length);

    /**
     * Check for the different types of attributes.
     */
    //LLVMBool LLVMIsEnumAttribute(LLVMAttributeRef A);
    //LLVMBool LLVMIsStringAttribute(LLVMAttributeRef A);
}
