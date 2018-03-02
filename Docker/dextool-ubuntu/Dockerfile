FROM ubuntu:xenial

MAINTAINER Joakim Brännström <joakim.brannstrom@gmx.com>

RUN apt-get update && \
    apt-get -y --no-install-recommends install wget

RUN wget -O - http://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -

RUN echo "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-3.9 main" >> /etc/apt/sources.list.d/llvm.list

# Dependencies:
# ca-certificates - "Problem with the SSL CA cert" when cloning dextool otherwise.
# libz, ncurses - LLVM's dependencies.
# sqlite3 - generates SQLite reports.
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
        ca-certificates \
        git \
        vim \
        libz-dev sqlite3 libsqlite3-dev ncurses-dev \
        make cmake ninja-build \
        llvm-3.9 llvm-3.9-dev clang-3.9 libclang-3.9-dev

RUN apt-get -y --no-install-recommends install \
        gcc g++

RUN apt-get -y --no-install-recommends install \
        curl

RUN apt-get -y --no-install-recommends install \
        xz-utils

RUN curl -fsS https://dlang.org/install.sh | bash -s ldc-1.7.0

RUN cd /opt && \
        git clone https://github.com/joakim-brannstrom/dextool.git

RUN ln -s /usr/bin/llvm-config-3.9 /usr/bin/llvm-config

WORKDIR /opt/dextool
RUN git checkout update-readme
RUN ["/bin/bash", "-c", "source ~/dlang/ldc-1.7.0/activate && mkdir -p build && cd build && cmake .."]

WORKDIR /opt/dextool/build
RUN make && make install
