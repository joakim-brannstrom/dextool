# Stage 1
FROM ubuntu:focal AS base
MAINTAINER Joakim Brännström <joakim.brannstrom@gmx.com>

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends install \
        ca-certificates \
        git \
        sqlite3 libsqlite3-dev \
        make cmake ninja-build \
        llvm-10 llvm-10-dev clang-10 libclang-10-dev \
        gcc g++ \
        curl \
        xz-utils \
        gnupg2 && \
        rm -rf /var/lib/apt/lists/*

WORKDIR /opt

# ldc_latest_version
ENV LDC_VERSION=1.27.1

# ldc
RUN curl -fsS https://dlang.org/install.sh | bash -s ldc-$LDC_VERSION
ENV PATH "/root/dlang/ldc-$LDC_VERSION/bin:$PATH"
ENV DC "ldc2"
RUN apt remove -y curl

# fix_repo
RUN git clone --depth 1 https://github.com/joakim-brannstrom/dextool.git

# prepare_release_build_ubuntu
RUN mkdir -p build && cd build && cmake ../dextool -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/dextool_install -DLOW_MEM=ON

# build_release
RUN cd build && make all VERBOSE=1
RUN cd build && make install VERBOSE=1
RUN rm -rf build dextool

ENV PATH "/opt/dextool_install/bin:$PATH"

# Stage 2
FROM ubuntu:focal AS final
MAINTAINER Joakim Brännström <joakim.brannstrom@gmx.com>

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends install \
        ca-certificates \
        sqlite3 libsqlite3-dev \
        libllvm10 libclang1-10 \
        && \
        rm -rf /var/lib/apt/lists/*

WORKDIR /opt

COPY --from=0 /opt/dextool_install /opt/dextool_install

ENV PATH "/opt/dextool_install/bin:$PATH"
