# ubuntu_latest_base
FROM ubuntu:focal
MAINTAINER Joakim Brännström <joakim.brannstrom@gmx.com>

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends install \
        ca-certificates \
        git \
        sqlite3 libsqlite3-dev \
        make cmake ninja-build \
        llvm-10 llvm-10-dev clang-10 libclang-10-dev

RUN apt-get -y --no-install-recommends install \
        gcc g++ \
        curl \
        xz-utils \
        gnupg2

WORKDIR /opt

# ldc_latest_version
ENV LDC_VERSION=1.24.0

# ldc
RUN curl -fsS https://dlang.org/install.sh | bash -s ldc-$LDC_VERSION
ENV PATH "/root/dlang/ldc-$LDC_VERSION/bin:$PATH"
ENV DC "ldc2"

# fix_repo
COPY dextool_to_docker.tar.gz /opt
RUN mkdir dextool
RUN tar xfz dextool_to_docker.tar.gz -C dextool
RUN rm dextool_to_docker.tar.gz

# prepare_release_build_ubuntu
RUN mkdir -p build && cd build && cmake ../dextool -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/dextool_install $BUILD_DOC $LIBLLVM_CXX_FLAGS

# build_release
RUN cd build && make all -j$(nproc)
RUN cd build && make install
RUN rm -rf build

ENV PATH "/opt/dextool_install/bin:$PATH"

# Specific

RUN apt-get -y --no-install-recommends install autoconf automake autopoint bison gperf texinfo bear
RUN apt-get -y --no-install-recommends install rsync patch gettext-base wget

RUN git clone git://git.sv.gnu.org/coreutils
RUN cd coreutils && ./bootstrap
RUN cd coreutils && FORCE_UNSAFE_CONFIGURE=1 ./configure
RUN cd coreutils && bear make
RUN cd coreutils && chmod u+w -R src

# must be a dextool_mutate.toml in the directory the docker is built
COPY dextool_mutate.toml coreutils/.dextool_mutate.toml
RUN cd coreutils && dextool mutate analyze
