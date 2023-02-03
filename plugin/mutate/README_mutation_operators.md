## Mutation Operators

This is the mutation operators that dextool support with a description of how
the operator mutate the codebase.

### Relational Operator Replacement (ROR)

Dextool implement the ROR operator as descripted in the paper "Improving
Logic-Based Testing" (Journal of Systems and Software 2012 by Kaminski, Gary,
Paul Ammann, and Jeff Offutt).

"Improving Logic-Base Testing" showed that out of the seven possible mutations
only three are required to be generated to guarantee detection of the remaining
four.

Mutation subsuming:

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 |
|---------------------|----------|----------|----------|
| `x < y`             | `x <= y` | `x != y` | `false`  |
| `x > y`             | `x >= y` | `x != y` | `false`  |
| `x <= y`            | `x < y`  | `x == y` | `true`   |
| `x >= y`            | `x > y`  | `x == y` | `true`   |
| `x == y`            | `x <= y` | `x >= y` | `false`  |
| `x != y`            | `x < y`  | `x > y`  | `true`   |

#### ROR for Booleans

Mutations such as `<` for a boolean type is nonsensical in C++ or in C when the
type is `_Bool`.

This schema is only applicable when the type of the expressions on both sides
of an operator are of boolean type.

| Original Expression | Mutant 1 | Mutant 2 |
| ------------------- | -------- | -------- |
| `x == y`            | `x != y` |  `false` |
| `x != y`            | `x == y` |  `true`  |

#### ROR for Floating Points

The purpuse of the special casing of floating points are to reduce the number
of undesired/junk mutants.

Strict equal is not recommended to ever use for floating point numbers. Because
of this the test suite is probably not designed to catch these type of
mutations which lead to *undesired* mutants. They are *techincally* not
equivalent but they aren't supposed to be caught because the SUT is never
supposed to do these type of operations.

This schema is only applicable when the type of the expressions on both sides
of an operator are of floating point type.

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 |
| ------------------- | -------- | -------- | ---------- |
| `x < y`             | `x > y`  |          | `false`    |
| `x > y`             | `x < y`  |          | `false`    |
| `x <= y`            | `x > y`  |          | `true`     |
| `x >= y`            | `x < y`  |          | `true`     |
| `x == y`            | `x <= y` | `x >= y` | `false`    |
| `x != y`            | `x < y`  | `x > y`  | `true`     |

*Note*: that `==` and `!=` isn't changed compared to the original mutation
schema because normally they shouldn't be used for a floating point value but
if they are, and it is a valid use, the original schema should work.

#### ROR for Enumerations

The schema try to avoid generating mutants that isn't possible to kill in C/C++
without using undefined behavior. We do not want users to write that type of
test cases. The mutants that are problematic is those that are on the boundary
of the enumerations range. Normally an enum can't be *outside* the boundaries
of an enum thus the test suite can't possibly kill such a mutants that would
require an enum outside the boundaries.

This schema is only applicable when the type of the expressions on both sides
of an operator are enums and the same enum type.

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 |
| ------------------- | -------- | -------- | -------- |
| `x < y`             | `x <= y` | `x != y` | `false`  |
| `x > y`             | `x >= y` | `x != y` | `false`  |
| `x <= y`            | `x < y`  | `x == y` | `true`   |
| `x >= y`            | `x > y`  | `x == y` | `true`   |
| `x == y`            | `false`  |          |          |
| `x != y`            | `true`   |          |          |

Additional schema for equal and not equal when the range of lhs and rhs is
known:

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 | Condition                    |
| ------------------- | -------- | -------- | -------- | ---------------------------- |
| `x == y`            | `x <= y` | `x >= y` | `false`  |                              |
| `x != y`            | `x < y`  | `x > y`  | `true`   |                              |
| `x == y`            |          | `true`   | `false`  | if x is the min enum literal |
| `x == y`            |          | `true`   | `false`  | if x is the max enum literal |
| `x == y`            |          | `true`   | `false`  | if y is the min enum literal |
| `x == y`            |          | `true`   | `false`  | if y is the max enum literal |
| `x != y`            |          | `false`  | `true`   | if x is the min enum literal |
| `x != y`            |          | `false`  | `true`   | if x is the max enum literal |
| `x != y`            |          | `false`  | `true`   | if y is the min enum literal |
| `x != y`            |          | `false`  | `true`   | if y is the max enum literal |

Lets explain why the third line is true. Because `x` is on the boundary of `y`
it means that the only valid mutants are `>=` and `false` if we consider the
RORG schema. `>=` would in this case always be `true`. Thus it follows that the
mutants for the third line should be `true` and `false`.

#### ROR for Pointers

The goal is to reduce the number of undesired mutants when the user of the
plugin has knowledge about the internal design of the program.

This schema can't fully replace parts of ROR because there are programs that
make use of the memory address order that is guaranteed by the language. But
from empirical data it is deemed to be a special case thus the operator is
tuned for the normal use.

This schema is only applicable when type of the expressions either sides is a
pointer type.

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 |
| ------------------- | -------- | -------- | -------- |
| `x < y`             | `x <= y` | `x != y` | `false`  |
| `x > y`             | `x >= y` | `x != y` | `false`  |
| `x <= y`            | `x < y`  | `x == y` | `true`   |
| `x >= y`            | `x > y`  | `x == y` | `true`   |
| `x == y`            | `x != y` | `false`  |
| `x != y`            | `x == y` | `true`   |

