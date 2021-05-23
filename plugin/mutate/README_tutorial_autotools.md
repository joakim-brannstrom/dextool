# Mutation Testing using automake

This tutorial demonstrate how to use dextool with autotools when coverage and
schematan do not work out of the box. The process is pretty simple but can be
hard if one do not know the tricks. The tutorial assume that you have set the
variable `$DEXTOOL_INSTALL` to where you have installed dextool.

Generate and configure dextool as normally:

```sh
dextool mutate admin --init
# edit .dextool_mutate.toml
```

Normally dextool is able to inject the runtime for coverage and schemata in the
existing source code. But for your project, which this tutorial try to cover,
this didn't work. Maybe it complained about DTO sections, missing symbol's etc.
What we therefore now do is to instruct dextool to **not** inject the runtime
because **you** will configure the project to link with them as static
libraries.

Scroll down to the section `[schema]` and change the runtime to `"library"`. Do
the same for `[coverage]`. Done! Dextool now trust that you provide the
runtimes.

Run the normall setup that you do for the autotools project. When you come to running configure then add this LDFLAGS:

```sh
LDFLAGS="-L$DEXTOOL_INSTALL/lib -Wl,--whole-archive -ldextool_coverage_runtime -ldextool_schema_runtime -Wl,--no-whole-archive" ./configure
```

Sweet potatoes, that is all. The `--whole-archive` is important because it
tells the linker to not throw away the translation unit constructors in the
libraries.

It should now be possible for you, if you have done the other configuration in
`.dextool_mutate.toml` correct, to run the analyze, test and report phases as
normal.
