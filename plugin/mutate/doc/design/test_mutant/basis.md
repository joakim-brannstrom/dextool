# REQ-test_mutant
partof: REQ-purpose
###

The user wants to process the mutants by applying the test suite on one mutant at a time and record the status for future processing.

# SPC-test_mutant
partof: REQ-test_mutant
###

## Design Decision

The implementation testing mutants should separate the drivers in three parts:
 * process mutants. Two sub-drivers are needed
     * static timeout
     * mutation timeout reduction algorithm
 * test a mutant

## Drivers

# SPC-test_mutant_timeout
partof: SPC-test_mutant
###

The program shall terminate a test suite when it reached the *timeout*.

The program shall *adjust* the timeout when there are no mutants in the state *unknown* and there are at least one mutant in the state *timeout*.

TODO: further refine the requirements. The intent is what is described in the below algorithm.

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

# REQ-unstable_test_suite
partof: REQ-test_mutant
###

The users test suite is unreliable. Because of different reasons it can sometimes fail when testing a mutant. When the test suite fails the plugin should try, as instructed by the user, to apply a re-test strategy to achieve as accurate data as possible.

In other words try to avoid writing erroneous or even wrong data which could result in a highly inaccurate report.

Failing means either or a combination of these:
1. the test suite is unable to state passed/failed by setting the exist status. This can happen if e.g. the test suite relies on external hardware that sometimes lock up and need to be manually restored. If the status "passed" where written (via exit status 0) it would be a lie because maybe the tests would have killed it. In the same vein a "failed" would also be a lie because maybe the test wouldn't fail? It is thus unknown what the actual status is on the test suite. Would the test suite kill the mutant or not.
2. the test suite fail in the middle of running test cases but one of the tests killed the mutant. The problem here occurs when the user wants to record what test cases killed the mutant. In this case the suite *could* exit with exit status 1 because it has proved that at least one test case kills the mutant **but** because the test suite started to produce incomprehensible errors in the middle dextool is unable to discern all the test cases that killed the mutant.

The two scenarios described will most likely require that two or more tools are provided to the user.

## TODO

Impl a strategy for handling scenario 1) if needed. For now the control over the exit status is always in the users hand (!= 0 means killed) together with the "retest:" mean that the user probably have enough tools at hand.

# SPC-retest_mutant_on_unstable_test_case
partof: REQ-unstable_test_suite
###

The plugin shall record *unknown* as the status of the mutant being tested when the *external test case analyser* writes "retest:" to stdout.

**Note**: This mean that it ignores the exist status from the test suite if it finds a "retest:".

## Rationale

This makes it possible for a user to inform dextool that the mutant should be retested because the test suite started to become unstable when executing the test suite.

The user is free to use this or to ignore the instability because if the user chooses to **not** write "retest:" to stdout the exist status will be used to write the status of the mutant.
