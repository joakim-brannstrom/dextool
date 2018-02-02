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

 Original Expression | Mutant 1 | Mutant 2 | Mutant 3
-------------------|----------|----------|----------
 `x < y`           | `x <= y` | `x != y` | `false`
 `x > y`           | `x >= y` | `x != y` | `false`
 `x <= y`          | `x < y`  | `x == y` | `true`
 `x >= y`          | `x > y`  | `x == y` | `true`
 `x == y`          | `x <= y` | `x >= y` | `false`
 `x != y`          | `x < y`  | `x > y`  | `true`

### Reduce Equivalens Mutants

This is a simple schema that is type aware with the intention of reducing the number of equivalent mutants that are generated.

1. If either side is a boolean type use the following schema instead:

 Original Expression | Mutant 1 | Mutant 2
-------------------|------------|-----------
 `x == y`          | `x != y`   |  `false`
 `x != y`          | `x == y`   |  `true`

2. If either side is a floating point type use the following schema instead:

 Original Expression | Mutant 1 | Mutant 2 | Mutant 3
-------------------|----------|----------|----------
 `x < y`           | `x > y`  |          | `false`
 `x > y`           | `x < y`  |          | `false`
 `x <= y`          | `x > y`  |          | `true`
 `x >= y`          | `x < y`  |          | `true`
 `x == y`          | `x <= y` | `x >= y` | `false`
 `x != y`          | `x < y`  | `x > y`  | `true`

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

The mutation abs(0) and abs(0.0) is undesired because it has no semantic effect.
Note though that abs(-0.0) is a separate case.

TODO: update ABS mutator to use the semantic information to fix this.

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

Original Expression | Mutant 1 | Mutant 2 | Mutant 3 | Mutant 4
--------------------|----------|----------|----------|---------
 `a && b`           | `false`  | `a`      | `b`      | `a == b`
 `a || b`           | `true`   | `a`      | `b`      | `a != b`

# SPC-plugin_mutate_mutation_dcc
partof: REQ-plugin_mutate-mutations
###

TODO: add requirement.

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

Expected result for a C++ file containg _ops_ between integers.

Expected result for a C++ file containg _ops_ between instances of a class overloading the tested operator.

# TST-plugin_mutate_mutation_lcr
partof: SPC-plugin_mutate_mutation_lcr
###

ops = {&&,||}

Expected result for a C++ file containg _ops_ between integers.

Expected result for a C++ file containg _ops_ between instances of a class overloading the tested operator.

# TST-plugin_mutate_mutation_ror
partof: SPC-plugin_mutate_mutation_ror
###

```
ops = {<,<=,>,>=,==,!=}
```

Expected result for a C++ file containg _ops_ between integers.

Expected result for a C++ file containg _ops_ between instances of a class overloading the tested operator.

# TST-plugin_mutate_mutation_cor
partof: SPC-plugin_mutate_mutation_cor
###

ops = {&&,||}

Expected result for a C++ file containg _ops_ between integers.

Expected result for a C++ file containg _ops_ between instances of a class overloading the tested operator.

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

Note: For the one clause case only ONE mutation point shall be generated.
