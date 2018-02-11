# REQ-plugin_mutate-mutations
partof: REQ-plugin_mutate
###

The plugin shall support **at least** the mutations ROR, AOR, LCR, UOI and ABS.

## Why?

Quote from [@mutationSurvey, p. 6] :
*Offutt et al. [182] extended their 6-selective mutation further
using a similar selection strategy. Based on the type of the Mothra
mutation operators, they divided them into three categories:
statements, operands and expressions. They tried to omit operators
from each class in turn. They discovered that 5 operators from
the operands and expressions class became the key operators.
These 5 operators are ABS, UOI, LCR, AOR and ROR. These
key operators achieved 99.5% mutation score.*

Quote from [@detSufficientMutOperators, p. 18] :
*The 5 sufficient operators are ABS, which forces each arithmetic expression to
take on the value 0, a positive value and a negative value, AOR, which replaces
each arithmetic operator with every syntactically legal operator, LCR, which
replaces each logical connector (AND and OR) with several kinds of logical
connectors, ROR, which replaces relational operators with other relational
operators, and UOI, which insert unary operators in front of expressions. It is
interesting to note that this set includes the operators that are required to
satisfy branch and extended branch coverage leading us to believe that extended
branch coverage is in some sense a major part of mutation.*

# SPC-plugin_mutate_mutation_ror
partof: REQ-plugin_mutate-mutations
###

The plugin shall mutate the relational operators according to the RORG schema.

The plugin shall use the *floating point RORG schema* when the type of the expressions on both sides of the operator are floating point types.

**Note**: See [[SPC-plugin_mutate_mutation_ror_float]].

The plugin shall use the *enum RORG schema* when the type of the expressions on both sides of the operator are enums and of the same enum type.

**Note**: See [[SPC-plugin_mutate_mutation_ror_enum]]

The plugin shall use the *pointer RORG schema* when the type of the expressions on both sides of the operator are pointer types and the mutation type is RORP.

**Note**: See [[SPC-plugin_mutate_mutation_ror_ptr]]

## Relational Operator Replacement (ROR)
Replace a single operand with another operand.

The operands are: `<,<=,>,>=,==,!=,true,false`

The implementation should use what is in literature called RORG (Relational
Operator Replacement Global) because it results in fewer mutations and less
amplification of infeasible mutants.

### RORG

In [@improvingLogicBasedTesting] showed that out of the seven possible mutations only
three are required to be generated to guarantee detection of the remaining
four.

Mutation subsuming table from [@thesis1]:

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 |
|---------------------|----------|----------|----------|
| `x < y`             | `x <= y` | `x != y` | `false`  |
| `x > y`             | `x >= y` | `x != y` | `false`  |
| `x <= y`            | `x < y`  | `x == y` | `true`   |
| `x >= y`            | `x > y`  | `x == y` | `true`   |
| `x == y`            | `x <= y` | `x >= y` | `false`  |
| `x != y`            | `x < y`  | `x > y`  | `true`   |

# SPC-plugin_mutate_mutation_ror_bool
partof: SPC-plugin_mutate_mutation_ror
###

This schema is only applicable when the type of the expressions on both sides of an operator are of boolean type.

| Original Expression | Mutant 1 | Mutant 2 |
| ------------------- | -------- | -------- |
| `x == y`            | `x != y` |  `false` |
| `x != y`            | `x == y` |  `true`  |

## Why?

Mutations such as `<` for a boolean type is nonsensical in C++ or in C when the type is `_Bool`.

# SPC-plugin_mutate_mutation_ror_float
partof: SPC-plugin_mutate_mutation_ror
###

This schema is only applicable when the type of the expressions on both sides of an operator are of floating point type.

TODO investigate Mutant 3. What should it be?

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 |
| ------------------- | -------- | -------- | ---------- |
| `x < y`             | `x > y`  |          | `false`    |
| `x > y`             | `x < y`  |          | `false`    |
| `x <= y`            | `x > y`  |          | `true`     |
| `x >= y`            | `x < y`  |          | `true`     |
| `x == y`            | `x <= y` | `x >= y` | `false`    |
| `x != y`            | `x < y`  | `x > y`  | `true`     |

*Note*: that `==` and `!=` isn't changed compared to the original mutation schema because normally they shouldn't be used for a floating point value but if they are, and it is a valid use, the original schema should work.

## Why?

The goal is to reduce the number of *undesired* mutants.

