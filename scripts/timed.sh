#!/bin/sh
# Version: 0.001
# The wall time of a make command (Makefile: TIMED).  Runs the recipe command, then prints ONE last line with the time since make
# started (the build check of `all` included), e.g. "make wordstat wall time: 0m12s (12s)"; the exit status of the command is kept.
# Usage: scripts/timed.sh <label> <start, seconds since 1970> <quiet 0|1 (make -s: the command is not echoed)> command [args ...]
label=$1; t0=$2; quiet=$3
shift 3
[ "$quiet" = 1 ] || echo "$*"
rc=0
trap 'rc=130' INT   # Ctrl-C stops the program (it gets the signal as before); the time line still comes
"$@" || rc=$?
t=$(( $(date +%s) - t0 ))
[ "$t" -ge 0 ] || t=0
printf 'make %s wall time: %dm%02ds (%ds)\n' "$label" $((t / 60)) $((t % 60)) "$t"
exit $rc
