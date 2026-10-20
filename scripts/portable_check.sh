#!/bin/bash
# Build with GNAT 14 and GNAT 12 in a copy without .git; fail on any warning.
root=$(cd "$(dirname "$0")/.." && pwd)
GNAT12_ENV=${GNAT12_ENV:-}   # optional: a script that puts gnatmake-12 on PATH
status=0
for v in 14 12; do
  tmp=$(mktemp -d)
  tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities -cf - . | tar -C "$tmp" -xf -
  out=$(
    cd "$tmp" || exit 1
    if [ "$v" = 12 ]; then [ -n "$GNAT12_ENV" ] && . "$GNAT12_ENV"; gn=${GNATMAKE12:-gnatmake-12}
    else PATH=$(echo "$PATH" | tr ':' '\n' | grep -v gnat12 | paste -sd:); gn=gnatmake; fi
    rc=0; : > build.log
    for opt in "-O0" "-O1 -fno-inline" "-O2"; do   # the quick build, the strict one and the default
      rm -rf obj bin; make GNATMAKE=$gn OPT="$opt" >> build.log 2>&1 || rc=1
    done
    echo "$($gn --version | head -1): rc=$rc, warnings=$(grep -ci warning build.log), errors=$(grep -ci error build.log) (-O0, -O1, -O2)"
    [ $rc = 0 ] && ! grep -qi -E "warning|error" build.log
  ) || { echo "$out"; status=1; continue; }
  echo "$out"
  rm -rf "$tmp"
done
exit $status
