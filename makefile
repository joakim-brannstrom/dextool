# Copyright: Copyright (c) 2016, Joakim Brännström. All rights reserved.
# License: http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0
# Author: Joakim Brännström (joakim.brannstrom@gmx.com)

SRC := $(shell find source/application -name "*.d") \
	$(shell find source/cpptooling -name "*.d") \
	$(shell find clang -name "*.d") \
	$(shell find libclang/deimos -name "*.d") \
	$(shell find plugin -name "*.d") \
	$(shell find docopt/source -name "*.d") \
	$(shell find dsrcgen/source -name "*.d")

INCLUDE_PATHS := -Isource -Iclang -Ilibclang -Idsrcgen/source -Idocopt/source -Jclang/resources
VERSION_FLAGS := -version=Have_dextool -version=Have_docopt
COMMON_FLAGS := -dip25 -w $(INCLUDE_PATHS) $(VERSION_FLAGS)
DEBUG_FLAGS := -g

DMD_FLAGS := -release -O -inline $(COMMON_FLAGS)

LDC_FLAGS := -oq $(COMMON_FLAGS)
LDC_OPTIMIZE_FLAGS := -release -enable-inlining -O5

LINK_DMD_CLANG := -L-no-as-needed -L--enable-new-dtags -L-rpath=. -L${LFLAG_CLANG_PATH} -L-l${LFLAG_CLANG_LIB}

DC ?= dmd
LDC ?= ldmd2

.PHONY: dmd ldc2 clean

all: dmd

ldc2: $(SRC)
	$(LDC) $(LDC_FLAGS) $(LDC_OPTIMIZE_FLAGS) $(LINK_DMD_CLANG) $^ -ofbuild/dextool
	-rm -f *.o

ldc-debug: $(SRC)
	$(LDC) $(DEBUG_FLAGS) $(LDC_FLAGS) $(LINK_DMD_CLANG) $^ -ofbuild/dextool-debug
	-rm -f *.o

dmd: $(SRC)
	$(DC) $(DMD_FLAGS) $(LINK_DMD_CLANG) $^ -ofbuild/dextool

clean:
	-rm build/dextool
