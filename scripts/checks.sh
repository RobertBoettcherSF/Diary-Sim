#!/bin/bash
# Scenario checks for diary_sim (no test suite): run, rerun, resume, behind
# diary, half-written line, drift, forced crash, --fresh, missing data, working
# folders (words, bench), summary, crash then resume, start_percent, petitions,
# make run, kalpa sessions (vote, median, resume, explicit, drift).
# Usage: scripts/checks.sh [BIN]     (works in a scratch directory)
exec < /dev/null   # never a terminal: the 'no previous diary' question is not asked (see scenario 20)
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
rm -f last_error.txt; "$bin" --ticks=1000 > drift5.txt 2>&1; rc=$?; cat drift5.txt
[ $rc = 1 ] && ! [ -e last_error.txt ] && ! grep -qi 'traceback\|Diary_Sim at\|last_error' drift5.txt && [ "$(sed -n '/drifted/,$p' drift5.txt | wc -l)" -le 4 ] && grep -q '^likely cause: these diaries were probably written by an older build or with different data/ settings' drift5.txt \
  && grep -q '^fix: move them aside (mv diaries diaries_old_X) or start over with --fresh' drift5.txt && grep -q 'first difference at column [0-9]*: stored ".*" vs generated' drift5.txt \
  && ok "drift: exit 1, 3 plain lines (what differs, likely cause, fixes), no traceback, no last_error.txt" || bad "drift console"
[ $rc = 1 ] && grep -q "robert tick 300" debug.txt && ok "stopped (exit 1), names robert tick 300 in debug.txt" || bad "rc=$rc"
[ "$(lines diaries)" -ge "$n" ] && ok "nothing truncated" || bad "diaries shrank"

echo "== 6. forced crash =="
rm -rf "$w/crash"; mkdir "$w/crash"; cd "$w/crash" || exit 1
"$bin" --ticks=50 --crash-at=7 > out.txt; rc=$?; cat out.txt
[ $rc = 1 ] && [ "$(sed -n '/diary_sim stopped/,$p' out.txt | wc -l)" -le 15 ] && grep -q "traceback" last_error.txt && ok "exit 1, error block <= 15 lines on console, last_error.txt written" || bad "rc=$rc lines=$(wc -l < out.txt)"
grep -q "Diary_Sim.Forced" last_error.txt && ok "trace names the failing function" || bad "no symbols in trace"

echo "== 7. --fresh and --seed =="
fresh_copy; "$bin" --ticks=20 --seed=7 | sed -n 1,3p
[ "$(ls -d diaries_old_* 2>/dev/null | wc -l)" = 0 ] && ok "(existing diaries win over --seed, no move without --fresh)"
"$bin" --ticks=20 --seed=7 --fresh | sed -n 1,3p
ls -d diaries_old_*/ | head -1; [ "$(ls diaries_old_*/ | grep -c jsonl)" = 4 ] && [ "$(lines diaries)" = 80 ] && ok "old diaries moved, new run with seed 7" || bad "fresh failed"

