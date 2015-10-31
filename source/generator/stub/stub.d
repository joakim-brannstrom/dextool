/// Written in the D programming language.
/// Date: 2015, Joakim Brännström
/// License: GPL
/// Author: Joakim Brännström (joakim.brannstrom@gmx.com)
///
/// This program is free software; you can redistribute it and/or modify
/// it under the terms of the GNU General Public License as published by
/// the Free Software Foundation; either version 2 of the License, or
/// (at your option) any later version.
///
/// This program is distributed in the hope that it will be useful,
/// but WITHOUT ANY WARRANTY; without even the implied warranty of
/// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
/// GNU General Public License for more details.
///
/// You should have received a copy of the GNU General Public License
/// along with this program; if not, write to the Free Software
/// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
module generator.stub.stub;

import dsrcgen.cpp;

import generator.stub.types;

CppHdrImpl namespaceTranslator(CppNs nest, ref CppHdrImpl hdr_impl) {
    static CppModule doHeader(CppNs nest, ref CppModule hdr) {
        auto r = hdr.namespace(nest.str);
        r.suppressIndent(1);
        hdr.sep(2);
        return r;
    }

    static CppModule doImpl(CppNs nest, ref CppModule impl) {
        auto r = impl.namespace(nest.str);
        r.suppressIndent(1);
        impl.sep(2);
        return r;
    }

    return CppHdrImpl(doHeader(nest, hdr_impl.hdr), doImpl(nest, hdr_impl.impl));
}
