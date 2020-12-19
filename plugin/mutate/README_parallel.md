## Parallel Run

Parallel mutation testing is realized in dextool mutate by using the same
database in multiple instances via a symlink to a master database. Each
instance of dextool have their own source tree and build environment but the
database that is used is one and the same because of the symlink. This approach
scales reasonably well up to five parallel instances.

Lets say you want to setup parallel execution of googletest with two instances.
First clone the source code to two different locations.

```sh
git clone https://github.com/google/googletest.git gtest1
git clone https://github.com/google/googletest.git gtest2
```

Configure each instance appropriately. As if they would run the mutation
testing by them self. When you are done it should look something like this.

```sh
ls -a gtest1
build/ ..... .dextool_mutate.toml test.sh build.sh
ls -a gtest2
build/ ..... .dextool_mutate.toml test.sh build.sh
```

The next step is the analyze. This is only executed in one of the instances.
Lets say gtest1.

```sh
cd gtest1
dextool mutate analyze
```

Now comes the magic that makes it parallel. Create a symlink in gtest2 to the
database in gtest1.

```sh
cd gtest2
ln -s ../gtest1/dextool_mutate.sqlite3
```

Everything is now prepared for the parallel test phase. Start an instance of
dextool mutate in each of the directories.

```sh
cd gtest1
dextool mutate test
# new console
cd gtest2
dextool mutate test
```

Done!
This can significantly cut down on the test time.

You will now and then see output in the console about the database being
locked. That is as it should be. As noted earlier in this guide it scales OK to
five instances. This is the source of the scaling problem. The more instances
the more lock contention for the database.

