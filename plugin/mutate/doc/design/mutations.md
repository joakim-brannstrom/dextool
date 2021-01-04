# Mutations {id="req-mutations"}

This chapter describe the supported mutants, the requirements and how those
requirements are verified.

There are a multitude of mutants described in the academical literature (100+).
It isn't feasible to support all of them and there are neither a consensus of
which ones are *best* for a specific language and code base. But to allow a
predetermined *stop* in the development of the plugin a specific few have been
chosen as recommended by the following papers and quotes.

Quote from [@mutationSurvey, p. 6] :

    Offutt et al. [182] extended their 6-selective mutation further using a
    similar selection strategy. Based on the type of the Mothra mutation
    operators, they divided them into three categories: statements, operands
    and expressions. They tried to omit operators from each class in turn. They
    discovered that 5 operators from the operands and expressions class became
    the key operators.  These 5 operators are ABS, UOI, LCR, AOR and ROR. These
    key operators achieved 99.5% mutation score.

Quote from [@detSufficientMutOperators, p. 18] :

    The 5 sufficient operators are ABS, which forces each arithmetic expression
    to take on the value 0, a positive value and a negative value, AOR, which
    replaces each arithmetic operator with every syntactically legal operator,
    LCR, which replaces each logical connector (AND and OR) with several kinds
    of logical connectors, ROR, which replaces relational operators with other
    relational operators, and UOI, which insert unary operators in front of
    expressions. It is interesting to note that this set includes the operators
    that are required to satisfy branch and extended branch coverage leading us
    to believe that extended branch coverage is in some sense a major part of
    mutation.

The plugin focus on generating as good as possible mutants from these mutation
operators by using type information from the language to reduce unproductive and
equivalent mutants as much as possible.

## Requirements

The plugin shall support **at least** the mutations ROR, AOR, LCR, UOI and ABS.

## Relational Operator Replacement (ROR) {id="design-mutation_ror"}

