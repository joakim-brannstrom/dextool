/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Utility functions gathered from the D forum. Authors are unknown.
*/
module my.range;

/// use for structs with a present and value member.
alias orElse = (a, b) => a.present ? a.value : b;

/** alias for .then which is useful for range concatenation
 * Example:
---
auto triples=recurrence!"a[n-1]+1"(1.BigInt)
    .then!(z=>iota(1,z+1).then!(x=>iota(x,z+1).map!(y=>(x,y,z))))
    .filter!((x,y,z)=>x^^2+y^^2==z^^2);
triples.each!((x,y,z){ writeln(x," ",y," ",z); });
---
 */
alias then(alias a) = (r) => map!a(r).joiner;
