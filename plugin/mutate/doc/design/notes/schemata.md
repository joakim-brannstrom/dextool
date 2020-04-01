Last updated 2020-04-01.

# Discussion

The time it takes to test a mutant in a compiled language via source code
mutants is the sum of compile+link+execute tests. Mutant schemata reduces the
compile+link step by generating one source code that contains multiple,
inactive mutants with a way of activating them.  The execution activates one
mutant at a time and then execute the test suite.

As is observable is that as long as the execution time is low it means that the
total time it takes to test all mutants can be significantly reduced. The
change in the ordo complexity is somewhere between O(n) to O(n^2).

So far, so easy.

# Execution

The problem that can occur during the execute is:

1. a schemata isn't possible to compile.
2. the schemata give a different result even if the mutants are inactive.
3. what schematas to execute?
4. how to execute in parallel

## Compilcation 1

There may be schematas that isn't possible to compile.

### Design

The design in dextool assumes that 1) isn't possible to perfectly solve for all
cases and that the generator that is implemented is incorrect. dextool will use
a strategy wherein it first try to execute all applicable schematas and then go
over to, if any are left to test, source code mutants. This should make it
highly robust against invalid schematas but still see a speedup where schematas
are used.

## Complication 2

There may be a bug or something else unforseen in the language semantic
interaction that lead to a schemata changing the behavior of the test. It would
for example be *fatal* to the mutation testing result if a schemata affects the
test cases so one or more of the tests start to always *fail* which would mean
that all mutants are marked as **killed**. The result is faulty in this case.

### Design

The design for 2) is to introduce a sanity check for a schemata. Before a
schemata is used the test suite is executed in order to see that it reports
"passed" when no mutant is activated.

## Complication 3

There will be multiple, available schematas saved in the database but not all
of them are useful.

### Design

Dextool will only execute schematas that contains mutants that need to be
tested. This is possible because each schemata have the mutants that it
contains associated with it.

Thus a schemata is only executed if any of the mutants that is associated with
it is marked as `unknown`.

## Complication 4

There can be multiple instances of dextool executing in parallel against one
and the same database.

### Design

Each instances of dextool retrieve at startup a list of all the schematas that
exists in the database that have mutants associated with it of the user
specifid mutation operator kind.

From this local list of schematas a random one is chosen to be executed. It is
important that it is random to avoid redudant work because another instances is
already testing that specific schemata. The chose schemata is checked to see if
it has any `unknown` mutants.

The schemata is executed, the result is saved in the database. The schemata is
removed from the local list.

The database further have a list of "invalid" schematas. If a schemata turnes
out to not be possible to compile it is added to this list. It means that it
will never be returned, in the future, to the local instances in the list of
available schematas.

# Schemata Generator

The generator is done on the mutant AST. It lacks some of the original AST's
semantic information but shoudl be good enough for schemata. It also simplifies
the process a lot because the mutant AST is constructed for mutation testing.

The problems thought that occur for both the analyser and overall schemata is:

1. when should a scheamta be removed?
2. when should a schemata that is found during the analyse be saved?
3. a schemata isn't possible to compile.

Each schemata have a unique identifier which is the checksum of the mutants
that it contains.

## Design 1

A schemata is removed if any of the files that it is associated with is changed.

## Design 2

A schemata that is found during the analyse phase is only saved if its
identifier isn't already in the database. This avoids re-introducing schematas
all the time into the database which mean less work being done. Becuase when a
schemata is removed more tables need to be updated than what this check cost to
perform.

## Compilcation 1

The schemata generator must be either precis (1) or conservative (2) in order
to be able to *always* generate schematas that are possible to compile.

Precis mean that the schemata generator uses semantic information from the
source code AST in order to only generate those mutants that are compiliable.
An example of this would be that it isn't possible to generate schemata AOR
mutants for a variable that must be possible to evaluate at compile time. A
precis generator would for example find these cases and not inject schematas
for these.

```c++
const int x = 42;
const int y = x + 5;
// schemata for y
const int y = (ID == 1) ? (x - 5) : (x + 5);
// not possible to compile the schemata because ID is initialized at runtime.
```

In other words a precis generator is able to produce as many of the theoretical
possible schematas as possible.

Conservative mean that the generator throw away far more of the possible
schematas than it would necessarily have to do. One such example would be that
most schematas that are generated for a header-file in C++ is not possible to
compile. Instead of improving the precision of the generator one could just
blacklist all header files.

### Design

The design in dextool assumes that 1) isn't possible to perfectly solve for all
cases and that the generator that is implemented is incorrect.

dextool uses a strategy where it generates one schemata per file. It will
result in dexotool seeing a lower speedup than is optimal from schemata but it
makes dextool the schemata strategy robust against compilation errors. One
compilation error only invalidates that specific schemata.

It will further be so that each mutation operator generates its own schemata.
It is for example easier to generate a valid schemata for LCR than SDL.
