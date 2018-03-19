# REQ-plugin_mutate_sanity_check
partof: REQ-plugin_mutate
###

The plugin shall perform a sanity check of the database before the mutation testing start.

## Why?

It has through use of the tool been a constant problem that files belonging to the SUT are different from those that are in the database.

The intent of this requirement is to make it easy to do the *corret* action as a user namely NOT run the mutation testing tool when the files on the filesystem and the database are out of sync. Because if they do run the result is unusable. The results pollute the data.

# SPC-plugin_mutate_sanity_check_db_vs_filesys
partof: REQ-plugin_mutate_sanity_check
###

The plugin shall compare the checksum of all files in the database with those on the filesystem.

The plugin shall interrupt the mutation testing when the checksum is different.