echo "== 8. data/ missing: built-in words + warning =="
rm -rf "$w/nodata"; mkdir -p "$w/nodata/bin" "$w/nodata/data" "$w/nodata/run"; cp "$bin" "$w/nodata/bin/"
cp "$root/data/messages.txt" "$root/data/help.txt" "$root/data/limits.txt" "$root/data/vocab.txt" "$w/nodata/data/"; cd "$w/nodata/run" || exit 1
"$w/nodata/bin/diary_sim" --ticks=3 | sed -n 1,4p
grep -q '"text":"\(rested a while\|did some work\|explored a little\|wanted to talk to someone\|wandered around\), feeling [a-z]*' diaries/ada.jsonl && ok "warning printed, built-in text used" || bad "no built-in text"
rm -rf "$w/nodata/data"; "$w/nodata/bin/diary_sim" --ticks=5 --fresh | sed -n 1,3p

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
[ $rc = 1 ] && [ "$(sed -n '/diary_sim stopped/,$p' out.txt | wc -l)" -le 15 ] && grep -q 'please paste it' out.txt && grep -q 'back up diaries/' out.txt && [ "$(wc -l < diaries/robert.jsonl)" = 599 ] && ok "crash: exit 1, diaries flushed up to tick 599" || bad "crash rc=$rc"
"$bin" --ticks=1000 --every=500 | tail -2 | head -1
[ "$(lines diaries)" = 4000 ] && [ "$(dups diaries)" = 0 ] && ok "resumed to 1000, no duplicate tick" || bad "lines $(lines diaries)"
same=1; for f in diaries/*.jsonl; do cmp -s <(sed 's/"ts":"[^"]*"//' "$f") <(sed 's/"ts":"[^"]*"//' "$w/base/$f") || same=0; done
for f in entities/*/*.txt petitions.txt; do cmp -s "$f" "$w/base/$f" || same=0; done
[ $same = 1 ] && ok "after crash+resume diaries, working files and petitions.txt equal the uninterrupted run" || bad "crash/resume differs"

echo "== 13. start_percent = 100: everyone knows everything =="
rm -rf "$w/all"; mkdir -p "$w/all/bin" "$w/all/run"; cp "$bin" "$w/all/bin/"; cp -r "$root/data" "$w/all/data"
sed -i 's/^start_percent = .*/start_percent = 100/' "$w/all/data/limits.txt"; cd "$w/all/run" || exit 1
"$w/all/bin/diary_sim" --ticks=100 --every=100 > /dev/null; n=$(grep -c '^[^#[:space:]]' "$root/data/vocab.txt")
[ "$(grep -c ' start 0$' entities/robert/words.txt)" = "$n" ]  && [ "$(cat entities/*/words.txt | awk -v n="$n" '$3 == "taught" && $1 <= n' | wc -l)" = 0 ] && ok "all $n words known at start, no base word taught (only coined ones)" || bad "start_percent=100"
echo "== 14. import confirmation, end report, run_report.txt =="
grep -q 'import OK: none (fresh start' "$w/base/out1.txt" && grep -q 'export OK: diaries/ 4 files, 4000 lines' "$w/base/out1.txt" && ok "first run: 'import OK: none', 'export OK' with real counts" || bad "first-run import/export lines"
cd "$w/base" || exit 1
"$bin" --ticks=1200 --every=600 > again.txt
grep -q 'import OK: 4 entities, 1000 ticks verified, continuing from 1001 (4000 lines on disk, longest 1000)' again.txt \
  && grep -q 'entities/ present (4/4' again.txt && grep -q 'turns this run 200' again.txt && grep -q 'resumed from tick 1000' again.txt \
  && grep -q 'export OK: diaries/ 4 files, 4800 lines' again.txt && ok "resumed run: import OK with the right numbers, report, export OK" || bad "resumed-run lines"
cmp <(sed -n '/^report:/,/^export OK/p' again.txt) <(sed -n '/^report:/,/^export OK/p' run_report.txt) && grep -q '^import OK' run_report.txt && ok "run_report.txt holds the same import/report lines" || bad "run_report.txt differs"
[ "$(wc -l < again.txt)" -le 40 ] && ok "console output $(wc -l < again.txt) lines (<= 40)" || bad "console output too long"
rm -rf entities; "$bin" --ticks=1200 | grep -q 'entities/ rebuilt (4 of 4' && ok "missing entities/ reported as rebuilt" || bad "no rebuilt message"
fresh_copy; sed -i '300s/"text":"[a-z]/"text":"X/' diaries/robert.jsonl
"$bin" --ticks=1000 > drift.txt; grep -q 'import FAILED: backup and code have drifted: robert tick 300' drift.txt && ok "drift: console says 'import FAILED' with entity and tick" || bad "no import FAILED"