Strict equal is not recommended to ever use for floating point numbers. Because of this the test suite is probably not designed to catch these type of mutations which lead to *undesired* mutants. They are *techincally* not equivalent but they aren't supposed to be cought because the SUT is never supposed to do these type of operations.

TODO empirical evidence needed to demonstrate how much the undesired mutations are reduced.

# SPC-plugin_mutate_mutation_ror_enum
partof: SPC-plugin_mutate_mutation_ror
###

This schema is only applicable when type of the expressions on both sides of an operator are enums and the same enum type.

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3               |
| ------------------- | -------- | -------- | ---------------------- |
| `x < y`             | `x <= y` | `x != y` | `false`                |
| `x > y`             | `x >= y` | `x != y` | `false`                |
| `x <= y`            | `x < y`  | `x == y` | `true`                 |
| `x >= y`            | `x > y`  | `x == y` | `true`                 |
| `x == y`            | `x <= y` if x isn't the min enum literal     |
| `x == y`            | `x >= y` if y isn't the max enum literal     |
| `x == y`            | `false`                                      |
| `x != y`            | `x < y` if x isn't the min enum literal      |
| `x != y`            | `x > y` if y isn't the max enum literal      |
| `x != y`            | `true`                                       |

## Why?

The goal is to reduce the number of equivalent mutants.
Normally an enum can't be *less than* the lowest enum literal of that type thus the test suite can't possibly kill such a mutant.

# SPC-plugin_mutate_mutation_ror_ptr
partof: SPC-plugin_mutate_mutation_ror
###

This schema is only applicable when type of the expressions either sides is a pointer type.

| Original Expression | Mutant 1 | Mutant 2 | Mutant 3 |
| ------------------- | -------- | -------- | -------- |
| `x < y`             | `x <= y` | `x != y` | `false`  |
| `x > y`             | `x >= y` | `x != y` | `false`  |
| `x <= y`            | `x < y`  | `x == y` | `true`   |
| `x >= y`            | `x > y`  | `x == y` | `true`   |
| `x == y`            | `x != y` | `false`  |
| `x != y`            | `x == y` | `true`   |

## Why?

The goal is to reduce the number of undesired mutants when the user of the plugin has knowledge about the internal design of the program.

Design knowledge: Do the program use such C++ constructs that guarantee memory address order and use this guarantees?

This schema can't fully replace parts of ROR because there are programs that make use of the memory address order that is guaranteed by the language. It is thus left to the user to choose the correct schema.

# SPC-plugin_mutate_mutation_aor
partof: REQ-plugin_mutate-mutations
###

TODO: add requirement.

## Arithmetic Operator Replacement (AOR)
Replace a single arithmetic operator with another operand.
The operators are:
```cpp
+,-,*,/,%
```

# SPC-plugin_mutate_mutation_lcr
partof: REQ-plugin_mutate-mutations
###

TODO: add requirement.

## Logical Connector Replacement (LCR)
Replace a single operand with another operand.
The operands are:
```cpp
||,&&
```

# SPC-plugin_mutate_mutation_uoi
partof: REQ-plugin_mutate-mutations
###

TODO: add requirement.

## Unary Operator Insertion (UOI)
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

# SPC-plugin_mutate_mutation_abs
partof: REQ-plugin_mutate-mutations
###

TODO: add requirement.

## Absolute Value Insertion (ABS)

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

# SPC-plugin_mutate_mutation_cor
partof: REQ-plugin_mutate-mutations
###

TODO: add requirement.

## Conditional Operator Replacement (COR)

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
| `a || b`            | `true`   | `a`      | `b`      | `a != b` |


# SPC-plugin_mutate_mutation_dcc
partof: REQ-plugin_mutate-mutations
###

TODO: add requirement.

The intention is to be at least equivalent to a coverage tools report for decision/condition coverage.
This is the reason why a *bomb* is part of DCC.

## Why?
See [@thesis1].

A test suite that achieve MC/DC should kill 100% of these mutants.

As discussed in [@thesis1] a specialized mutation for DC/C results in:
 * less mutations overall
 * less equivalent mutations
 * makes it easier for the human to interpret the results

## Decision Coverage

The DC criteria requires that all branches in a program are executed.

As discussed in [@thesis1, p. 19] the DC criteria is simulated by replacing predicates with `true` or `false`.
For switch statements this isn't possible to do. In those cases a bomb is inserted.

## Condition Coverage

