# Install Dextool on Ubuntu 19.04

**(Optional) Step 1:** Update and install the latest packages:

```
sudo apt-get update
sudo apt-get upgrade
```

**(Optional) Step 2:** Check which llvm, clang and libclang version to use.

Dextool has been tested with libclang 4.0, 5.0, 6.0, 7.0, 8.0 and 10.0

Run the following to check which versions are available:

```
apt search llvm-
apt search clang-
apt search libclang-
```

You should see for example `libclang-10-dev`.

**Step 3:** Install the dependencies:

```
sudo apt install build-essential cmake llvm-10 llvm-10-dev clang-10 libclang-10-dev libsqlite3-dev
```

**Step 4:** Install the D compiler:

Download and install the latest LDC compiler from [the official distribution page](https://github.com/ldc-developers/ldc/releases).

Example (2021-01-07):

```sh
wget https://github.com/ldc-developers/ldc/releases/download/v1.24.0/ldc2-1.24.0-linux-x86_64.tar.xz
tar -xf ldc2-1.24.0-linux-x86_64.tar.xz -C ~/dlang
```

Add it to your `$PATH`:
```
export PATH=~/dlang/ldc2-1.24.0-linux-x86_64/bin:$PATH
```

You are now ready to build dextool. Go to the section [Build and Install](../../README.md#build-and-install) in README.md