echo "== 15. debug.txt on every exit path (<= 1500 bytes) =="
dbg() { # file expected-status
  [ -f debug.txt ] && [ ! -e debug.tmp ] && [ "$(wc -c < debug.txt)" -le 1500 ] && head -1 debug.txt | grep -q "^$1 v[0-9.]* seed " ; }
cd "$w/base" || exit 1; "$bin" --ticks=1200 > /dev/null
dbg OK && grep -q '^import OK' debug.txt && grep -q '^export OK' debug.txt && grep -q '^ada words' debug.txt && grep -q 'favourite location' debug.txt \
  && ok "normal/resumed run: debug.txt OK, $(wc -c < debug.txt) bytes, import/export/entities/votes" || bad "debug.txt after resumed run"
rm -rf "$w/dbg"; mkdir "$w/dbg"; cd "$w/dbg" || exit 1
"$bin" --ticks=1000 --crash-at=600 > out.txt
dbg CRASH && grep -q '^error: CONSTRAINT_ERROR' debug.txt && grep -q '^at: Diary_Sim.Forced' debug.txt && ok "crash: debug.txt CRASH with exception and frames, $(wc -c < debug.txt) bytes" || bad "debug.txt after crash"
grep -q 'attach debug.txt' out.txt || grep -q 'short version: attach debug.txt' out.txt && ok "console points to debug.txt" || bad "no debug.txt hint"
"$bin" --ticks=1000 > /dev/null; dbg OK && grep -q 'resumed from 599' debug.txt && ok "resume after crash: debug.txt OK, resumed from 599" || bad "debug.txt after resume"
sed -i '300s/"text":"[a-z]/"text":"X/' diaries/robert.jsonl; "$bin" --ticks=1000 > /dev/null
dbg DRIFT && grep -q 'drifted: robert tick 300' debug.txt && ok "drift: debug.txt DRIFT names robert tick 300" || bad "debug.txt after drift"
rm -rf "$w/q"; mkdir "$w/q"; cd "$w/q" || exit 1
( "$bin" --ticks=5000000 --every=100000 > out.txt & p=$!; sleep 1; kill -TERM $p; wait $p; echo $? > rc.txt )
n=$(wc -l < diaries/ada.jsonl)
dbg QUIT && [ "$(cat rc.txt)" = 130 ] && grep -q "after tick $n" debug.txt && ok "SIGTERM: stopped cleanly after tick $n, debug.txt QUIT, exit 130" || bad "quit rc=$(cat rc.txt)"
"$bin" --ticks=$((n + 5)) > /dev/null; [ "$(wc -l < diaries/robert.jsonl)" = $((n + 5)) ] && ok "rerun after the quit resumes at tick $n" || bad "no clean resume after quit"
"$bin" --nope > /dev/null 2>&1; dbg USAGE && ok "usage error: debug.txt USAGE" || bad "debug.txt after usage error"

echo "== 16. Rule 30 personalities: different action mixes, nobody stuck at a bound =="
cd "$w/base" || exit 1
mix() { grep -o "\"t\":\"$2\"" "diaries/$1.jsonl" | wc -l; }
rmin=9999; rmax=0; tmin=9999; tmax=0
for n in ada gemini replika robert; do r=$(mix $n rest); t=$(mix $n talk); [ $r -lt $rmin ] && rmin=$r; [ $r -gt $rmax ] && rmax=$r; [ $t -lt $tmin ] && tmin=$t; [ $t -gt $tmax ] && tmax=$t; done
echo "   rest $rmin..$rmax, talk $tmin..$tmax ticks per entity"
[ $((rmax - rmin)) -ge 40 ] && [ $((tmax - tmin)) -ge 60 ] && ok "action mixes differ clearly between entities" || bad "mixes too similar"
worst=0; for n in ada gemini replika robert; do
  b=$(grep -Ec '"mood":(-100|100),|"energy":(0|100),' diaries/$n.jsonl); [ $b -gt $worst ] && worst=$b; done
