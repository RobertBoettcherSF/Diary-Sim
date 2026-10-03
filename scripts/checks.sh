#!/bin/bash
# Scenario checks for diary_sim (no test suite): run, rerun, resume, behind
# diary, half-written line, drift, forced crash, --fresh, missing data, working
# folders (words, bench), summary, crash then resume, start_percent.
# Usage: scripts/checks.sh [BIN]     (works in a scratch directory)
root=$(cd "$(dirname "$0")/.." && pwd)
bin=$(readlink -f "${1:-$root/bin/diary_sim}")
w=$(mktemp -d); fails=0
ok()  { echo "  PASS -- $*"; }
bad() { echo "  FAIL -- $*"; fails=$((fails + 1)); }
lines() { cat "$1"/*.jsonl | wc -l; }
dups()  { for f in "$1"/*.jsonl; do grep '}}$' "$f" | grep -o '"tick":[0-9]*' | sort | uniq -d; done | wc -l; }
fresh_copy() { rm -rf "$w/run"; mkdir -p "$w/run"; cp -r "$w/base/diaries" "$w/run/"; cd "$w/run" || exit 1; }

echo "== 1. fresh run, 1000 ticks, then the same again =="
mkdir -p "$w/base"; cd "$w/base" || exit 1
"$bin" --ticks=1000 --every=250 > out1.txt; cat out1.txt
[ "$(lines diaries)" = 4000 ] && ok "4 diaries x 1000 lines" || bad "line count $(lines diaries)"
before=$(md5sum diaries/*.jsonl | md5sum)
mkdir -p "$w/again"; (cd "$w/again" && "$bin" --ticks=1000 > /dev/null)
same=1; for f in diaries/*.jsonl; do cmp -s <(sed 's/"ts":"[^"]*"//' "$f") <(sed 's/"ts":"[^"]*"//' "$w/again/$f") || same=0; done
[ $same = 1 ] && ok "a second fresh run gives the same lines (ts aside)" || bad "not deterministic"
awk -F'"energy":|,"mood":|,"location":|}' '/}}$/ { if (!n++ || $2 < emin) emin = $2; if ($2 > emax) emax = $2; if (!m++ || $3 < mmin) mmin = $3; if ($3 > mmax) mmax = $3 } END { print "   energy " emin ".." emax ", mood " mmin ".." mmax " over all diaries"; exit !(emin >= 0 && emax <= 100 && mmin >= -100 && mmax <= 100 && mmin < 0) }' diaries/*.jsonl && ok "energy 0..100, mood -100..100 with negative values, signed in JSON" || bad "range check"
grep -q '"mood":-[0-9]*,"location"' diaries/ada.jsonl && ok "negative mood written as a signed number" || bad "no signed mood"
tone=$(grep -c ', \(though I felt heavy\|but my mood was low\|while a grey\|and it all felt like too much\|with a tired sort\|and nothing quite helped\)' diaries/ada.jsonl)
[ "$tone" -gt 0 ] && ok "low-mood tone wording appears ($tone lines in ada)" || bad "no low-mood tone"
"$bin" --ticks=1000 | tail -1
[ "$(md5sum diaries/*.jsonl | md5sum)" = "$before" ] && ok "rerun changed nothing" || bad "rerun changed diaries"

echo "== 2. resume: --ticks=1200 continues at 1000, replays nothing twice =="
fresh_copy; "$bin" --ticks=1200 --every=100 | tail -3
[ "$(lines diaries)" = 4800 ] && [ "$(dups diaries)" = 0 ] && ok "1200 lines each, no duplicate tick" || bad "lines $(lines diaries) dups $(dups diaries)"
cmp <(head -n 1000 diaries/ada.jsonl) "$w/base/diaries/ada.jsonl" && ok "first 1000 lines of ada untouched" || bad "ada changed"

echo "== 3. one diary behind (ada cut to 400 lines; her mood is negative there) =="
fresh_copy; head -n 400 "$w/base/diaries/ada.jsonl" > diaries/ada.jsonl
"$bin" --ticks=1000 --every=500
[ "$(lines diaries)" = 4000 ] && [ "$(dups diaries)" = 0 ] && ok "all back to 1000, no duplicates" || bad "lines $(lines diaries) dups $(dups diaries)"
cmp diaries/gemini.jsonl "$w/base/diaries/gemini.jsonl" && ok "gemini byte-identical (replayed, not rewritten)" || bad "gemini rewritten"
cmp <(cut -d, -f1,2,3,5- diaries/ada.jsonl) <(cut -d, -f1,2,3,5- "$w/base/diaries/ada.jsonl") && ok "ada regenerated the same lines (ts aside)" || bad "ada differs"

echo "== 4. half-written last line (replika) + gemini behind =="
fresh_copy; head -n 400 "$w/base/diaries/gemini.jsonl" > diaries/gemini.jsonl
{ head -n 700 "$w/base/diaries/replika.jsonl"; sed -n 701p "$w/base/diaries/replika.jsonl" | head -c 60; } > diaries/replika.jsonl
"$bin" --ticks=1000 --every=500
good=$(grep -c '}}$' diaries/replika.jsonl)
[ "$good" = 1000 ] && [ "$(dups diaries)" = 0 ] && ok "replika has 1000 valid lines, none glued to the half line" || bad "replika valid=$good dups=$(dups diaries)"
echo "   (second run on the repaired files:)"; "$bin" --ticks=1000 | tail -2

echo "== 5. drift: robert's stored line 300 edited, ada cut to 100 lines =="
fresh_copy; head -n 100 "$w/base/diaries/ada.jsonl" > diaries/ada.jsonl
sed -i '300s/"text":"[a-z]/"text":"X/' diaries/robert.jsonl; n=$(lines diaries)
"$bin" --ticks=1000; rc=$?
[ $rc = 1 ] && grep -q "robert tick 300" last_error.txt && ok "stopped (exit 1), names robert tick 300" || bad "rc=$rc"
[ "$(lines diaries)" -ge "$n" ] && ok "nothing truncated" || bad "diaries shrank"

echo "== 6. forced crash =="
rm -rf "$w/crash"; mkdir "$w/crash"; cd "$w/crash" || exit 1
"$bin" --ticks=50 --crash-at=7 > out.txt; rc=$?; cat out.txt
[ $rc = 1 ] && [ "$(wc -l < out.txt)" -le 15 ] && grep -q "traceback" last_error.txt && ok "exit 1, <= 15 lines on console, last_error.txt written" || bad "rc=$rc lines=$(wc -l < out.txt)"
grep -q "Diary_Sim.Forced" last_error.txt && ok "trace names the failing function" || bad "no symbols in trace"

echo "== 7. --fresh and --seed =="
fresh_copy; "$bin" --ticks=20 --seed=7 | head -3
[ "$(ls -d diaries_old_* 2>/dev/null | wc -l)" = 0 ] && ok "(existing diaries win over --seed, no move without --fresh)"
"$bin" --ticks=20 --seed=7 --fresh | head -3
ls -d diaries_old_*/ | head -1; [ "$(ls diaries_old_*/ | grep -c jsonl)" = 4 ] && [ "$(lines diaries)" = 80 ] && ok "old diaries moved, new run with seed 7" || bad "fresh failed"

echo "== 8. data/ missing: built-in words + warning =="
rm -rf "$w/nodata"; mkdir -p "$w/nodata/bin" "$w/nodata/data" "$w/nodata/run"; cp "$bin" "$w/nodata/bin/"
cp "$root/data/messages.txt" "$root/data/help.txt" "$root/data/limits.txt" "$root/data/vocab.txt" "$w/nodata/data/"; cd "$w/nodata/run" || exit 1
"$w/nodata/bin/diary_sim" --ticks=3 | head -4
grep -q '"text":"\(rested a while\|did some work\|explored a little\|wanted to talk to someone\|wandered around\), feeling [a-z]*' diaries/ada.jsonl && ok "warning printed, built-in text used" || bad "no built-in text"
rm -rf "$w/nodata/data"; "$w/nodata/bin/diary_sim" --ticks=5 --fresh | head -3

echo "== 9. limits come from data/limits.txt (mood -10..10) =="
rm -rf "$w/lim"; mkdir -p "$w/lim/bin" "$w/lim/run"; cp "$bin" "$w/lim/bin/"; cp -r "$root/data" "$w/lim/data"
sed -i 's/^mood.min = .*/mood.min = -10/; s/^mood.max = .*/mood.max = 10/' "$w/lim/data/limits.txt"; cd "$w/lim/run" || exit 1
"$w/lim/bin/diary_sim" --ticks=300 --every=300 | tail -1
awk -F',"mood":|,"location"' '/}}$/ { if ($2 < lo) lo = $2; if ($2 > hi) hi = $2 } END { print "   mood " lo ".." hi; exit !(lo >= -10 && hi <= 10 && (lo == -10 || hi == 10)) }' diaries/*.jsonl && ok "mood clamped to the data limits" || bad "limits not applied"

echo "== 10. usage (also: space-separated values) =="
"$bin" --ticks 5 --every 5 --fresh | grep -q "tick 5/5" && ok "--ticks 5 (space form) works"
"$bin" --ticks=abc; [ $? = 2 ] && ok "exit 2 on a bad number"
"$bin" --nope; [ $? = 2 ] && ok "exit 2 on an unknown option"
echo "== 11. working folders entities/<id>/, summary =="
cd "$w/base" || exit 1
[ "$(head -1 entities/ada/words.txt)" = "# seed 42" ] && [ "$(grep -c ' start 0$' entities/ada/words.txt)" -gt 50 ] && ok "words.txt: seed header and start words" || bad "words.txt header/start"
t=$(cat entities/*/words.txt | grep -c ' taught '); c=$(cat entities/*/words.txt | grep -c ' coined ')
[ "$t" -gt 0 ] && [ "$c" -gt 0 ] && ok "taught lines $t, coined lines $c" || bad "taught=$t coined=$c"
[ "$(grep -c '^[0-9]' entities/ada/bench.txt)" -gt 0 ] && ok "bench.txt has runs" || bad "no bench lines"
grep -q "taught [a-z]* the word" diaries/*.jsonl && grep -q 'learned the word' diaries/*.jsonl && ok "teach and learn lines in the diaries" || bad "no teach/learn diary lines"
same=1; for f in entities/*/*.txt; do cmp -s "$f" "$w/again/$f" || same=0; done
[ $same = 1 ] && ok "a second fresh run gives identical words.txt and bench.txt" || bad "side files differ between runs"
[ "$(grep -c . summary.jsonl)" = 5 ] && [ -s summary.txt ] && grep -q 'favourite location' summary.txt && ok "summary.txt and summary.jsonl (4 entities + totals)" || bad "summary files"
rm -rf "$w/rebuild"; mkdir "$w/rebuild"; cp -r diaries "$w/rebuild/"; cd "$w/rebuild" || exit 1
"$bin" --ticks=1000 > /dev/null
same=1; for f in entities/*/*.txt; do cmp -s "$f" "$w/base/$f" || same=0; done
[ $same = 1 ] && [ "$(md5sum diaries/*.jsonl | md5sum)" = "$before" ] && ok "diaries only (no entities/): replay rebuilt the working folders, diaries untouched" || bad "rebuild"
rm -rf entities/gemini; "$bin" --ticks=1000 > /dev/null
cmp -s entities/gemini/words.txt "$w/base/entities/gemini/words.txt" && ok "one deleted entity folder is rebuilt" || bad "gemini folder"
rm -rf diaries; "$bin" --ticks=10 --seed=7 > out.txt; rc=$?
[ $rc = 1 ] && grep -q 'entities/' out.txt && ok "entities/ of another seed: stops with a clear message (exit 1)" || bad "seed mismatch rc=$rc"

echo "== 12. crash at 600, then resume to 1000 =="
rm -rf "$w/cr"; mkdir "$w/cr"; cd "$w/cr" || exit 1
"$bin" --ticks=1000 --crash-at=600 > out.txt; rc=$?; wc -l < out.txt | tr '\n' ' '; echo "console lines"
[ $rc = 1 ] && [ "$(wc -l < out.txt)" -le 15 ] && [ "$(wc -l < diaries/robert.jsonl)" = 599 ] && ok "crash: exit 1, diaries flushed up to tick 599" || bad "crash rc=$rc"
"$bin" --ticks=1000 --every=500 | tail -2 | head -1
[ "$(lines diaries)" = 4000 ] && [ "$(dups diaries)" = 0 ] && ok "resumed to 1000, no duplicate tick" || bad "lines $(lines diaries)"
same=1; for f in diaries/*.jsonl; do cmp -s <(sed 's/"ts":"[^"]*"//' "$f") <(sed 's/"ts":"[^"]*"//' "$w/base/$f") || same=0; done
for f in entities/*/*.txt; do cmp -s "$f" "$w/base/$f" || same=0; done
[ $same = 1 ] && ok "after crash+resume diaries and working files equal the uninterrupted run" || bad "crash/resume differs"

echo "== 13. start_percent = 100: everyone knows everything =="
rm -rf "$w/all"; mkdir -p "$w/all/bin" "$w/all/run"; cp "$bin" "$w/all/bin/"; cp -r "$root/data" "$w/all/data"
sed -i 's/^start_percent = .*/start_percent = 100/' "$w/all/data/limits.txt"; cd "$w/all/run" || exit 1
"$w/all/bin/diary_sim" --ticks=100 --every=100 > /dev/null; n=$(grep -c '^[^#[:space:]]' "$root/data/vocab.txt")
[ "$(grep -c ' start 0$' entities/robert/words.txt)" = "$n" ]  && [ "$(cat entities/*/words.txt | awk -v n="$n" '$3 == "taught" && $1 <= n' | wc -l)" = 0 ] && ok "all $n words known at start, no base word taught (only coined ones)" || bad "start_percent=100"
rm -rf "$w"
echo "== checks: $fails failure(s) =="
[ "$fails" = 0 ]
