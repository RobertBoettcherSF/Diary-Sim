#!/bin/bash
# Scenario checks for diary_sim (no test suite): run, rerun, resume, behind
# diary, half-written line, drift, forced crash, --fresh, missing data, working
# folders (words, bench), summary, crash then resume, start_percent, petitions,
# make run, kalpa sessions (vote, median, resume, explicit, drift).
# Usage: scripts/checks.sh [BIN]     (works in a scratch directory)
export DIARY_HOME=.   # every scenario saves in its own current directory (the default is ../diary-data, see scenario 22)
exec < /dev/null   # never a terminal: the 'no previous diary' question is not asked (see scenario 20)
root=$(cd "$(dirname "$0")/.." && pwd)
bin=$(readlink -f "${1:-$root/bin/diary_sim}")
w=$(mktemp -d); fails=0
ok()  { echo "  PASS -- $*"; }
bad() { echo "  FAIL -- $*"; fails=$((fails + 1)); }
# The scenarios read the internal ids (ada, sol, ...) in the console: they run on a data copy whose
# data/names.txt maps every id to itself.  The display names have their own scenario (27).
idn() { sed 's/^\([a-z]*\) *=.*/\1 = \1/' "$root/data/names.txt" > "$1/names.txt"; }
idata="$w/idata"; mkdir -p "$idata"; cp -r "$root/data/." "$idata/"; idn "$idata"
# screens (and later chess) change the dice of the words: the older scenarios run with them off; their own scenarios switch them on
sed -i 's/^screen.enabled = .*/screen.enabled = 0/; s/^chess.enabled = .*/chess.enabled = 0/; s/^robot.enabled = .*/robot.enabled = 0/; s/^govern.enabled = .*/govern.enabled = 0/' "$idata/limits.txt"
mkdir -p "$w/ib/bin"; cp "$bin" "$w/ib/bin/"; cp -r "$idata" "$w/ib/data"; bin="$w/ib/bin/diary_sim"   # the binary beside its identity-names data
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
[ $rc = 1 ] && ! [ -e last_error.txt ] && ! grep -qi 'traceback\|Diary_Sim at\|last_error' drift5.txt && [ "$(sed -n '/drifted/,$p' drift5.txt | wc -l)" -le 5 ] && grep -q '^likely cause: these diaries were probably written by an older build or with different data/ settings' drift5.txt \
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
rm -rf "$w/lim"; mkdir -p "$w/lim/bin" "$w/lim/run"; cp "$bin" "$w/lim/bin/"; cp -r "$idata" "$w/lim/data"
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
rm -rf "$w/all"; mkdir -p "$w/all/bin" "$w/all/run"; cp "$bin" "$w/all/bin/"; cp -r "$idata" "$w/all/data"
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
[ "$(wc -l < again.txt)" -le 76 ] && ok "console output $(wc -l < again.txt) lines (<= 76, with the treadmill block)" || bad "console output too long"
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
mix() { grep -Eo "\"t\":\"($2)\"" "diaries/$1.jsonl" | wc -l; }   # the world verbs refine rest (eat) and talk (greet)
rmin=9999; rmax=0; tmin=9999; tmax=0
for n in ada gemini replika robert; do r=$(mix $n "rest|eat"); t=$(mix $n "talk|greet"); [ $r -lt $rmin ] && rmin=$r; [ $r -gt $rmax ] && rmax=$r; [ $t -lt $tmin ] && tmin=$t; [ $t -gt $tmax ] && tmax=$t; done
echo "   rest $rmin..$rmax, talk $tmin..$tmax ticks per entity"
[ $((rmax - rmin)) -ge 40 ] && [ $((tmax - tmin)) -ge 60 ] && ok "action mixes differ clearly between entities" || bad "mixes too similar"
worst=0; for n in ada gemini replika robert; do
  b=$(grep -Ec '"mood":(-100|100),|"energy":(0|100),' diaries/$n.jsonl); [ $b -gt $worst ] && worst=$b; done
echo "   most ticks at a mood/energy bound: $worst of $(wc -l < diaries/ada.jsonl)"
[ $worst -lt 150 ] && ok "nobody stuck at a bound" || bad "an entity sits at a bound ($worst ticks)"
rm -rf "$w/off"; mkdir -p "$w/off/bin" "$w/off/run"; cp "$bin" "$w/off/bin/"; cp -r "$idata" "$w/off/data"
sed -i 's/^rule30.enabled = .*/rule30.enabled = 0/' "$w/off/data/limits.txt"; cd "$w/off/run" || exit 1
"$w/off/bin/diary_sim" --ticks=1000 --every=1000 > /dev/null; "$w/off/bin/diary_sim" --ticks=1000 --every=1000 | grep -q 'import OK: 4 entities, 1000 ticks verified' \
  && ! cmp -s <(sed 's/"ts":"[^"]*"//' diaries/ada.jsonl) <(sed 's/"ts":"[^"]*"//' "$w/base/diaries/ada.jsonl") && ok "rule30.enabled=0: old fixed table, deterministic, differs from rule 30" || bad "rule30.enabled=0"
grep -q '^ada acts r' "$w/base/debug.txt" && grep -q '^actions ' "$w/base/run_report.txt" && ok "action counts in debug.txt and run_report.txt" || bad "no action counts"

