# SPC-plugin_mutate_architecture
partof: REQ-plugin_mutate-derived
###

The overarching purpose of the design is to break down mutation and
classification in separate components that can operate practically independent
of each other. The purpose is to make it easy to integrate new components and
replace existing.

The main components are:
 - analyzer
 - mutation tester
 - report generator
 - command center
 - information center

Figures (to be moved to each functional design when they are created):
 - figures/structure.pu : top view of the components.
 - figures/report.pu : generate a report for the user from the database.
 - figures/test_mutant.pu : test a mutation point.

# SPC-plugin_mutate_information_center
partof: SPC-plugin_mutate_architecture
###
*Note: component*

Note: The database takes the role of the *information center* at this stage of
the PoC. It should be encapsulated in a network aware API in the future.

The database shall have an API that enables:
 - initialization of the database
 - saving mutation points
 - mark/unmark a mutation point as alive/dead
 - getting all mutations points that are in the database
 - getting all mutation points in a file
 - save the checksum of a file
 - comparing a checksum+file to what is in the database