### Arithmetic Operator Replacement (AOR)

Replace a single arithmetic operator with another operand.

| Original | 1       | 2       | 3       | 4       |
|----------|---------|---------|---------|---------|
| `x + y`  | `x - y` | `x * y` | `x / y` | `x % y` |
| `x - y`  | `x + y` | `x * y` | `x / y` | `x % y` |
| `x * y`  | `x - y` | `x + y` | `x / y` | `x % y` |
| `x / y`  | `x - y` | `x * y` | `x + y` | `x % y` |
| `x % y`  | `x - y` | `x * y` | `x / y` | `x + y` |

### Arithmetic Operator Replacement Simple (AORS)

AOR generated a large number of mutants. For a codebase which isn't math heavy
this may be highly redundant. It is enough to generate those that are the
counter part. It also seems from empirical use that if the counter part survive
then the other mutants also survive. Thus the AORS schema is recommended for
normal use and AOR for math heavy code bases.

| Original | 1       |
|----------|---------|
| `x + y`  | `x - y` |
| `x - y`  | `x + y` |
| `x * y`  | `x / y` |
| `x / y`  | `x * y` |

### Logical Connector Replacement (LCR)

The operator mutate the logical operators `||` and `&&` by replacing them with
their counter part.

| Original | 1        | 2        | 3        | 4   | 5   |
|----------|----------|----------|----------|-----|-----|
| `x && y` | `x || y` | `true`   | `false`  | `x` | `y` |
| `x || y` | `x && y` | `true`   | `false`  | `x` | `y` |

A note for the eagle eye is that the schema is extended compared to the
academical literature. This where done based on a study by Google 2018 ["An Industrial Application of Mutation Testing: Lessons, Challenges and Research Directions" published in ICST 2018 by Goran Petrovic, Marko Ivankovic, Bob Kurtz, Paul Ammann, Rene Just](https://people.cs.umass.edu/~rjust/publ/industrial_mutation_icst_2018.pdf)

### Logical Connector Replacement Bit-wise (LCRB)

The operator mutate the bitwise operators `|` and `&`.

These two bitwise operators correlate well with the LCR operator. Coverage
tools for MC/DC have a general problem with bitwise operators. The MC/DC
criteria together with RTCA-178C requires that all logical expressions are
covered but a common pattern for embedded systems is to use bitwise operators
to merge the result from multiple sources to then evaluate the merge only once.
A correct MC/DC tool would require that each bit is tested but most tools fail
to do so. The following example code should for a correctly implemented MC/DC
tool result in the same coverage:

```c++
bool x = a || b || c;
if (x) {...}
```

Sneaky code:
```c++
unsigned x = a | b | c;
if (x) {...}
```

| Original | 1       | 2   | 3   |
|----------|---------|-----|-----|
| `x & y`  | `x | y` | `x` | `y` |
| `x | y`  | `x & y` | `x` | `y` |

### Unary Operator Insertion (UOI)

The operator is not fully implemented as it is described in academical
literature. After practical use it was found that UOI produces a large number
of unproductive mutants. This lead to the redesign of how it mutates. Instead
of mutating everything it where changed to only generated those mutants that
are highly likely to be productive. Less "false positives".

| Original | 1   |
|----------|-----|
| `!x`     | `x` |

### Decision/Condition Requirement (DCR)

The operator mutate decision/conditions by fully replacing them with `true` or
`false`.The simplest way to demonstrate the operator is via a code snippet.

Original:
```c++
if (x || y) {..}
```

Mutants:
```c++
if (false) {..}
if (true) {..}
if (true || y) {..}
if (false || y) {..}
if (x || true) {..}
if (x || false) {..}
```

#### DCR for Boolean Function

The intention of DCR is to test that the test suite verify logical expressions.
It is assumed that a function that returns bool is used in logical expressions
in *some* way. This use should be verified by the test suite.

Original:
```c++
bool fun(int x);
bool wun(int x) { return fun(x); }
```

Mutants:
```c++
bool wun(int x) { return true; }
bool wun(int x) { return false; }
```

### Statement Deletion (SDL)

The main purpose of this mutation operator is to find unused code. By
selectively deleting code that turns out to not affecting the test cases it is
found and can be removed. Because if it was crucial, the code that where
removed by SDL, it should have affected the behavior of the program in such a
way that at least one test case failed.

The operator somewhat diverge from the academical literature because it deletes
blocks of code compared to individual lines. It where found by practical use
that deleting individual lines resulted in a very large number of mutants and a
large number of them where killed by the compiler (syntax errors).

The operator groups code by their scope. Lets demonstrate by an example:

Original:
```c++
void fun(int x) { int y; y=x+1; if (y>3) {y=-2} }
```

Mutants
```c++
void fun(int x) {}
void fun(int x) { int y; y=x+1; if (y>3) {} }
void fun(int x) { int y; if (y>3) {y=-2} }
```

### Constant Replacement (CR)

The operator replace literal values with other constants such as zero. The main
purpose is to see that the constants and how they are used are tested.

| Original Expression | Mutant 1 |
| ------------------- | -------- |
| `<literal>`         | `0`      |
