# SPC-plugin_mutate_references
done: by definition
###

1. [ROR Logic](https://cs.gmu.edu/~offutt/rsrch/papers/rorlogic-jss.pdf)
2. [An Analysis and Survey of the Development of Mutation Testing](http://crest.cs.ucl.ac.uk/fileadmin/crest/sebasepaper/JiaH10.pdf)

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

## Choice of mutations
The plugin shall support **at least** the mutations ROR, AOR, LCR and UOR.

[[SPC-plugin_mutate_references]] Quote from 2, p.6:

*The most recent research work on selective mutation was conducted by Namin et
al. [168]–[170]. They formulated the selective mutation problem as a
statistical problem: the variable selection or reduction problem. They applied
linear statistical approaches to identify a subset of 28 mutation operators
from 108 C mutation operators. The results suggested that these 28 operators
are sufficient to predict the effectiveness of a test suite and it reduced 92%
of all generated mutants. According to their results, this approach achieved
the highest rate of reduction compared with other approaches.*


# TST-plugin_mutate_references
done: by definition
###