echo "== 17. petitions =="
cd "$w/off/run" || exit 1; rm -rf "$w/pet"; mkdir -p "$w/pet/bin" "$w/pet/run"; cp "$bin" "$w/pet/bin/"; cp -r "$idata" "$w/pet/data"; cd "$w/pet/run" || exit 1
"$w/pet/bin/diary_sim" --ticks=1000 --every=1000 > out.txt
total=$(grep -h -o 'filed petition P[0-9]*' diaries/*.jsonl | wc -l); lines=$(grep -c '^P[0-9]* tick=' petitions.txt)
echo "   $total petitions in the diaries, $lines in petitions.txt"
[ "$total" -ge 8 ] && [ "$total" -le 60 ] && [ "$lines" = "$total" ] && ok "a handful of petitions, one per diary line, all in petitions.txt" || bad "petition counts"
grep -q '^P1 tick=[0-9]* from=[a-z]* topic=[a-z_]* .*wish=' petitions.txt && ok "line format P<n> tick= from= topic= wish=" || bad "petition line format"
bad_o=$(grep -v ' repeat=' petitions.txt | grep -c 'Once again'); bad_r=$(grep ' repeat=' petitions.txt | grep -vc 'wish=Once again'); bad_w=$(grep -ci 'we could use\|I mean it kindly' petitions.txt)
[ "$bad_o" = 0 ] && [ "$bad_r" = 0 ] && [ "$bad_w" = 0 ] && ok "'Once again' opens exactly the repeat=N petitions; no 'we could use ... my days' person mix, no 'Kindly ... I mean it kindly'" || bad "petition wording ($bad_o $bad_r $bad_w)"
for n in ada gemini replika robert; do c=$(grep -c "from=$n " petitions.txt); [ "$c" -ge 1 ] && [ "$c" -le 30 ] || bad "$n filed $c petitions"; done
grep -q 'petitions.txt (small) for the agenda' out.txt && grep -q 'wrote petitions.txt' out.txt && grep -q '^ada words.* pet [0-9]' debug.txt && grep -q '^topics ' debug.txt && ok "console/debug.txt mention petitions, topics line present" || bad "console/debug petition lines"
cp petitions.txt p_full.txt; sed -i 's/^propose.file_cap = .*/propose.file_cap = 5/' "$w/pet/data/limits.txt"; "$w/pet/bin/diary_sim" --ticks=1000 > /dev/null
[ "$(grep -c '^P[0-9]* tick=' petitions.txt)" = 5 ] && head -1 petitions.txt | grep -q "last 5 of $total" && [ "$(grep -c filed diaries/ada.jsonl)" -ge 1 ] && cmp -s <(tail -n 5 p_full.txt) <(tail -n 5 petitions.txt) && ok "file cap keeps the newest 5 lines; the diaries keep all" || bad "file cap"
rm -f petitions.txt; "$w/pet/bin/diary_sim" --ticks=1000 > /dev/null; [ -s petitions.txt ] && ok "deleted petitions.txt is rebuilt by the replay" || bad "petitions.txt not rebuilt"

echo "== 18. make run / make play, --more, misplaced backups =="
rm -rf "$w/proj"; mkdir "$w/proj"; tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities -cf - . | tar -C "$w/proj" -xf -; idn "$w/proj/data"
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
rm -rf "$w/kal"; mkdir -p "$w/kal/bin" "$w/kal/a" "$w/kal/b"; cp "$bin" "$w/kal/bin/"; cp -r "$idata" "$w/kal/data"
kb="$w/kal/bin/diary_sim"; cd "$w/kal/a" || exit 1; "$kb" --yes --every 1000 > out.txt 2>&1
cd "$w/kal/b" || exit 1; "$kb" --yes --every 1000 > out.txt 2>&1
cmp -s "$w/kal/a/diaries/sessions.txt" "$w/kal/b/diaries/sessions.txt" && cmp -s <(sed 's/"ts":"[^"]*"//' "$w/kal/a/diaries/ada.jsonl") <(sed 's/"ts":"[^"]*"//' diaries/ada.jsonl) \
  && ok "two fresh bare runs vote the same and write identical diaries and sessions.txt" || bad "vote not deterministic"
rec=$(grep '^S1 ' diaries/sessions.txt); echo "   $rec"; grep '^W1 ' diaries/sessions.txt | sed 's/^/   /'
grep -Eq "^W1 tick=[0-9]+ ada=[a-z]+/(start|taught-by-[a-z]+|coined-by-ada|the-world) gemini=[a-z]+/[a-z-]+ replika=[a-z]+/[a-z-]+ robert=[a-z]+/[a-z-]+$" diaries/sessions.txt && grep -q '^words vote (session 1): ada [a-z]* | gemini [a-z]* | replika [a-z]* | robert ' out.txt && grep -q '^words vote (session 1)' debug.txt && grep -q '^words vote (session 1)' run_report.txt \
  && ok "end-of-session word vote: one favourite word per wesen with origin in sessions.txt W1, one line on console, debug.txt and run_report.txt" || bad "word vote line"
echo "$rec" | grep -Eq '^S1 start=0 votes=[0-9]+/[0-9]+/[0-9]+/[0-9]+ len=[0-9]+ src=vote dharma=1 world=1 rest=1[a-z0-9= ]*$' && ok "sessions.txt record format (dharma=1 world=1)" || bad "session record format"
mapfile -t v < <(echo "$rec" | sed 's/.*votes=\([^ ]*\).*/\1/' | tr '/' '\n' | sort -n); len=$(echo "$rec" | sed 's/.*len=\([0-9]*\).*/\1/')
med=$(( (v[1] + v[2]) / 2 )); [ "$med" -lt 20 ] && med=20; [ "$med" -gt 1500 ] && med=1500
[ "$len" = "$med" ] && [ "$(wc -l < diaries/ada.jsonl)" = "$len" ] && ok "decided length = median of the four votes (clamped), and that many ticks ran" || bad "median ($len vs $med)"
grep -Eq '^kalpa 1 \((Satya)\): votes [0-9/]+ -> [0-9]+ ticks \(median\)$' out.txt && grep -q '^kalpa 1 ' debug.txt && grep -q '^kalpa 1 ' run_report.txt && [ "$(wc -c < debug.txt)" -le 1500 ] && ok "kalpa line in console, debug.txt (<= 1500 B) and run_report.txt" || bad "kalpa line"
cp diaries/sessions.txt s_full.txt; "$kb" --every 1000 > out.txt 2>&1
cmp -s s_full.txt diaries/sessions.txt || true
grep -q '^S2 ' diaries/sessions.txt && grep -q '^kalpa 2 (Treta)' out.txt && ok "a finished session is followed by a new vote (S2, Treta) at the common tick" || bad "second session"
rm -rf "$w/kal/c"; mkdir "$w/kal/c"; cd "$w/kal/c" || exit 1
"$kb" --yes --every 1000 --crash-at 120 > out.txt 2>&1; [ $? = 1 ] && grep -q "^$(echo "$rec" | cut -d' ' -f1-4)" diaries/sessions.txt && [ "$(wc -l < diaries/sessions.txt)" = 6 ] && ok "crash mid-session: the S1 record is already on disk" || bad "crash record"
"$kb" --every 1000 > out.txt 2>&1
grep -q '^kalpa 1 (Satya) resumes: votes' out.txt && grep -q "target tick $len" out.txt && [ "$(wc -l < diaries/sessions.txt)" = 17 ] && cmp -s "$w/kal/a/diaries/sessions.txt" <(cat diaries/sessions.txt) && [ "$(wc -l < diaries/gemini.jsonl)" = "$len" ] \
  && ok "crash then bare rerun: same target, no second vote, sessions.txt identical to the clean run" || bad "resume of a crashed session"
cmp -s <(sed 's/"ts":"[^"]*"//' diaries/robert.jsonl) <(sed 's/"ts":"[^"]*"//' "$w/kal/a/diaries/robert.jsonl") && ok "resumed diaries identical to the uninterrupted run" || bad "resumed diaries differ"
"$kb" --ticks $((len + 30)) --every 1000 > out.txt 2>&1
grep "^S2 " diaries/sessions.txt | grep -Eq "^S2 start=$len votes=[0-9/]+ len=30 src=explicit dharma=1 world=1 rest=1[a-z0-9= ]*$" && grep -q '^kalpa 2 (Treta): explicit, 30 ticks' out.txt && ok "--ticks overrides the vote: recorded as src=explicit with the would-be votes" || bad "explicit session"
"$kb" --more 5 --every 1000 > out.txt 2>&1; grep "^S3 " diaries/sessions.txt | grep -Eq "^S3 start=$((len + 30)) .* len=5 src=explicit dharma=1 world=1 rest=1[a-z0-9= ]*$" && ok "--more overrides the vote too (S3, Dvapara)" || bad "--more session"
cp -r diaries ../d_ok; sed -i '/^S1 /s/votes=[0-9]*/votes=7/' diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'import FAILED.*sessions.txt S1' out.txt && ok "tampered votes in sessions.txt: import FAILED, DRIFT" || bad "tampered sessions.txt"
rm -rf diaries; cp -r ../d_ok diaries; sed -i '/^W1 /s/ada=[^ ]*/ada=zzz\/start/' diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'import FAILED.*sessions.txt W1 (tick' out.txt && ok "tampered word vote (W line): import FAILED, DRIFT" || bad "tampered W line"
rm -rf diaries; cp -r ../d_ok diaries; head -n 17 diaries/sessions.txt > s.cut; rm -f diaries/inbox.txt; printf 'S9 start=99999 votes=1/2/3/4 len=5 src=vote\nS10 sta' >> s.cut; cp s.cut diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
grep -q 'warning: sessions.txt line .* is not a complete session record' out.txt && grep -q 'session 9 starting at tick 99999' out.txt && grep -q '^import OK' out.txt && ok "half-written / ahead records only warn" || bad "sessions.txt warnings"
rm -rf diaries; cp -r ../d_ok diaries; grep -q '^# build v' diaries/sessions.txt && ok "sessions.txt header carries '# build vX.YYY'" || bad "no build header"
rm -f last_error.txt; sed -i 's/^# build v.*/# build v0.001/' diaries/sessions.txt; sed -i '/^S1 /s/votes=[0-9]*/votes=7/' diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
grep -q 'diaries written by build v0.001, this is v' out.txt && ! [ -e last_error.txt ] && ok "drift hint names the build that wrote the diaries when it differs" || bad "build hint"
sed -i '/^# build v/d' diaries/sessions.txt; sed -i '/^S1 /s/votes=[0-9]*/votes=7/' diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
grep -q '^likely cause' out.txt && ! grep -q 'diaries written by build' out.txt && ok "an old sessions.txt without a build line: that sentence is skipped" || bad "old file hint"
rm -rf diaries; cp -r ../d_ok diaries; sed -i '1s/42/7/' diaries/sessions.txt; "$kb" --more 0 > out.txt 2>&1
grep -q 'sessions.txt is from seed 7' out.txt && ok "sessions.txt of another seed: clear error" || bad "sessions.txt seed"

echo "== 20. no previous diary: the question (terminal) and the non-interactive paths =="
rm -rf "$w/ask"; mkdir -p "$w/ask/bin" "$w/ask/run"; cp "$bin" "$w/ask/bin/"; cp -r "$idata" "$w/ask/data"; ab="$w/ask/bin/diary_sim"; cd "$w/ask/run" || exit 1
"$ab" > out.txt 2>&1; rc=$?
[ $rc = 2 ] && grep -q '^No previous diary found in .*/diaries and no terminal to ask: copy a backed-up diaries/ here, then make run' out.txt && [ -z "$(ls -A . | grep -v "^out.txt$")" ] \
  && ok "no diaries, no terminal, no length: exit 2 with the hint, nothing written (not even diaries/ or debug.txt)" || bad "no-terminal stop (rc=$rc: $(ls -A . | tr '\n' ' '))"
mkdir diaries; "$ab" > out.txt 2>&1; rc=$?; [ $rc = 2 ] && [ -z "$(ls -A diaries)" ] && ok "an EMPTY diaries/ counts as no previous diary" || bad "empty diaries/ (rc=$rc)"
echo "# seed 42" > diaries/sessions.txt; "$ab" > out.txt 2>&1; rc=$?; [ $rc = 2 ] && ok "diaries/ without any *.jsonl counts as no previous diary" || bad "no jsonl (rc=$rc)"
rm -rf diaries; "$ab" --more 5 > out.txt 2>&1; rc=$?; [ $rc = 0 ] && grep -q 'import OK: none (fresh start, seed 42)' out.txt && ! grep -q 'y/N' out.txt && ok "no terminal + explicit --more: old behaviour, fresh start, no question" || bad "explicit without terminal (rc=$rc)"
rm -rf diaries entities; "$ab" --ticks 5 --seed 7 > out.txt 2>&1; grep -q 'import OK: none (fresh start, seed 7)' out.txt && ok "no terminal + explicit --ticks: fresh start with --seed" || bad "explicit --ticks"
rm -rf diaries entities; "$ab" --yes --every 1000 > out.txt 2>&1; rc=$?; [ $rc = 0 ] && grep -q '^kalpa 1 ' out.txt && ! grep -q 'y/N' out.txt && ok "--yes answers for you (bare run: fresh start, the entities vote)" || bad "--yes (rc=$rc)"
rm -rf diaries entities; "$ab" --fresh --more 5 > out.txt 2>&1; grep -q 'import OK: none' out.txt && ok "--fresh never asks" || bad "--fresh asked"
rm -rf "$w/askp"; mkdir "$w/askp"; tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities -cf - . | tar -C "$w/askp" -xf -; idn "$w/askp/data"; cd "$w/askp" || exit 1
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
rm -rf "$w/pt"; mkdir -p "$w/pt"; cp -r "$idata" "$w/pt/data"; cd "$w/pt" || exit 1
ask . 'n\n' "$ab" --more 20 > out.txt 2>&1
grep -q 'Generate a new one? \[y/N\]' out.txt && grep -q '^copy a backed-up diaries/ here, then make run' out.txt && grep -q '^cancelled, nothing written' out.txt && grep -q '^rc=0' out.txt && [ "$(ls -A . | grep -v "^out.txt$" | tr '\n' ' ')" = "data " ] \
  && ok "terminal, answer n: hint, 'cancelled, nothing written', exit 0, no file written" || bad "answer n"
ask . '\n' "$ab" --more 20 > out.txt 2>&1; grep -q '^cancelled, nothing written' out.txt && ok "terminal, just Enter = N" || bad "default N"
ask . 'y\n' "$ab" --more 20 --seed 7 > out.txt 2>&1
grep -q '^new diary generated (seed 7)' out.txt && grep -q 'import OK: none (fresh start, seed 7)' out.txt && [ "$(wc -l < diaries/ada.jsonl)" = 20 ] && ok "terminal, answer y: 'new diary generated (seed 7)', a fresh world" || bad "answer y"
ask . 'yes\n' "$ab" --more 5 > out.txt 2>&1; ! grep -q 'y/N' out.txt && grep -q 'import OK: 4 entities, 20 ticks verified' out.txt && ok "terminal with diaries present: no question, normal resume" || bad "resume asked"
fi

echo "== 21. make demo is a preview: excerpts on screen, nothing written =="
rm -rf "$w/pv"; mkdir "$w/pv"; tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities -cf - . | tar -C "$w/pv" -xf -; idn "$w/pv/data"; cd "$w/pv" || exit 1
make > /dev/null 2>&1; list() { find . -printf '%p %s %T@\n' | sort; }; list > "$w/pv_before.txt"
make demo > "$w/pv_out.txt" 2>&1; rc=$?; list > "$w/pv_after.txt"
cmp -s "$w/pv_before.txt" "$w/pv_after.txt" && [ $rc = 0 ] && ok "make demo: exit 0, no file created or changed in the whole tree (listing with sizes and times compared)" || bad "make demo touched the tree (rc=$rc): $(diff "$w/pv_before.txt" "$w/pv_after.txt" | head -3)"
n=$(sed -n '/^demo preview:/,$p' "$w/pv_out.txt" | wc -l); echo "   preview output: $n lines"
[ "$n" -le 40 ] && grep -q '^demo preview: seed 42, 200 ticks' "$w/pv_out.txt" && grep -q '^ada  *100 ' "$w/pv_out.txt" && grep -q '^P1 tick=' "$w/pv_out.txt" && grep -q '^coined: ' "$w/pv_out.txt" && grep -q '^taught: ' "$w/pv_out.txt" \
  && grep -q 'kalpa 1 (Satya): votes' "$w/pv_out.txt" && grep -q '^favourite location:' "$w/pv_out.txt" && grep -q '^nothing was written to disk' "$w/pv_out.txt" && ok "excerpts: diary lines per wesen, petitions, words, vote one-liner, vote table (about one screen)" || bad "preview content"
bin/diary_sim --preview --ticks 50 --seed 7 > "$w/pv_o.txt"; grep -q '^demo preview: seed 7, 50 ticks' "$w/pv_o.txt" && ok "--preview takes --ticks and --seed" || bad "preview options"
for o in --fresh --yes "--more 5" "--crash-at 9"; do bin/diary_sim --preview $o > "$w/pv_e.txt" 2>&1; [ $? = 2 ] && grep -q 'writes nothing' "$w/pv_e.txt" || bad "--preview $o not rejected"; done
list > "$w/pv_after2.txt"; cmp -s "$w/pv_before.txt" "$w/pv_after2.txt" && ok "--preview with --fresh/--yes/--more/--crash-at: usage error (exit 2), still nothing written" || bad "rejected preview wrote files"
bin/diary_sim --ticks 20 > /dev/null 2>&1; cp -r diaries "$w/pv_d"; list > "$w/pv_b3.txt"; bin/diary_sim --preview > /dev/null 2>&1; list > "$w/pv_a3.txt"
cmp -s "$w/pv_b3.txt" "$w/pv_a3.txt" && ok "--preview next to an existing ./diaries leaves it (and the rest of the tree) untouched" || bad "preview touched existing diaries"

echo "== 22. the save lives next to the source folder: replace the source, the world continues =="
rm -rf "$w/par"; mkdir -p "$w/par/A"; tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities -cf - . | tar -C "$w/par/A" -xf -; idn "$w/par/A/data"
( cd "$w/par/A" && make > /dev/null 2>&1 && cd / && env -u DIARY_HOME "$w/par/A/bin/diary_sim" --more 30 --every 1000 > "$w/par/o1.txt" 2>&1 )
[ -d "$w/par/diary-data/diaries" ] && [ ! -e "$w/par/A/diaries" ] && [ "$(wc -l < "$w/par/diary-data/diaries/ada.jsonl")" = 30 ] && grep -q "^Saved to $w/par/diary-data\$" "$w/par/o1.txt" \
  && ok "default save folder = ../diary-data (started from /, not from the source folder); nothing inside the source tree; 'Saved to <abs path>' printed" || bad "save location"
rm -rf "$w/par/A"; mkdir "$w/par/B"; tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities -cf - . | tar -C "$w/par/B" -xf -; idn "$w/par/B/data"
( cd "$w/par/B" && env -u DIARY_HOME make run TICKS=25 EVERY=1000 > "$w/par/o2.txt" 2>&1 )
grep -q 'import OK: 4 entities, 30 ticks verified, continuing from 31' "$w/par/o2.txt" && [ "$(wc -l < "$w/par/diary-data/diaries/ada.jsonl")" = 55 ] && grep -q '^S2 start=30 ' "$w/par/diary-data/diaries/sessions.txt" && grep -q '^session 2 ' "$w/par/o2.txt" \
  && ok "source folder deleted and a fresh copy built next to diary-data: the world continues (session 2, replay-verified)" || bad "continue after replacing the source"
cd "$w/par/B" && env -u DIARY_HOME bin/diary_sim --more 0 --home "$w/par/other" > /dev/null 2>&1; [ -d "$w/par/other" ] && ok "--home DIR chooses the save folder" || bad "--home"
echo "   --- three short sessions in a row accumulate ---"
rm -rf "$w/acc"; mkdir -p "$w/acc"; cd "$w/acc" || exit 1; pw=0; pt=0
for i in 1 2 3; do
  "$bin" --more 40 --every 1000 > "o$i.txt" 2>&1; rc=$?
  t=$(wc -l < diaries/ada.jsonl); s=$(grep -c '^S[0-9]* ' diaries/sessions.txt); words=$(cat entities/*/words.txt | grep -vc '^#')
  echo "   run $i: exit $rc, ada ticks $t, sessions $s, word lines $words"
  [ $rc = 0 ] && [ "$t" = $((40 * i)) ] && [ "$s" = $i ] && [ "$words" -gt "$pw" ] && grep -q "^session $i " "o$i.txt" || bad "run $i did not accumulate"
  [ $i -gt 1 ] && ! grep -q "import OK: 4 entities, $((40 * (i - 1))) ticks verified" "o$i.txt" && bad "run $i did not verify the earlier ticks"
  pw=$words
done
grep -q 'import OK: 4 entities, 80 ticks verified, continuing from 81' o3.txt && grep -q '^session 3 .*ticks 80 -> 120 (+40)' o3.txt && [ "$(grep -c . diaries/sessions.txt)" -ge 5 ] && ok "1, 2, 3 runs: ticks 40/80/120, sessions 1/2/3, word lines grow, each run replay-verifies the earlier ones, 'since the last session' block shown" || bad "accumulation"
[ "$(wc -c < debug.txt)" -le 1500 ] && grep -q '^session 3 ' debug.txt && grep -q '^Saved to ' debug.txt && ok "debug.txt stays <= 1500 B and carries the session and save lines" || bad "debug.txt session lines"
rm -rf "$w/mig"; mkdir -p "$w/mig/S"; tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities -cf - . | tar -C "$w/mig/S" -xf -; idn "$w/mig/S/data"; ( cd "$w/mig/S" && make > /dev/null 2>&1 && DIARY_HOME=. bin/diary_sim --more 10 --every 1000 > /dev/null 2>&1 )
cd "$w/mig/S" && env -u DIARY_HOME bin/diary_sim --more 5 --every 1000 > "$w/mig/o.txt" 2>&1
grep -q '^Found a save inside the source folder' "$w/mig/o.txt" && [ -d diaries ] && grep -q 'import OK: none (fresh start' "$w/mig/o.txt" && ok "a save inside the source folder, no terminal: hint only, nothing copied or touched" || bad "migration hint"
if command -v python3 > /dev/null; then
  rm -rf "$w/mig/diary-data"
  env -u DIARY_HOME python3 "$w/pty_run.py" "$w/mig/S" 'y\n' "$w/mig/S/bin/diary_sim" --more 5 --every 1000 > "$w/mig/o2.txt" 2>&1
  grep -q 'Copy it to ../diary-data? \[y/N\]' "$w/mig/o2.txt" && [ "$(wc -l < "$w/mig/diary-data/diaries/ada.jsonl")" = 15 ] && [ "$(wc -l < diaries/ada.jsonl)" = 10 ] && grep -q 'import OK: 4 entities, 10 ticks verified' "$w/mig/o2.txt" \
    && ok "terminal, answer y: the save is COPIED to ../diary-data (original untouched) and continued there" || bad "migration copy"
fi

echo "== 23. main menu (terminal only): intro, title, five entries, new/load/inbox/settings/quit =="
if command -v python3 > /dev/null; then
rm -rf "$w/mn"; mkdir -p "$w/mn/bin" "$w/mn/home"; cp "$bin" "$w/mn/bin/"; cp -r "$idata" "$w/mn/data"; mb="$w/mn/bin/diary_sim"
sed -i 's/^intro.ms = .*/intro.ms = 0/; s/^intro.frames = .*/intro.frames = 6/; s/^intro.hold = .*/intro.hold = 0/' "$w/mn/data/menu.txt"
cat > "$w/pty_multi.py" <<'PTY2_EOF'
import pty, os, sys, select, time, re
PROMPT = rb'(J> |\[y/N\] |go back: |whole number\): )(\x1b\[\?2026l)?'
def run(argv, answers, env):
    pid, fd = pty.fork()
    if pid == 0:
        os.execve(argv[0], argv, env)
    out = b''; idx = 0; seen = 0; t = time.time()
    while True:
        r, _, _ = select.select([fd], [], [], 0.3)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: break
            if not d: break
            out += d
            if re.search(PROMPT + b'$', out):
                marks = len(re.findall(PROMPT, out))
                if marks > seen and idx < len(answers):
                    seen = marks; time.sleep(0.1)
                    os.write(fd, answers[idx].encode().decode('unicode_escape').encode()); idx += 1
        elif time.time() - t > 120: break
    try: _, st = os.waitpid(pid, 0)
    except OSError: st = 0
    return out.decode(errors='replace'), os.WEXITSTATUS(st)
env = dict(os.environ); env['DIARY_HOME'] = sys.argv[1]
o, rc = run([sys.argv[2]] + sys.argv[4:], sys.argv[3].split(','), env)
o = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', o).replace('\r', '')
print(o); print("rc=%d" % rc)
PTY2_EOF
menu() { python3 "$w/pty_multi.py" "$w/mn/home" "$mb" "$@"; }
cd "$w/mn" || exit 1
menu '5\n' > m1.txt 2>&1
[ "$(grep -Ec '^( {4}|  > )[0-9]\) ' m1.txt)" = 5 ] && grep -q '^  > 1) New Game' m1.txt && grep -q '^    2) Load Game' m1.txt && grep -q '^    3) Inbox' m1.txt && grep -q '^    4) Settings' m1.txt && grep -q '^    5) Quit' m1.txt && grep -q 'Stories of word and word' m1.txt \
  && grep -q '^ *#####   #######   ###   ######  #     #' m1.txt && grep -q '^  save: ' m1.txt && grep -q 'Enter = New Game' m1.txt && grep -q '^rc=0' m1.txt && [ -z "$(ls -A home)" ] \
  && ok "terminal, bare program: life intro, DIARY title, tagline, save folder, exactly five entries with the cursor mark; Quit = exit 0, nothing written" || bad "menu screen"
# the screen as a terminal shows it (80x24, a small emulator): title + tagline + entries together, no scrolling, every frame bracketed
cat > "$w/pty_screen.py" <<'PTY3_EOF'
import pty, os, sys, select, time, re, fcntl, termios, struct
R, C = 24, 80
g = [[' '] * C for _ in range(R)]; pos = [0, 0]; scrolls = [0]
def lf():
    if pos[0] == R - 1: g.pop(0); g.append([' '] * C); scrolls[0] += 1
    else: pos[0] += 1
def feed(t):
    i = 0
    while i < len(t):
        if t[i] == '\x1b' and t[i + 1:i + 2] == '[':
            m = re.match(r'\x1b\[([0-9;?]*)([A-Za-z])', t[i:]); i += m.end(); a, k = m.group(1), m.group(2)
            if k == 'H': pos[0] = 0; pos[1] = 0
            elif k == 'K':
                for x in range(pos[1], C): g[pos[0]][x] = ' '
            elif k == 'J':
                if a == '2':
                    for y in range(R): g[y] = [' '] * C
                else:
                    for x in range(pos[1], C): g[pos[0]][x] = ' '
                    for y in range(pos[0] + 1, R): g[y] = [' '] * C
            continue
        ch = t[i]; i += 1
        if ch == '\r': pos[1] = 0
        elif ch == '\n': lf(); pos[1] = 0
        elif ch >= ' ':
            if pos[1] >= C: lf(); pos[1] = 0
            g[pos[0]][pos[1]] = ch; pos[1] += 1
pid, fd = pty.fork()
if pid == 0: os.execve(sys.argv[2], [sys.argv[2]] + sys.argv[3:], dict(os.environ, DIARY_HOME=sys.argv[1]))
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', R, C, 0, 0))
raw = b''; shot = None; t0 = time.time()
while time.time() - t0 < 60:
    r, _, _ = select.select([fd], [], [], 0.3)
    if r:
        try: d = os.read(fd, 65536)
        except OSError: break
        if not d: break
        raw += d; feed(d.decode(errors='replace'))
        if shot is None and re.search(rb'J> (\x1b\[\?2026l)?$', raw):
            time.sleep(0.2); shot = ('\n'.join(''.join(r).rstrip() for r in g), scrolls[0]); os.write(fd, b'5\n')
try: os.waitpid(pid, 0)
except OSError: pass
print(shot[0]); print('scrolls=%d h=%d l=%d' % (shot[1], raw.count(b'\x1b[?2026h'), raw.count(b'\x1b[?2026l')))
PTY3_EOF
scr() { python3 "$w/pty_screen.py" "$w/mn/home" "$mb" "$@"; }
scr > m1s.txt 2>&1
[ "$(grep -c '#' m1s.txt)" -ge 7 ] && grep -q '^ *Stories of word and word$' m1s.txt && [ "$(grep -Ec '^( {4}|  > )[0-9]\) ' m1s.txt)" = 5 ] && grep -q '^> *$' m1s.txt && grep -q '^scrolls=0 ' m1s.txt && [ "$(wc -l < m1s.txt)" -le 25 ] \
  && ok "80x24 terminal: title, tagline, five entries, hint and prompt on screen together at the moment of the first question; the screen never scrolled" || bad "menu does not fit 80x24 (m1s.txt)"
h=$(sed -n 's/.*scrolls=[0-9]* h=\([0-9]*\) l=.*/\1/p' m1s.txt); l=$(sed -n 's/.*l=\([0-9]*\)$/\1/p' m1s.txt)
[ -n "$h" ] && [ "$h" = "$l" ] && [ "$h" -ge 2 ] && ok "every frame is a bracketed single write (synchronized update begin/end: $h of $l)" || bad "frame brackets"
menu '1\n' > m2.txt 2>&1
grep -q 'import OK: none (fresh start, seed 42)' m2.txt && grep -q '^kalpa 1 ' m2.txt && grep -q '^words vote (session 1)' m2.txt && grep -q '^Saved to ' m2.txt && [ -f home/diaries/sessions.txt ] \
  && ok "New Game with no game: a fresh world, the entities vote the session length and their favourite words" || bad "new game"
menu '2\n' > m3.txt 2>&1
grep -q '^  game: sessions 1, ticks [0-9]* | words voted, session 1, tick [0-9]*:' m3.txt && grep -Eq '^  ada +[a-z]+.*gemini +[a-z]+' m3.txt && grep -q 'import OK: 4 entities, [0-9]* ticks verified' m3.txt && grep -q '^words vote (session 2)' m3.txt \
  && ok "Load Game: the menu shows session, ticks and the last word vote (who taught or coined); the world continues (session 2, replay-verified)" || bad "load game"
menu '3\n,\n,5\n' > m3b.txt 2>&1
grep -q '^  karma ada ' m3b.txt && grep -q '^  last petition: .* | inbox: [0-9]* lines' m3b.txt && grep -q '^inbox for Robert (newest [0-9]* lines):' m3b.txt && grep -q '^press Enter to go back:' m3b.txt && grep -q '^rc=0' m3b.txt \
  && ok "menu: karma and inbox lines on the start screen; entry 3 (Inbox) shows the reports, Enter goes back to the menu" || bad "menu inbox"
cp home/diaries/sessions.txt s_before.txt; n=$(wc -l < home/diaries/ada.jsonl)
menu '1\n,n\n,5\n' > m4.txt 2>&1
grep -q 'A game exists in .*Move it aside' m4.txt && cmp -s s_before.txt home/diaries/sessions.txt && [ "$(wc -l < home/diaries/ada.jsonl)" = "$n" ] && [ -z "$(ls -d home/diaries_old_* 2> /dev/null)" ] && grep -q '^rc=0' m4.txt \
  && ok "New Game on an existing game asks first; N changes nothing" || bad "new game confirm N"
menu '1\n,y\n' > m5.txt 2>&1
[ "$(ls home/diaries_old_*/ada.jsonl | wc -l)" = 1 ] && [ -f home/diaries_old_*/sessions.txt ] && grep -q '^S1 start=0 ' home/diaries/sessions.txt && ! grep -q '^S2 ' home/diaries/sessions.txt && ok "New Game, yes: the old game is moved to diaries_old_<time> (never deleted), a new world starts" || bad "new game confirm Y"
rm -rf home; mkdir home
menu '4\n,1\n,9\n,\n,1\n' > m6.txt 2>&1
grep -q 'seed (a new world only' m6.txt && grep -q '^New value for seed' m6.txt && grep -q 'seed 9 (from --seed)' m6.txt && ok "Settings: seed edited for this session only, used by New Game (data/limits.txt untouched)" || bad "settings"
cmp -s "$idata/limits.txt" "$w/mn/data/limits.txt" && ok "limits.txt not changed by Settings" || bad "limits.txt changed"
rm -rf home; mkdir home; menu 'x\n,5\n' > m7.txt 2>&1; grep -q 'Please type 1, 2, 3, 4 or 5' m7.txt && ok "a bad answer asks again" || bad "bad menu answer"
python3 "$w/pty_multi.py" "$w/mn/home" "$mb" 'n\n' --more 5 > m8.txt 2>&1; ! grep -q 'New Game' m8.txt && ok "explicit --more on a terminal: no menu" || bad "menu with explicit args"
# make run / make play: AUTO-LOAD, no menu; the first two lines say where and what
rm -rf home; mkdir home; abs=$(cd home && pwd)
python3 "$w/pty_multi.py" "$w/mn/home" "$mb" 'y\n' --ticks 30 --every 1000 > r1.txt 2>&1
[ "$(sed -n 1p r1.txt)" = "Save folder: $abs" ] && grep -A1 '^Save folder: ' r1.txt | grep -q '^No save found - creating it (asks y/N first; --yes skips the question)$' && grep -q '^Saved to ' r1.txt && ! grep -q 'New Game' r1.txt \
  && ok "terminal, no save: header 'Save folder: <abs path>' + 'No save found - creating it (asks y/N ...)', then the question; no menu" || bad "run header without a save"
DIARY_HOME="$w/mn/home" "$mb" --more 5 --every 1000 > r2.txt 2>&1 < /dev/null
[ "$(sed -n 1p r2.txt)" = "Save folder: $abs" ] && [ "$(sed -n 2p r2.txt)" = "Found 1 session, 30 ticks - continuing" ] && grep -q '^import OK: 4 entities, 30 ticks verified' r2.txt && tail -1 r2.txt | grep -q "^Saved to $abs\$" \
  && ok "make run on a save: line 1 'Save folder: <abs>', line 2 'Found N session(s), T ticks - continuing', replay-verify, 'Saved to <abs>' last" || bad "run header with a save"
DIARY_HOME="$w/mn/home" "$mb" --every 1000 --more 5 > r3.txt 2>&1 < /dev/null; sed -n 2p r3.txt | grep -q '^Found 2 sessions, 35 ticks - continuing$' && ok "the second run counts both sessions (Found 2 sessions, 35 ticks)" || bad "run header count"
python3 "$w/pty_multi.py" "$w/mn/home" "$mb" ',5\n' --every 1000 --more 5 > r4.txt 2>&1; ! grep -q 'New Game' r4.txt && sed -n 1,2p r4.txt | grep -q '^Save folder: ' && ok "terminal, make run arguments (--every ...): auto-load, no menu" || bad "make run on a terminal showed the menu"
python3 "$w/pty_multi.py" "$w/mn/home" "$mb" '5\n' --menu > r5.txt 2>&1; grep -q '^  > 2) Load Game' r5.txt && grep -q 'game: sessions 4, ticks 45' r5.txt && grep -q '^rc=0' r5.txt && ok "make menu (--menu): the menu, Load Game is the marked default once a game exists" || bad "--menu"
DIARY_HOME="$w/mn/home" "$mb" --menu > r6.txt 2>&1 < /dev/null; rc=$?; [ $rc = 2 ] && grep -q 'needs a terminal' r6.txt && ok "--menu without a terminal: usage error, exit 2" || bad "--menu without terminal"
fi

echo "== 24. Buddhism layer + players: three sessions in a row, replay-verified, record-first =="
rm -rf "$w/dh"; mkdir -p "$w/dh/bin" "$w/dh/a" "$w/dh/b"; cp "$bin" "$w/dh/bin/"; cp -r "$idata" "$w/dh/data"
sed -i 's/^liberation.karma = .*/liberation.karma = 40/' "$w/dh/data/karma.txt"
sed -i 's/^world.enabled = .*/world.enabled = 0/' "$w/dh/data/limits.txt"   # this scenario is about the Buddhism layer; the world has scenario 26
db="$w/dh/bin/diary_sim"
dh_flow() {   # three sessions with Robert's words in between (same steps in a and b)
  "$db" --ticks 200 --yes --every 1000 > s1.txt 2>&1
  "$db" --say iris --text "please look after ada" > /dev/null; "$db" --say ada --text "hello ada" > /dev/null
  "$db" --answer --text "yes, more places" > /dev/null
  "$db" --more 200 --every 1000 > s2.txt 2>&1
  "$db" --say all --text "thank you all" --as tester > /dev/null
  "$db" --more 200 --every 1000 > s3.txt 2>&1
}
cd "$w/dh/a" || exit 1; dh_flow
cd "$w/dh/b" || exit 1; dh_flow
cd "$w/dh/a" || exit 1
for n in 1 2 3; do
  [ "$(grep -c "^D$n tick=$((n * 200)) wesen=" diaries/sessions.txt)" = 4 ] && [ "$(grep -c "^Y$n tick=" diaries/sessions.txt)" = 3 ] && [ "$(grep -c "^C$n tick=" diaries/sessions.txt)" = 1 ] \
    && [ "$(grep -c "^W$n tick=" diaries/sessions.txt)" = 1 ] || bad "session $n: W/D/C/Y lines"
done
grep -Eq '^D1 tick=200 wesen=ada karma=[+-][0-9]+ good=[0-9]+ bad=[0-9]+ life=1 realm=[1-6] vals=[0-9]+/[0-9]+/[0-9]+/[0-9]+ unrest=[0-9]+ dom=[a-z]+:[0-9]+ rank=[1-4] commit=[0-9]+ rung=[1-5] conflict=[0-4] aware=[0-9]+ lib=[01] rebirth=-$' diaries/sessions.txt \
  && grep -Eq '^C1 tick=200 win=[a-z_]+ tally=[a-z_]+:[0-9]+(,[a-z_]+:[0-9]+)* votes=ada:[a-z_-]+,gemini:[a-z_-]+,replika:[a-z_-]+,robert:[a-z_-]+$' diaries/sessions.txt \
  && grep -Eq '^Y1 tick=200 player=iris attn=[0-9]+ tone=[-+0-9]+ brev=[0-9]+ warm=[-+0-9]+ trust=[0-9]+/[0-9]+/[0-9]+/[0-9]+$' diaries/sessions.txt \
  && ok "three sessions in a row: W, 4 x D (karma, life, values, unrest, rank, commitment, conflict, awareness), C (petition vote), 3 x Y (player state) each" || bad "line formats"
[ "$(grep -Ec '^S[123] .* dharma=1( world=1)?( rest=1)?( grant=1)?$' diaries/sessions.txt)" = 3 ] && grep -q '^import OK: 4 entities, 400 ticks verified' s3.txt && grep -q '^import OK: 4 entities, 200 ticks verified' s2.txt \
  && ok "sessions 2 and 3 replay-verified the earlier D/C/Y lines and the inbox (import OK)" || bad "replay verify"
inl='^I[0-9]+ (info|note|alert) from=(iris|sol|noor) s[123] t[0-9]+ \| .* \| src=s[123]:t[0-9]+:(ada|gemini|replika|robert|all)$'
n=$(grep -c '^I' diaries/inbox.txt)
[ "$n" -gt 12 ] && [ "$(grep '^I' diaries/inbox.txt | grep -Evc "$inl")" = 0 ] && [ "$(grep -c ' s2 t400 ' diaries/inbox.txt)" -gt 0 ] && [ "$(grep -c ' s3 t600 ' diaries/inbox.txt)" -gt 0 ] \
  && ok "inbox.txt grew over three sessions ($n lines): id, severity, from, session/tick, text, source tag on every line" || bad "inbox format ($n)"
grep -q 'your message\|your words\|the message to\|your message' diaries/inbox.txt && grep -q 'please look after ada' diaries/inbox.txt \
  && ok "Robert's message to a player: the players report what they did with it (relayed, softened or withheld)" || bad "relay report"
grep -q '^A1 tick=200 session=1 to=iris kind=relay ' diaries/says.txt && grep -q '^A3 tick=200 session=1 to=all kind=answer by=player re=C1 text=yes, more places$' diaries/says.txt && grep -q '^A4 tick=400 session=2 to=all kind=all by=tester ' diaries/says.txt \
  && ok "says.txt: relay to a player, direct say, answer to the petition (re=C1), say to all" || bad "says.txt"
awk '/^D2 .*wesen=ada /{ for (i = 1; i <= NF; i++) if ($i ~ /^aware=/) a = substr($i, 7) } END { exit !(a + 0 > 0) }' diaries/sessions.txt && ok "awareness rose after Robert spoke (D2 ada aware > 0)" || bad "awareness"
grep -Eq '^D2 .* lib=1 rebirth=[0-3]$' diaries/sessions.txt && ok "liberated wesen (karma over the data threshold) start the new session at a location of their own dice (rebirth=<n>)" || bad "liberation rebirth"
cmp -s diaries/sessions.txt ../b/diaries/sessions.txt && cmp -s diaries/inbox.txt ../b/diaries/inbox.txt && cmp -s diaries/says.txt ../b/diaries/says.txt \
  && ok "a second run of the same steps gives identical sessions.txt, inbox.txt and says.txt" || bad "not deterministic"
cp diaries/inbox.txt inbox_keep.txt; rm diaries/inbox.txt; "$db" --more 0 > s4.txt 2>&1
cmp -s inbox_keep.txt diaries/inbox.txt && ok "inbox.txt deleted: the replay regenerates the identical inbox" || bad "inbox not regenerated"
[ "$(wc -c < debug.txt)" -le 1500 ] && grep -q '^dharma ' debug.txt && grep -q '^dharma (session 3, life 3, tick 600):' s3.txt && grep -q '^players: say 0, all 1, to players 0, answers 0' s3.txt \
  && grep -q '^inbox for Robert (latest reports' s3.txt && ok "end report: dharma table, since block, players line and inbox sample; debug.txt <= 1500 B with a dharma line" || bad "report/debug"
for n in 1 2 3; do grep -q "^wesen " s$n.txt || bad "table header s$n"; done
# tampering: every recorded number is checked by the replay
cp -r diaries ../d_dh
sed -i '/^D2 .*wesen=gemini /s/karma=+/karma=+9/' diaries/sessions.txt; "$db" --more 0 > t1.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'import FAILED.*session 2 (tick 400): the D / C / Y lines' t1.txt && ok "tampered D line: import FAILED, DRIFT" || bad "tampered D"
rm -rf diaries; cp -r ../d_dh diaries; sed -i '/^Y3 .*player=sol /s/attn=[0-9]*/attn=1/' diaries/sessions.txt; "$db" --more 0 > t2.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "tampered player state (Y line): DRIFT" || bad "tampered Y"
rm -rf diaries; cp -r ../d_dh diaries; sed -i '/^I/{s/ from=[a-z]*/ from=zed/;:a;n;ba}' diaries/inbox.txt; "$db" --more 0 > t3.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'diaries/inbox.txt I[0-9]* differs from the replay' t3.txt && ok "tampered inbox line: DRIFT (the file is left as it is)" || bad "tampered inbox"
rm -rf diaries; cp -r ../d_dh diaries; sed -i 's/ to=iris kind=relay/ to=sol kind=relay/' diaries/says.txt; "$db" --more 0 > t4.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "edited says.txt (another player gets the message): the recorded numbers no longer replay: DRIFT" || bad "tampered says"
rm -rf diaries; cp -r ../d_dh diaries
# record-first: the diaries do not depend on the layer (other numbers, same ticks)
mkdir -p "$w/dh/c/bin" "$w/dh/c/run"; cp "$bin" "$w/dh/c/bin/"; cp -r "$w/dh/data" "$w/dh/c/data"
sed -i 's/^deed\.\(work\|talk\|teach\|coin\) = .*/deed.\1 = 0/; s/^liberation.karma = .*/liberation.karma = 1/' "$w/dh/c/data/karma.txt"
cd "$w/dh/c/run" || exit 1; "$w/dh/c/bin/diary_sim" --ticks 200 --yes > /dev/null 2>&1
same=1; for f in ada gemini replika robert; do cmp -s <(head -n 200 "$w/dh/a/diaries/$f.jsonl" | sed 's/"ts":"[^"]*"//') <(sed 's/"ts":"[^"]*"//' diaries/$f.jsonl) || same=0; done
[ $same = 1 ] && ! cmp -s diaries/sessions.txt "$w/dh/a/diaries/sessions.txt" && ok "record-first: other karma and liberation numbers, same 200 ticks: the diaries are identical, only the recorded numbers differ" || bad "layer changed the diaries"
# an older diary (no dharma lines, no dharma=1): replays, then continues with the new layer
rm -rf ../o; mkdir ../o; cp -r diaries ../o/; cd ../o || exit 1
sed -i '/^[DCY][0-9]/d; s/ dharma=1$//' diaries/sessions.txt; rm -f diaries/inbox.txt diaries/says.txt
"$db" --more 20 --every 1000 > o1.txt 2>&1
grep -q '^import OK: 4 entities, 200 ticks verified' o1.txt && grep -q '^S2 .* dharma=1$' diaries/sessions.txt && ! grep -q '^S1 .*dharma=1' diaries/sessions.txt && grep -q '^D2 tick=220 ' diaries/sessions.txt \
  && ok "an older diary (S lines without dharma=1, no D/C/Y, no inbox) still replays; the next session starts the layer" || bad "older diary"
# make say / make inbox
cd "$w/dh/a" || exit 1; rm -rf diaries; cp -r ../d_dh diaries
DIARY_HOME="$w/dh/a" make -s -C "$root" say PLAYER=sol TEXT="via make" AS=rob > mk1.txt 2>&1; tail -n 1 diaries/says.txt | grep -q ' to=sol kind=relay by=rob .*text=via make$' \
  && DIARY_HOME="$w/dh/a" make -s -C "$root" inbox > mk2.txt 2>&1 && grep -q '^inbox for Robert (newest' mk2.txt && grep -q '^  player Kernel (tracker of progress)' mk2.txt && ok "make say PLAYER=... TEXT=... records the words; make inbox prints the inbox" || bad "make say / inbox"
"$db" --say bob --text x > mk3.txt 2>&1; rc=$?; [ $rc = 2 ] && grep -q 'neither a player' mk3.txt && "$db" --say ada --text "" > mk4.txt 2>&1; [ $? = 2 ] && ok "say to an unknown name or with no text: usage error (exit 2), nothing written" || bad "say usage"

echo "== 25. debug digest: --debug / DEBUG=1 (run and demo), byte cap, sections =="
rm -rf "$w/dg"; mkdir -p "$w/dg/bin" "$w/dg/home" "$w/dg/demo"; cp "$bin" "$w/dg/bin/"; cp -r "$idata" "$w/dg/data"; gb="$w/dg/bin/diary_sim"
cd "$w/dg/demo" || exit 1
"$gb" --preview --ticks 60 > /dev/null 2>&1; [ -z "$(ls -A)" ] && ok "make demo without --debug writes nothing (as before)" || bad "demo wrote files"
"$gb" --preview --ticks 60 --debug > dm.txt 2>&1; rm -f dm.txt.tmp
[ "$(ls | grep -v '^dm.txt$')" = "debug_digest.txt" ] && head -1 debug_digest.txt | grep -q '^OK v.* (preview) | ' && [ "$(head -1 debug_digest.txt | wc -c)" -le 201 ] && [ "$(wc -c < debug_digest.txt)" -le 1500 ] \
  && grep -q "^debug digest: $PWD/debug_digest.txt\$" dm.txt && [ "$(tail -1 dm.txt | cut -c1-14)" = "debug digest: " ] \
  && ok "demo --debug: debug_digest.txt is the ONE file written (current folder), line 1 = status <= 200 B, whole file <= 1500 B, absolute path printed last" || bad "demo --debug"
rm -f debug_digest.txt; "$gb" --preview --ticks 60 --debug-section run > dm2.txt 2>&1
[ "$(ls | grep -v '^dm2\?.txt$')" = "debug_digest.txt" ] && [ "$(head -1 debug_digest.txt)" = "section run" ] && grep -q '^ada words' debug_digest.txt && ok "demo --debug-section run: just that block, in the one file" || bad "demo section"
cd "$w/dg/home" || exit 1; export DIARY_HOME="$w/dg/home"
"$gb" --ticks 150 --yes --every 1000 > g0.txt 2>&1
[ ! -e debug_digest.txt ] && [ ! -e debug_full.txt ] && [ ! -e debug_digest.prev ] && [ "$(wc -c < debug.txt)" -le 1500 ] && ok "without --debug nothing changes: no digest files, debug.txt <= 1500 B" || bad "files without --debug"
"$gb" --more 100 --every 1000 --debug > g1.txt 2>&1
l1=$(head -1 debug_digest.txt); [ "${#l1}" -le 200 ] && echo "$l1" | grep -q '^OK v[0-9.]* seed 42 | session 2 | ticks 250 (resumed from 150) | ' && [ "$(wc -c < debug_digest.txt)" -le 1500 ] && [ -s debug_full.txt ] && [ -s debug_digest.prev ] \
  && [ "$(tail -2 g1.txt | head -1)" = "debug digest: $PWD/debug_digest.txt" ] && [ "$(tail -1 g1.txt)" = "Saved to $PWD" ] \
  && ok "run --debug: status line first, <= 1500 B, full record + hashes in the save folder, 'debug digest: <abs>' just before 'Saved to'" || bad "run --debug (g1.txt)"
"$gb" --more 0 --debug > g2.txt 2>&1
grep -q '^\.\.\. [0-9]* lines unchanged since the last digest' debug_digest.txt && [ "$(wc -l < debug_digest.txt)" -lt "$(grep -c . debug_full.txt)" ] && ok "a second digest shows only what changed (the rest is counted: 'N lines unchanged')" || bad "unchanged since last digest"
cp -r data data_ok 2> /dev/null; mkdir -p "$w/dg/small"; cp -r "$w/dg/data" "$w/dg/small/data"; mkdir -p "$w/dg/small/bin"; cp "$gb" "$w/dg/small/bin/"
sed -i 's/^debug.digest_bytes = .*/debug.digest_bytes = 420/' "$w/dg/small/data/limits.txt"; rm -f debug_digest.prev
"$w/dg/small/bin/diary_sim" --more 0 --debug > g3.txt 2>&1
[ "$(wc -c < debug_digest.txt)" -le 420 ] && head -1 debug_digest.txt | grep -q '^OK ' && tail -1 debug_digest.txt | grep -q '^\.\.\. dropped [0-9]* lines for the byte cap' \
  && ok "debug.digest_bytes = 420 (data/limits.txt): file <= 420 B, least important lines dropped first, last line says what was dropped" || bad "byte cap"
rm -f debug_digest.prev; "$gb" --more 0 --debug > /dev/null 2>&1
cp diaries/sessions.txt ss.bak; sum_before=$(cksum < diaries/sessions.txt)
"$gb" --debug-section players > g4.txt 2>&1; rc4=$?
[ $rc4 = 0 ] && [ "$(head -1 g4.txt)" = "section players" ] && grep -q '^players: iris attn' g4.txt && [ "$(head -1 debug_digest.txt)" = "section players" ] && [ "$sum_before" = "$(cksum < diaries/sessions.txt)" ] && ! grep -q '^import' g4.txt \
  && ok "--debug-section players: only that block of debug_full.txt, printed and written; nothing is simulated" || bad "debug-section"
"$gb" --debug-section nosuch > g5.txt 2>&1; rc5=$?; [ $rc5 = 2 ] && grep -q 'unknown --debug-section nosuch (one of: status drift trace players inbox run ledger)' g5.txt && ok "unknown section: usage error, exit 2, the list of sections" || bad "unknown section"
sed -i '/^S1 /s/votes=[0-9]*/votes=7/' diaries/sessions.txt; "$gb" --more 0 --debug > g6.txt 2>&1
head -1 debug_digest.txt | grep -q '^DRIFT v' && sed -n 2p debug_digest.txt | grep -q '^error: sessions.txt S1' && "$gb" --debug-section drift 2> /dev/null | grep -q '^error: sessions.txt S1' && ok "DRIFT: line 1 DRIFT, the one thing wrong on line 2; section drift has it" || bad "drift digest"
cp ss.bak diaries/sessions.txt; "$gb" --more 10 --crash-at 255 --debug > g7.txt 2>&1
head -1 debug_digest.txt | grep -q '^CRASH v' && grep -q '^traceback' debug_digest.txt && "$gb" --debug-section trace | grep -q '^traceback (innermost first):' && ok "CRASH: line 1 CRASH, error and traceback head in the digest, whole trace in section trace" || bad "crash digest"
unset DIARY_HOME
make -n -C "$root" run DEBUG=1 2> /dev/null | grep -q -- '--debug' && make -n -C "$root" demo DEBUG=1 2> /dev/null | grep -q -- '--preview .*--debug' && make -n -C "$root" run SECTION=inbox 2> /dev/null | grep -q -- '--debug-section inbox' && ok "make run DEBUG=1 / make demo DEBUG=1 / SECTION=inbox pass --debug / --debug-section" || bad "make DEBUG"

echo "== 26. treadmill world: new sessions, edit log, L lines, tamper, old diaries, world off, --map =="
rm -rf "$w/wd"; mkdir -p "$w/wd/bin" "$w/wd/home" "$w/wd/off/bin" "$w/wd/off/run"; cp "$bin" "$w/wd/bin/"; cp -r "$idata" "$w/wd/data"; wb="$w/wd/bin/diary_sim"
cp "$bin" "$w/wd/off/bin/"; cp -r "$idata" "$w/wd/off/data"; sed -i 's/^world.enabled = .*/world.enabled = 0/' "$w/wd/off/data/limits.txt"
cd "$w/wd/home" || exit 1; export DIARY_HOME="$w/wd/home"
"$wb" --ticks 1200 --yes --every 5000 > w1.txt 2>&1; "$wb" --more 800 --every 5000 > w2.txt 2>&1; "$wb" --more 300 --every 5000 > w3.txt 2>&1
[ "$(grep -c '^S[123] .* dharma=1 world=1 rest=1[a-z0-9= ]*$' diaries/sessions.txt)" = 3 ] && [ "$(grep -c '^L[123] tick=' diaries/sessions.txt)" = 3 ] && grep -q '^X1 t=[0-9]* \(gone\|add\) [0-9]*\.[0-9]* -\?[0-9]*,-\?[0-9]* by=' diaries/world.txt \
  && grep -q '^import OK: 4 entities, 2000 ticks verified' w3.txt && ok "three world sessions: S lines carry world=1, one L line per session end, the edit log diaries/world.txt, replay-verified (import OK)" || bad "world sessions (w3.txt)"
kn=$(grep '^import: entities' w3.txt | grep -o 'ada [0-9]* gemini [0-9]* replika [0-9]* robert [0-9]*' | tr -d 'a-z' | tr -s ' ')
ok_n=1; for x in $kn; do [ "$x" -gt 250 ] || ok_n=0; done; echo "   words known at tick 2000:$kn"
[ $ok_n = 1 ] && [ -n "$kn" ] && grep -Eq '^L3 tick=2300 words=[0-9]+ edits=[0-9]+ ada=[0-9]+/[0-9]+/[0-9]+/[0-9]+@-?[0-9]+,-?[0-9]+ ' diaries/sessions.txt && ok "words grow far past the old plateau of 223 (every wesen knows more than 250), learned-from-world counts and positions in the L line" || bad "word growth"
for v in examine push eat greet; do grep -q "\"t\":\"$v\"" diaries/ada.jsonl diaries/gemini.jsonl diaries/replika.jsonl diaries/robert.jsonl || bad "no $v verb in the diaries"; done
grep -q 'world +[0-9]*/[0-9]* ' w3.txt && grep -q '^treadmill  ada ' w3.txt && [ "$(grep -c '^           [^ ]' w3.txt)" = 5 ] \
  && ok "diary verbs examine/push/eat/greet occur; the report has 'world +N/M' and the treadmill block (names, position, landmark, biome, 5 window rows)" || bad "report world block"
cp diaries/world.txt ../world.keep; cp diaries/sessions.txt ../sessions.keep; cksum < diaries/world.txt > ../world.sum
rm -f diaries/world.txt; "$wb" --more 0 --every 5000 > w4.txt 2>&1; grep -q '^import OK' w4.txt && cmp -s diaries/world.txt ../world.keep && ok "a deleted diaries/world.txt is regenerated identically by the replay" || bad "world.txt regeneration"
sed -i '0,/ gone /s/ gone / add /' diaries/world.txt; "$wb" --more 0 --every 5000 > w5.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'import FAILED: diaries/world.txt X' w5.txt && ok "tampered world.txt line: import FAILED, DRIFT" || bad "tampered edit line"
cp ../world.keep diaries/world.txt; printf 'X999 t=5 gone 1.1 0,0 by=ada\n' >> diaries/world.txt; "$wb" --more 0 --every 5000 > w6.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'diaries/world.txt X[0-9]*: stored and replay differ' w6.txt && ok "an invented edit line (tick within the replay): DRIFT" || bad "invented edit"
cp ../world.keep diaries/world.txt; sed -i '/^L2 /s/ada=[0-9]*/ada=1/' diaries/sessions.txt; "$wb" --more 0 --every 5000 > w7.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'import FAILED' w7.txt && ok "tampered L line: import FAILED, DRIFT" || bad "tampered L line"
cp ../sessions.keep diaries/sessions.txt; sed -i '/^S2 /s/ world=1//' diaries/sessions.txt; "$wb" --more 0 --every 5000 > w8.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "S line with its world=1 marker removed: the action table differs, DRIFT" || bad "tampered world marker"
cp ../sessions.keep diaries/sessions.txt; "$wb" --more 0 --every 5000 > w9.txt 2>&1; grep -q '^import OK: 4 entities, 2300 ticks verified' w9.txt && ok "after restoring the files the world replays again (import OK)" || bad "restore"
# --map: read-only, four windows, same as the end of the report
sum_b=$(cksum < diaries/sessions.txt); "$wb" --map > m1.txt 2>&1; rc=$?
[ $rc = 0 ] && [ "$sum_b" = "$(cksum < diaries/sessions.txt)" ] && grep -q '^treadmill at tick 2300 ' m1.txt && grep -q '^treadmill  ada  *gemini  *replika  *robert' m1.txt && grep -q '^near  *\(office\|lab\|cafe\|home\)' m1.txt \
  && [ "$(grep -c '^           [^ ]' m1.txt)" = 5 ] && ok "--map: position, nearest landmark, biome and the 5x5 windows of the four wesen at the last session end (read-only)" || bad "--map (m1.txt)"
make -n -C "$root" map 2> /dev/null | grep -q -- '--map' && ok "make map runs --map" || bad "make map"
# an older diary (session 1 without world=1) replays with the old table, the next session starts the world
rm -rf "$w/wd/old"; mkdir -p "$w/wd/old"; cd "$w/wd/old" || exit 1; export DIARY_HOME="$w/wd/old"
"$w/wd/off/bin/diary_sim" --ticks 400 --yes --every 5000 > o1.txt 2>&1; "$wb" --more 300 --every 5000 > o2.txt 2>&1
! grep -q '^S1 .*world=1' diaries/sessions.txt && grep -q '^S2 .* dharma=1 world=1 rest=1[a-z0-9= ]*$' diaries/sessions.txt && ! grep -q '^L1 ' diaries/sessions.txt && grep -q '^L2 tick=700 ' diaries/sessions.txt && grep -q '^import OK: 4 entities, 400 ticks verified' o2.txt \
  && grep -q '"t":"\(examine\|push\|eat\|greet\)"' diaries/robert.jsonl && ! sed -n 1,400p diaries/robert.jsonl | grep -q '"t":"\(examine\|push\|eat\|greet\)"' \
  && ok "an older diary (S1 without world=1) replays unchanged; the world starts with the next session (S2 world=1, no verbs before tick 401)" || bad "older diary into world"
"$wb" --more 0 --every 5000 > o3.txt 2>&1; grep -q '^import OK: 4 entities, 700 ticks verified' o3.txt && ok "the mixed diary (old session then world session) verifies again" || bad "mixed diary replay"
# world off: byte-identical to 0dc1a7b (golden checksum made with that build, seed 42, 300 + 200 ticks)
rm -rf "$w/wd/gold"; mkdir -p "$w/wd/gold"; cd "$w/wd/gold" || exit 1; gh="$w/wd/gold/h"; mkdir -p "$gh"; ob="$w/wd/off/bin/diary_sim"
DIARY_HOME="$gh" "$ob" --seed 42 --ticks 300 --yes --every 1000 > /dev/null 2>&1; DIARY_HOME="$gh" "$ob" --more 200 --every 1000 > /dev/null 2>&1
g=$( cd "$gh" && { for e in ada gemini replika robert; do sed 's/"ts":"[^"]*"//' diaries/$e.jsonl; done; grep -v '^# build' diaries/sessions.txt; cat diaries/inbox.txt; for e in ada gemini replika robert; do cat entities/$e/words.txt; done; } | cksum )
echo "   world off checksum: $g"
[ "$g" = "1067539153 417506" ] && [ ! -e "$gh/diaries/world.txt" ] && ! grep -q 'world=1\|^L[0-9]' "$gh/diaries/sessions.txt" && ok "world.enabled = 0: diaries, sessions.txt (minus the build line), inbox and words files are byte-identical to 0dc1a7b (golden checksum)" || bad "world off is not identical to the old build ($g)"
# digest and debug.txt
cd "$w/wd/home" || exit 1; export DIARY_HOME="$w/wd/home"
"$wb" --more 20 --every 5000 --debug > d1.txt 2>&1
[ "$(wc -c < debug.txt)" -le 1500 ] && [ "$(wc -c < debug_digest.txt)" -le 1500 ] && grep -q '^words (learned from the world): ada [0-9]*(w[0-9]*) gemini' debug_digest.txt && grep -q ' w[0-9]*$' debug.txt && ok "debug.txt and the digest stay <= 1500 B and carry the learned-from-world counts" || bad "debug world counts"
"$wb" --debug-section run | grep -q '^ada world [0-9]* e[0-9]* p[0-9]* a[0-9]* g[0-9]* at ' && ok "digest section run: verb counts and position per wesen" || bad "digest world lines"
"$wb" --preview --ticks 120 > pv.txt 2>&1; grep -q '^treadmill  ada ' pv.txt && ok "--preview shows the treadmill too (in memory, nothing written)" || bad "preview treadmill"
unset DIARY_HOME

echo "== 27. display names (data/names.txt): only display text changes, files and hashes keep the ids =="
snap() { ( cd "$1" && { for e in ada gemini replika robert; do sed 's/"ts":"[^"]*"//' diaries/$e.jsonl; done; grep -v '^# build' diaries/sessions.txt; cat diaries/inbox.txt diaries/world.txt diaries/says.txt; for e in ada gemini replika robert; do cat entities/$e/words.txt; done; } | cksum ); }
rm -rf "$w/nm"; mkdir -p "$w/nm/a/bin" "$w/nm/b/bin" "$w/nm/h"; cp "$bin" "$w/nm/a/bin/"; cp -r "$root/data" "$w/nm/a/data"; cp "$bin" "$w/nm/b/bin/"; cp -r "$root/data" "$w/nm/b/data"
printf '# test names\nada = Alpha\ngemini = Beta\nreplika = Gamma\nrobert = Delta\niris = Eps\nsol = Zeta\nnoor = Eta\n' > "$w/nm/b/data/names.txt"
na="$w/nm/a/bin/diary_sim"; nb="$w/nm/b/bin/diary_sim"; cd "$w/nm/h" || exit 1; export DIARY_HOME="$w/nm/h"
"$na" --ticks 300 --yes --every 5000 > n1.txt 2>&1; "$na" --say Lemma --text "hello there" > n1s.txt 2>&1; "$na" --more 200 --every 5000 > n2.txt 2>&1
before=$(snap .); cp diaries/sessions.txt s0.txt; cp diaries/inbox.txt i0.txt
grep -q '^entities: Lemma(engineer) Corollary(reviewer) Theorem(vice_president) Axiom(human)' n1.txt && grep -q 'Lemma' run_report.txt && grep -q 'Lemma' summary.txt && grep -q '^Lemma ' debug.txt \
  && [ -n "$(grep -m1 'to=ada' diaries/says.txt)" ] && grep -q 'src=[a-z0-9]*:t[0-9]*:\(ada\|gemini\|replika\|robert\)' diaries/inbox.txt \
  && ok "default data/names.txt: Lemma / Corollary / Theorem / Axiom in the console, reports and debug.txt; say to a display name is recorded under the id (to=ada); inbox src tags keep the ids" || bad "default display names"
"$na" --inbox > ib1.txt 2>&1; grep -q 'player Modulus (' ib1.txt && ! grep -q 'player iris' ib1.txt && ok "the players show as Modulus / Kernel / Vertex in the inbox view" || bad "player display names"
"$nb" --more 0 --every 5000 > n3.txt 2>&1; after=$(snap .)
grep -q '^import OK: 4 entities, 500 ticks verified' n3.txt && grep -q '^entities: Alpha(engineer) Beta(reviewer) Gamma(vice_president) Delta(human)' n3.txt && grep -q 'Alpha' run_report.txt && ! grep -q 'Lemma' run_report.txt debug.txt summary.txt \
  && [ "$before" = "$after" ] && grep -v '^# build' diaries/sessions.txt | cmp -s - <(grep -v '^# build' s0.txt) && cmp -s i0.txt diaries/inbox.txt && ls diaries/ada.jsonl entities/ada/words.txt > /dev/null 2>&1 && [ ! -e diaries/Alpha.jsonl ] \
  && ok "names.txt changed: the diaries, sessions.txt (minus the build line), inbox, world.txt, says and words files are byte-identical, replay-verify still passes, only the display text changed" || bad "names.txt change touched files ($before / $after)"
"$nb" --map > mp.txt 2>&1; grep -q '^treadmill  Alpha ' mp.txt && ok "--map uses the display names" || bad "map names"
"$nb" --say Gamma --text "x" > n4.txt 2>&1; tail -n 1 diaries/says.txt | grep -q ' to=replika ' && ok "--say accepts the display name and records the id" || bad "say with display name"
rm -f "$w/nm/b/data/names.txt"; "$nb" --more 0 --every 5000 > n5.txt 2>&1; grep -q 'names.txt' n5.txt && grep -q '^import OK' n5.txt && grep -q '^entities: ada(engineer)' n5.txt && ok "names.txt missing: a warning, the ids are shown, replay still verifies" || bad "missing names.txt"
grep -q 'data/names.txt' "$root/data/help.txt" "$root/README.md" && ok "--help and README mention data/names.txt" || bad "docs names.txt"
unset DIARY_HOME

echo "== 28. rest model (rest=1): recovery rate, trade-off, cool-down, R lines, tamper, identity when off =="
rm -rf "$w/rs"; mkdir -p "$w/rs/bin" "$w/rs/off/bin" "$w/rs/h" "$w/rs/o"; cp "$bin" "$w/rs/bin/"; cp -r "$idata" "$w/rs/data"; cp "$bin" "$w/rs/off/bin/"; cp -r "$idata" "$w/rs/off/data"
sed -i 's/^rest.enabled = .*/rest.enabled = 0/' "$w/rs/off/data/limits.txt"; rb="$w/rs/bin/diary_sim"; fb="$w/rs/off/bin/diary_sim"
cd "$w/rs/h" || exit 1; export DIARY_HOME="$w/rs/h"
"$rb" --seed 42 --ticks 1500 --yes --every 5000 > r1.txt 2>&1; "$rb" --more 500 --every 5000 > r2.txt 2>&1
[ "$(grep -c '^S[12] .* dharma=1 world=1 rest=1[a-z0-9= ]*$' diaries/sessions.txt)" = 2 ] && [ "$(grep -Ec '^R[12] tick=[0-9]+ ada=[0-9]+/[0-9]+/[0-9]+/[0-9]+ gemini=[0-9]+/[0-9]+/[0-9]+/[0-9]+ replika=[0-9]+/[0-9]+/[0-9]+/[0-9]+ robert=[0-9]+/[0-9]+/[0-9]+/[0-9]+$' diaries/sessions.txt)" = 2 ] && grep -q '^import OK: 4 entities, 1500 ticks verified' r2.txt \
  && ok "new sessions carry rest=1 and write an R line (rate/cool-downs/cut short/quick rests per wesen), replay-verified" || bad "rest sessions"
rates=$(grep '^R2 ' diaries/sessions.txt | grep -o '[a-z]*=[0-9]*/' | tr -d '/a-z=' | sort -u | wc -l); taken=$(grep '^R2 ' diaries/sessions.txt | grep -o '=[0-9]*/[0-9]*/' | cut -d/ -f2 | awk '{ n += $1 } END { print n + 0 }')
echo "   distinct recovery rates: $rates; cool-downs taken (all wesen): $taken"
[ "$rates" -ge 3 ] && [ "$taken" -gt 0 ] && [ "$(grep -Ec '^[a-z]+ rate [0-9]+% \| cool-down [0-9]+ ticks \| taken [0-9]+ \| cut short [0-9]+ \| quick rests [0-9]+$' r2.txt)" = 4 ] && ok "the end report shows rate, cool-down, taken, cut short and quick rests per wesen; the wesen differ in rate and cool-downs happen" || bad "rest report ($rates rates, $taken taken)"
grep -Eq 'topic=(more_rest|faster_work_recovery) ' petitions.txt && ok "more_rest / faster_work_recovery petitions are filed" || bad "no recovery petitions"
! grep -Eq 'wish=.*(for|like|have|consider|is|use|request) (kindly|again|honestly|briefly|politely),' petitions.txt && grep -Eq 'wish=(Kindly|Honestly|Briefly|Politely|Once again), ' petitions.txt && ok "petition wording: the adverb opens the sentence ('Briefly, I would like ...'), never sits in the middle" || bad "petition adverb slot"
cp diaries/sessions.txt ../s.keep; cp diaries/world.txt ../w.keep
sed -i '/^R1 /s/ada=[0-9]*/ada=1/' diaries/sessions.txt; "$rb" --more 0 --every 5000 > r3.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'import FAILED' r3.txt && ok "tampered R line: import FAILED, DRIFT" || bad "tampered R line"
cp ../s.keep diaries/sessions.txt; sed -i '/^S2 /s/ rest=1//' diaries/sessions.txt; "$rb" --more 0 --every 5000 > r4.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "S line with its rest=1 marker removed: DRIFT" || bad "tampered rest marker"
cp ../s.keep diaries/sessions.txt; "$rb" --more 0 --every 5000 > r5.txt 2>&1; grep -q '^import OK: 4 entities, 2000 ticks verified' r5.txt && ok "restored: replays again" || bad "rest restore"
# rest.enabled = 0: byte-identical to 5331fc3 (golden checksum from that build: seed 42, 300 + 500 + 900 ticks, world on)
gh="$w/rs/o/h"; mkdir -p "$gh"
DIARY_HOME="$gh" "$fb" --seed 42 --ticks 300 --yes --every 100000 > /dev/null 2>&1; DIARY_HOME="$gh" "$fb" --more 500 --every 100000 > /dev/null 2>&1; DIARY_HOME="$gh" "$fb" --more 900 --every 100000 > /dev/null 2>&1
g=$( cd "$gh" && { for e in ada gemini replika robert; do sed 's/"ts":"[^"]*"//' diaries/$e.jsonl; done; grep -v '^# build' diaries/sessions.txt; cat diaries/inbox.txt diaries/world.txt; for e in ada gemini replika robert; do cat entities/$e/words.txt; done; } | cksum )
echo "   rest off checksum: $g"
[ "$g" = "121612284 1505992" ] && ! grep -Eq ' rest=1$|^R[0-9]+ tick' "$gh/diaries/sessions.txt" && ok "rest.enabled = 0: diaries, sessions.txt, inbox, world.txt and words files are byte-identical to 5331fc3 (golden checksum)" || bad "rest off is not identical to the old build ($g)"
# the trade-off helps the worker: ada's mean mood is higher with the model than without (same seed, same ticks)
mm() { grep -o '"mood":-\?[0-9]*' "$1/diaries/ada.jsonl" | cut -d: -f2 | awk '{ s += $1 } END { printf "%d", s / NR }'; }
a_on=$(mm "$w/rs/h"); mkdir -p "$w/rs/o/h2"; DIARY_HOME="$w/rs/o/h2" "$fb" --seed 42 --ticks 2000 --yes --every 100000 > /dev/null 2>&1; a_off=$(mm "$w/rs/o/h2")
echo "   ada mean mood over 2000 ticks: rest model $a_on, without $a_off"
[ "$a_on" -gt "$a_off" ] && ok "ada's mean mood is higher with the rest model than without it" || bad "ada mood $a_on vs $a_off"
unset DIARY_HOME

echo "== 29. mood ledger (report only): sums equal the diary's mood changes, nothing is stored or changed =="
rm -rf "$w/lg"; mkdir -p "$w/lg"; cd "$w/lg" || exit 1; export DIARY_HOME="$w/lg"
"$bin" --seed 42 --ticks 300 --yes --every 5000 > l1.txt 2>&1; "$bin" --more 300 --every 5000 > l2.txt 2>&1
before=$(snap .); sz=$(find . -type f -printf '%p %s\n' | sort | cksum)
"$bin" --ledger=full > led.txt 2>&1; rc=$?; "$bin" --ledger > led_short.txt 2>&1
[ $rc = 0 ] && [ "$before" = "$(snap .)" ] && [ "$sz" = "$(find . -type f -printf '%p %s\n' | grep -v 'led' | sort | cksum)" ] && ok "--ledger replays and verifies, prints, and writes nothing (diaries, sessions, every file size unchanged)" || bad "ledger changed files"
[ "$(awk 'length > 79' led.txt led_short.txt | wc -l)" = 0 ] && grep -q '^mood ledger: seed 42; whole run = ticks 1..600; last session = ticks 301..600' led.txt && [ "$(wc -l < led_short.txt)" -le 40 ] && ok "80 columns at most, header names the scopes (whole run 1..600, last session 301..600), short form fits a screen" || bad "ledger layout"
good=1
for e in ada gemini replika robert; do
  want=$(awk -F'"mood":|,"location"' '/}}$/ { n++; if (n == 300) b = $2; last = $2 } END { print last + 0, last - b }' diaries/$e.jsonl)
  got=$(awk -v n=$e '$1 == n && $2 == "run" { print $3 + 0, $9 + 0 }' led.txt)
  sums=$(awk -v n=$e '/^[a-z]+ +run / { cur = ($1 == n) } cur && /^  by (action|place|verb) / { sec = $2 } cur && /^  (events|rest model) / { sec = "" } cur && sec != "" { while (match($0, /[-+]?[0-9]+\/[0-9]+t/)) { t = substr($0, RSTART, RLENGTH); sub(/\/.*/, "", t); S[sec] += t; $0 = substr($0, RSTART + RLENGTH) } } END { print S["action"] + 0, S["place"] + 0, S["verb"] + 0 }' led.txt)
  run_net=${want%% *}; [ "$got" = "$want" ] && [ "$sums" = "$run_net $run_net $run_net" ] || { good=0; echo "   $e: diary $want, ledger $got, sums $sums"; }
done
[ $good = 1 ] && ok "per wesen: the ledger's whole-run and last-session net equal the diary's mood change, and by action / place / verb each add up to it" || bad "ledger sums differ from the diary"
good=1
for e in ada gemini replika robert; do
  d=$(awk -F'"t":"|","text"|"mood":|,"location"' '/}}$/ { m = $4; v[$2] += m - prev; c[$2]++; prev = m } END { for (k in v) print k, v[k] + 0, c[k] }' diaries/$e.jsonl | sort)
  l=$(awk -v n=$e '/^[a-z]+ +run / { cur = ($1 == n) } cur && /^  by verb / { sec = 1 } cur && /^  events / { sec = 0 } cur && sec { while (match($0, /[a-z]+ [-+]?[0-9]+\/[0-9]+t/)) { t = substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH); split(t, a, /[ \/]/); sub(/t$/, "", a[3]); print a[1], a[2] + 0, a[3] } }' led.txt | sort)
  [ "$d" = "$l" ] || { good=0; echo "   $e verbs differ"; }
done
[ $good = 1 ] && ok "by verb: every diary verb (rest, work, ..., examine, push, eat, greet) has exactly the ledger's sum and tick count" || bad "ledger verbs"
grep -q '^  rest model .*quick-rest penalty -[0-9]*/[0-9]*t' led.txt && grep -q '^  - run ' led.txt && grep -q '^  + last ' led.txt && [ "$(grep -c ' loses most mood from ' led.txt)" = 4 ] && ok "top drains and gains for both scopes, the rest-model line and one sentence per wesen" || bad "ledger lines"
"$bin" --ledger=full > led2.txt 2>&1; cmp -s led.txt led2.txt && ok "the same replay prints the same ledger" || bad "ledger not deterministic"
"$w/nm/a/bin/diary_sim" --ledger > led_n.txt 2>&1; grep -q '^Lemma  ' led_n.txt && grep -q 'Lemma loses most mood from' led_n.txt && ! grep -q '^ada' led_n.txt && [ "$(awk 'length > 79' led_n.txt | wc -l)" = 0 ] && ok "display names from data/names.txt (Lemma ...), still within 79 columns" || bad "ledger names"
"$bin" --more 20 --every 5000 --debug > l3.txt 2>&1
sz_d=$(wc -c < debug.txt); sz_g=$(wc -c < debug_digest.txt); "$w/nm/a/bin/diary_sim" --more 0 --every 5000 --debug > l3n.txt 2>&1; sz_dn=$(wc -c < debug.txt); sz_gn=$(wc -c < debug_digest.txt)
grep -q '^mood ledger: seed 42' run_report.txt && grep -q '^\[ledger\]' debug_full.txt && "$bin" --debug-section ledger | grep -q '^section ledger' && [ "$sz_d" -le 1500 ] && [ "$sz_g" -le 1500 ] && [ "$sz_dn" -le 1500 ] && [ "$sz_gn" -le 1500 ] && ok "run_report.txt carries the ledger, the digest section 'ledger' is in debug_full.txt (--debug-section ledger), debug.txt and the digest stay <= 1500 B (with the identity ids and with the longer display names)" || bad "ledger in reports"
"$bin" --ledger=bogus > l4.txt 2>&1; [ $? = 2 ] && ok "--ledger=bogus: usage error (exit 2)" || bad "ledger usage"
rm -rf "$w/lg/e"; mkdir -p "$w/lg/e"; DIARY_HOME="$w/lg/e" "$bin" --ledger > l5.txt 2>&1; grep -q 'no save found' l5.txt && [ -z "$(ls -A "$w/lg/e")" ] && ok "--ledger without a save: says so, writes nothing" || bad "ledger without save"
unset DIARY_HOME

echo "== 30. grants: make grant PETITION=P<n>, recovery rate raised for those who asked, replay-verified =="
rm -rf "$w/gr"; mkdir -p "$w/gr/bin" "$w/gr/off/bin" "$w/gr/h" "$w/gr/o"; cp "$bin" "$w/gr/bin/"; cp -r "$idata" "$w/gr/data"; cp "$bin" "$w/gr/off/bin/"; cp -r "$idata" "$w/gr/off/data"
sed -i 's/^grant.enabled = .*/grant.enabled = 0/' "$w/gr/off/data/limits.txt"; gb="$w/gr/bin/diary_sim"; gfb="$w/gr/off/bin/diary_sim"
cd "$w/gr/h" || exit 1; export DIARY_HOME="$w/gr/h"
"$gb" --seed 42 --ticks 1000 --yes --every 5000 > g1.txt 2>&1
n=$(grep -E 'topic=(more_rest|faster_work_recovery) ' petitions.txt | tail -1 | sed 's/^P\([0-9]*\) .*/\1/'); echo "   granting P$n: $(grep "^P$n " petitions.txt | cut -c1-70)"
"$gb" --grant "P$n" --as robert > g2.txt 2>&1; rc=$?; "$gb" --grant "P$n" > g3.txt 2>&1; rc2=$?; "$gb" --grant P99999 > g4.txt 2>&1; rc3=$?; "$gb" --grant > g5.txt 2>&1; rc4=$?
[ $rc = 0 ] && [ $rc2 = 2 ] && [ $rc3 = 2 ] && [ $rc4 = 2 ] && grep -q "^G1 tick=1000 petition=P$n wesen=[a-z]* topic=[a-z_]* by=robert$" diaries/grants.txt && [ "$(grep -c '^G' diaries/grants.txt)" = 1 ] \
  && ok "make grant records one G line at the lowest common tick; a second grant of the same petition, an unknown petition and no argument are usage errors (exit 2)" || bad "grant command ($rc $rc2 $rc3 $rc4)"
"$gb" --more 300 --every 5000 > g6.txt 2>&1
grep -q '^S2 .* rest=1 grant=1$' diaries/sessions.txt && grep -q '^S1 .* rest=1 grant=1$' diaries/sessions.txt && grep -q '^E1 tick=1000 g=G1 topic=[a-z_]* applied=1 ada=' diaries/grants.txt && grep -q '^granted petitions' g6.txt && grep -q '^import OK' g6.txt \
  && ok "new sessions carry grant=1; the replay appends the effect line E1 (applied=1) and the report lists it" || bad "grant effect"
ok_r=$(awk '/^E1 / { n = 0; mx = -1; for (i = 5; i <= NF; i++) if ($i ~ /^[a-z]+=[0-9]+>[0-9]+\/[0-9]+$/) { split($i, a, /[=>\/]/); st = a[3] - a[2]; as = a[4]; if (as > mx) { mx = as; ms = st } if (st > 0) n++; if (st > best) best = st } } END { print (n >= 1 && ms == best) ? "ok" : "no" }' diaries/grants.txt)
r1=$(grep '^R1 ' diaries/sessions.txt | sed 's/.*ada=\([0-9]*\)\/.*/\1/'); r2=$(grep '^R2 ' diaries/sessions.txt | sed 's/.*ada=\([0-9]*\)\/.*/\1/')
a_old=$(sed -n 's/^E1 .* ada=\([0-9]*\)>\([0-9]*\)\/.*/\1 \2/p' diaries/grants.txt)
echo "   ada rate in E1: $a_old; R1 $r1 R2 $r2"
[ "$ok_r" = ok ] && grep -q "granted=G1" petitions.txt && ok "the wesen who asked most gets the biggest step, a rate never above grant.cap; petitions.txt marks the granted petition (granted=G1)" || bad "grant step ($ok_r)"
cp diaries/grants.txt ../grants.keep
sed -i "/^G1 /s/petition=P$n/petition=P1/" diaries/grants.txt; "$gb" --more 0 --every 5000 > g7.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'grants.txt G1' g7.txt && ok "tampered G line (another petition): import FAILED, DRIFT" || bad "tampered G line"
cp ../grants.keep diaries/grants.txt; sed -i '/^E1 /s/ada=\([0-9]*\)>[0-9]*/ada=\1>199/' diaries/grants.txt; "$gb" --more 0 --every 5000 > g8.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'grants.txt E1' g8.txt && ok "tampered E line (a rate): DRIFT" || bad "tampered E line"
cp ../grants.keep diaries/grants.txt; sed -i '/^G1 /d' diaries/grants.txt; "$gb" --more 0 --every 5000 > g9.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "an effect line without its grant (grant removed): DRIFT" || bad "removed grant"
cp ../grants.keep diaries/grants.txt; "$gb" --more 0 --every 5000 > g10.txt 2>&1; grep -q '^import OK: 4 entities, 1300 ticks verified' g10.txt && ok "restored: replays again" || bad "grant restore"
# no grant given: the same diaries with grant.enabled 1 or 0 (the marker alone changes nothing)
DIARY_HOME="$w/gr/o" "$gb" --seed 42 --ticks 600 --yes --every 5000 > /dev/null 2>&1; mkdir -p "$w/gr/o2"; DIARY_HOME="$w/gr/o2" "$gfb" --seed 42 --ticks 600 --yes --every 5000 > /dev/null 2>&1
a=$(cat "$w/gr/o"/diaries/*.jsonl | sed 's/"ts":"[^"]*"//' | cksum); b=$(cat "$w/gr/o2"/diaries/*.jsonl | sed 's/"ts":"[^"]*"//' | cksum)
[ "$a" = "$b" ] && ! grep -q 'grant=1' "$w/gr/o2/diaries/sessions.txt" && ok "without a grant, grant=1 changes no diary byte (identical to grant.enabled = 0, whose S lines have no marker)" || bad "grant marker changed the diaries"
unset DIARY_HOME

echo "== 31. screens (screen=1): taught / coined from a screen, K lines replay-verified, --screens view, off = identical =="
rm -rf "$w/sc"; mkdir -p "$w/sc/bin" "$w/sc/off/bin" "$w/sc/h" "$w/sc/o"; cp "$bin" "$w/sc/bin/"; cp -r "$idata" "$w/sc/data"; cp "$bin" "$w/sc/off/bin/"; cp -r "$idata" "$w/sc/off/data"
sed -i 's/^screen.enabled = .*/screen.enabled = 1/' "$w/sc/data/limits.txt"; sb="$w/sc/bin/diary_sim"; sfb="$w/sc/off/bin/diary_sim"
cd "$w/sc/h" || exit 1; export DIARY_HOME="$w/sc/h"
"$sb" --seed 42 --ticks 300 --yes --every 5000 > c1.txt 2>&1; "$sb" --more 300 --every 5000 > c2.txt 2>&1
n_k=$(grep -c '^K[0-9]' diaries/screens.txt)
grep -q '^S1 .* screen=1$' diaries/sessions.txt && grep -q '^S2 .* screen=1$' diaries/sessions.txt && head -1 diaries/screens.txt | grep -q '^# seed 42$' && [ "$n_k" -gt 500 ] && grep -q '^K1 t=1 ada add w=[0-9]* src=' diaries/screens.txt \
  && ok "new sessions carry screen=1; every change of a screen is a K line in diaries/screens.txt ($n_k lines)" || bad "screens.txt ($n_k)"
t_sum=$(sed -n 's/.*taught from a screen \([0-9]*\), coined.*/\1/p' run_report.txt | awk '{ s += $1 } END { print s + 0 }'); c_sum=$(sed -n 's/.*coined from a screen \([0-9]*\)$/\1/p' run_report.txt | awk '{ s += $1 } END { print s + 0 }')
t_k=$(grep ' l=' diaries/screens.txt | sed 's/.* l=\([^ ]*\) .*/\1/' | grep -v '^-$' | tr ',' '\n' | wc -l); c_k=$(grep -c ' blend a=' diaries/screens.txt)
echo "   taught from a screen: report $t_sum, K lines $t_k | coined from a screen: report $c_sum, K lines $c_k"
[ "$t_sum" -gt 0 ] && [ "$c_sum" -gt 0 ] && [ "$t_sum" = "$t_k" ] && [ "$c_sum" = "$c_k" ] && grep -q '^screens (' run_report.txt \
  && ok "'taught from a screen' and 'coined from a screen' are reported separately and equal what the K lines record" || bad "screen word counts"
grep -q 'showed its screen to' diaries/ada.jsonl && grep -q ' screen ' entities/gemini/words.txt && grep -q 'side by side on a screen' diaries/*.jsonl && ok "the diaries tell about showing a screen and a blend; words.txt files carry the 'screen' origin" || bad "screen diary text"
"$sb" --screens > c3.txt 2>&1; rc=$?
[ $rc = 0 ] && [ "$(grep -c '^+-*+$' c3.txt)" = 8 ] && [ "$(grep -c '^|.*|$' c3.txt)" = 24 ] && [ "$(awk '/^\|/ && length != 22' c3.txt | wc -l)" = 0 ] && [ "$(awk 'length > 79' c3.txt | wc -l)" = 0 ] && grep -q '^screens after tick 600' c3.txt && grep -q '^notes lying on things: ' c3.txt \
  && ok "--screens replays and prints four 20x6 screens (24 rows, framed, no line over 79 columns)" || bad "--screens view ($rc)"
"$sb" --more 0 --every 5000 > c4.txt 2>&1; grep -q '^import OK: 4 entities, 600 ticks verified' c4.txt && ok "a rerun replays the screens and verifies them (import OK)" || bad "screens replay"
cp diaries/screens.txt ../screens.keep; sed -i '100s/$/x/' diaries/screens.txt; "$sb" --more 0 --every 5000 > c5.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'screens.txt K99 differs' c5.txt && ok "tampered K line: import FAILED, DRIFT" || bad "tampered K line"
cp ../screens.keep diaries/screens.txt; echo "K99999 t=5 ada add w=3 src=x s=3" >> diaries/screens.txt; "$sb" --more 0 --every 5000 > c6.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "an invented K line (not in the replay): DRIFT" || bad "invented K line"
cp ../screens.keep diaries/screens.txt; sed -i '/^S1 /s/ screen=1//' diaries/sessions.txt; "$sb" --more 0 --every 5000 > c7.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "S line with its screen=1 marker removed: DRIFT" || bad "tampered screen marker"
sed -i '/^S1 /s/$/ screen=1/' diaries/sessions.txt; "$sb" --more 0 --every 5000 > c8.txt 2>&1; grep -q '^import OK: 4 entities, 600 ticks verified' c8.txt && ok "restored: replays again" || bad "screens restore"
# off: no marker, no file, no screen text, and the diaries are what the build without screens writes (golden of scenario 28 holds with screens off)
DIARY_HOME="$w/sc/o" "$sfb" --seed 42 --ticks 300 --yes --every 5000 > /dev/null 2>&1; DIARY_HOME="$w/sc/o" "$sfb" --screens > c9.txt 2>&1
[ ! -e "$w/sc/o/diaries/screens.txt" ] && ! grep -q 'screen=1' "$w/sc/o/diaries/sessions.txt" && ! grep -q 'screen' "$w/sc/o"/diaries/*.jsonl && ! grep -q ' screen ' "$w/sc/o"/entities/*/words.txt && grep -q 'no screens in this save' c9.txt \
  && ok "screen.enabled = 0: no marker, no screens.txt, no screen text anywhere; --screens says so" || bad "screens off"
grep -q -- '--screens' "$root/data/help.txt" && grep -q 'make screens' "$root/README.md" && grep -q 'screen.width' "$root/data/limits.txt" && grep -q 'condensed' "$root/README.md" && ok "--help, README and limits.txt cover screens (and name the condensed-vocabulary hook)" || bad "docs screens"
unset DIARY_HOME

echo "== 32. chess (chess=1): perft, games, Elo, timeout / resignation, players vs wesen, replay-verified C lines =="
"$bin" --perft > "$w/p1.txt" 2>&1; rc=$?
[ $rc = 0 ] && grep -q '^18 checks, 0 failed' "$w/p1.txt" && grep -q 'perft 4 197281' "$w/p1.txt" && grep -q 'state checkmate' "$w/p1.txt" && grep -q 'move e1g1 = 5171' "$w/p1.txt" && ok "--perft: six reference positions (castling, en passant, promotion), mate / stalemate / fifty-move states and ICCF notation, 18 checks" || bad "perft ($rc)"
rm -rf "$w/ch"; mkdir -p "$w/ch/bin" "$w/ch/h" "$w/ch/bad/bin" "$w/ch/off/bin" "$w/ch/o" "$w/ch/t/bin" "$w/ch/t/h" "$w/ch/r/bin" "$w/ch/r/h" "$w/ch/n/bin" "$w/ch/n/h"
cp "$bin" "$w/ch/bin/"; cp -r "$idata" "$w/ch/data"; sed -i 's/^chess.enabled = .*/chess.enabled = 1/' "$w/ch/data/limits.txt"; cb="$w/ch/bin/diary_sim"
cp "$bin" "$w/ch/bad/bin/"; cp -r "$w/ch/data" "$w/ch/bad/data"; sed -i 's/^perft.2 = 3 97862/perft.2 = 3 97863/' "$w/ch/bad/data/chess.txt"; ( cd "$w/ch/bad" && ./bin/diary_sim --perft > "$w/ch/p2.txt" 2>&1 ); rc=$?; cp "$w/ch/p2.txt" "$w/p2.txt"
[ $rc = 1 ] && grep -q '^FAIL.*expected 97863, got 97862' "$w/p2.txt" && grep -q '1 failed' "$w/p2.txt" && ok "--perft with a wrong count: FAIL line and exit 1" || bad "perft failing ($rc)"
cd "$w/ch/h" || exit 1; export DIARY_HOME="$w/ch/h"
"$cb" --seed 42 --ticks 300 --yes --every 5000 > h1.txt 2>&1; "$cb" --more 300 --every 5000 > h2.txt 2>&1
n_c=$(grep -c '^C[0-9]' diaries/chess.txt); n_m=$(grep -c ' move ' diaries/chess.txt)
grep -q '^S1 .* chess=1$' diaries/sessions.txt && grep -q '^S2 .* chess=1$' diaries/sessions.txt && head -1 diaries/chess.txt | grep -q '^# seed 42$' && [ "$n_m" -gt 100 ] && grep -q ' start white=' diaries/chess.txt \
  && ok "new sessions carry chess=1; starts, moves and ends are C lines in diaries/chess.txt ($n_c lines, $n_m moves)" || bad "chess.txt ($n_c $n_m)"
bad_n=$(grep ' move ' diaries/chess.txt | awk '{ c = $7; n = $8; f = index("abcdefgh", substr(c, 1, 1)); t = index("abcdefgh", substr(c, 3, 1)); e = f substr(c, 2, 1) t substr(c, 4, 1); p = (length(c) == 5) ? index("qrbn", substr(c, 5, 1)) : ""; if (n != e p) bad++ } END { print bad + 0 }')
[ "$bad_n" = 0 ] && ok "every recorded move is both coordinate notation and the matching ICCF number" || bad "ICCF notation ($bad_n differ)"
grep ' start white=' diaries/chess.txt | grep -Eq 'white=(iris|sol|noor) black=(ada|gemini|replika|robert)|white=(ada|gemini|replika|robert) black=(iris|sol|noor)' && grep ' start white=' diaries/chess.txt | grep -Eq 'white=(iris|sol|noor) black=(iris|sol|noor)' && grep ' start white=' diaries/chess.txt | grep -Eq 'white=(ada|gemini|replika|robert) black=(ada|gemini|replika|robert)' \
  && ok "wesen play wesen, players play wesen, players play players (all three kinds of games are recorded)" || bad "game kinds"
"$cb" --elo > e1.txt 2>&1; rc=$?
tot=$(grep -E '^[0-9]\. ' e1.txt | sed -E 's/^[0-9]\. [A-Za-z]+ ([0-9]+) .*/\1/' | awk '{ s += $1 } END { print s + 0 }')
[ $rc = 0 ] && [ "$(grep -cE '^[0-9]\. ' e1.txt)" = 7 ] && [ "$tot" = 8400 ] && ok "--elo ranks all seven (4 wesen, 3 players); the ratings sum to 7 x 1200 (exactly conserved)" || bad "elo table ($rc, sum $tot)"
op=$(grep ' end ' diaries/chess.txt | awk '{ ok = 1; for (i = 1; i <= NF; i++) if ($i ~ /^[a-z]+=[0-9]+>[0-9]+$/) { split($i, a, /[=>]/); d[++n] = a[3] - a[2] } if (n != 2 || d[1] + d[2] != 0) ok = 0; n = 0; if (!ok) bad++ } END { print bad + 0 }')
[ "$op" = 0 ] && ok "in every finished game the two rating changes are exact opposites" || bad "elo deltas ($op)"
mkdir -p "$w/ch/dn/bin" "$w/ch/dn/h"; cp "$bin" "$w/ch/dn/bin/"; cp -r "$root/data" "$w/ch/dn/data"; sed -i 's/^chess.enabled = .*/chess.enabled = 1/' "$w/ch/dn/data/limits.txt"
DIARY_HOME="$w/ch/dn/h" "$w/ch/dn/bin/diary_sim" --seed 42 --ticks 300 --yes --every 5000 > /dev/null 2>&1; DIARY_HOME="$w/ch/dn/h" "$w/ch/dn/bin/diary_sim" --elo > e2.txt 2>&1
grep -q 'Modulus' e2.txt && grep -q 'Kernel' e2.txt && grep -q 'Vertex' e2.txt && grep -q 'Lemma' e2.txt && ! grep -Eq '^[0-9]\. (ada|iris|sol|noor) ' e2.txt && [ "$(awk 'length > 79' e2.txt | wc -l)" = 0 ] && ok "--elo shows display names (Lemma .. Axiom, Modulus, Kernel, Vertex), no line over 79 columns" || bad "elo display names"
if [ -f "$w/pty_multi.py" ]; then   # (the menu scenario's pty helper exists in a full run)
  python3 "$w/pty_multi.py" "$w/ch/h" "$cb" '5\n' > mu.txt 2>&1; grep -aq '^ *chess Elo [A-Za-z]* [0-9]* |' mu.txt && ok "menu: the start screen has a 'chess Elo' line with the best ratings" || bad "menu elo line"
fi
# the mood ledger still adds up with chess results in it
good=1; "$cb" --ledger=full > l1.txt 2>&1
for e in ada gemini replika robert; do
  fin=$(grep -o '"mood":-\?[0-9]*' diaries/$e.jsonl | tail -1 | cut -d: -f2); led=$(grep -E "^$e +run" l1.txt | sed -E 's/^[a-z]+ +run ([-+]?[0-9]+) .*/\1/' | sed 's/^+//')
  [ "$fin" = "$led" ] || { good=0; echo "   $e final mood $fin, ledger $led"; }
done
grep -q 'chess results' l1.txt && [ $good = 1 ] && ok "the mood ledger lists 'chess results' and its sums equal the diaries' mood changes" || bad "ledger with chess"
grep -q '^chess (' run_report.txt && grep -q '^G1 ' run_report.txt && grep -q 'rating' run_report.txt && "$cb" --more 10 --every 5000 --debug > h3.txt 2>&1 && grep -q 'elo ' debug_full.txt && [ "$(wc -c < debug.txt)" -le 1500 ] && [ "$(wc -c < debug_digest.txt)" -le 1500 ] \
  && ok "the end report lists ratings, results and every game with its moves; the digest has an elo line; caps held" || bad "chess report"
cp diaries/chess.txt ../chess.keep
sed -i '0,/ end /s/ elo \([a-z]*\)=\([0-9]*\)>\([0-9]*\)/ elo \1=\2>\3x/' diaries/chess.txt; "$cb" --more 0 --every 5000 > h4.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'chess.txt C' h4.txt && ok "tampered rating in an end line: import FAILED, DRIFT" || bad "tampered elo"
cp ../chess.keep diaries/chess.txt; sed -i '0,/ move /s/ move \([0-9]*\) \([a-z]*\) \([a-h]\)/ move \1 \2 \3z/' diaries/chess.txt; "$cb" --more 0 --every 5000 > h5.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "tampered move: DRIFT" || bad "tampered move"
cp ../chess.keep diaries/chess.txt; echo "C99999 t=5 g=1 move 1 ada e2e4 5254 k=0" >> diaries/chess.txt; "$cb" --more 0 --every 5000 > h6.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "an invented C line: DRIFT" || bad "invented C line"
cp ../chess.keep diaries/chess.txt; cp diaries/sessions.txt ../sess.keep; sed -i '/^S1 /s/ chess=1//' diaries/sessions.txt; "$cb" --more 0 --every 5000 > h7.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "S line with its chess=1 marker removed: DRIFT" || bad "tampered chess marker"
cp ../sess.keep diaries/sessions.txt; "$cb" --more 0 --every 5000 > h8.txt 2>&1; grep -q '^import OK: 4 entities, 610 ticks verified' h8.txt && ok "restored: replays again" || bad "chess restore"
# timeouts: a short clock; resignations: a hair trigger
cp "$bin" "$w/ch/t/bin/"; cp -r "$w/ch/data" "$w/ch/t/data"; sed -i 's/^chess.timeout = .*/chess.timeout = 12/' "$w/ch/t/data/limits.txt"; DIARY_HOME="$w/ch/t/h" "$w/ch/t/bin/diary_sim" --seed 42 --ticks 500 --yes --every 5000 > t1.txt 2>&1
cp "$bin" "$w/ch/r/bin/"; cp -r "$w/ch/data" "$w/ch/r/data"; sed -i 's/^chess.resign_pct = .*/chess.resign_pct = 90/; s/^chess.resign_gap = .*/chess.resign_gap = 1/' "$w/ch/r/data/limits.txt"; DIARY_HOME="$w/ch/r/h" "$w/ch/r/bin/diary_sim" --seed 42 --ticks 500 --yes --every 5000 > r1.txt 2>&1
nt=$(grep -c ' end .* timeout ' "$w/ch/t/h/diaries/chess.txt"); nr=$(grep -c ' end .* resign ' "$w/ch/r/h/diaries/chess.txt"); echo "   short clock: $nt timeouts; hair-trigger resignation: $nr resignations"
tw=$(grep ' end .* timeout ' "$w/ch/t/h/diaries/chess.txt" | head -1); gn=$(echo "$tw" | sed 's/.* g=\([0-9]*\) end.*/\1/')
[ "$nt" -ge 1 ] && [ "$nr" -ge 1 ] && grep -q 'by timeout [1-9]' "$w/ch/t/h/run_report.txt" && grep -q 'by resignation [1-9]' "$w/ch/r/h/run_report.txt" && ok "a win by timeout and a win by resignation happen, are recorded as end reasons and counted in the report" || bad "timeout / resign paths"
DIARY_HOME="$w/ch/t/h" "$w/ch/t/bin/diary_sim" --more 0 --every 5000 > t2.txt 2>&1; grep -q '^import OK: 4 entities, 500 ticks verified' t2.txt && ok "the timeout run replays and verifies (import OK)" || bad "timeout replay"
# holiday: the clock of the holidaying side stops (no timeout is charged to it while it is away)
hol=$(grep -c ' hol ' "$w/ch/h/diaries/chess.txt"); echo "   holiday notices in the 600-tick run: $hol"
[ "$hol" -ge 1 ] && ok "holiday notices are recorded (hol <wesen> until=<tick>)" || bad "no holiday notice"
# off: no marker, no file, no chess text; --elo says so
cp "$bin" "$w/ch/off/bin/"; cp -r "$idata" "$w/ch/off/data"; DIARY_HOME="$w/ch/o" "$w/ch/off/bin/diary_sim" --seed 42 --ticks 300 --yes --every 5000 > /dev/null 2>&1; DIARY_HOME="$w/ch/o" "$w/ch/off/bin/diary_sim" --elo > e3.txt 2>&1
[ ! -e "$w/ch/o/diaries/chess.txt" ] && ! grep -q 'chess=1' "$w/ch/o/diaries/sessions.txt" && ! grep -q 'chess' "$w/ch/o"/diaries/*.jsonl && grep -q 'no chess games' e3.txt && ok "chess.enabled = 0: no marker, no chess.txt, no chess text; --elo says so" || bad "chess off"
grep -q -- '--elo' "$root/data/help.txt" && grep -q -- '--perft' "$root/data/help.txt" && grep -q 'make elo' "$root/README.md" && grep -q 'elo.table' "$root/data/chess.txt" && grep -q 'chess.elo.k' "$root/data/limits.txt" && ok "--help, README, limits.txt and chess.txt cover chess and Elo" || bad "docs chess"
unset DIARY_HOME

echo "== 33. robot (robot=1): commands pinned on a screen, battery, camera written back, shared screens, replay-verified Q lines =="
rm -rf "$w/rb"; mkdir -p "$w/rb/bin" "$w/rb/h" "$w/rb/o" "$w/rb/off/bin" "$w/rb/k/bin" "$w/rb/k/h" "$w/rb/b/bin" "$w/rb/b/h" "$w/rb/s/bin" "$w/rb/s/h"
cp "$bin" "$w/rb/bin/"; cp -r "$idata" "$w/rb/data"; sed -i 's/^screen.enabled = .*/screen.enabled = 1/; s/^robot.enabled = .*/robot.enabled = 1/' "$w/rb/data/limits.txt"; rbn="$w/rb/bin/diary_sim"
cd "$w/rb/h" || exit 1; export DIARY_HOME="$w/rb/h"
"$rbn" --seed 42 --ticks 300 --yes --every 5000 > r1.txt 2>&1; "$rbn" --more 300 --every 5000 > r2.txt 2>&1
n_q=$(grep -c '^Q[0-9]' diaries/robot.txt); n_x=$(grep -c ' exec ' diaries/robot.txt); n_c=$(grep -c ' cmd ' diaries/robot.txt)
grep -q '^S1 .* robot=1$' diaries/sessions.txt && grep -q '^S2 .* robot=1$' diaries/sessions.txt && head -1 diaries/robot.txt | grep -q '^# seed 42$' && [ "$n_c" -ge 10 ] && [ "$n_x" -ge 5 ] \
  && ok "new sessions carry robot=1; commands, executions and shared screens are Q lines in diaries/robot.txt ($n_q lines, $n_c commands, $n_x executions)" || bad "robot.txt ($n_q $n_c $n_x)"
np=$(grep ' exec ' diaries/robot.txt | sed -E 's/.* pos=([-0-9,]+) .*/\1/' | sort -u | wc -l); nb=$(grep ' exec ' diaries/robot.txt | sed -E 's/.* bat=([0-9]+) .*/\1/' | sort -u | wc -l)
up=$(grep ' exec ' diaries/robot.txt | sed -E 's/.* bat=([0-9]+) .*/\1/' | awk 'NR>1 && $1>p {n++} {p=$1} END{print n+0}'); dn=$(grep ' exec ' diaries/robot.txt | sed -E 's/.* bat=([0-9]+) .*/\1/' | awk 'NR>1 && $1<p {n++} {p=$1} END{print n+0}')
[ "$np" -ge 3 ] && [ "$nb" -ge 3 ] && [ "$up" -ge 1 ] && [ "$dn" -ge 1 ] && grep -q ' exec [a-z]* go [a-z]* ok ' diaries/robot.txt && ok "the robot moves ($np positions) and its battery drains ($dn times) and recharges ($up times)" || bad "robot moves ($np $nb $up $dn)"
grep -q ' exec .* err=unknown command: ' diaries/robot.txt && grep -q ' exec .* err=[a-z]* where? ' diaries/robot.txt && ok "an unknown command and a command without its direction give an error line (err=...)" || bad "robot errors"
bad_cam=$(grep ' exec ' diaries/robot.txt | sed -E 's/.* cam=//' | awk -F'|' 'NF != 5 || length($1) != 5 || length($3) != 5 || length($5) != 5 {n++} END{print n+0}')
[ "$bad_cam" = 0 ] && ok "every execution records a 5x5 camera view (five rows of five glyphs)" || bad "camera rows ($bad_cam)"
"$rbn" --screens > sc.txt 2>&1; ncam=$(grep -cE '^  [^ ]{5}$' sc.txt); npin=$(grep -c ' cmd w=.*\*' diaries/screens.txt)
[ "$ncam" -ge 5 ] && [ "$npin" -ge 5 ] && ok "a pinned command word sits on the screen (* in the K lines, $npin) and the camera view is written back under the frame ($ncam rows)" || bad "screen camera ($ncam $npin)"
ns=$(grep -c '^Q[0-9]* t=[0-9]* share ' diaries/robot.txt); nl=$(grep -c '^Q[0-9]* t=[0-9]* learn ' diaries/robot.txt)
[ "$ns" -ge 1 ] && [ "$nl" -ge 3 ] && ok "a wesen that reads a steering wesen's screen gets the view and may steer too ($ns shares); command words are learned beside the robot ($nl)" || bad "shares ($ns $nl)"
second=$(awk '/ share /{ split($4, a, ">"); v[a[2]] = 1 } / cmd /{ c[$4]++ } END { for (k in v) if (c[k] > 0) n++; print n + 0 }' diaries/robot.txt)
[ "$second" -ge 1 ] && ok "$second wesen steered the robot after getting the view by reading another screen" || bad "second controller ($second)"
grep -q 'by=robot' diaries/world.txt && ok "the robot's pick / push are world edits (by=robot in diaries/world.txt)" || bad "robot edits"
"$rbn" --robot > rv.txt 2>&1; rc=$?
mkdir -p "$w/rb/disp"; cp -r "$w/rb/data" "$w/rb/disp/data"; cp "$root/data/names.txt" "$w/rb/disp/data/names.txt"; ( cd "$w/rb/disp" && "$rbn" --robot > "$w/rb/h/rd.txt" 2>&1 )
[ $rc = 0 ] && grep -q '^robot ' rv.txt && grep -q 'battery' rv.txt && grep -q 'steered by' rv.txt && [ "$(grep -cE '^  [^ ]{5}$' rv.txt)" = 5 ] && [ "$(awk 'length > 79' rv.txt | wc -l)" = 0 ] && ok "--robot: state, battery, 5x5 camera, controllers, last commands (display names, <= 79 columns)" || bad "--robot view ($rc)"
grep -qE 'Lemma|Corollary|Theorem|Axiom' rd.txt && ! grep -qwE 'ada|gemini|replika|robert' rd.txt && ok "the robot view uses the display names (Lemma, Corollary, Theorem, Axiom)" || bad "robot names"
grep -q '^robot (' run_report.txt && grep -q '^ada: commands' run_report.txt && ok "the end report has the robot block" || bad "robot report"
cp diaries/robot.txt ../robot.keep
sed -i '0,/ exec /s/ pos=\([-0-9]*\),/ pos=\1\1,/' diaries/robot.txt; "$rbn" --more 0 --every 5000 > h4.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'robot.txt Q' h4.txt && ok "tampered position in an exec line: import FAILED, DRIFT" || bad "tampered robot line"
cp ../robot.keep diaries/robot.txt; echo "Q99999 t=5 cmd ada go north ready=9" >> diaries/robot.txt; "$rbn" --more 0 --every 5000 > h5.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "an invented Q line: DRIFT" || bad "invented Q line"
cp ../robot.keep diaries/robot.txt; cp diaries/sessions.txt ../sess.keep; sed -i '/^S1 /s/ robot=1//' diaries/sessions.txt; "$rbn" --more 0 --every 5000 > h6.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "S line with its robot=1 marker removed: DRIFT" || bad "tampered robot marker"
cp ../sess.keep diaries/sessions.txt; "$rbn" --more 0 --every 5000 > h7.txt 2>&1; grep -q '^import OK: 4 entities, 600 ticks verified' h7.txt && ok "restored: replays again" || bad "robot restore"
# command words must already be known: no contact learning, no sloppy picks -> never a word nobody knows
cp "$bin" "$w/rb/k/bin/"; cp -r "$w/rb/data" "$w/rb/k/data"; sed -i 's/^robot.contact_pct = .*/robot.contact_pct = 0/; s/^robot.sloppy_pct = .*/robot.sloppy_pct = 0/' "$w/rb/k/data/limits.txt"
DIARY_HOME="$w/rb/k/h" "$w/rb/k/bin/diary_sim" --seed 42 --ticks 400 --yes --every 5000 > k1.txt 2>&1
kc=$(grep -c ' cmd ' "$w/rb/k/h/diaries/robot.txt"); kb=$(grep ' cmd ' "$w/rb/k/h/diaries/robot.txt" | grep -Ec ' (north|east|south|west)')
[ "$kc" -ge 1 ] && [ "$kb" = 0 ] && grep -q ' err=go where? ' "$w/rb/k/h/diaries/robot.txt" && ok "a command word nobody knows is never sent ($kc commands, none with a direction word nobody knows)" || bad "known command words ($kc $kb)"
# a low battery: too little for the commands -> "battery low" errors
cp "$bin" "$w/rb/b/bin/"; cp -r "$w/rb/data" "$w/rb/b/data"; sed -i 's/^robot.battery.start = .*/robot.battery.start = 3/; s/^robot.charge = .*/robot.charge = 0/; s/^robot.trickle = .*/robot.trickle = 100000/' "$w/rb/b/data/limits.txt"
DIARY_HOME="$w/rb/b/h" "$w/rb/b/bin/diary_sim" --seed 42 --ticks 400 --yes --every 5000 > b1.txt 2>&1; DIARY_HOME="$w/rb/b/h" "$w/rb/b/bin/diary_sim" --more 0 --every 5000 > b2.txt 2>&1
grep -q ' err=battery low' "$w/rb/b/h/diaries/robot.txt" && grep -q '^import OK' b2.txt && ok "a drained battery: commands answer 'battery low' (and replay)" || bad "battery low"
# sloppy controllers: the error line shows on the screen too
cp "$bin" "$w/rb/s/bin/"; cp -r "$w/rb/data" "$w/rb/s/data"; sed -i 's/^robot.sloppy_pct = .*/robot.sloppy_pct = 100/; s/^robot.cmd_pct = .*/robot.cmd_pct = 60/' "$w/rb/s/data/limits.txt"
DIARY_HOME="$w/rb/s/h" "$w/rb/s/bin/diary_sim" --seed 42 --ticks 200 --yes --every 5000 > s1.txt 2>&1; DIARY_HOME="$w/rb/s/h" "$w/rb/s/bin/diary_sim" --screens > s2.txt 2>&1
grep -q '^  ERR unknown command' s2.txt && ok "an unknown command puts an ERR line on the controller's screen" || bad "ERR on screen"
# off: no marker, no file, no robot text
cp "$bin" "$w/rb/off/bin/"; cp -r "$w/rb/data" "$w/rb/off/data"; sed -i 's/^robot.enabled = .*/robot.enabled = 0/' "$w/rb/off/data/limits.txt"; DIARY_HOME="$w/rb/o" "$w/rb/off/bin/diary_sim" --seed 42 --ticks 300 --yes --every 5000 > /dev/null 2>&1; DIARY_HOME="$w/rb/o" "$w/rb/off/bin/diary_sim" --robot > rn.txt 2>&1
[ ! -e "$w/rb/o/diaries/robot.txt" ] && ! grep -q 'robot=1' "$w/rb/o/diaries/sessions.txt" && ! grep -qi 'robot' "$w/rb/o"/diaries/*.jsonl && grep -q 'no robot' rn.txt && ok "robot.enabled = 0: no marker, no robot.txt, no robot text; --robot says so" || bad "robot off"
grep -q -- '--robot' "$root/data/help.txt" && grep -q 'make robot' "$root/README.md" && grep -q 'robot.battery.max' "$root/data/limits.txt" && grep -q 'robot.verbs' "$root/data/robot.txt" && ok "--help, README, limits and data/robot.txt describe the robot" || bad "robot docs"
unset DIARY_HOME

echo "== 34. govern (govern=1): players decide petitions, D records replay-verified, veto / approve, bounds, trust, reports from the D lines =="
rm -rf "$w/gv"; mkdir -p "$w/gv/bin" "$w/gv/h" "$w/gv/o" "$w/gv/off/bin" "$w/gv/b/bin" "$w/gv/b/h" "$w/gv/s/bin" "$w/gv/s/h"
cp "$bin" "$w/gv/bin/"; cp -r "$idata" "$w/gv/data"; sed -i 's/^govern.enabled = .*/govern.enabled = 1/' "$w/gv/data/limits.txt"; gvb="$w/gv/bin/diary_sim"
cd "$w/gv/h" || exit 1; export DIARY_HOME="$w/gv/h"
"$gvb" --seed 42 --ticks 300 --yes --every 5000 > g1.txt 2>&1; "$gvb" --more 300 --every 5000 > g2.txt 2>&1
n_d=$(grep -c '^D[0-9]' diaries/govern.txt); n_k=$(grep '^D[0-9]' diaries/govern.txt | sed -E 's/.* kind=([a-z]*) .*/\1/' | sort -u | wc -l)
grep -q '^S1 .* govern=1' diaries/sessions.txt && grep -q '^S2 .* govern=1' diaries/sessions.txt && head -1 diaries/govern.txt | grep -q '^# seed 42$' && [ "$n_d" -ge 8 ] && [ "$n_k" -ge 3 ] \
  && ok "new sessions carry govern=1; every decision is a D line in diaries/govern.txt ($n_d decisions, $n_k different outcomes)" || bad "govern.txt ($n_d $n_k)"
bad_f=$(grep '^D[0-9]' diaries/govern.txt | awk '{ ok = 1; split("pet player wesen topic lever kind why old new trust stand", k, " "); for (i = 1; i <= 11; i++) if (index($0, " " k[i] "=") == 0) ok = 0; if (!ok) n++ } END { print n + 0 }')
nl=$(grep '^D[0-9]' diaries/govern.txt | grep -c 'lever=- ' ); nl_ok=$(grep '^D[0-9]' diaries/govern.txt | grep 'lever=- ' | grep -c 'kind=refuse why=refuse.nolever')
[ "$bad_f" = 0 ] && [ "$nl" = "$nl_ok" ] && ok "every record names petition, player, wesen, topic, lever, outcome, reason, old -> new, trust and standing (a topic without a lever is refused as such, $nl)" || bad "D fields ($bad_f $nl $nl_ok)"
# bounds: every new offset inside data/govern.txt min .. max; one step at most
oob=$(grep '^D[0-9]' diaries/govern.txt | grep -v 'lever=- ' | awk -v f="$w/gv/data/govern.txt" 'BEGIN { while ((getline l < f) > 0) if (l ~ /^lever\.[a-z]+ = /) { split(l, a, " "); n = substr(a[1], 7); lo[n] = a[3]; hi[n] = a[4]; st[n] = a[5] } }
  { for (i = 1; i <= NF; i++) { if ($i ~ /^lever=/) lv = substr($i, 7); if ($i ~ /^old=/) o = substr($i, 5) + 0; if ($i ~ /^new=/) nw = substr($i, 5) + 0 }
    d = nw - o; if (d < 0) d = -d; if (nw < lo[lv] || nw > hi[lv] || d > st[lv]) bad++ } END { print bad + 0 }')
[ "$oob" = 0 ] && ok "no lever ever leaves its bounds, no change is bigger than one step (data/govern.txt)" || bad "bounds ($oob)"
dfr=$(grep '^D[0-9].* kind=defer ' diaries/govern.txt | wc -l); bk=0
grep '^D[0-9].* kind=defer ' diaries/govern.txt | while read -r key tk pet rest; do :; done
for u in $(grep '^D[0-9].* kind=defer ' diaries/govern.txt | sed -E 's/.* pet=(P[0-9]+) .* until=([0-9]+).*/\1:\2/'); do p=${u%%:*}; t=${u##*:}; grep -q "^D[0-9]* t=$t pet=$p " diaries/govern.txt || bk=$((bk + 1)); done
[ "$dfr" -ge 1 ] && [ "$bk" = 0 ] && ok "a deferred petition comes back at the tick the record names ($dfr deferrals)" || bad "defer ($dfr $bk)"
"$gvb" --govern > gv1.txt 2>&1; rc=$?
[ $rc = 0 ] && [ "$(grep -cE '[0-9]+ petitions seen, [0-9]+ granted, [0-9]+ partial, [0-9]+ deferred, [0-9]+ refused' gv1.txt)" = 3 ] && grep -q 'trust' gv1.txt && grep -q '^last decisions' gv1.txt && [ "$(awk 'length > 79' gv1.txt | wc -l)" = 0 ] \
  && ok "--govern: counter line per player ('N petitions seen, N granted, N partial, N deferred, N refused'), trust, standing, levers, last decisions (<= 79 columns)" || bad "--govern view ($rc)"
# the reports to Robert come from the D lines only: counters and every change at the session end
c1=$(grep -c 'src=s1:govern' diaries/inbox.txt); ch1=$(grep 'src=s1:govern' diaries/inbox.txt | grep -vc 'petitions seen'); dch=$(awk '{ t = ""; k = ""; for (i = 1; i <= NF; i++) { if ($i ~ /^t=/) t = substr($i, 3) + 0; if ($i ~ /^kind=/) k = substr($i, 6) } if (t <= 300 && (k == "grant" || k == "partial" || k == "veto")) n++ } END { print n + 0 }' diaries/govern.txt)
sg=$(grep 'src=s1:govern' diaries/inbox.txt | grep -o '[0-9]* granted' | awk '{ s += $1 } END { print s + 0 }'); dg=$(awk '{ t = ""; k = ""; for (i = 1; i <= NF; i++) { if ($i ~ /^t=/) t = substr($i, 3) + 0; if ($i ~ /^kind=/) k = substr($i, 6) } if (t <= 300 && k == "grant") n++ } END { print n + 0 }' diaries/govern.txt)
echo "   inbox: $c1 governance lines in session 1, $ch1 change lines (D records: $dch), granted counters $sg (D records: $dg)"
[ "$c1" -ge 3 ] && [ "$ch1" = "$dch" ] && [ "$sg" = "$dg" ] && ok "each player's report has the counter line and EVERY change from the D records (none omitted); counters equal the D records" || bad "govern reports"
grep -q '^govern (' run_report.txt || grep -q 'petitions seen' run_report.txt; grep -q 'petitions seen' run_report.txt && "$gvb" --more 5 --every 5000 --debug > g3.txt 2>&1 && grep -q '^govern ' debug_full.txt && [ "$(wc -c < debug.txt)" -le 1500 ] && [ "$(wc -c < debug_digest.txt)" -le 1500 ] \
  && ok "the end report has the governance block, the digest has a govern line, caps held" || bad "govern report/digest"
# mood: refusals dip, grants raise; the ledger lists them and still adds up
good=1; "$gvb" --ledger=full > l1.txt 2>&1
for e in ada gemini replika robert; do
  fin=$(grep -o '"mood":-\?[0-9]*' diaries/$e.jsonl | tail -1 | cut -d: -f2); led=$(grep -E "^$e +run" l1.txt | sed -E 's/^[a-z]+ +run ([-+]?[0-9]+) .*/\1/' | sed 's/^+//')
  [ "$fin" = "$led" ] || { good=0; echo "   $e final mood $fin, ledger $led"; }
done
grep -q 'governance decisions' l1.txt && grep -q 'the answer was yes' diaries/*.jsonl && grep -q 'the answer was no' diaries/*.jsonl && [ $good = 1 ] && ok "a wesen is a little happier after a grant and sadder after a refusal; the mood ledger lists 'governance decisions' and its sums equal the diaries" || bad "govern mood ($good)"
# tamper
cp diaries/govern.txt ../govern.keep; sed -i '0,/ old=\([-0-9]*\) new=/s// old=\17 new=/' diaries/govern.txt; "$gvb" --more 0 --every 5000 > h4.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'govern.txt D' h4.txt && ok "a tampered old value in a D line: import FAILED, DRIFT" || bad "tampered D line"
cp ../govern.keep diaries/govern.txt; sed -i '0,/ kind=refuse /s// kind=grant /' diaries/govern.txt; "$gvb" --more 0 --every 5000 > h5.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "a refusal rewritten as a grant: DRIFT" || bad "refuse->grant"
cp ../govern.keep diaries/govern.txt; echo "D99999 t=5 pet=P1 player=iris wesen=ada topic=more_rest lever=rate kind=grant why=grant.fair old=0 new=4 trust=50>52 stand=50>51" >> diaries/govern.txt; "$gvb" --more 0 --every 5000 > h6.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "an invented D line: DRIFT" || bad "invented D line"
cp ../govern.keep diaries/govern.txt; cp diaries/sessions.txt ../sess.keep; sed -i '/^S1 /s/ govern=1//' diaries/sessions.txt; "$gvb" --more 0 --every 5000 > h7.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "S line with its govern=1 marker removed: DRIFT" || bad "tampered govern marker"
cp ../sess.keep diaries/sessions.txt; "$gvb" --more 0 --every 5000 > h8.txt 2>&1; grep -q '^import OK: 4 entities, 605 ticks verified' h8.txt && ok "restored: replays again" || bad "govern restore"
# veto and approve (Robert's input)
g1=$(grep '^D[0-9].* kind=grant ' diaries/govern.txt | head -1 | cut -d' ' -f1); r1=$(grep '^D[0-9].* kind=refuse ' diaries/govern.txt | head -1 | cut -d' ' -f1); g2=$(grep '^D[0-9].* kind=partial ' diaries/govern.txt | head -1 | cut -d' ' -f1)
"$gvb" --veto "$g1" > v1.txt 2>&1; rc1=$?; "$gvb" --veto "$r1" > v2.txt 2>&1; rc2=$?; "$gvb" --veto "$g1" > v3.txt 2>&1; rc3=$?; "$gvb" --approve "$r1" > v4.txt 2>&1; rc4=$?
[ $rc1 = 0 ] && [ $rc2 = 2 ] && [ $rc3 = 2 ] && [ $rc4 = 0 ] && grep -q "^V1 tick=605 decision=$g1 act=veto" diaries/vetoes.txt && grep -q "^V2 tick=605 decision=$r1 act=approve" diaries/vetoes.txt \
  && ok "make veto / approve write one V line each at the lowest common tick; a refusal cannot be vetoed and nothing is vetoed twice (exit 2)" || bad "veto input ($rc1 $rc2 $rc3 $rc4)"
"$gvb" --more 5 --every 5000 > v5.txt 2>&1
vl=$(grep " of=$g1\$" diaries/govern.txt | grep ' kind=veto '); al=$(grep " of=$r1\$" diaries/govern.txt | grep ' kind=approve ')
vt=$(echo "$vl" | sed -E 's/.* trust=([0-9]+)>([0-9]+) .*/\1 \2/'); vs=$(echo "$vl" | sed -E 's/.* stand=([0-9]+)>([0-9]+) .*/\1 \2/'); at=$(echo "$al" | sed -E 's/.* trust=([0-9]+)>([0-9]+) .*/\1 \2/'); as=$(echo "$al" | sed -E 's/.* stand=([0-9]+)>([0-9]+) .*/\1 \2/')
vo=$(echo "$vl" | sed -E 's/.* old=(-?[0-9]+) new=(-?[0-9]+) .*/\1 \2/'); go=$(grep "^$g1 " diaries/govern.txt | sed -E 's/.* old=(-?[0-9]+) new=(-?[0-9]+) .*/\1 \2/')
echo "   veto of $g1: change was ($go), veto line ($vo), trust ($vt), standing ($vs); approval of $r1: trust ($at), standing ($as)"
[ -n "$vl" ] && [ -n "$al" ] && awk -v v="$vt" -v s="$vs" -v a="$at" -v b="$as" 'BEGIN { split(v, x, " "); split(s, y, " "); split(a, p, " "); split(b, q, " "); exit !(x[2] < x[1] && y[2] < y[1] && p[2] > p[1] && q[2] > q[1]) }' \
  && ok "the veto is its own D record: the change is reverted, the player's trust and its standing with the wesen fall; an approval raises both" || bad "veto effect"
grep -q ' of=' diaries/govern.txt && grep -q 'vetoed' <("$gvb" --govern 2>&1) && ok "--govern counts the veto in the player's counter line" || bad "veto counter"
cp diaries/vetoes.txt ../vetoes.keep; sed -i '/^V1 /d' diaries/vetoes.txt; "$gvb" --more 0 --every 5000 > h9.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "a veto line removed from vetoes.txt: its D record has no source - DRIFT" || bad "removed V line"
cp ../vetoes.keep diaries/vetoes.txt; "$gvb" --more 0 --every 5000 > h10.txt 2>&1; grep -q '^import OK: 4 entities, 610 ticks verified' h10.txt && ok "veto restored: replays again" || bad "veto restore"
# bounds: a tight cool-down lever, every petition granted -> 'refuse.bound'; spam: threshold 0 -> trust falls
cp "$bin" "$w/gv/b/bin/"; cp -r "$w/gv/data" "$w/gv/b/data"; sed -i 's/^lever.cool = .*/lever.cool = -2 2 2/' "$w/gv/b/data/govern.txt"; sed -i 's/^govern.base = .*/govern.base = 200/; s/^govern.grant_share = .*/govern.grant_share = 100/' "$w/gv/b/data/limits.txt"
DIARY_HOME="$w/gv/b/h" "$w/gv/b/bin/diary_sim" --seed 42 --ticks 600 --yes --every 5000 > b1.txt 2>&1
nb=$(grep -c 'why=refuse.bound' "$w/gv/b/h/diaries/govern.txt"); ob=$(grep 'lever=cool' "$w/gv/b/h/diaries/govern.txt" | sed -E 's/.* new=(-?[0-9]+) .*/\1/' | awk '$1 < -2 || $1 > 2 { n++ } END { print n + 0 }')
[ "$nb" -ge 1 ] && [ "$ob" = 0 ] && ok "at its bound a lever is never moved further: 'refuse.bound' ($nb), cool-down never outside -2 .. 2" || bad "lever bound ($nb $ob)"
cp "$bin" "$w/gv/s/bin/"; cp -r "$w/gv/data" "$w/gv/s/data"; sed -i 's/^govern.spam = .*/govern.spam = 0/' "$w/gv/s/data/limits.txt"
DIARY_HOME="$w/gv/s/h" "$w/gv/s/bin/diary_sim" --seed 42 --ticks 600 --yes --every 5000 > s1.txt 2>&1
ns=$(grep 'why=refuse.spam' "$w/gv/s/h/diaries/govern.txt" | sed -E 's/.* trust=([0-9]+)>([0-9]+) .*/\1 \2/' | awk '$2 < $1 { n++ } END { print n + 0 }')
[ "$ns" -ge 1 ] && ok "a petition asked too often is refused as spam and the player's trust in that wesen falls ($ns)" || bad "spam ($ns)"
DIARY_HOME="$w/gv/b/h" "$w/gv/b/bin/diary_sim" --more 0 --every 5000 > b2.txt 2>&1; grep -q '^import OK' b2.txt && ok "the tight-bounds run replays and verifies" || bad "bounds replay"
# off: no marker, no file, no governance text; nothing else changes
cp "$bin" "$w/gv/off/bin/"; cp -r "$w/gv/data" "$w/gv/off/data"; sed -i 's/^govern.enabled = .*/govern.enabled = 0/' "$w/gv/off/data/limits.txt"; DIARY_HOME="$w/gv/o" "$w/gv/off/bin/diary_sim" --seed 42 --ticks 300 --yes --every 5000 > /dev/null 2>&1; DIARY_HOME="$w/gv/o" "$w/gv/off/bin/diary_sim" --govern > gn.txt 2>&1
[ ! -e "$w/gv/o/diaries/govern.txt" ] && ! grep -q 'govern=1' "$w/gv/o/diaries/sessions.txt" && ! grep -qi 'governance\|the answer was' "$w/gv/o"/diaries/*.jsonl "$w/gv/o/diaries/inbox.txt" && grep -q 'no governance' gn.txt && ok "govern.enabled = 0: no marker, no govern.txt, no governance text; --govern says so" || bad "govern off"
grep -q -- '--govern' "$root/data/help.txt" && grep -q -- '--veto' "$root/data/help.txt" && grep -q 'make govern' "$root/README.md" && grep -q 'make veto' "$root/README.md" && grep -q 'govern.base' "$root/data/limits.txt" && grep -q 'lever.rate' "$root/data/govern.txt" && ok "--help, README, limits and data/govern.txt describe the governance" || bad "govern docs"
unset DIARY_HOME

rm -rf "$w"
echo "== checks: $fails failure(s) =="
[ "$fails" = 0 ]
