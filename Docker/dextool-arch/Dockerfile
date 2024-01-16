FROM archlinux:base-devel-20240101.0.204074

RUN pacman -Sy
RUN pacman --noconfirm -S extra/clang15
# RUN pacman --noconfirm -S gnupg

WORKDIR /opt

ENV LDC_VERSION=1.36.0
# RUN curl -O https://dlang.org/d-keyring.gpg
# RUN gpg --import d-keyring.gpg
# RUN gpg --list-keys
RUN curl -O https://dlang.org/install.sh && chmod 755 install.sh
RUN sed -i 's/\/usr\/bin\/env bash/\/bin\/bash -x/' install.sh
RUN sed -i 's/verify "$path/echo foo #/' install.sh
RUN ./install.sh ldc-$LDC_VERSION
ENV PATH "/root/dlang/ldc-$LDC_VERSION/bin:$PATH"
ENV DC "ldc2"

RUN pacman --noconfirm -S extra/git

# Run `source ~/dlang/ldc-1.36.0/activate` in your shell to use ldc-1.36.0.

# fix_repo
RUN git clone --depth 1 https://github.com/joakim-brannstrom/dextool.git

RUN pacman --noconfirm -S extra/cmake
RUN pacman --noconfirm -S extra/llvm

RUN pacman -Fy
# RUN pacman -F CFG.h

# build
RUN mkdir -p build && cd build && cmake ../dextool -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/dextool_install -DLOW_MEM=ON -DLIBLLVM_VERSION="LLVM_15_0_0" -DLIBLLVM_MAJOR_VERSION="15" -DLIBLLVM_CXX_FLAGS="-I/usr/lib/llvm15/include -std=c++17 -fno-exceptions -D_GNU_SOURCE -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS"
#
# # build_release
RUN cd build && make all -j2 VERBOSE=1
RUN cd build && make install VERBOSE=1
# RUN rm -rf build dextool