[partof](#req-mutations)

Replace a single operand with another operand.

The operands are: `<,<=,>,>=,==,!=,true,false`

The implementation should use what is in literature called RORG (Relational
Operator Replacement Global) because it results in fewer mutations and less
amplification of infeasible mutants.

### Requirements

The plugin shall mutate the relational operators according to the RORG schema.

The plugin shall use the *floating point RORG schema* when the type of the
expressions on both sides of the operator are floating point types.

**Note**: See [ROR for Floating Point](#design-mutation_ror_float).

The plugin shall use the *enum RORG schema* when the type of the expressions on
both sides of the operator are enums and of the same enum type.

**Note**: See [ROR for Enumeration](#design-mutation_ror_enum).

The plugin shall use the *pointer RORG schema* when the type of the expressions
on either sides of the operator are pointer types and the mutation type is
RORP.

**Note**: See [ROR for Pointers](#design-mutation_ror_ptr).

The plugin shall use the *bool RORG schema* when the type of the expressions on
both sides of the operator are boolean types.

**Note**: See [ROR for Booleans](#design-mutation_ror_bool).

### RORG

In [@improvingLogicBasedTesting] showed that out of the seven possible
mutations only three are required to be generated to guarantee detection of the
remaining four.

Mutation subsuming table from [@thesis1]:

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 |
|---------------------|----------|----------|----------|
| `x < y`             | `x <= y` | `x != y` | `false`  |
| `x > y`             | `x >= y` | `x != y` | `false`  |
| `x <= y`            | `x < y`  | `x == y` | `true`   |
| `x >= y`            | `x > y`  | `x == y` | `true`   |
| `x == y`            | `x <= y` | `x >= y` | `false`  |
| `x != y`            | `x < y`  | `x > y`  | `true`   |

### ROR for Booleans {id="design-mutation_ror_bool"}

[partof](#design-mutation_ror)

Mutations such as `<` for a boolean type is nonsensical in C++ or in C when the
type is `_Bool`.

This schema is only applicable when the type of the expressions on both sides
of an operator are of boolean type.

| Original Expression | Mutant 1 | Mutant 2 |
| ------------------- | -------- | -------- |
| `x == y`            | `x != y` |  `false` |
| `x != y`            | `x == y` |  `true`  |

### ROR for Floating Points {id="design-mutation_ror_float"}

[partof](#design-mutation_ror)

The goal is to reduce the number of *undesired* mutants.

Strict equal is not recommended to ever use for floating point numbers. Because
of this the test suite is probably not designed to catch these type of
mutations which lead to *undesired* mutants. They are *techincally* not
equivalent but they aren't supposed to be cought because the SUT is never
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


TODO investigate Mutant 3. What should it be?

TODO empirical evidence needed to demonstrate how much the undesired mutations
are reduced.

### ROR for Enumerations {id="design-mutation_ror_enum"}

[partof](#design-mutation_ror)

The schema try to avoid generating mutants that isn't possible to kill in C/C++
without using undefined behavior. We do not want users to write that type of
test cases. The mutants that are problematic is those that are on the boundary
of the enumerations range. Normally an enum can't be *outside* the boundaries
of an enum thus the test suite can't possibly kill such a mutants that would
require an enum outside the boundaries.


This schema is only applicable when type of the expressions on both sides of an
operator are enums and the same enum type.

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

### ROR for Pointers {id="design-mutation_ror_ptr"}

[partof](#design-mutation_ror)

The goal is to reduce the number of undesired mutants when the user of the
plugin has knowledge about the internal design of the program.

Design knowledge: Do the program use such C++ constructs that guarantee memory
address order and use this guarantees?

This schema can't fully replace parts of ROR because there are programs that
make use of the memory address order that is guaranteed by the language. It is
thus left to the user to choose the correct schema.

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

## Arithmetic Operator Replacement (AOR) {id="design-mutation_aor"}

[partof](#req-mutations)

Replace a single arithmetic operator with another operand.

| Original | 1   | 2   | 3       | 4       | 5       | 6       |
|----------|-----|-----|---------|---------|---------|---------|
| `x + y`  | `x` | `y` | `x - y` | `x * y` | `x / y` | `x % y` |
| `x - y`  | `x` | `y` | `x + y` | `x * y` | `x / y` | `x % y` |
| `x * y`  | `x` | `y` | `x - y` | `x + y` | `x / y` | `x % y` |
| `x / y`  | `x` | `y` | `x - y` | `x * y` | `x + y` | `x % y` |
| `x % y`  | `x` | `y` | `x - y` | `x * y` | `x / y` | `x + y` |

Column 1-2 where added after studying [@googleStateOfMutationTesting2018] p.4.

## Logical Connector Replacement (LCR) {id="design-mutation_lcr"}

[partof](#req-mutations)

The plugin shall mutate the logical operators `||` and `&&`.

The plugin shall mutate the bitwise operators `|` and `&`.

Replace a logical operand with the inverse.

| Original | 1        | 2        | 3        | 4   | 5   |
|----------|----------|----------|----------|-----|-----|
| `x && y` | `x || y` | `true`   | `false`  | `x` | `y` |
| `x || y` | `x && y` | `true`   | `false`  | `x` | `y` |

Also see the table for [LCRb](#design-mutation_lcrb).

### Note

Column 2-5 where added after studying [@googleStateOfMutationTesting2018] p.4.

The plugin shall mutate the bitwise operators `|` and `&`.

## Logical Connector Replacement Bit-wise (LCRB) {id="design-mutation_lcrb"}

[partof](#req-mutations)

The plugin shall mutate the bitwise operators `|` and `&`.

These two bitwise operators correlate well with the LCR operator. Coverage
tools have a general problem with bitwise operators. This mutation operator can
replace the manual coverage inspection activity when bitwise operators are
used.

| Original Expression | Mutant 1 |
| ------------------- | -------- |
| `x | y`             | `x & y`  |
| `x & y`             | `x | y`  |

| Original | 1       | 2   | 3   |
|----------|---------|-----|-----|
| `x & y`  | `x | y` | `x` | `y` |
| `x | y`  | `x & y` | `x` | `y` |

### Note

Column 2-3 where added after studying [@googleStateOfMutationTesting2018] p.4
and concluding that if LCR is updated then LCRb should also be updated.

## Unary Operator Insertion (UOI) {id="design-mutation_uoi"}

[partof](#req-mutations)

The plugins shall mutate `!` in unary expressions by removing it.

## Note

The operator do not fully implement the academical definition of UOI. After
practical use it was found that UOI produces a large number of unproductive
mutants. This lead to the redesign of how it mutates. Instead of mutating
everything it can it now only generate mutants that is highly likely to be
productive. Less "false positives".

Insert a single unary operator in expressions where it is possible.

The operands are:

 * Increment: ++x, x++
 * Decrement: --x, x--
 * Address: &x
 * Indirection: *x
 * Positive: +x
 * Negative: -x
 * Ones' complement: ~x
 * Logical negation: !x
 * Sizeof: sizeof x, sizeof(type-name)

The cast operator is ignored because it is *probably* not possible to create
any useful mutant with it.
 * Cast: (type-name) cast-expression

Note: The address, indirection and complement operator need to be evaluated to
see how efficient those mutants are.
Are most mutants killed? Compilation errors?

## Absolute Value Insertion (ABS) {id="design-mutation_abs"}

[partof](#req-mutations)

Replace a numerical expression with the absolute value.

Example:
```cpp
// original
a = b + c
// the absolute value
a = abs(b + c)
// the negative absolute value
a = -abs(b + c)
// a bomb that go of if the expression is evaluated to zero
a = fail_on_zero(b + c)
```

## Undesired Mutant

Based on empirical observations integer literals are not mutated because they usually result in equivalent mutants.
Further studies on this subject is needed.

> The mutation abs(0) and abs(0.0) is undesired because it has no semantic effect.
> Note though that abs(-0.0) is a separate case.

## Conditional Operator Replacement (COR) {id="design-mutation_cor"}

[partof](#req-mutations)

This mutation subsumes LCR and all negation mutations generated by UOI.

See [@conf:1, p. 2].
> Generally, valid mutations for a conditional expression such as a <op> b,
> where <op> denotes one of the logical connectors, include the following:
>  * a&&b : Apply the logical connector AND
>  * a||b : Apply the logical connector OR
>  * a==b : Apply the relational operator a==b
>  * a!=b : Apply the relational operator a!=b
>  * lhs : Return the value of the left hand side operand
>  * rhs : Return the value of the right hand side operand
>  * true : Always evaluate to the boolean value true
>  * false : Always evaluate to the boolean value false

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 | Mutant 4 |
| ------------------- | -------- | -------- | -------- | -------- |
| `a && b`            | `false`  | `a`      | `b`      | `a == b` |
| `a OR b`            | `true`   | `a`      | `b`      | `a != b` |

TODO: OR should be `||` but it doesn't render corrently on github.

### Note

This mutant is inactivated in the tool because it has turned out to generate
too much junk.

## Decision/Condition Requirement (DCR) {id="design-mutation_dcr"}

[partof](#req-mutations)

The DCR mutation operator is modelled after the DCC in [@thesis1]. [@thesis1]
argues that a test suite that achieve MC/DC should kill 100% of these mutants.
As discussed in [@thesis1] a specialized mutation for DC/C results in:
 * less mutations overall
 * less equivalent mutations
 * makes it easier for the human to interpret the results

The intention is to be at least equivalent to a coverage tools report for
decision/condition coverage.

[@thesis1] name this mutation operator as DCC.

The difference between DCC and DCR is that the *bomb* for case statements is
replaced by statement deletion in DCR. The intention is to require the test
suite to *prove* that it verifies the behavior and not just visit the branch.

### Decision Coverage

The DC criteria requires that all branches in a program are executed.

As discussed in [@thesis1, p. 19] the DC criteria is simulated by replacing
predicates with `true` or `false`.  For switch statements this isn't possible
to do. In those cases a bomb is inserted.

### Condition Coverage

The CC criteria requires that all conditions clauses are executed with true/false.

As discussed in [@thesis1, p. 20] the CC criteria is simulated by replacing
clauses with `true` or `false`.  See [@subsumeCondMutTesting] for further
discussions.

### Case Deletion

This is only needed for switch statements.
It *deactivates* the functionality in the case branch in a switch statement.

It is **more** equivalent to the DCC mutation for predicates (decision) that is
set to *false* than using a bomb for the branch because deleting the
functionality requires the test suite to *test* the side effect to be able to
kill the mutant.  It isn't enough to *visit* the branch which is the case for a
bomb.

Motivation why it is equivalent.

Consider the following switch statement:
```cpp
switch (x) {
case A: y = 1; break;
case B: y = 2; break;
default: y = 3; break;
}
```

It can be rewritten as:
```cpp
if (x == A) { y = 1; }
else if (x == B) { y = 2; }
else { y = 3; }
```

A decision mutation of the first branch is equivalent to replacement of `x == A` with `true`/`false`.
```cpp
if (false) { y = 1; }
else if (x == B) { y = 2; }
else { y = 3; }
```

Note that when it is set to `false` it is equivalent to *never* being taken.
It is thus equivalent to the rewrite:
```cpp
if (x == B) { y = 2; }
else { y = 3; }
```

The branch is deleted.

Thus `false` is equivalent to statement deletion of the branch content.

### DCR for Bool Function {id="design-mutation_dcr-bool_func"}

[partof](#design-mutation_dcr)

The intention of DCR is to test that the test suite verify logical expressions.
It is assumed that a function that returns bool is used in logical expressions
in *some* way.  This use should be verified by the test suite.

## Statement Deletion (SDL) {id="design-mutation_sdl"}

[partof](#req-mutations)

The main purpose of this mutation operator is to find unused code. By
selectively deleting code that turns out to not affecting the test cases it is
found and can be removed. Because if it was crucial, the code that where
removed by SDL, it should have affected the behavior of the program in such a
way that at least one test case failed.

The plugin shall remove statements either individually or as a group.

### SDL for Function and Method Calls {id="design-mutation_sdl-calls"}

[partof](#design-mutation_sdl)

The plugin shall remove the specific function call.

**Note**: How it is removed depend on where it is in the AST.
A function call that is terminated with a `;` should remove the trailing `;`.
In contrast with the initialization list where it should remove the trailing `,`.

### SDL for Void Function Body {id="design-mutation_sdl-void_func"}

[partof](#design-mutation_sdl)

This is useful to force a test case to demonstrate that a function has
observable and testable side effects. It is a *high probability* that when the
body is deleted and test cases do not kill the mutant that the function is
*unused* or *dead code*.

The plugin shall remove the content of the specified void function body.

## Mutation Identifier {id="design-mutation_id"}

[partof](#req-mutations)

This is to reduce the number of mutations that need to be tested by enabling
reuse of the results. From this perspective it is an performance improvements.
The checksum is intended to be used in the future for mutation metaprograms.
See [@thesis1].

The plugin shall generate an identifier for each mutant.

### Checksum algorithm

The algorithm is a simple Merkel tree. It is based on [@thesis1, p. 27].
The hash algorithm should be murmurhash3 128-bit.

1. Generate the hash *s* of the entire source code.
2. Generate the hash *o1* of the begin offset.
3. Generate the hash *o2* of the end offset.
4. Generate the hash *m* of the textual representation of the mutation.
5. Generate the final hash of *s*, *o1*, *o2* and *m*.
