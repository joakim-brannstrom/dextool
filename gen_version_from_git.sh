#!/bin/bash

VERSION_FILE="resources/version.txt"

git describe --tags > $VERSION_FILE
if [[ $? -ne 0 ]]; then
    echo "unknown build" > $VERSION_FILE
fi
