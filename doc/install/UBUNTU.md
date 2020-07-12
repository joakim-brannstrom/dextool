# Install Dextool on Ubuntu 19.04

**(Optional) Step 1:** Update and install the latest packages:

```
sudo apt-get update
sudo apt-get upgrade
```

**(Optional) Step 2:** Check which llvm, clang and libclang version to use.

Dextool has been tested with libclang 4.0, 5.0, 6.0, 7.0 and 8.0

Run the following to check which versions are available:

```
apt search llvm-
apt search clang-
apt search libclang-
```

You should see for example `libclang-8-dev`.

**Step 3:** Install the dependencies:

```
sudo apt install build-essential cmake llvm-8 llvm-8-dev clang-8 libclang-8-dev libsqlite3-dev
```

**Step 4:** Install the D compiler:

Download and install the latest DMD compiler from [the official distribution page](https://dlang.org/download.html).

Example (2020-07-12):

```sh
wget http://downloads.dlang.org/releases/2.x/2.093.0/dmd.2.093.0.linux.tar.xz
tar -xf dmd.2.093.0.linux.tar.xz -C ~/dlang
```

Add it to your `$PATH`:
```
export PATH=$PATH:~/dlang/dmd2/linux/bin64
```

You are now ready to build dextool. Go to the section [Build and Install](../../README.md#build-and-install) in README.md
