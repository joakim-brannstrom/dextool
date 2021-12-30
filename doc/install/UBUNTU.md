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

You should see for example `libclang-12-dev`.

**Step 3:** Install the dependencies:

```
sudo apt install build-essential cmake llvm-13 llvm-13-dev clang-13 libclang-13-dev libsqlite3-dev
```

**Step 4:** Install the D compiler:

Download and install the latest LDC compiler from [the official distribution page](https://github.com/ldc-developers/ldc/releases).

Example (2021-12-30):

```sh
export LDC_VERSION=<see Docker/partial/ldc_latest_version>
wget https://github.com/ldc-developers/ldc/releases/download/v${LDC_VERSION}/ldc2-${LDC_VERSION}-linux-x86_64.tar.xz
mkdir -p ~/dlang
tar -xf ldc2-${LDC_VERSION}-linux-x86_64.tar.xz -C ~/dlang
```

Add it to your `$PATH`:
```sh
export PATH=~/dlang/ldc2-${LDC_VERSION}-linux-x86_64/bin:$PATH
```

You are now ready to build dextool. Go to the section [Build and Install](../../README.md#build-and-install) in README.md
