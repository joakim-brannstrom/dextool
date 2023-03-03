# Install Dextool on Ubuntu

**(Optional) Step 1:** Update and install the latest packages:

```
sudo apt-get update
sudo apt-get upgrade
```

**(Optional) Step 2:** Check which llvm, clang and libclang version to use.

Run the following to check which versions are available:

```
apt search llvm-
apt search clang-
apt search libclang-
```

You should see for example `libclang-15-dev`.

**Step 3:** Install the dependencies:

```
sudo apt install build-essential cmake llvm-15 llvm-15-dev clang-15 libclang-15-dev libsqlite3-dev
```

**Step 4:** Install the D compiler:

The supported compiler versions are found at:
   * [dmd minimal version](Docker/partial/dmd_min_version)
   * [dmd max version](Docker/partial/dmd_latest_version)
   * [ldc minimal version](Docker/partial/ldc_min_version)
   * [ldc max version](Docker/partial/ldc_latest_version)

You can install them via the install script at dlang.org.

In the example below replace the compiler version with one of the supported.
The version that is written below should only be seen as an example.

Example (2021-12-30):

```sh
mkdir -p ~/dlang
wget https://dlang.org/install.sh -O ~/dlang/install.sh
sudo chmod +777 ~/dlang/install.sh
~/dlang/install.sh install ldc-1.30.0
~/dlang/install.sh install dub 
```

Add the compilers to your `$PATH` variable:
```sh
source ~/dlang/ldc-1.30.0/activate
source ~/dlang/dub-1.22.0/activate
```

You are now ready to build dextool. Go to the section [Build and
Install](../../README.md#build-and-install) in README.md

```sh
git clone https://github.com/joakim-brannstrom/dextool.git
mkdir dextool/build
cd dextool/build
cmake -DCMAKE_INSTALL_PREFIX=$HOME/local ..
make install
```
