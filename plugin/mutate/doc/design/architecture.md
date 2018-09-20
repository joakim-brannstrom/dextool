# REQ-architecture
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

# SPC-architecture
partof: REQ-architecture
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

# SPC-information_center
partof: SPC-architecture
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
