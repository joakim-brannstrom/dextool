# REQ-plugin_mutate_architecture
partof: REQ-plugin_mutate
###

## Non-Functional Requirements

The vision that the design should strive for is an architecture that enables functional components to freely added and replaced.

Assume that the future is uncertain.

Architectural goals:
 * it should be *expandable* with new modules without affecting existing modules
 * it should be possible to parallelize
 * the programming language a module is written in should be left as an implementation detail for the module
 * the architecture should not limit the programing languages that can be mutation tested. It should be possible to use the architecture for mutation testing of any programming language
 * enable reuse of components. A visualization component should be reusable independent of the programming language that is mutation tested
 * it should be possible to incrementally use mutation testing during development.
 * it should be robust to infrastructure failures

# SPC-plugin_mutate_architecture
partof: REQ-plugin_mutate_architecture
###

The overarching purpose of the design is to break down mutation and
classification in separate components that can operate practically independent
of each other.

The main components are:
 * coordinator
 * analyzer
 * mutation tester
 * report generator
 * visualization

Figures (to be moved to each functional design when they are created):
 * figures/structure.pu : top view of the components.
 * figures/report.pu : generate a report for the user from the database.
 * figures/test_mutant.pu : test a mutation point.

# SPC-plugin_mutate_information_center
partof: SPC-plugin_mutate_architecture
###
*Note: component*

Note: The database takes the role of the *information center* at this stage of
the PoC. It should be encapsulated in a network aware API in the future.

The database shall have an API that enables:
 * initialization of the database
 * saving mutation points
 * mark/unmark a mutation point as alive/dead
 * getting all mutations points that are in the database
 * getting all mutation points in a file
 * save the checksum of a file
 * comparing a checksum+file to what is in the database

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
