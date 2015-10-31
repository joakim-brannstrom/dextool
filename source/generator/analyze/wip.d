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
module generator.analyze.wip;

import clang.Cursor;
import clang.Visitor : Visitor;

void visitAst(VisitorType)(ref Cursor cursor, ref VisitorType v) {
    static void helperVisitAst(VisitorType)(ref Cursor child, ref Cursor parent, ref VisitorType v) {
        import std.traits;

        static if (__traits(hasMember, VisitorType, "incr")) {
            v.incr();
        }
        bool decend = v.apply(child, parent);

        if (!child.isEmpty && decend) {
            foreach (child_, parent_; Visitor(child)) {
                helperVisitAst(child_, parent_, v);
            }
        }

        static if (__traits(hasMember, VisitorType, "decr")) {
            v.decr();
        }
    }

    Cursor e = Cursor.empty(cursor.translationUnit);
    helperVisitAst(cursor, e, v);
}
