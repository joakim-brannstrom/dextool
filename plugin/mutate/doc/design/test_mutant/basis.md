# SPC-plugin_mutate_test_mutant
partof: SPC-plugin_mutate_architecture
###

## Design Decision

The implementation testing mutants should separate the drivers in three parts:
 * process mutants. Two sub-drivers are needed
     * static timeout
     * mutation timeout reduction algorithm
 * test a mutant

## Drivers

### Mutation Timeout Reduction Algorithm

The purpose is to progressively increase the timeout until the pool of mutants tagged as *timeout* stop being reduced.
It is to give the test suite enough time to *finish* and thus *fail* to detect a mutant.

$timeout(R, n) = R \times
\begin{cases}
    C_0 & \quad \text{if } n \text{ is 0}\\
    C_1 \sqrt{n} & \quad \text{otherwise}
\end{cases}$
 * n = iteration
 * R = test suite runtime when tests passes
 * $C_0$ = 1.5
 * $C_1$ = 10

Pseudo-code:
 1. set loop variable *n* to 0.
 2. measure the runtime of the test suite. Save as *t*.
     3. test mutants with `timeout(t, 0)`
     4. add mutations that timeout to pool $p_0$
 5. increment *n*.
 6. if there are any mutants in $p_{n-1}$
     7. test mutations with timeout `timeout(t, n)`
     8. add mutations that timeout to pool $p_n$
 9. if $(p_{n-1} - p_n) != 0$
     10. goto 3 (5 when viewing as Markdown)

#### Mathematical Properties of Timeout Increase

It is important to understand the assumptions the algorithm try to handle. The assumptions have not been verified.
 * a timeout is a sign that the test suite has gone into an infinite loop
 * a timeout is counted as the mutation being killed because it is an observable effect. Semantic difference
 * the runtime of the test suite when it passes (normal runtime) is the *max* it takes to run the test suite because it stops early when it finds a defect (mutant)
 * the normal runtime will fluctuate when a mutant fails. By choosing a timeout of 200% of the normal runtime these fluctuations are covered
 * by increasing the mutation timeout to 1000% the second iteration it is such a sharp increase that it should with a wide margin catch those cases there is a test suite that takes *markedly* longer to finish for *some* mutations but still result in the mutant being killed

The desired mathematical property of the algorithm for increasing the mutation testing is a sharp increase in the mutation time the second iteration. After that it slowly increases but flattens out.

