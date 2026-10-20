#!/bin/sh
# make test: every quick check with one pass/fail summary; exit status 1 if any group failed.
#   version-check, the unit tests (tests/unit), the smoke test (scripts/smoke_test.sh: layout guard, fresh save + verify,
#   the 0.059 checkpoint fixture).  FULL=1 adds the full scenario checks (scripts/checks.sh, ~16 min).
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root" || exit 1
pass=0; fail=0; failed=""
group() {
  name=$1; shift
  echo "=== $name ==="
  if "$@"; then pass=$((pass + 1)); echo "--- $name: PASS"; else fail=$((fail + 1)); failed="$failed $name"; echo "--- $name: FAIL"; fi
}
group version-check make -s --no-print-directory version-check
group unit scripts/unit_tests.sh
group smoke scripts/smoke_test.sh
[ "${FULL:-0}" = 1 ] && group checks scripts/checks.sh
echo "=== test summary: $pass group(s) passed, $fail failed${failed:+ (failed:$failed)} ==="
[ "$fail" = 0 ]