echo "   most ticks at a mood/energy bound: $worst of $(wc -l < diaries/ada.jsonl)"
[ $worst -lt 150 ] && ok "nobody stuck at a bound" || bad "an entity sits at a bound ($worst ticks)"
rm -rf "$w/off"; mkdir -p "$w/off/bin" "$w/off/run"; cp "$bin" "$w/off/bin/"; cp -r "$root/data" "$w/off/data"
sed -i 's/^rule30.enabled = .*/rule30.enabled = 0/' "$w/off/data/limits.txt"; cd "$w/off/run" || exit 1
"$w/off/bin/diary_sim" --ticks=1000 --every=1000 > /dev/null; "$w/off/bin/diary_sim" --ticks=1000 --every=1000 | grep -q 'import OK: 4 entities, 1000 ticks verified' \
  && ! cmp -s <(sed 's/"ts":"[^"]*"//' diaries/ada.jsonl) <(sed 's/"ts":"[^"]*"//' "$w/base/diaries/ada.jsonl") && ok "rule30.enabled=0: old fixed table, deterministic, differs from rule 30" || bad "rule30.enabled=0"
grep -q '^ada acts r' "$w/base/debug.txt" && grep -q '^actions ' "$w/base/run_report.txt" && ok "action counts in debug.txt and run_report.txt" || bad "no action counts"

