#!/bin/bash
# Build with GNAT 14 and GNAT 12 in a copy without .git; fail on any warning.
root=$(cd "$(dirname "$0")/.." && pwd)
GNAT12_ENV=${GNAT12_ENV:-/home/box/deps/gnat12/env.sh}
status=0
for v in 14 12; do
  tmp=$(mktemp -d)
  tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities --exclude=demo_run -cf - . | tar -C "$tmp" -xf -
  out=$(
    cd "$tmp" || exit 1
    if [ "$v" = 12 ]; then . "$GNAT12_ENV"; gn=gnatmake-12
    else PATH=$(echo "$PATH" | tr ':' '\n' | grep -v gnat12 | paste -sd:); gn=gnatmake; fi
    make GNATMAKE=$gn > build.log 2>&1; rc=$?
    echo "$($gn --version | head -1): rc=$rc, warnings=$(grep -ci warning build.log), errors=$(grep -ci error build.log)"
    [ $rc = 0 ] && ! grep -qi -E "warning|error" build.log
  ) || { echo "$out"; status=1; continue; }
  echo "$out"
  rm -rf "$tmp"
done
exit $status
