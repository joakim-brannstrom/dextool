# Copyright: Copyright (c) 2016-2017, Joakim Brännström. All rights reserved.
# License: http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0
# Author: Joakim Brännström (joakim.brannstrom@gmx.com)

.PHONY: all clean install

all:
	-mkdir -p build
	cd build && cmake .. && make -j2

install:
	cd build && make install

clean:
	-rm -r build