The CC criteria requires that all conditions clauses are executed with true/false.

As discussed in [@thesis1, p. 20] the CC criteria is simulated by replacing clauses with `true` or `false`.
See [@subsumeCondMutTesting] for further discussions.

## Bomb

A statement that halts the program.

The DCC bomb is only needed for case statements.

Note that the bomb do not provide any more information than a coverage report do because it doesn't force the test suite to check the output of the program. It is equivalent to coverage information.

# SPC-plugin_mutate_mutation_dcr
partof: REQ-plugin_mutate-mutations
###

TODO: add requirement.

## Why?

This is a twist of DCC. It replaces the bomb with statement deletion.
The intention is to require the test suite to check the output.

## Case Deletion

This is only needed for switch statements.
It deletes case branch in a switch statement.
It is equivalent to the DCC mutation for predicates (decision) that is set to *false*.

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

# SPC-plugin_mutate_mutations_statement_del
partof: REQ-plugin_mutate-mutations
###

The plugin shall remove one statement when generating a _SDL_ mutation.

## Statement Deletion (SDL)

Delete one statement at a time.

# SPC-plugin_mutate_mutations_statement_del-call_expression
###

The plugin shall remove the specific function call.

Note: How it is removed depend on where it is in the AST.
A function call that is terminated with a `;` should remove the trailing `;`.
In contrast with the initialization list where it should remove the trailing `,`.

# TST-plugin_mutate_statement_del_call_expression
partof: SPC-plugin_mutate_mutations_statement_del-call_expression
###

A mutation is expected to produce valid code.

# TST-plugin_mutate_mutation_ror
partof: SPC-plugin_mutate_mutation_ror
###

Expected result when the input is a single assignment using the operator from column _original expression_.

# SPC-plugin_mutate_mutant_identifier
partof: REQ-plugin_mutate-mutations
###

The plugin shall generate an identifier for each mutant.

## Checksum algorithm

The algorithm is a simple Merkel tree. It is based on [@thesis1, p. 27].
The hash algorithm should be murmurhash3 128-bit.

1. Generate the hash *s* of the entire source code.
2. Generate the hash *o1* of the begin offset.
3. Generate the hash *o2* of the end offset.
4. Generate the hash *m* of the textual representation of the mutation.
5. Generate the final hash of *s*, *o1*, *o2* and *m*.

## Why?

This is to reduce the number of mutations that need to be tested by enabling reuse of the results.
From this perspective it is an performance improvements.

The checksum is intended to be used in the future for mutation metaprograms. See [@thesis1].

# TST-plugin_mutate_mutation_aor
partof: SPC-plugin_mutate_mutation_aor
###

```
ops = {+,-,/,%,*}
```

Expected result for a C++ file containg *ops* between integers.

Expected result for a C++ file containg *ops* between instances of a class overloading the tested operator.

# TST-plugin_mutate_mutation_lcr
partof: SPC-plugin_mutate_mutation_lcr
###

```
ops = {&&, ||}
```

Expected result for a C++ file containg *ops* between integers.

Expected result for a C++ file containg *ops* between instances of a class overloading the tested operator.

# TST-plugin_mutate_mutation_ror
partof: SPC-plugin_mutate_mutation_ror
###

```
ops = {<,<=,>,>=,==,!=}
```

Expected result for a C++ file containg *ops* between integers.

Expected result for a C++ file containg *ops* between instances of a class overloading the tested operator.

# TST-plugin_mutate_mutation_cor
partof: SPC-plugin_mutate_mutation_cor
###

```
ops = {&&, ||}
```

Expected result for a C++ file containg *ops* between integers.

Expected result for a C++ file containg *ops* between instances of a class overloading the tested operator.

# TST-plugin_mutate_mutation_dcc
partof: SPC-plugin_mutate_mutation_dcc
###

## Decision Coverage

*ifstmt* = {
 * `if` stmt with one clause
 * `if` stmt with multiple clauses
 * nested `if` stmts
}

Expected result for *ifstmt*.

*switchstmt* = {
 * `switch` stmt with one case and the default branch
 * empty `switch` stmt
}

Expected result for *switchstmt*.

## Condition Coverage

*ifstmt* = {
 * `if` stmt with one clause
 * `if` stmt with multiple clauses
 * `if` stmt with nested clauses
}

Expected result for *ifstmt*.

**Note**: For the one clause case only ONE mutation point shall be generated.
