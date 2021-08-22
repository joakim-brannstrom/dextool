#!/bin/bash

echo "Train the adaptable schema generator five times"

dextool mutate analyze
for I in seq 0 5; do
    dextool mutate test --schema-only --schema-train
    dextool mutate analyze --force-save
done
