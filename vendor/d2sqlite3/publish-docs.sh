#!/usr/bin/env bash

rm -rf docs
dub build -b ddox -c travis
cd docs
git init
git add .
git commit -m 'Deployed doc to Github Pages'
git push --force --quiet "https://github.com/biozic/d2sqlite3" master:gh-pages
