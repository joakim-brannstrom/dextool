# fedora_base
FROM fedora:34
MAINTAINER Joakim Brännström <joakim.brannstrom@gmx.com>

RUN dnf -y install ca-certificates
RUN update-ca-trust enable
RUN dnf -y upgrade
RUN dnf -y update

# base
RUN dnf -y install curl git xz

# toolchain
RUN dnf -y install gcc binutils gcc-c++

# dextool dependencies
RUN dnf -y install clang11-devel
RUN dnf -y install llvm11-devel
RUN dnf -y install make
RUN dnf -y install cmake3
RUN dnf -y install sqlite-devel

RUN yum clean packages

WORKDIR /opt

# ldc_latest_version
ENV LDC_VERSION=1.27.1

# ldc
RUN curl -fsS https://dlang.org/install.sh | bash -s ldc-$LDC_VERSION
ENV PATH "/root/dlang/ldc-$LDC_VERSION/bin:$PATH"
ENV DC "ldc2"

# fix_repo
RUN git clone --depth 1 https://github.com/joakim-brannstrom/dextool.git

# prepare_release_build_fedora
# NOTE that the -DLIBLLVM_CXX_FLAGS is not needed but added here as a
# demonstration. If you link with another LLVM lib then it is important that
# the correct headers are used otherwise the final result is, "undefined.
# See README.md for other example of the flags and how to derive the specific
# for your llvm installation.
RUN mkdir -p build && cd build && cmake ../dextool -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/dextool_install -DLOW_MEM=ON -DLIBLLVM_VERSION="LLVM_11_0_0" -DLIBLLVM_MAJOR_VERSION="11" -DLIBLLVM_LIBS="-lLLVM-11" -DLIBLLVM_CXX_FLAGS="-I/usr/lib64/llvm11/include -std=c++14 -fno-exceptions -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS"  -DLIBCLANG_LDFLAGS="-Wl,--enable-new-dtags -Wl,--no-as-needed -L/usr/lib64/llvm11/lib -Wl,-rpath,/usr/lib64/llvm11/lib" -DLIBCLANG_LIBS="-lclang-cpp -lclang"

# build_release
RUN cd build && make all VERBOSE=1
RUN cd build && make install VERBOSE=1
RUN rm -rf build dextool

ENV PATH "/opt/dextool_install/bin:$PATH"
