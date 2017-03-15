# Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
# License: http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0
# Author: Joakim Brännström (joakim.brannstrom@gmx.com)

SRC := \
	$(shell find clang -name "*.d") \
	$(shell find libclang/deimos -name "*.d") \
	$(shell find dsrcgen/source -name "*.d") \

SRC_APP := $(shell find source/application -name "*.d")

SRC_CPPTOOLING := $(shell find source/cpptooling -name "*.d")
SRC_DEXTOOL := $(shell find source/dextool -name "*.d")

SRC_PLUGIN := $(SRC_DEXTOOL) $(SRC_CPPTOOLING) $(shell find plugin/source -name "*.d")
SRC_UML := $(SRC) $(SRC_PLUGIN) $(shell find plugin/uml -name "*.d")
SRC_GRAPHML := $(SRC) $(SRC_PLUGIN) $(shell find plugin/graphml -name "*.d")
SRC_CTESTDOUBLE := $(SRC) $(SRC_PLUGIN) $(shell find plugin/ctestdouble -name "*.d")
SRC_CPPTESTDOUBLE := $(SRC) $(SRC_PLUGIN) $(shell find plugin/cpptestdouble -name "*.d")

INCLUDE_PATHS := -Isource -Iclang -Ilibclang -Idsrcgen/source -Iplugin/source -Jclang/resources -Jresources
VERSION_FLAGS := -version=Have_dextool
COMMON_FLAGS := -w $(INCLUDE_PATHS) $(VERSION_FLAGS)
DEBUG_FLAGS := -g

DMD_FLAGS := -release -O -inline $(COMMON_FLAGS)

LDC_FLAGS := -oq $(COMMON_FLAGS)
LDC_OPTIMIZE_FLAGS := -release -enable-inlining -O5

LINK_DMD_CLANG := -L-no-as-needed -L--enable-new-dtags -L-rpath=. -L${LFLAG_CLANG_PATH} -L-l${LFLAG_CLANG_LIB}

DC ?= dmd
LDC ?= ldmd2

COMPILER = $(DC)
COMPILER_FLAGS = $(DMD_FLAGS)

.PHONY: dmd_compiler dmd_debug_compiler ldc_compiler ldc_compiler_debug gen_version main_app_dep dmd ldc2 clean version
.NOTPARALLEL:

all: dmd

gen_version:
	./gen_version_from_git.sh

plugin_uml: $(SRC_UML)
	time $(COMPILER) -Iplugin/uml/source $(COMPILER_FLAGS) $(LINK_DMD_CLANG) $^ -ofbuild/dextool-uml
	strip build/dextool-uml

plugin_graphml: $(SRC_GRAPHML)
	time $(COMPILER) -Iplugin/graphml/source $(COMPILER_FLAGS) $(LINK_DMD_CLANG) $^ -ofbuild/dextool-graphml
	strip build/dextool-graphml

plugin_ctestdouble: $(SRC_CTESTDOUBLE)
	time $(COMPILER) -Iplugin/ctestdouble/source $(COMPILER_FLAGS) $(LINK_DMD_CLANG) $^ -ofbuild/dextool-ctestdouble
	strip build/dextool-ctestdouble

plugin_cpptestdouble: $(SRC_CPPTESTDOUBLE)
	time $(COMPILER) -Iplugin/cpptestdouble/source $(COMPILER_FLAGS) $(LINK_DMD_CLANG) $^ -ofbuild/dextool-cpptestdouble
	strip build/dextool-cpptestdouble

main_app: $(SRC_APP) $(SRC_CPPTOOLING) $(SRC) $(SRC_DEXTOOL)
	time $(COMPILER) $(COMPILER_FLAGS) $(LINK_DMD_CLANG) $^ -ofbuild/dextool
	strip build/dextool

main_app_dep: gen_version main_app plugin_uml plugin_graphml plugin_ctestdouble plugin_cpptestdouble

dmd_compiler:
	$(eval COMPILER = $(DC))
	$(eval COMPILER_FLAGS = $(DMD_FLAGS))

dmd_compiler_debug:
	$(eval COMPILER = $(DC))
	$(eval COMPILER_FLAGS = $(DMD_FLAGS) $(DEBUG_FLAGS))

ldc_compiler:
	$(eval COMPILER = $(LDC))
	$(eval COMPILER_FLAGS = $(LDC_FLAGS) $(LDC_OPTIMIZE_FLAGS))

ldc_compiler_debug:
	$(eval COMPILER = $(LDC))
	$(eval COMPILER_FLAGS = $(LDC_FLAGS) $(DEBUG_FLAGS))

dmd: dmd_compiler main_app_dep

dmd-debug: dmd_compiler_debug main_app_dep

ldc2: ldc_compiler main_app_dep

ldc2-debug: ldc_compiler_debug main_app_dep

clean:
	-rm build/*
