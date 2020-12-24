#
# Obtain path to this Makefile
#
MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
MAKEFILE_DIR  := $(dir $(MAKEFILE_PATH))


#
# Compilation parameters
#
CFLAGS  := -I$(MAKEFILE_DIR)/inc
LDFLAGS := -lm

SOURCE := $(MAKEFILE_DIR)/src/triangle.c
TEST   := $(MAKEFILE_DIR)/test/test_triangle.c


#
# Mutation testing parameters
#
MUTATION_DB := dextool_mutate.sqlite3
MUTATION_REPORT := html

DEXTOOL     ?= dextool

#
# Make targets
#

all: report

test_triangle: $(SOURCE) $(TEST)
	$(CC) $(CFLAGS) $(SOURCE) $(TEST) $(LDFLAGS) -o $@

test: test_triangle
	./test_triangle

report: $(MUTATION_DB)
	$(DEXTOOL) mutate report \
			--section summary \
			--style html

$(MUTATION_DB): $(SOURCE) $(TEST)
	$(DEXTOOL) mutate analyze --in $(SOURCE) --fast-db-store
	$(DEXTOOL) mutate test

clean:
	rm -rf \
		test_triangle \
		$(MUTATION_DB) \
		$(MUTATION_REPORT)
