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
MUTATION_DB     := test_triangle.mut.db
MUTATION_REPORT := html

DEXTOOL ?= $(MAKEFILE_DIR)/../../../../build/dextool
MFLAGS  := --db $(MUTATION_DB)

#
# Make targets
#

all: report

test_triangle: $(SOURCE) $(TEST)
	$(CC) $(CFLAGS) $(SOURCE) $(TEST) $(LDFLAGS) -o $@

test: test_triangle
	./test_triangle

report: $(MUTATION_DB)
	$(DEXTOOL) mutate report $(MFLAGS) \
			--section summary \
			--section alive \
			--section killed \
			--style html

$(MUTATION_DB): $(SOURCE) $(TEST)
	$(DEXTOOL) mutate analyze $(MFLAGS) \
			--in $(SOURCE) \
			-- $(CFLAGS)
	$(DEXTOOL) mutate test $(MFLAGS) \
			--build-cmd $(MAKEFILE_DIR)/build.sh \
			--test-cmd $(MAKEFILE_DIR)/test.sh \
			--test-timeout 1000

clean:
	rm -rf \
		test_triangle \
		$(MUTATION_DB) \
		$(MUTATION_REPORT)
