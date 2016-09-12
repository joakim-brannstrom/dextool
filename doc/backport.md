# Backport to dsrcgen via subtree

A handy way to backport is via the subtree module for git.
```sh
git checkout -b backport-dsrcgen
git subtree -d split --prefix=dsrcgen --squash -b dsrcgen
```

To merge it all back (assuming still in the branch backport-dsrcgen):
```sh
git subtree merge --prefix=dsrcgen/ --squash dsrcgen
```
