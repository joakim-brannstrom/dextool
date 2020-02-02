# Test Mutant {id="req-test_mutant"}

The user wants to process the mutants by applying the test suite on one mutant at a time and record the status for future processing.

## SPC-test_mutant {id="design-test_mutant"}

[partof](#req-test_mutant)

### Design Decision

The implementation testing mutants should separate the drivers in three parts:

 * process mutants. Two sub-drivers are needed
     * static timeout
     * mutation timeout reduction algorithm
 * test a mutant

## Timeout Mutant {id="design-test_mutant_timeout"}

[partof](#req-test_mutant)

The plugin shall terminate a test suite when it reached the *timeout*.

The plugin shall *adjust* the timeout when there are no mutants in the state
*unknown* and there are at least one mutant in the state *timeout*.

TODO: further refine the requirements. The intent is what is described in the
below algorithm.

### Mutation Timeout Reduction Algorithm

The purpose is to progressively increase the timeout until the pool of mutants
tagged as *timeout* stop being reduced.  It is to give the test suite enough
time to *finish* and thus *fail* to detect a mutant.

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
     a. test mutants with `timeout(t, 0)`
     b. add mutations that timeout to pool $p_0$
 3. increment *n*.
 4. if there are any mutants in $p_{n-1}$
     a. test mutations with timeout `timeout(t, n)`
     b. add mutations that timeout to pool $p_n$
 5. if $(p_{n-1} - p_n) != 0$
     a. goto

#### Mathematical Properties of Timeout Increase

It is important to understand the assumptions the algorithm try to handle. The
assumptions have not been verified.

 * a timeout is a sign that the test suite has gone into an infinite loop
 * a timeout is counted as the mutation being killed because it is an
   observable effect. Semantic difference
 * the runtime of the test suite when it passes (normal runtime) is the *max*
   it takes to run the test suite because it stops early when it finds a defect
   (mutant)
 * the normal runtime will fluctuate when a mutant fails. By choosing a timeout
   of 200% of the normal runtime these fluctuations are covered
 * by increasing the mutation timeout to 1000% the second iteration it is such
   a sharp increase that it should with a wide margin catch those cases there
   is a test suite that takes *markedly* longer to finish for *some* mutations
   but still result in the mutant being killed

The desired mathematical property of the algorithm for increasing the mutation
testing is a sharp increase in the mutation time the second iteration. After
that it slowly increases but flattens out.

### Background for the improvements to the timeout algorithm

The previous algorithm where problematic when there are multiple instances
dextool running in parallel an using the same database among them.

What happens when there are significant amount of timeout mutants is that the
instances aren't aware of each other and thus end up constantly resetting the
timeout mutants which mean that they basically end up in a loop behavior that
takes a long time to break.

It can go like this:

1. A is testing the mutants.
2. B is testing the mutants.
3. A finish mutation testing but some are marked as timeout.
4. A resets the timeout mutants to unknown.
5. B see that there are no mutants left to test and that some are marked as
   timeout. B reset the timeout mutants to unknown. This invalidate some of A's
   results.
6. A and B are testing the timeout mutants in tandem.
7. B finish a mutant and see that all are now tested. It increases the timeout
   limit and resets all mutants to unknown.  A did not observe this state and
   thinks it still has to test some mutants so keeps going with the old timeout
   limit.
8. etc etc....

The proposed change is to improve the marking of timeout mutants in such a way
that an instance know in which iteration it is. That should mean that B in step
7 is aware that A has already reset the mutants and thus do not need to do it.

**Note**: It was also problematic when only a subset of the timeout mutants
needed to be tested because it added all mutants it knew to the worklist. This
lead to a scaling problem.

#### Design

The design is based on a shared context that is stored in the database. The
shared context consist of:

 * a `worklist` which contains the timeout mutants that are being processed.
 * an `iter` which is how many times the FSM have passed through the `running`
   state.
 * the `state` which is the state that the timeout algorithm is in. This is the states in figure \ref{fig-timeout-mutant-fsm} marked with bold.
 * a `worklist_cnt` which is how many mutants there are in the worklist. This is used by the purge state in figure \ref{fig-timeout-mutant-fsm}.

Any access to the shared context is guarded by a traditional database
transaction. This ensures that modifications to the context is multi-process
safe which allows multiple instances of the plugin to be ran in parallel.

The state machine, see figure \ref{fig-timeout-mutant-fsm}, governs any changes
to the shared context.

The state machine is updated after each time a mutation status update has been
performed.

The state machines state is set to `init` and `iter` is set to one if the
plugin do an analyse.

![FSM for timeout mutants](figures/timeout_mutant_001.eps){#fig-timeout-mutant-fsm height=60%}

Description of the events used in figure \ref{fig-timeout-mutant-fsm}:

 * evAllStatus. All mutants has a status other thatn `unknown`.
 * evChange. The mutants that are left in the worklist has changed compared to
   the counter in the context. $worklist_{count} != count(worklist)$
 * evSame. The inverse of evChange. $worklist_{count} == count(worklist)$

The status of a mutant is update as described in figure \ref{fig-timeout-mutant-act}.

![Setting the status of a mutant](figures/timeout_mutant.eps){#fig-timeout-mutant-act height=40%}

## Unstable Test Suite {id="req-unstable_test_suite"}

The users test suite is unreliable. Because of different reasons it can
sometimes fail when testing a mutant. When the test suite fails the plugin
should try, as instructed by the user, to apply a re-test strategy to achieve
as accurate data as possible.

In other words try to avoid writing erroneous or even wrong data which could
result in a highly inaccurate report.

Failing means either or a combination of these:
1. the test suite is unable to state passed/failed by setting the exist status.
   This can happen if e.g. the test suite relies on external hardware that
   sometimes lock up and need to be manually restored. If the status "passed"
   where written (via exit status 0) it would be a lie because maybe the tests
   would have killed it. In the same vein a "failed" would also be a lie
   because maybe the test wouldn't fail? It is thus unknown what the actual
   status is on the test suite. Would the test suite kill the mutant or not.
2. the test suite fail in the middle of running test cases but one of the tests
   killed the mutant. The problem here occurs when the user wants to record
   what test cases killed the mutant. In this case the suite *could* exit with
   exit status 1 because it has proved that at least one test case kills the
   mutant **but** because the test suite started to produce incomprehensible
   errors in the middle dextool is unable to discern all the test cases that
   killed the mutant.

The two scenarios described will most likely require that two or more tools are
provided to the user.

## TODO

Impl a strategy for handling scenario 1) if needed. For now the control over
the exit status is always in the users hand (!= 0 means killed) together with
the "retest:" mean that the user probably have enough tools at hand.

## Re-Test Mutant On Unstable Test Case {id="design-retest_mutant_on_unstable_test_case"}

[partof](#req-unstable_test_suite)

The plugin shall record *unknown* as the status of the mutant being tested when
the *external test case analyser* writes "retest:" to stdout.

**Note**: This mean that it ignores the exist status from the test suite if it
finds a "retest:".

### Rationale

This makes it possible for a user to inform dextool that the mutant should be
retested because the test suite started to become unstable when executing the
test suite.

The user is free to use this or to ignore the instability because if the user
chooses to **not** write "retest:" to stdout the exist status will be used to
write the status of the mutant.

## Configurable Max Mutant Test Time {id="req-configurable_max_mutant_test_time"}

[partof](#req-test_mutant)

The user wants to configure the maximum time used for mutation testing. If the
limit is reached the plugin should exit cleanly. This is to make it possible
for the user to run the plugin between 22.00 to 07.00 and thus avoid using the
build servers unnecessarily during the workday.

This is also a feature that can be used to quickly finish a report for a pull
request.