echo "== 17. petitions =="
cd "$w/off/run" || exit 1; rm -rf "$w/pet"; mkdir -p "$w/pet/bin" "$w/pet/run"; cp "$bin" "$w/pet/bin/"; cp -r "$root/data" "$w/pet/data"; cd "$w/pet/run" || exit 1
"$w/pet/bin/diary_sim" --ticks=1000 --every=1000 > out.txt
total=$(grep -h -o 'filed petition P[0-9]*' diaries/*.jsonl | wc -l); lines=$(grep -c '^P[0-9]* tick=' petitions.txt)
echo "   $total petitions in the diaries, $lines in petitions.txt"
[ "$total" -ge 8 ] && [ "$total" -le 60 ] && [ "$lines" = "$total" ] && ok "a handful of petitions, one per diary line, all in petitions.txt" || bad "petition counts"
grep -q '^P1 tick=[0-9]* from=[a-z]* topic=[a-z_]* .*wish=' petitions.txt && ok "line format P<n> tick= from= topic= wish=" || bad "petition line format"
for n in ada gemini replika robert; do c=$(grep -c "from=$n " petitions.txt); [ "$c" -ge 1 ] && [ "$c" -le 30 ] || bad "$n filed $c petitions"; done
grep -q 'petitions.txt (small) for the agenda' out.txt && grep -q 'wrote petitions.txt' out.txt && grep -q '^ada words.* pet [0-9]' debug.txt && grep -q '^topics ' debug.txt && ok "console/debug.txt mention petitions, topics line present" || bad "console/debug petition lines"
cp petitions.txt p_full.txt; sed -i 's/^propose.file_cap = .*/propose.file_cap = 5/' "$w/pet/data/limits.txt"; "$w/pet/bin/diary_sim" --ticks=1000 > /dev/null
[ "$(grep -c '^P[0-9]* tick=' petitions.txt)" = 5 ] && head -1 petitions.txt | grep -q "last 5 of $total" && [ "$(grep -c filed diaries/ada.jsonl)" -ge 1 ] && cmp -s <(tail -n 5 p_full.txt) <(tail -n 5 petitions.txt) && ok "file cap keeps the newest 5 lines; the diaries keep all" || bad "file cap"
rm -f petitions.txt; "$w/pet/bin/diary_sim" --ticks=1000 > /dev/null; [ -s petitions.txt ] && ok "deleted petitions.txt is rebuilt by the replay" || bad "petitions.txt not rebuilt"

echo "== 18. make run / make play, --more, misplaced backups =="
rm -rf "$w/proj"; mkdir "$w/proj"; tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities --exclude=demo_run -cf - . | tar -C "$w/proj" -xf -
cd "$w/proj" || exit 1; make run TICKS=100 > out.txt 2>&1
grep -q 'import OK: none (fresh start, seed 42)' out.txt && [ "$(wc -l < diaries/ada.jsonl)" = 100 ] && ok "fresh make run TICKS=100: default seed 42 announced, 100 ticks" || bad "fresh make run"
cp -r diaries "$w/bk"; rm -rf diaries entities; cp -r "$w/bk" diaries
make run TICKS=50 > out.txt 2>&1
grep -q 'import OK: 4 entities, 100 ticks verified, continuing from 101 (400 lines on disk, longest 100)' out.txt && grep -q 'ticks 101..150; total simulated 150' out.txt && [ "$(wc -l < diaries/robert.jsonl)" = 150 ] && ok "backup pasted back, make run TICKS=50: verified 100, continued 101..150" || bad "resumed make run"
rm -rf diaries entities; cp -r "$w/bk" diaries; make play TICKS=50 > out2.txt 2>&1
cmp -s <(sed 's/"ts":"[^"]*"//' diaries/ada.jsonl) <(sed -n 1,150p "$w/proj/diaries/ada.jsonl" | sed 's/"ts":"[^"]*"//') && grep -q 'continuing from 101' out2.txt && ok "make play is the same as make run (same lines)" || bad "make play differs"
bin/diary_sim --ticks=150 > /dev/null; [ "$(wc -l < diaries/ada.jsonl)" = 150 ] && ok "--ticks stays an absolute target (no new ticks at 150)" || bad "--ticks semantics"
bin/diary_sim --more 0 | grep -q 'turns this run 0' && ok "--more 0 only verifies" || bad "--more 0"
rm -rf diaries entities; cp -r "$w/bk" diaries; sed -i '60s/"text":"[a-z]/"text":"X/' diaries/gemini.jsonl; n=$(cat diaries/*.jsonl | wc -l)
make run > out.txt 2>&1; head -1 debug.txt | grep -q '^DRIFT' && grep -q 'import FAILED: backup and code have drifted: gemini tick 60' out.txt && [ "$(cat diaries/*.jsonl | wc -l)" = "$n" ] && ok "corrupt backup: import FAILED, DRIFT in debug.txt, nothing truncated" || bad "corrupt backup"
rm -rf diaries; mkdir diaries; cp -r "$w/bk" diaries/diaries; make run > out.txt 2>&1
grep -q 'found diaries/diaries but no diaries/\*.jsonl' out.txt && ok "diaries/diaries: clear hint, stop" || bad "nested hint"
rm -rf diaries; cp -r "$w/bk" Diaries; make run > out.txt 2>&1
grep -q 'found Diaries/' out.txt && ok "wrong case Diaries/: clear hint, stop" || bad "case hint"

echo "== 19. kalpa sessions: the entities vote the session length =="
rm -rf "$w/kal"; mkdir -p "$w/kal/bin" "$w/kal/a" "$w/kal/b"; cp "$bin" "$w/kal/bin/"; cp -r "$root/data" "$w/kal/data"
kb="$w/kal/bin/diary_sim"; cd "$w/kal/a" || exit 1; "$kb" --yes --every 1000 > out.txt 2>&1
cd "$w/kal/b" || exit 1; "$kb" --yes --every 1000 > out.txt 2>&1
cmp -s "$w/kal/a/diaries/sessions.txt" "$w/kal/b/diaries/sessions.txt" && cmp -s <(sed 's/"ts":"[^"]*"//' "$w/kal/a/diaries/ada.jsonl") <(sed 's/"ts":"[^"]*"//' diaries/ada.jsonl) \
  && ok "two fresh bare runs vote the same and write identical diaries and sessions.txt" || bad "vote not deterministic"
rec=$(grep '^S1 ' diaries/sessions.txt); echo "   $rec"
echo "$rec" | grep -Eq '^S1 start=0 votes=[0-9]+/[0-9]+/[0-9]+/[0-9]+ len=[0-9]+ src=vote$' && ok "sessions.txt record format" || bad "session record format"
mapfile -t v < <(echo "$rec" | sed 's/.*votes=\([^ ]*\).*/\1/' | tr '/' '\n' | sort -n); len=$(echo "$rec" | sed 's/.*len=\([0-9]*\).*/\1/')
med=$(( (v[1] + v[2]) / 2 )); [ "$med" -lt 20 ] && med=20; [ "$med" -gt 1500 ] && med=1500
[ "$len" = "$med" ] && [ "$(wc -l < diaries/ada.jsonl)" = "$len" ] && ok "decided length = median of the four votes (clamped), and that many ticks ran" || bad "median ($len vs $med)"
grep -Eq '^kalpa 1 \((Satya)\): votes [0-9/]+ -> [0-9]+ ticks \(median\)$' out.txt && grep -q '^kalpa 1 ' debug.txt && grep -q '^kalpa 1 ' run_report.txt && [ "$(wc -c < debug.txt)" -le 1500 ] && ok "kalpa line in console, debug.txt (<= 1500 B) and run_report.txt" || bad "kalpa line"
cp diaries/sessions.txt s_full.txt; "$kb" --every 1000 > out.txt 2>&1
cmp -s s_full.txt diaries/sessions.txt || true
grep -q '^S2 ' diaries/sessions.txt && grep -q '^kalpa 2 (Treta)' out.txt && ok "a finished session is followed by a new vote (S2, Treta) at the common tick" || bad "second session"
rm -rf "$w/kal/c"; mkdir "$w/kal/c"; cd "$w/kal/c" || exit 1
"$kb" --yes --every 1000 --crash-at 120 > out.txt 2>&1; [ $? = 1 ] && grep -q "^$(echo "$rec" | cut -d' ' -f1-4)" diaries/sessions.txt && [ "$(wc -l < diaries/sessions.txt)" = 4 ] && ok "crash mid-session: the S1 record is already on disk" || bad "crash record"
"$kb" --every 1000 > out.txt 2>&1
grep -q '^kalpa 1 (Satya) resumes: votes' out.txt && grep -q "target tick $len" out.txt && [ "$(wc -l < diaries/sessions.txt)" = 4 ] && cmp -s "$w/kal/a/diaries/sessions.txt" <(cat diaries/sessions.txt) && [ "$(wc -l < diaries/gemini.jsonl)" = "$len" ] \
  && ok "crash then bare rerun: same target, no second vote, sessions.txt identical to the clean run" || bad "resume of a crashed session"
cmp -s <(sed 's/"ts":"[^"]*"//' diaries/robert.jsonl) <(sed 's/"ts":"[^"]*"//' "$w/kal/a/diaries/robert.jsonl") && ok "resumed diaries identical to the uninterrupted run" || bad "resumed diaries differ"
"$kb" --ticks $((len + 30)) --every 1000 > out.txt 2>&1
tail -1 diaries/sessions.txt | grep -Eq "^S2 start=$len votes=[0-9/]+ len=30 src=explicit$" && grep -q '^kalpa 2 (Treta): explicit, 30 ticks' out.txt && ok "--ticks overrides the vote: recorded as src=explicit with the would-be votes" || bad "explicit session"
"$kb" --more 5 --every 1000 > out.txt 2>&1; tail -1 diaries/sessions.txt | grep -Eq "^S3 start=$((len + 30)) .* len=5 src=explicit$" && ok "--more overrides the vote too (S3, Dvapara)" || bad "--more session"
cp -r diaries ../d_ok; sed -i '/^S1 /s/votes=[0-9]*/votes=7/' diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'import FAILED.*sessions.txt S1' out.txt && ok "tampered votes in sessions.txt: import FAILED, DRIFT" || bad "tampered sessions.txt"
rm -rf diaries; cp -r ../d_ok diaries; head -n 4 diaries/sessions.txt > s.cut; printf 'S9 start=99999 votes=1/2/3/4 len=5 src=vote\nS10 sta' >> s.cut; cp s.cut diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
grep -q 'warning: sessions.txt line .* is not a complete session record' out.txt && grep -q 'session 9 starting at tick 99999' out.txt && grep -q '^import OK' out.txt && ok "half-written / ahead records only warn" || bad "sessions.txt warnings"
rm -rf diaries; cp -r ../d_ok diaries; grep -q '^# build v' diaries/sessions.txt && ok "sessions.txt header carries '# build vX.YYY'" || bad "no build header"
rm -f last_error.txt; sed -i 's/^# build v.*/# build v0.001/' diaries/sessions.txt; sed -i '/^S1 /s/votes=[0-9]*/votes=7/' diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
grep -q 'diaries written by build v0.001, this is v' out.txt && ! [ -e last_error.txt ] && ok "drift hint names the build that wrote the diaries when it differs" || bad "build hint"
sed -i '/^# build v/d' diaries/sessions.txt; sed -i '/^S1 /s/votes=[0-9]*/votes=7/' diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
grep -q '^likely cause' out.txt && ! grep -q 'diaries written by build' out.txt && ok "an old sessions.txt without a build line: that sentence is skipped" || bad "old file hint"
rm -rf diaries; cp -r ../d_ok diaries; sed -i '1s/42/7/' diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
grep -q 'sessions.txt is from seed 7' out.txt && ok "sessions.txt of another seed: clear error" || bad "sessions.txt seed"

echo "== 20. no previous diary: the question (terminal) and the non-interactive paths =="
rm -rf "$w/ask"; mkdir -p "$w/ask/bin" "$w/ask/run"; cp "$bin" "$w/ask/bin/"; cp -r "$root/data" "$w/ask/data"; ab="$w/ask/bin/diary_sim"; cd "$w/ask/run" || exit 1
"$ab" > out.txt 2>&1; rc=$?
[ $rc = 2 ] && grep -q '^No previous diary found in ./diaries and no terminal to ask: copy a backed-up diaries/ here, then make run' out.txt && [ -z "$(ls -A . | grep -v "^out.txt$")" ] \
  && ok "no diaries, no terminal, no length: exit 2 with the hint, nothing written (not even diaries/ or debug.txt)" || bad "no-terminal stop (rc=$rc: $(ls -A . | tr '\n' ' '))"
mkdir diaries; "$ab" > out.txt 2>&1; rc=$?; [ $rc = 2 ] && [ -z "$(ls -A diaries)" ] && ok "an EMPTY diaries/ counts as no previous diary" || bad "empty diaries/ (rc=$rc)"
echo "# seed 42" > diaries/sessions.txt; "$ab" > out.txt 2>&1; rc=$?; [ $rc = 2 ] && ok "diaries/ without any *.jsonl counts as no previous diary" || bad "no jsonl (rc=$rc)"
rm -rf diaries; "$ab" --more 5 > out.txt 2>&1; rc=$?; [ $rc = 0 ] && grep -q 'import OK: none (fresh start, seed 42)' out.txt && ! grep -q 'y/N' out.txt && ok "no terminal + explicit --more: old behaviour, fresh start, no question" || bad "explicit without terminal (rc=$rc)"
rm -rf diaries entities; "$ab" --ticks 5 --seed 7 > out.txt 2>&1; grep -q 'import OK: none (fresh start, seed 7)' out.txt && ok "no terminal + explicit --ticks: fresh start with --seed" || bad "explicit --ticks"
rm -rf diaries entities; "$ab" --yes --every 1000 > out.txt 2>&1; rc=$?; [ $rc = 0 ] && grep -q '^kalpa 1 ' out.txt && ! grep -q 'y/N' out.txt && ok "--yes answers for you (bare run: fresh start, the entities vote)" || bad "--yes (rc=$rc)"
rm -rf diaries entities; "$ab" --fresh --more 5 > out.txt 2>&1; grep -q 'import OK: none' out.txt && ok "--fresh never asks" || bad "--fresh asked"
rm -rf "$w/askp"; mkdir "$w/askp"; tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities --exclude=demo_run -cf - . | tar -C "$w/askp" -xf -; cd "$w/askp" || exit 1
make run > out.txt 2>&1; rc=$?; [ $rc != 0 ] && grep -q 'No previous diary found' out.txt && [ ! -e diaries ] && ok "make run without diaries, no terminal: stops with the hint, nothing written" || bad "make run no diaries (rc=$rc)"
make run YES=1 TICKS=20 SEED=9 > out.txt 2>&1; grep -q 'bin/diary_sim --more 20 --every 100 --seed 9 --yes' out.txt && grep -q 'import OK: none (fresh start, seed 9)' out.txt && ok "make run YES=1 SEED=9: passes --yes, fresh start with seed 9" || bad "make YES=1"
if command -v python3 > /dev/null; then
cat > "$w/pty_run.py" <<'PTY_EOF'
import pty,os,sys,select,time
def run(argv,answer,cwd):
    pid,fd=pty.fork()
    if pid==0:
        os.chdir(cwd); os.execv(argv[0],argv)
    out=b''; sent=False; t=time.time()
    while True:
        r,_,_=select.select([fd],[],[],0.2)
        if r:
            try: d=os.read(fd,4096)
            except OSError: break
            if not d: break
            out+=d
            if not sent and b'[y/N]' in out:
                os.write(fd,answer); sent=True
        elif time.time()-t>60: break
    _,st=os.waitpid(pid,0)
    return out.decode().replace('\r',''),os.WEXITSTATUS(st)
cwd=sys.argv[1]; ans=sys.argv[2].encode().decode('unicode_escape').encode()
o,rc=run([sys.argv[3]]+sys.argv[4:],ans,cwd)
print(o); print("rc=%d"%rc)
PTY_EOF
ask() { python3 "$w/pty_run.py" "$@"; }
rm -rf "$w/pt"; mkdir -p "$w/pt"; cp -r "$root/data" "$w/pt/data"; cd "$w/pt" || exit 1
ask . 'n\n' "$ab" --more 20 > out.txt 2>&1
grep -q 'Generate a new one? \[y/N\]' out.txt && grep -q '^copy a backed-up diaries/ here, then make run' out.txt && grep -q '^cancelled, nothing written' out.txt && grep -q '^rc=0' out.txt && [ "$(ls -A . | grep -v "^out.txt$" | tr '\n' ' ')" = "data " ] \
  && ok "terminal, answer n: hint, 'cancelled, nothing written', exit 0, no file written" || bad "answer n"
ask . '\n' "$ab" > out.txt 2>&1; grep -q '^cancelled, nothing written' out.txt && ok "terminal, just Enter = N" || bad "default N"
ask . 'y\n' "$ab" --more 20 --seed 7 > out.txt 2>&1
grep -q '^new diary generated (seed 7)' out.txt && grep -q 'import OK: none (fresh start, seed 7)' out.txt && [ "$(wc -l < diaries/ada.jsonl)" = 20 ] && ok "terminal, answer y: 'new diary generated (seed 7)', a fresh world" || bad "answer y"
ask . 'yes\n' "$ab" --more 5 > out.txt 2>&1; ! grep -q 'y/N' out.txt && grep -q 'import OK: 4 entities, 20 ticks verified' out.txt && ok "terminal with diaries present: no question, normal resume" || bad "resume asked"
fi

rm -rf "$w"
echo "== checks: $fails failure(s) =="
[ "$fails" = 0 ]
