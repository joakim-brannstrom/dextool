/**
Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module cpptooling.analyzer.clang.ast.declaration;

import std.meta : AliasSeq;

import deimos.clang.index : CXCursorKind;

import cpptooling.analyzer.clang.ast.node : Node, generateNodes;

abstract class Declaration : Node {
    import clang.Cursor : Cursor;
    import cpptooling.analyzer.clang.ast.visitor : Visitor;

    Cursor cursor;
    alias cursor this;

    this(Cursor cursor) @safe {
        this.cursor = cursor;
    }

    import cpptooling.analyzer.clang.ast.node : generateNodeAccept;

    mixin(generateNodeAccept!());
}

// dfmt off
alias DeclarationSeq = AliasSeq!(
                                 CXCursorKind.CXCursor_UnexposedDecl,
                                 CXCursorKind.CXCursor_StructDecl,
                                 CXCursorKind.CXCursor_UnionDecl,
                                 CXCursorKind.CXCursor_ClassDecl,
                                 CXCursorKind.CXCursor_EnumDecl,
                                 CXCursorKind.CXCursor_FieldDecl,
                                 CXCursorKind.CXCursor_EnumConstantDecl,
                                 CXCursorKind.CXCursor_FunctionDecl,
                                 CXCursorKind.CXCursor_VarDecl,
                                 CXCursorKind.CXCursor_ParmDecl,
                                 CXCursorKind.CXCursor_ObjCInterfaceDecl,
                                 CXCursorKind.CXCursor_ObjCCategoryDecl,
                                 CXCursorKind.CXCursor_ObjCProtocolDecl,
                                 CXCursorKind.CXCursor_ObjCPropertyDecl,
                                 CXCursorKind.CXCursor_ObjCIvarDecl,
                                 CXCursorKind.CXCursor_ObjCInstanceMethodDecl,
                                 CXCursorKind.CXCursor_ObjCClassMethodDecl,
                                 CXCursorKind.CXCursor_ObjCImplementationDecl,
                                 CXCursorKind.CXCursor_ObjCCategoryImplDecl,
                                 CXCursorKind.CXCursor_TypedefDecl,
                                 CXCursorKind.CXCursor_CXXMethod,
                                 CXCursorKind.CXCursor_Namespace,
                                 CXCursorKind.CXCursor_LinkageSpec,
                                 CXCursorKind.CXCursor_Constructor,
                                 CXCursorKind.CXCursor_Destructor,
                                 CXCursorKind.CXCursor_ConversionFunction,
                                 CXCursorKind.CXCursor_TemplateTypeParameter,
                                 CXCursorKind.CXCursor_NonTypeTemplateParameter,
                                 CXCursorKind.CXCursor_TemplateTemplateParameter,
                                 CXCursorKind.CXCursor_FunctionTemplate,
                                 CXCursorKind.CXCursor_ClassTemplate,
                                 CXCursorKind.CXCursor_ClassTemplatePartialSpecialization,
                                 CXCursorKind.CXCursor_NamespaceAlias,
                                 CXCursorKind.CXCursor_UsingDirective,
                                 CXCursorKind.CXCursor_TypeAliasDecl,
                                 CXCursorKind.CXCursor_ObjCSynthesizeDecl,
                                 CXCursorKind.CXCursor_ObjCDynamicDecl,
                                 CXCursorKind.CXCursor_CXXAccessSpecifier,
                                 );
// dfmt on

mixin(generateNodes!(Declaration, DeclarationSeq));
