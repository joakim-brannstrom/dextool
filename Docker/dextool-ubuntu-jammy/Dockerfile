# Stage 1
FROM ubuntu:jammy AS base
LABEL authors="Joakim Brännström <joakim.brannstrom@gmx.com>"

RUN apt update && apt upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends install \
        ca-certificates \
        git \
        sqlite3 libsqlite3-dev \
        make cmake ninja-build \
        llvm-14 llvm-14-dev clang-14 libclang-14-dev \
        gcc g++ \
        xz-utils \
        ldc \
        gnupg2 && \
        rm -rf /var/lib/apt/lists/*

WORKDIR /opt

# fix_repo
RUN git clone --depth 1 https://github.com/joakim-brannstrom/dextool.git

# prepare_release_build_ubuntu
RUN mkdir -p build && cd build && cmake ../dextool -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/dextool_install -DLOW_MEM=ON -DCMAKE_VERBOSE_MAKEFILE=ON

# build_release
RUN cd build && make -j all
RUN cd build && make install
RUN rm -rf build dextool

ENV PATH="/opt/dextool_install/bin:$PATH"

# Stage 2
FROM ubuntu:jammy AS final
LABEL authors="Joakim Brännström <joakim.brannstrom@gmx.com>"

RUN apt update && apt upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" --no-install-recommends install \
        ca-certificates \
        sqlite3 libsqlite3-dev \
        libllvm14 libclang1-14 \
        libphobos2-ldc-shared98 && \
        rm -rf /var/lib/apt/lists/*

WORKDIR /opt

COPY --from=0 /opt/dextool_install /opt/dextool_install

ENV PATH="/opt/dextool_install/bin:$PATH"
