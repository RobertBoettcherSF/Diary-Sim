#!/bin/sh
# Build and run the unit tests in tests/unit (plain gnatmake, same flags as the program; any compiler warning fails).
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root" || exit 1
GNATMAKE=${GNATMAKE:-gnatmake}
mkdir -p obj/unit bin
rc=0
for t in tests/unit/test_*.adb; do
  n=$(basename "$t" .adb)
  log=obj/unit/$n.build.log
  if ! $GNATMAKE -q -g -O0 -gnatwa -gnat2022 -gnata -D obj/unit -aI. -aItests/unit "$t" -o "bin/$n" -bargs -E > "$log" 2>&1; then
    cat "$log"; echo "  FAIL -- $n does not build"; rc=1; continue
  fi
  if grep -qi warning "$log"; then cat "$log"; echo "  FAIL -- $n: compiler warnings"; rc=1; fi
  "bin/$n" || rc=1
done
rm -f b~*
exit $rc
