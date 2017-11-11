# SPC-plugin_mutate_references
done: by definition
###

1. [ROR Logic](https://cs.gmu.edu/~offutt/rsrch/papers/rorlogic-jss.pdf)
2. [An Analysis and Survey of the Development of Mutation Testing](http://crest.cs.ucl.ac.uk/fileadmin/crest/sebasepaper/JiaH10.pdf)
 or [An Analysis and Survey of the Development of Mutation Testing](http://www0.cs.ucl.ac.uk/staff/mharman/tse-mutation-survey.pdf)
3. [An Experimental Determination of Sufficient Mutant Operators](http://cse.unl.edu/~grother/papers/tosem96apr.pdf)

## Classification of equivalent mutants

A sample of some of the tested techniques. [[SPC-plugin_mutate_references]]
Quote from 2, p.8-9:

*Based on the work of constraint test data generation, Offutt and Pan [186],
[187], [197] introduced a new equivalent mutant detection approach using
constraint solving. In their approach, the equivalent mutant problem is
formulated as a constraint satisfaction problem by analysing the path condition
of a mutant. A mutant is equivalent if and only if the input constraint is
unsat- isfiable. Empirical evaluation of a prototype has shown that this
technique is able to detect a significant percentage of equivalent mutants
(47.63% among 11 subject programs) for most of the programs. Their results
suggest that the constraint satisfaction formulation is more powerful than the
compiler optimization technique [178].*

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
interetsting to note that this set includes the operators that are required to
satisfy branch and extended branch coverage leading us to believe that extended
branch coverage is in some sense a major part of mutation.*

# TST-plugin_mutate_references
done: by definition
###
