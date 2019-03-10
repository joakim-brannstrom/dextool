FROM ubuntu:xenial AS base
MAINTAINER Joakim Brännström <joakim.brannstrom@gmx.com>

RUN apt-get update && \
    apt-get -y --no-install-recommends install wget

RUN wget -O - http://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -

RUN echo "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-3.9 main" >> /etc/apt/sources.list.d/llvm.list

# Dependencies:
# ca-certificates - "Problem with the SSL CA cert" when cloning dextool otherwise.
# sqlite3 - generates SQLite reports.
RUN apt-get update && \
    apt-get -y --no-install-recommends install \
        ca-certificates \
        git \
        sqlite3 libsqlite3-dev \
        make cmake ninja-build \
        llvm-4.0 llvm-4.0-dev clang-4.0 libclang-4.0-dev

RUN apt-get -y --no-install-recommends install \
        gcc g++ \
        curl \
        xz-utils

WORKDIR /opt

RUN git clone --depth 1 https://github.com/joakim-brannstrom/dextool.git

ENV LDC_VERSION=1.11.0
RUN curl -fsS https://dlang.org/install.sh | bash -s ldc-$LDC_VERSION
ENV PATH "~/dlang/ldc-$LDC_VERSION/bin:$PATH"
ENV DC "ldc2"

RUN mkdir -p build && cd build && cmake ../dextool -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/dextool_install
RUN cd build && make install
