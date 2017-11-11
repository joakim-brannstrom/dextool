# REQ-plugin_mutate-mutations
###
The plugin shall support **at least** the mutations ROR, AOR, LCR, UOI and ABS.

[[SPC-plugin_mutate_references]] Quote from 2, p.6:
*Offutt et al. [182] extended their 6-selective mutation further
using a similar selection strategy. Based on the type of the Mothra
mutation operators, they divided them into three categories:
statements, operands and expressions. They tried to omit operators
from each class in turn. They discovered that 5 operators from
the operands and expressions class became the key operators.
These 5 operators are ABS, UOI, LCR, AOR and ROR. These
key operators achieved 99.5% mutation score.*

[[SPC-plugin_mutate_references]] Conclusions from 3, p.18:
*The 5 sufficient operators are ABS, whic forces each arithmetic expression to
take on the value 0, a positive value and a negative value, AOR, which replaces
each arithmetic operator with every syntactically legal operator, LCR, which
replaces each logical connector (AND and OR) with several kinds of logical
connectors, ROR, which replaces relational operators with other relational
operators, and UOI, which insert unary operators in front of expressions. It is
interesting to note that this set includes the operators that are required to
satisfy branch and extended branch coverage leading us to believe that extended
branch coverage is in some sense a major part of mutation.*

## Relational Operator Replacement (ROR)
Replace a single operand with another operand.
The operands are:
```cpp
<,<=,>,>=,==,!=
```

## Arithmetic Operator Replacement (AOR)
Replace a single arithmetic operator with another operand.
The operators are:
```cpp
+,-,*,/,%
```

## Logical Connector Replacement (LCR)
Replace a single operand with another operand.
The operands are:
```cpp
||,&&
```

## Unary Operator Insertion (UOI)
Insert a single unary operator:
The operands are:
```cpp
++,--
```

## Absolute Value Insertion (ABS)
Replace an expression.

Example:
```cpp
// original
a = b + c
// the three resulting mutants
a = abs(b) + c
a = -abs(b) + c
a = 0 + c
```
