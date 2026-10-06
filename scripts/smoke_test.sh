#!/bin/sh
# Version: 0.002
# make test (build 0.061): a quick smoke test in seconds (make check is the full one, ~16 min): the layout guard; a fresh save of 2
# sessions in a scratch folder, make verify-full and make verify on it; the 0.059 checkpoint fixture (tests/ckpt059.tar.gz) loads
# and 2 more sessions give the files 0.059 gave (tests/ckpt059.expect).  Exit 0 = all passed.
root=$(cd "$(dirname "$0")/.." && pwd); cd "$root" || exit 1
exe=$root/bin/diary_sim; w=$(mktemp -d) || exit 1; trap 'rm -rf "$w"' EXIT
fails=0; ok() { echo "  PASS -- $*"; }; bad() { echo "  FAIL -- $*"; fails=$((fails + 1)); }
run() { env -u DIARY_VERBOSE "$exe" --home "$@" < /dev/null; }
scripts/ckpt_layout.sh --check > "$w/l.txt" 2>&1 && ok "$(cat "$w/l.txt")" || bad "$(cat "$w/l.txt")"
sp=$(scripts/sim_print.sh)
run "$w/s" --continuous --session-ticks 120 --max-sessions 2 --end-check-ticks 0 > "$w/n.txt" 2>&1 \
  && run "$w/s" --verify-full --sim-print "$sp" > "$w/vf.txt" 2>&1 && run "$w/s" --verify --sim-print "$sp" > "$w/vi.txt" 2>&1 \
  && grep -q '^verify: OK, 240 ticks' "$w/vf.txt" && grep -q '^verify: OK (incremental)' "$w/vi.txt" \
  && ok "fresh save of 2 sessions; verify-full and the incremental verify pass" || bad "fresh save / verify ($(tail -n 2 "$w/n.txt" "$w/vf.txt" "$w/vi.txt" 2>/dev/null | tr '\n' ' ' | cut -c1-200))"
# 0.061: without word carrying (carry.enabled = 0 in a data copy) the new sessions follow the 0.059 rules: the same record files; the
# format 3 payload is 0.059's plus the section "carry" (24 bytes head + its body)
mkdir -p "$w/f" "$w/nc"; tar -C "$w/f" -xzf tests/ckpt059.tar.gz; cp -r data "$w/nc/data"; sed -i 's/^carry.enabled = .*/carry.enabled = 0/' "$w/nc/data/limits.txt"
( cd "$w/nc" && run "$w/f/save" --continuous --session-ticks 300 --max-sessions 2 --end-check-ticks 0 ) > "$w/f.txt" 2>&1
( cd "$w/f/save" && for f in $(find diaries entities -type f | LC_ALL=C sort); do printf '%s %s\n' "$(sed 's/"ts":"[^"]*"//' "$f" | cksum | tr -s ' ' | cut -d' ' -f1-2)" "$f"; done
  LC_ALL=C sed -n '/^tick /{p;q;}' state.ckpt ) > "$w/k.txt"
n=$(LC_ALL=C sed -n '/^payload /{s/^payload \([0-9]*\) .*/\1/p;q;}' "$w/f/save/state.ckpt"); c=$(LC_ALL=C sed -n '/^section16 carry /{s/.* \([0-9]*\)$/\1/p;q;}' "$w/f/save/state.ckpt")
grep -q '^start: checkpoint of tick 600 loaded' "$w/f.txt" && grep -v '^payload ' tests/ckpt059.expect | cmp -s "$w/k.txt" - \
  && [ "payload $(( n - ${c:-0} - 24 ))" = "$(sed -n 's/^\(payload [0-9]*\) .*/\1/p' tests/ckpt059.expect)" ] \
  && ok "the 0.059 checkpoint (tests/ckpt059.tar.gz) loads; 2 more sessions without carrying = the files 0.059 wrote; payload = 0.059's + the carry section" || bad "0.059 checkpoint fixture"
echo "== make test: $fails failure(s) (make check runs everything) =="
[ "$fails" = 0 ]
