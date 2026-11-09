#!/bin/bash
# Summarize ir3 per-shader stats from a disasm dump: one line per program, biggest last.
for f in "$@"; do
  echo "=== $f"
  sed 's/^MESA: info: //' "$f" | grep -E '^; CL prog [0-9]+/[0-9]+:' |
    awk '{k=$4; sub(/:$/, "", k); $1=$2=$3=$4=""; a[k]=a[k] "|" $0} END {for (k in a) print k a[k]}' |
    awk -F'|' '{n=$0; sub(/.* ([0-9]+) instr.*/, "\\1", n); print n "\t" $0}' | sort -n | tail -2 | cut -f2-
done
