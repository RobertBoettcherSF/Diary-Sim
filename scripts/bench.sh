#!/bin/bash
# make bench: seconds per session, the old way against the night run.
#   old: one program start per session (--more N): every session replays the whole history first
#   new: bin/diary_sim --continuous: the history is replayed once, the sessions follow in the same process
# Both start from the same save (BASE_TICKS ticks, seed 42) and must end with the same diaries (checked without the time stamps).
# BENCH_SESSIONS (20), BENCH_TICKS (300 per session), BENCH_BASE (6000), BENCH_OLD (sessions run the old way, default = BENCH_SESSIONS).
exe=${1:-bin/diary_sim}
exe=$(cd "$(dirname "$exe")" && pwd)/$(basename "$exe")
n=${BENCH_SESSIONS:-20}; per=${BENCH_TICKS:-300}; base=${BENCH_BASE:-6000}; old=${BENCH_OLD:-$n}
dir=$(mktemp -d /tmp/diary-bench.XXXXXX)
trap 'rm -rf "$dir"' EXIT
now() { date +%s.%N; }
echo "bench: building a save of $base ticks (seed 42) ..."
t0=$(now)
"$exe" --home "$dir/base" --seed 42 --ticks "$base" --yes --every 100000 > /dev/null 2>&1 || { echo "bench: could not build the base save"; exit 1; }
t1=$(now)
calc() { awk "BEGIN { printf \"%.2f\", $* }"; }
echo "base save: $base ticks in $(calc "$t1 - $t0") s"
cp -r "$dir/base" "$dir/old"; cp -r "$dir/base" "$dir/new"
t0=$(now)
for i in $(seq 1 "$old"); do
  "$exe" --home "$dir/old" --more "$per" --yes --every 100000 > /dev/null 2>&1 || { echo "bench: old way failed in session $i"; exit 1; }
done
t1=$(now)
old_s=$(calc "($t1 - $t0) / $old")
t0=$(now)
"$exe" --continuous --home "$dir/new" --max-sessions "$n" --session-ticks "$per" < /dev/null > "$dir/night.txt" 2>&1 || { echo "bench: night run failed"; tail -5 "$dir/night.txt"; exit 1; }
t1=$(now)
new_all=$(calc "$t1 - $t0")
new_s=$(calc "$new_all / $n")
echo "old way (one start per session): $old sessions of $per ticks, $old_s s per session"
echo "night run (one process):         $n sessions of $per ticks, $new_s s per session ($new_all s in all, incl. the one replay and the final verify)"
echo "  inside the night run, a session alone: $(grep -o '[0-9.]* s per session' "$dir/night.txt" | head -1) (the box at its end; the replay and the check are not in it)"
echo "faster by: $(calc "$old_s / $new_s") times ($(awk "BEGIN { printf \"%.0f\", 100 - 100 * $new_s / $old_s }") % less time per session)"
if [ "$old" = "$n" ]; then
  same=1
  for f in "$dir"/old/diaries/*.jsonl; do
    b=$(basename "$f")
    cmp -s <(sed 's/"ts":"[^"]*"//' "$f") <(sed 's/"ts":"[^"]*"//' "$dir/new/diaries/$b") || same=0
  done
  [ $same = 1 ] && echo "diaries of both ways: identical (without time stamps)" || { echo "diaries of both ways DIFFER"; exit 1; }
fi
