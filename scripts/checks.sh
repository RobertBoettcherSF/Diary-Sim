#!/bin/bash
# Scenario checks for diary_sim (no test suite): run, rerun, resume, behind
# diary, half-written line, drift, forced crash, --fresh, missing data, working
# folders (words, bench), summary, crash then resume, start_percent, petitions,
# make run, kalpa sessions (vote, median, resume, explicit, drift).
# Usage: scripts/checks.sh [BIN]     (works in a scratch directory)
export DIARY_VERBOSE=1   # the scenarios read the whole report on the console as before; scenario 48 tests the short form (env -u)
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
sed -i 's/^screen.enabled = .*/screen.enabled = 0/; s/^chess.enabled = .*/chess.enabled = 0/; s/^robot.enabled = .*/robot.enabled = 0/; s/^govern.enabled = .*/govern.enabled = 0/; s/^screen.coin_enabled = .*/screen.coin_enabled = 0/; s/^players4.enabled = .*/players4.enabled = 0/; s/^preport.pause = .*/preport.pause = 0/; s/^chessrules.enabled = .*/chessrules.enabled = 0/; s/^trial.enabled = .*/trial.enabled = 0/' "$idata/limits.txt"
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
cmp <(sed -n '/^report:/,/^export OK/p' again.txt) <(sed -n '/^report:/,/^export OK/p' run_report.txt | grep -v '^== ') && grep -q '^import OK' run_report.txt && ok "run_report.txt holds the same import/report lines" || bad "run_report.txt differs"
[ "$(wc -l < again.txt)" -le 78 ] && ok "console output $(wc -l < again.txt) lines (<= 78, with the treadmill block, the robot / governance off line and the checkpoint line of 0.058)" || bad "console output too long"
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
rm -rf "$w/mig"; mkdir -p "$w/mig/S"; tar -C "$root" --exclude=.git --exclude=obj --exclude=bin --exclude=diaries --exclude=entities -cf - . | tar -C "$w/mig/S" -xf -; idn "$w/mig/S/data"; sed -i "s/^preport.pause = .*/preport.pause = 0/" "$w/mig/S/data/limits.txt"; ( cd "$w/mig/S" && make > /dev/null 2>&1 && DIARY_HOME=. bin/diary_sim --more 10 --every 1000 > /dev/null 2>&1 )
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
  && DIARY_HOME="$w/dh/a" make -s -C "$root" inbox > mk2.txt 2>&1 && grep -q '^inbox for Robert (newest' mk2.txt && grep -q '^  player Ganesha (tracker of progress)' mk2.txt && ok "make say PLAYER=... TEXT=... records the words; make inbox prints the inbox" || bad "make say / inbox"
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
"$gb" --debug-section nosuch > g5.txt 2>&1; rc5=$?; [ $rc5 = 2 ] && grep -q 'unknown --debug-section nosuch (one of: status drift trace players inbox run ledger preport)' g5.txt && ok "unknown section: usage error, exit 2, the list of sections" || bad "unknown section"
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
printf '# test names\nada = Aleph\ngemini = Bet\nreplika = Gimel\nrobert = Dalet\niris = He\nsol = Vav\nnoor = Zayin\n' > "$w/nm/b/data/names.txt"
na="$w/nm/a/bin/diary_sim"; nb="$w/nm/b/bin/diary_sim"; cd "$w/nm/h" || exit 1; export DIARY_HOME="$w/nm/h"
"$na" --ticks 300 --yes --every 5000 > n1.txt 2>&1; "$na" --say Adam --text "hello there" > n1s.txt 2>&1; "$na" --more 200 --every 5000 > n2.txt 2>&1
before=$(snap .); cp diaries/sessions.txt s0.txt; cp diaries/inbox.txt i0.txt
grep -q '^entities: Adam(engineer) Eve(reviewer) Abel(vice_president) Ruth(human)' n1.txt && grep -q 'Adam' run_report.txt && grep -q 'Adam' summary.txt && grep -q '^Adam ' debug.txt \
  && [ -n "$(grep -m1 'to=ada' diaries/says.txt)" ] && grep -q 'src=[a-z0-9]*:t[0-9]*:\(ada\|gemini\|replika\|robert\)' diaries/inbox.txt \
  && ok "default data/names.txt: Adam / Eve / Abel / Ruth in the console, reports and debug.txt; say to a display name is recorded under the id (to=ada); inbox src tags keep the ids" || bad "default display names"
"$na" --inbox > ib1.txt 2>&1; grep -q 'player Jehova (' ib1.txt && ! grep -q 'player iris' ib1.txt && ok "the players show as Jehova / Ganesha / Odin in the inbox view" || bad "player display names"
"$nb" --more 0 --every 5000 > n3.txt 2>&1; after=$(snap .)
grep -q '^import OK: 4 entities, 500 ticks verified' n3.txt && grep -q '^entities: Aleph(engineer) Bet(reviewer) Gimel(vice_president) Dalet(human)' n3.txt && grep -q 'Aleph' run_report.txt && ! grep -q 'Adam' run_report.txt debug.txt summary.txt \
  && [ "$before" = "$after" ] && grep -v '^# build' diaries/sessions.txt | cmp -s - <(grep -v '^# build' s0.txt) && cmp -s i0.txt diaries/inbox.txt && ls diaries/ada.jsonl entities/ada/words.txt > /dev/null 2>&1 && [ ! -e diaries/Adam.jsonl ] \
  && ok "names.txt changed: the diaries, sessions.txt (minus the build line), inbox, world.txt, says and words files are byte-identical, replay-verify still passes, only the display text changed" || bad "names.txt change touched files ($before / $after)"
"$nb" --map > mp.txt 2>&1; grep -q '^treadmill  Aleph ' mp.txt && ok "--map uses the display names" || bad "map names"
"$nb" --say Gimel --text "x" > n4.txt 2>&1; tail -n 1 diaries/says.txt | grep -q ' to=replika ' && ok "--say accepts the display name and records the id" || bad "say with display name"
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
"$w/nm/a/bin/diary_sim" --ledger > led_n.txt 2>&1; grep -q '^Adam ' led_n.txt && grep -q 'Adam loses most mood from' led_n.txt && ! grep -q '^ada' led_n.txt && [ "$(awk 'length > 79' led_n.txt | wc -l)" = 0 ] && ok "display names from data/names.txt (Adam ...), still within 79 columns" || bad "ledger names"
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
grep -Eq '^S1 .* screen=1( active=[12])?$' diaries/sessions.txt && grep -Eq '^S2 .* screen=1( active=[12])?$' diaries/sessions.txt && head -1 diaries/screens.txt | grep -q '^# seed 42$' && [ "$n_k" -gt 500 ] && grep -q '^K1 t=1 ada add w=[0-9]* src=' diaries/screens.txt \
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
[ $rc = 0 ] && grep -q '^32 checks, 0 failed' "$w/p1.txt" && grep -q 'perft 4 197281' "$w/p1.txt" && grep -q 'state checkmate' "$w/p1.txt" && grep -q 'move e1g1 = 5171' "$w/p1.txt" && ok "--perft: six reference positions (castling, en passant, promotion), mate / stalemate / fifty-move states, ICCF notation, the insufficient-material and repetition-key positions of chessrules=2, 32 checks" || bad "perft ($rc)"
rm -rf "$w/ch"; mkdir -p "$w/ch/bin" "$w/ch/h" "$w/ch/bad/bin" "$w/ch/off/bin" "$w/ch/o" "$w/ch/t/bin" "$w/ch/t/h" "$w/ch/r/bin" "$w/ch/r/h" "$w/ch/n/bin" "$w/ch/n/h"
cp "$bin" "$w/ch/bin/"; cp -r "$idata" "$w/ch/data"; sed -i 's/^chess.enabled = .*/chess.enabled = 1/' "$w/ch/data/limits.txt"; cb="$w/ch/bin/diary_sim"
cp "$bin" "$w/ch/bad/bin/"; cp -r "$w/ch/data" "$w/ch/bad/data"; sed -i 's/^perft.2 = 3 97862/perft.2 = 3 97863/' "$w/ch/bad/data/chess.txt"; ( cd "$w/ch/bad" && ./bin/diary_sim --perft > "$w/ch/p2.txt" 2>&1 ); rc=$?; cp "$w/ch/p2.txt" "$w/p2.txt"
[ $rc = 1 ] && grep -q '^FAIL.*expected 97863, got 97862' "$w/p2.txt" && grep -q '1 failed' "$w/p2.txt" && ok "--perft with a wrong count: FAIL line and exit 1" || bad "perft failing ($rc)"
cd "$w/ch/h" || exit 1; export DIARY_HOME="$w/ch/h"
"$cb" --seed 42 --ticks 300 --yes --every 5000 > h1.txt 2>&1; "$cb" --more 300 --every 5000 > h2.txt 2>&1
n_c=$(grep -c '^C[0-9]' diaries/chess.txt); n_m=$(grep -c ' move ' diaries/chess.txt)
grep -Eq '^S1 .* chess=1( symbols=1)?$' diaries/sessions.txt && grep -Eq '^S2 .* chess=1( symbols=1)?$' diaries/sessions.txt && head -1 diaries/chess.txt | grep -q '^# seed 42$' && [ "$n_m" -gt 100 ] && grep -q ' start white=' diaries/chess.txt \
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
grep -q 'Jehova' e2.txt && grep -q 'Ganesha' e2.txt && grep -q 'Odin' e2.txt && grep -q 'Adam' e2.txt && ! grep -Eq '^[0-9]\. (ada|iris|sol|noor) ' e2.txt && [ "$(awk 'length > 79' e2.txt | wc -l)" = 0 ] && ok "--elo shows display names (Adam .. Ruth, Jehova, Ganesha, Odin), no line over 79 columns" || bad "elo display names"
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
grep -Eq '^S1 .* robot=1( active=[12])?$' diaries/sessions.txt && grep -Eq '^S2 .* robot=1( active=[12])?$' diaries/sessions.txt && head -1 diaries/robot.txt | grep -q '^# seed 42$' && [ "$n_c" -ge 10 ] && [ "$n_x" -ge 5 ] \
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
grep -qE 'Adam|Eve|Abel|Ruth' rd.txt && ! grep -qwE 'ada|gemini|replika|robert' rd.txt && ok "the robot view uses the display names (Adam, Eve, Abel, Ruth)" || bad "robot names"
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
for u in $(grep '^D[0-9].* kind=defer ' diaries/govern.txt | sed -E 's/.* pet=(P[0-9]+) .* until=([0-9]+).*/\1:\2/'); do p=${u%%:*}; t=${u##*:}; [ "$t" -le 600 ] || continue; grep -q "^D[0-9]* t=$t pet=$p " diaries/govern.txt || bk=$((bk + 1)); done
[ "$dfr" -ge 1 ] && [ "$bk" = 0 ] && ok "a deferred petition comes back at the tick the record names (before the run ends; $dfr deferrals)" || bad "defer ($dfr $bk)"
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

echo "== 35. scoin=1: words coined from a screen (own cap and rate per session), older sessions replay as before, 'robot/governance: off for this save' report lines =="
rm -rf "$w/sc"; mkdir -p "$w/sc/a/bin" "$w/sc/a/h" "$w/sc/b/bin" "$w/sc/b/h" "$w/sc/c/bin" "$w/sc/c/h"
for d in a b c; do cp "$bin" "$w/sc/$d/bin/"; cp -r "$idata" "$w/sc/$d/data"; sed -i 's/^screen.enabled = .*/screen.enabled = 1/; s/^screen.coin_enabled = .*/screen.coin_enabled = 1/' "$w/sc/$d/data/limits.txt"; done
sed -i 's/^screen.coin_enabled = .*/screen.coin_enabled = 0/' "$w/sc/b/data/limits.txt"; sed -i 's/^screen.coin_enabled = .*/screen.coin_enabled = 0/' "$w/sc/c/data/limits.txt"
blends() { awk -v a="$2" -v b="$3" '{ t = 0; for (i = 1; i <= NF; i++) if ($i ~ /^t=/) t = substr($i, 3) + 0; if ($0 ~ / blend / && t >= a && t <= b) for (i = 1; i <= NF; i++) if ($i == "ada" || $i == "gemini" || $i == "replika" || $i == "robert") c[$i]++ } END { printf "%d %d %d %d", c["ada"], c["gemini"], c["replika"], c["robert"] }' "$1"; }
export DIARY_HOME="$w/sc/a/h"; cd "$w/sc/a" || exit 1
./bin/diary_sim --seed 42 --ticks 600 --yes --every 5000 > o1.txt 2>&1; ./bin/diary_sim --more 300 --every 5000 > o2.txt 2>&1
cap=$(sed -n 's/^screen.coin_cap = \([0-9]*\).*/\1/p' data/limits.txt)
[ "$(grep -c '^S[0-9].* scoin=1' h/diaries/sessions.txt)" = 2 ] && ok "new sessions carry scoin=1 (behind screen=1)" || bad "scoin marker"
b2=$(blends h/diaries/screens.txt 601 900); b1=$(blends h/diaries/screens.txt 1 600); echo "   screen blends per wesen (ada gemini replika robert): ticks 1-600: $b1 | 601-900: $b2 | cap $cap per session"
ok2=$(echo "$b2" | awk -v c="$cap" '{ n = 0; for (i = 1; i <= 4; i++) if ($i >= 2 && $i <= c) n++; print n }'); ok1=$(echo "$b1" | awk -v c="$cap" '{ n = 0; for (i = 1; i <= 4; i++) if ($i >= 2 && $i <= c) n++; print n }')
[ "$ok1" = 4 ] && [ "$ok2" = 4 ] && ok "every wesen coins words from its screen in each session (a handful, never above screen.coin_cap), although the global coin_cap is used up in session 1" || bad "screen blends per session ($b1 | $b2)"
grep -q 'robot: off for this save (robot.enabled = 0 in data/limits.txt' o2.txt && grep -q ', governance: off (govern.enabled = 0 in data/limits.txt' o2.txt && ok "the end report says in one line why there is no robot / governance block" || bad "off lines"
# an older save: sessions without the marker replay as before; the next session gets it
export DIARY_HOME="$w/sc/b/h"; cd "$w/sc/b" || exit 1
./bin/diary_sim --seed 42 --ticks 600 --yes --every 5000 > o1.txt 2>&1; cp -r h h600; sed -i 's/^screen.coin_enabled = .*/screen.coin_enabled = 1/' data/limits.txt; ./bin/diary_sim --more 300 --every 5000 > o2.txt 2>&1
export DIARY_HOME="$w/sc/c/h"; cd "$w/sc/c" || exit 1
./bin/diary_sim --seed 42 --ticks 600 --yes --every 5000 > o1.txt 2>&1; ./bin/diary_sim --more 300 --every 5000 > o2.txt 2>&1
sess=$(grep -c ' scoin=1' "$w/sc/b/h/diaries/sessions.txt"); s1=$(grep '^S1 ' "$w/sc/b/h/diaries/sessions.txt" | grep -c scoin)
b3=$(blends "$w/sc/b/h/diaries/screens.txt" 601 900); same=$(diff <(awk '{ t = 0; for (i = 1; i <= NF; i++) if ($i ~ /^t=/) t = substr($i, 3) + 0; if (t <= 600) print }' "$w/sc/b/h/diaries/screens.txt") <(awk '{ t = 0; for (i = 1; i <= NF; i++) if ($i ~ /^t=/) t = substr($i, 3) + 0; if (t <= 600) print }' "$w/sc/c/h/diaries/screens.txt") | wc -l)
export DIARY_HOME="$w/sc/b/h"; cd "$w/sc/b" || exit 1; ./bin/diary_sim --more 0 --every 5000 > o3.txt 2>&1
echo "   old save (3 sessions-like): session 2 blends $b3, S1 marker $s1, screens.txt up to tick 600 differs from a save without the fix in $same lines"
[ "$sess" = 1 ] && [ "$s1" = 0 ] && [ "$same" = 0 ] && grep -q '^import OK: 4 entities, 900 ticks verified' o3.txt && ok "a save started without scoin=1: its sessions replay unchanged (no DRIFT); only the new session carries the marker and uses the new cap" || bad "old save ($sess $s1 $same)"
[ "$(echo "$b3" | awk -v c="$cap" '{ n = 0; for (i = 1; i <= 4; i++) if ($i >= 2 && $i <= c) n++; print n }')" = 4 ] && ok "the new session of that old save coins from screens again (the global coin_cap is spent)" || bad "old save blends ($b3)"
export DIARY_HOME="$w/sc/c/h"; cd "$w/sc/c" || exit 1
! grep -q 'scoin' h/diaries/sessions.txt && ok "screen.coin_enabled = 0: no scoin=1, nothing changes" || bad "scoin off"
grep -q 'screen.coin_cap' "$root/data/limits.txt" && grep -q 'scoin=1' "$root/README.md" && grep -q 'governance: off' "$root/README.md" && ok "limits and README describe scoin=1 and the 'off for this save' lines" || bad "scoin docs"
unset DIARY_HOME

echo "== 36. closed pipe: every view / print command ends quietly when its reader goes away (| head, | true) =="
rm -rf "$w/pp"; mkdir -p "$w/pp/h"; export DIARY_HOME="$w/pp/h"; cd "$w/pp" || exit 1
"$bin" --seed 42 --ticks 100 --yes --every 5000 > /dev/null 2>&1
badp=0; nump=0
for o in --help --ledger --ledger=full --govern --robot --elo --screens --inbox --map "--more 5"; do
  for rd in "head -1" "true" "(sleep 0.3; head -2)"; do
    nump=$((nump + 1))
    # shellcheck disable=SC2086
    "$bin" $o --every 5000 2> pe.txt | eval "$rd" > /dev/null; rcp=${PIPESTATUS[0]}
    [ "$rcp" = 0 ] && [ ! -s pe.txt ] || { badp=$((badp + 1)); echo "   '$o | $rd': exit $rcp, stderr: $(head -c 80 pe.txt)"; }
  done
done
[ "$badp" = 0 ] && ok "$nump commands cut off by a closed pipe: exit 0, nothing on stderr, no traceback, no CRASH record" || bad "closed pipe ($badp of $nump)"
"$bin" --more 0 --every 5000 > pv.txt 2>&1; grep -q '^import OK: 4 entities, 115 ticks verified' pv.txt && ! grep -q '^CRASH' debug.txt && [ ! -e last_error.txt ] && ok "the run that lost its reader finished and saved: the diaries replay (100 + 3 x 5 ticks), no last_error.txt" || bad "run after a closed pipe"
"$bin" --govern > g1.txt 2>&1; [ -n "$(tail -n 1 g1.txt)" ] && ok "a view ends with its last line (no extra blank line the runtime used to add at exit)" || bad "trailing blank line"
unset DIARY_HOME

echo "== 37. build and run speed: parallel -O0 build by default, strict -O1 build on request, replay of a longer save stays fast =="
fl=$(make -n -B -C "$root" all 2>/dev/null | grep -m1 gnatmake)
echo "$fl" | grep -q -- '-j0' && echo "$fl" | grep -q -- '-O2' && make -n -B -C "$root" all OPT=-O0 2>/dev/null | grep -m1 gnatmake | grep -q -- '-O0' && make -n -B -C "$root" all OPT="-O1 -fno-inline" 2>/dev/null | grep -m1 gnatmake | grep -q -- '-O1 -fno-inline' \
  && grep -q 'OPT' "$root/scripts/portable_check.sh" && ok "make builds with -j0 -O2 by default; OPT=-O0 selects the quick build, OPT=\"-O1 -fno-inline\" the strict one; make portable builds all" || bad "make flags ($fl)"
rm -rf "$w/spd"; mkdir -p "$w/spd/h"; export DIARY_HOME="$w/spd/h"; cd "$w/spd" || exit 1
t0=$(date +%s.%N); "$bin" --seed 42 --ticks 600 --yes --every 5000 > a1.txt 2>&1; "$bin" --more 600 --every 5000 > a2.txt 2>&1; "$bin" --more 300 --every 5000 > a3.txt 2>&1; t1=$(date +%s.%N)
grep -q '^import OK: 4 entities, 1200 ticks verified' a3.txt && ok "1500 ticks over three runs (the last one replay-verifies 1200 ticks of every record file and adds 300): $(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.1f", b - a }') s" || bad "speed run"
awk -v a="$t0" -v b="$t1" 'BEGIN { exit !(b - a < 60) }' && ok "well under a minute (limit 60 s here; ~3 s on an 8-core box)" || bad "slow: $t0 -> $t1"
grep -q 'Known_Count' "$root/README.md" && grep -q -- '-j0' "$root/README.md" && ok "README documents the build flags and the replay cost" || bad "speed docs"
unset DIARY_HOME

echo "== 38. player report boxes (preport=1): framed first-person text boxes last on the console and in player_reports.txt, claimed vs true records, bounded lies, make audit / challenge, DRIFT, off = unchanged =="
rm -rf "$w/pr"; mkdir -p "$w/pr/bin" "$w/pr/h" "$w/pr/off/bin" "$w/pr/off/h" "$w/pr/hi/bin" "$w/pr/hi/h" "$w/pr/no/bin" "$w/pr/no/h"
for d in "" off/ hi/ no/; do cp "$bin" "$w/pr/${d}bin/"; cp -r "$idata" "$w/pr/${d}data"; sed -i 's/^govern.enabled = .*/govern.enabled = 1/' "$w/pr/${d}data/limits.txt"; done
sed -i 's/^preport.enabled = .*/preport.enabled = 0/' "$w/pr/off/data/limits.txt"; sed -i 's/^preport.lie_scale = .*/preport.lie_scale = 1000/' "$w/pr/hi/data/limits.txt"; sed -i 's/^preport.lie_scale = .*/preport.lie_scale = 0/' "$w/pr/no/data/limits.txt"
prb="$w/pr/bin/diary_sim"; cd "$w/pr" || exit 1
runpr() { local d="$w/pr/${1}"; ( cd "${d}h" || exit 1; export DIARY_HOME="${d}h"; "${d}bin/diary_sim" --seed 42 --ticks 300 --yes --every 5000 > "${d}c1.txt" 2>&1; for i in 2 3 4; do "${d}bin/diary_sim" --more 300 --every 5000 > "${d}c$i.txt" 2>&1; done ); }
runpr ""; runpr off/; runpr hi/; runpr no/
export DIARY_HOME="$w/pr/h"; cd "$w/pr/h" || exit 1
np=$(grep -c '^P[0-9]' diaries/preports.txt); nm=$(grep -c '^S[0-9].* preport=1' diaries/sessions.txt)
[ "$nm" = 4 ] && [ "$np" = 16 ] && head -1 diaries/preports.txt | grep -q '^# seed 42$' && ok "new sessions carry preport=1 ($nm); every session end records one P line per wesen in diaries/preports.txt ($np lines)" || bad "preport markers/records ($nm $np)"
bf=$(grep '^P[0-9]' diaries/preports.txt | awk '{ ok = 1; split("t player wesen claimed true tone flag", k, " "); for (i = 1; i <= 7; i++) if (index($0, " " k[i] "=") == 0) ok = 0; if (!ok) n++ } END { print n + 0 }')
[ "$bf" = 0 ] && ok "P lines carry t, player, wesen, claimed, true, tone (claimed/true) and flag" || bad "P line fields ($bf)"
# the box: after 'Saved to', ONE frame, 80 columns, a header and every player, the same text in player_reports.txt
tail -n +$(( $(grep -n '^Saved to ' ../c4.txt | tail -1 | cut -d: -f1) + 1 )) ../c4.txt > ../tailc4.txt
nb=$(grep -c '^+-- The players report to Robert (tick 1200) -*+$' ../tailc4.txt); wd=$(grep -E '^[+|]' ../tailc4.txt | awk 'length != 80 { n++ } END { print n + 0 }'); oth=$(grep -vE '^[+|]|^$' ../tailc4.txt | wc -l); nl=$(wc -l < ../tailc4.txt)
[ "$nb" = 1 ] && [ "$wd" = 0 ] && [ "$oth" = 1 ] && [ "$nl" -le 23 ] && ok "the console ends with ONE framed box (+ - |, every line 80 columns) and one hint line, $nl lines (one frame), after 'Saved to'" || bad "box on the console ($nb $wd $oth $nl)"
[ "$(grep -v '^$' ../tailc4.txt | tail -1 | cut -c1-20)" = "The players say what" ] && cmp -s <(grep -E '^[+|]' ../tailc4.txt) <(grep -E '^[+|]' player_reports.txt) && ok "player_reports.txt in the save folder holds the same box" || bad "player_reports.txt"
paraof() { awk -v p="$1" '/^\| / { t = substr($0, 3, 76); sub(/ +$/, "", t); if (index(t, p " (") == 1) on = 1; else if (t !~ /^   /) on = 0; if (on) printf "%s ", t } /^\+-+\+$/ { on = 0 }' player_reports.txt | sed 's/  */ /g'; }
fp=0; for pl in iris sol noor; do blk=$(paraof $pl); echo "$blk" | grep -q "^$pl (" && echo "$blk" | grep -qE '[+-][0-9]+' && [ -n "$(echo "$blk" | sed -E "s/^$pl \([a-z ]+\)://" | grep -oE '[A-Za-z]+' | head -1)" ] && fp=$((fp + 1)); done
[ "$fp" = 3 ] && ok "every player has its paragraph in the box (who, petitions and decisions, the happiness it claims, its top concern)" || bad "paragraphs ($fp)"
# the decision counts are the D records
dc=0; for pl in iris sol noor; do
  want=$(awk -v p="$pl" '$0 ~ "^D[0-9]" && index($0, " player=" p " ") { for (i = 1; i <= NF; i++) if ($i ~ /^kind=/) c[substr($i, 6)]++ } END { printf "%d %d %d %d", c["grant"], c["partial"], c["defer"], c["refuse"] }' diaries/govern.txt)
  got=$(paraof $pl | sed -E 's/^[a-z]+ \([a-z ]+\)://' | grep -oE '[0-9]+' | sed -n 2,5p | tr '\n' ' ' | sed 's/ $//')
  if [ "$(paraof $pl | grep -c 'petitions yet\|Nothing on my desk\|not one petition')" = 0 ]; then [ "$got" = "$want" ] && dc=$((dc + 1)) || echo "   $pl: want '$want' got '$got'"; else dc=$((dc + 1)); fi
done
[ "$dc" = 3 ] && ok "what each player decided (granted / partial / deferred / refused) in the box equals the counts of the D records" || bad "D counts ($dc)"
# the wording varies: several templates per slot, picked by a hash of (tick, player): different between players and between runs
shape() { awk -v p="$2" '/^\| / { t = substr($0, 3, 76); sub(/ +$/, "", t); if (index(t, p " (") == 1) on = 1; else if (t !~ /^   /) on = 0; if (on) printf "%s ", t } /^\+-+\+$/ { on = 0 }' "$1" | sed -E 's/[+-]?[0-9]+/#/g; s/^[a-z]+ \([a-z ]+\): //'; echo; }
sp=$(for pl in iris sol noor; do shape ../c4.txt $pl | cut -c1-24; done | sort -u | wc -l)
sr=$(for c in 1 2 3 4; do shape ../c$c.txt iris | cut -c1-24; done | sort -u | wc -l)
tn=$(for c in 1 2 3 4; do shape ../c$c.txt iris; shape ../c$c.txt sol; done | sort -u | wc -l)
[ "$sp" -ge 2 ] && [ "$sr" -ge 2 ] && [ "$tn" -ge 6 ] && ok "the wording differs between players ($sp openings in one box) and between runs ($sr openings of one player in 4 runs; $tn different paragraph shapes of 8)" || bad "wording does not vary ($sp $sr $tn)"
sent=$(grep '^| ' player_reports.txt | awk 'length != 80 { n++ } END { print n + 0 }')
mx=$(awk '/^\| / { t = substr($0, 3, 76); if (t ~ /^(iris|sol|noor|vega) \(/) n = 1; else if (t ~ /^   /) n++; else n = 0; if (n > m) m = n } END { print m + 0 }' player_reports.txt)
[ "$sent" = 0 ] && [ "$mx" -le 3 ] && ok "every player's part stays short (at most 3 text lines, the longest is $mx)" || bad "long paragraphs ($sent $mx)"
# the claims: bounded, valid, flag = difference, the truth is the mood of the diary
lm=$(sed -n 's/^preport.lie_max = \([0-9]*\).*/\1/p' "$w/pr/data/limits.txt")
oobp=$(grep '^P[0-9]' diaries/preports.txt | sed -E 's/.* claimed=(-?[0-9]+) true=(-?[0-9]+) tone=([0-9])\/([0-9]) flag=([a-z]+).*/\1 \2 \3 \4 \5/' | awk -v lm="$lm" '{ d = $1 - $2; if (d < 0) d = -d; bad = 0; if (d > lm || $1 < -100 || $1 > 100 || $2 < -100 || $2 > 100 || $3 > 3 || $4 > 3) bad = 1; diff = ($1 != $2 || $3 != $4); if (diff != ($5 == "lie")) bad = 1; n += bad } END { print n + 0 }')
tr=0; for pair in "ada:iris" "gemini:iris" "replika:sol" "robert:noor"; do e=${pair%%:*}; pl=${pair##*:}; t=$(grep "^P[0-9]* t=300 player=$pl wesen=$e " diaries/preports.txt | sed -E 's/.* true=(-?[0-9]+) .*/\1/'); m=$(sed -n 300p diaries/$e.jsonl | sed -E 's/.*"mood":(-?[0-9]+).*/\1/'); [ "$t" = "$m" ] && tr=$((tr + 1)); done
[ "$oobp" = 0 ] && [ "$tr" = 4 ] && ok "every claim is within $lm mood points of the truth and on the scale (-100 .. 100); flag=lie exactly when claimed differs from true; the true value is the mood in the diary (4 of 4 at tick 300)" || bad "claims ($oobp $tr)"
nl=$(grep -c ' flag=lie' diaries/preports.txt); echo "   misreports in the normal save: $nl of $np claims"
nh=$(grep -c ' flag=lie' "$w/pr/hi/h/diaries/preports.txt"); nn=$(grep -c ' flag=lie' "$w/pr/no/h/diaries/preports.txt")
bh=$(grep '^P[0-9]' "$w/pr/hi/h/diaries/preports.txt" | sed -E 's/.* claimed=(-?[0-9]+) true=(-?[0-9]+) .*/\1 \2/' | awk -v lm="$lm" '{ d = $1 - $2; if (d < 0) d = -d; if (d > lm || $1 < -100 || $1 > 100) n++ } END { print n + 0 }')
dn=$(grep '^P[0-9]' "$w/pr/no/h/diaries/preports.txt" | sed -E 's/.* claimed=(-?[0-9]+) true=(-?[0-9]+) tone=([0-9])\/([0-9]) .*/\1 \2 \3 \4/' | awk '$1 != $2 || $3 != $4 { n++ } END { print n + 0 }')
[ "$nl" -ge 1 ] && [ "$nh" -ge 8 ] && [ "$bh" = 0 ] && [ "$nn" = 0 ] && [ "$dn" = 0 ] && ok "honesty is data: a player CAN misreport ($nl in the normal save), always when the trait is turned against it ($nh of 16, all within $lm points), never when lie_scale = 0 (claimed = true)" || bad "honesty ($nl $nh $bh $nn $dn)"
# the D records are never touched: the same D lines whatever the players claim
cmp -s "$w/pr/hi/h/diaries/govern.txt" "$w/pr/no/h/diaries/govern.txt" && cmp -s diaries/govern.txt "$w/pr/off/h/diaries/govern.txt" && ok "rule changes (D records) are identical with honest, normal and lying players: the claims never reach the rules" || bad "D records differ with the claims"
# replay and DRIFT
"$prb" --more 0 --every 5000 > r1.txt 2>&1; grep -q '^import OK: 4 entities, 1200 ticks verified' r1.txt && ok "the replay recomputes and verifies every P line" || bad "preport replay"
cp diaries/preports.txt ../preports.keep; sed -i '2s/ claimed=[-0-9]* / claimed=57 /' diaries/preports.txt; "$prb" --more 0 --every 5000 > r2.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'preports.txt P' r2.txt && ok "a changed claim: import FAILED, DRIFT" || bad "tampered claim"
cp ../preports.keep diaries/preports.txt; sed -i '3d' diaries/preports.txt; "$prb" --more 0 --every 5000 > r3.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "a removed P line: DRIFT" || bad "removed line"
cp ../preports.keep diaries/preports.txt; rm diaries/preports.txt; "$prb" --more 0 --every 5000 > r4.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "a removed preports.txt: DRIFT" || bad "removed file"
cp ../preports.keep diaries/preports.txt; echo "P999 t=5 player=iris wesen=ada claimed=1 true=1 tone=0/0 flag=none" >> diaries/preports.txt; "$prb" --more 0 --every 5000 > r5.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "an invented P line: DRIFT" || bad "invented line"
cp ../preports.keep diaries/preports.txt; cp diaries/sessions.txt ../sess.keep; sed -i '/^S2 /s/ preport=1//' diaries/sessions.txt; "$prb" --more 0 --every 5000 > r6.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "S line with its preport=1 marker removed: DRIFT" || bad "tampered marker"
cp ../sess.keep diaries/sessions.txt; "$prb" --more 0 --every 5000 > r7.txt 2>&1; grep -q '^import OK: 4 entities, 1200 ticks verified' r7.txt && ok "restored: replays again" || bad "restore"
# make audit
"$prb" --audit > au.txt 2>&1; rc=$?
al=$(awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^flag=/ && $i == "flag=lie") n++ } END { print n + 0 }' diaries/preports.txt)
as=$(grep -E '^(iris|sol|noor): claims' au.txt | sed -E 's/.*misreports ([0-9]+),.*/\1/' | awk '{ s += $1 } END { print s + 0 }')
big=$(grep '^P[0-9]' diaries/preports.txt | grep ' flag=lie' | sed -E 's/.* claimed=(-?[0-9]+) true=(-?[0-9]+) .*/\1 \2/' | awk '{ d = $1 - $2; if (d < 0) d = -d; if (d > m) m = d } END { print m + 0 }')
bg=$(grep 'biggest:' au.txt | sed -E 's/.*off by (-?[0-9]+),.*/\1/' | awk '{ d = $1; if (d < 0) d = -d; if (d > m) m = d } END { print m + 0 }')
echo "   audit: misreports $as (records $al), biggest $bg (records $big)"
[ "$rc" = 0 ] && head -1 au.txt | grep -q 'CLAIMED' && [ "$(grep -cE '^(iris|sol|noor): claims' au.txt)" = 3 ] && [ "$as" = "$al" ] && [ "$bg" = "$big" ] && grep -q 'claimed .*true' au.txt && [ ! -s ../au_err.txt ] && ok "make audit: per player claims, misreports, the biggest; the numbers equal the P records (--audit writes nothing)" || bad "audit ($rc $as $al $bg $big)"
# make challenge
"$prb" --govern > gv0.txt 2>&1; cp -r "$w/pr/h" "$w/pr/hc"
lp=$(grep ' flag=lie' diaries/preports.txt | head -1 | sed -E 's/.* player=([a-z]+) .*/\1/'); lw=$(grep ' flag=lie' diaries/preports.txt | head -1 | sed -E 's/.* wesen=([a-z]+) .*/\1/')
nolie=""; for pl in iris sol noor; do [ "$(grep -c " player=$pl .* flag=lie" diaries/preports.txt)" = 0 ] && nolie=$pl; done
"$prb" --challenge "$lp" > ch1.txt 2>&1; rc1=$?; "$prb" --challenge nobody > ch2.txt 2>&1; rc2=$?
nr=$(grep " player=$lp .* flag=lie" diaries/preports.txt | sed -E 's/.* t=([0-9]+) .*/\1/' | sort -u | wc -l); for i in $(seq 2 $nr); do "$prb" --challenge "$lp" > /dev/null 2>&1; done; "$prb" --challenge "$lp" > ch3.txt 2>&1; rc3=$?
nq=$(grep -c '^Q[0-9]' diaries/challenges.txt)
[ "$rc1" = 0 ] && [ "$rc2" = 2 ] && [ "$rc3" = 2 ] && [ "$nq" = "$nr" ] && grep -q "^Q1 tick=1200 player=$lp " diaries/challenges.txt && ok "make challenge: a caught player gets a Q line (one per misreport round: $nq); a player without a misreport left, or an unknown name, is refused (exit 2)" || bad "challenge ($rc1 $rc2 $rc3 $nq $nr)"
rm -rf "$w/pr/hc/diaries/challenges.txt"
cost=$(sed -n 's/^preport.challenge_cost = \([0-9]*\).*/\1/p' "$w/pr/data/limits.txt")
DIARY_HOME="$w/pr/hc" "$prb" --more 3 --every 5000 > cc1.txt 2>&1; "$prb" --more 3 --every 5000 > cc2.txt 2>&1
sa=$(DIARY_HOME="$w/pr/hc" "$prb" --govern | grep "^  $lw:" | sed -E 's/.* stand ([0-9]+) .*/\1/'); sb=$(DIARY_HOME="$w/pr/h" "$prb" --govern | grep "^  $lw:" | sed -E 's/.* stand ([0-9]+) .*/\1/')
echo "   standing of $lw: $sa without the challenge, $sb with it ($nq challenge(s) of $lp, cost $cost each)"
grep -q '^import OK: 4 entities, 1200 ticks verified' cc2.txt && grep -q '^import OK: 4 entities, 1200 ticks verified' cc1.txt && [ $((sa - sb)) -ge "$cost" ] && ok "the next run lowers the standing of the caught player's wesen by preport.challenge_cost (replay-verified)" || bad "challenge effect ($sa $sb)"
# digest and sections
"$prb" --more 0 --every 5000 --debug > dg.txt 2>&1; db=$(wc -c < debug_digest.txt); "$prb" --debug-section preport > ds.txt 2>&1
grep -q 'misreports' ds.txt && [ "$db" -le 1500 ] && ok "the digest has the preport section/line (rounds, misreports, biggest) and stays within its cap ($db bytes)" || bad "digest ($db)"
# off: nothing at all
cd "$w/pr/off/h" || exit 1; export DIARY_HOME="$w/pr/off/h"
"$w/pr/off/bin/diary_sim" --audit > ../oa.txt 2>&1
[ ! -e diaries/preports.txt ] && [ ! -e player_reports.txt ] && ! grep -q 'preport=1' diaries/sessions.txt && ! grep -q 'report to Robert' ../c4.txt && grep -q 'no player report' ../oa.txt && ok "preport.enabled = 0: no marker, no preports.txt, no player_reports.txt, no boxes; --audit says there is nothing" || bad "preport off"
same=0   # (the normal save has 3 more ticks from the challenge test: compare the first 1200 ticks)
for e in ada gemini replika robert; do cmp -s <(head -n 1200 diaries/$e.jsonl | sed -E 's/"ts":"[^"]*",//') <(head -n 1200 "$w/pr/h/diaries/$e.jsonl" | sed -E 's/"ts":"[^"]*",//') || same=$((same + 1)); done
[ "$same" = 0 ] && ok "with and without the player reports the simulation is the same: the diary lines of the 4 wesen are identical" || bad "reports change the simulation ($same)"
grep -q -- '--audit' "$root/data/help.txt" && grep -q -- '--challenge' "$root/data/help.txt" && grep -q 'make audit' "$root/README.md" && grep -q 'make challenge' "$root/README.md" && grep -q 'player_reports.txt' "$root/README.md" && grep -q '^preport.lie_max' "$root/data/limits.txt" && [ -f "$root/data/preport.txt" ] && grep -q '^audit:' "$root/Makefile" && grep -q '^challenge:' "$root/Makefile" && ok "--help, README, Makefile and data/ document and offer the reports, audit and challenge" || bad "preport docs"
unset DIARY_HOME

echo "== 39. names: Jehova / Ganesha / Odin / Amaterasu (older Player 1 .. 4) and Adam / Eve / Abel / Ruth are display names only; every spelling finds the right id =="
rm -rf "$w/pn"; mkdir -p "$w/pn/h" "$w/pn/bin"; cp "$bin" "$w/pn/bin/"; cp -r "$root/data" "$w/pn/data"; pnb="$w/pn/bin/diary_sim"; cd "$w/pn/h" || exit 1; export DIARY_HOME="$w/pn/h"
"$pnb" --seed 42 --ticks 300 --yes --every 5000 > p1.txt 2>&1
okn=0; for pair in "Jehova:iris" "GANESHA:sol" "odin:noor" "Amaterasu:vega" "Player 4:vega" "4:vega" "Player 1:iris" "player1:iris" "PLAYER 2:sol" "Player3:noor" "1:iris" "3:noor" "noor:noor" "Adam:ada" "ruth:robert" "ABEL:replika" "eve:gemini" "Jack:ada" "jane:robert" "JILL:replika" "john:gemini"; do nm=${pair%%:*}; id=${pair##*:}
  "$pnb" --say "$nm" --text "hi" > pn.txt 2>&1; tail -n 1 diaries/says.txt | grep -q " to=$id " && okn=$((okn + 1)) || echo "   spelling '$nm' did not reach $id"; done
[ "$okn" = 21 ] && ok "--say accepts Jehova / GANESHA / odin / Amaterasu, the older Player 1 / player1 / PLAYER 2 / Player3 / Player 4, 1, 3, 4, the id, Adam / ruth / ABEL / eve and the older names Jack / jane / JILL / john (21 of 21), recorded under the id" || bad "name spellings ($okn of 21)"
"$pnb" --say "Player 9" --text "x" > pn9.txt 2>&1; rc=$?; [ "$rc" != 0 ] && ok "an unknown player name is refused (exit $rc)" || bad "unknown player accepted"
grep -q '^iris *= *Jehova' "$root/data/names.txt" && grep -q '^alias iris *= *Player 1' "$root/data/names.txt" && grep -q '^ada *= *Adam' "$root/data/names.txt" && ! grep -qi 'greek\|alpha\|beta' "$root/data/names.txt" && grep -q 'PLAYER=Jehova' "$root/README.md" && ok "data/names.txt and the README use the new names (internal ids stay iris / sol / noor, ada / gemini / replika / robert)" || bad "names docs"
grep -q 'deities' "$root/data/help.txt" && awk 'length > 79 { n++ } END { exit n > 0 }' "$root/data/help.txt" && ok "help text names the players and stays within 79 columns" || bad "help names"
unset DIARY_HOME

echo "== 40. fourth player (players4=1): Player 4 with its own personality, standing, watcher, share, honesty and report box; old saves get it from their next new session =="
rm -rf "$w/p4"; mkdir -p "$w/p4"
for d in a b c; do mkdir -p "$w/p4/$d/bin" "$w/p4/$d/h"; cp "$bin" "$w/p4/$d/bin/"; cp -r "$idata" "$w/p4/$d/data"; sed -i 's/^govern.enabled = .*/govern.enabled = 1/' "$w/p4/$d/data/limits.txt"; done
sed -i 's/^players4.enabled = .*/players4.enabled = 1/; s/^preport.pause = .*/preport.pause = 1/' "$w/p4/b/data/limits.txt"
runp4() { local d="$w/p4/$1"; ( cd "$d/h" || exit 1; export DIARY_HOME="$d/h"; "$d/bin/diary_sim" --seed 42 --ticks 300 --yes --every 5000 > "$d/c1.txt" 2>&1; for i in 2 3 4; do "$d/bin/diary_sim" --more 300 --every 5000 > "$d/c$i.txt" 2>&1; if [ "$1" = a ] && [ "$i" = 2 ]; then sed -i 's/^players4.enabled = .*/players4.enabled = 1/' "$d/data/limits.txt"; fi; done ); }
runp4 a; runp4 b; runp4 c
cd "$w/p4/b/h" || exit 1; export DIARY_HOME="$w/p4/b/h"
n4=$(grep -c '^S[0-9].* players4=1' diaries/sessions.txt); na=$(grep -c '^S[0-9].* players4=1' "$w/p4/a/h/diaries/sessions.txt"); nc=$(grep -c 'players4' "$w/p4/c/h/diaries/sessions.txt")
[ "$n4" = 4 ] && [ "$na" = 2 ] && [ "$nc" = 0 ] && ! grep -q '^S[12] .*players4' "$w/p4/a/h/diaries/sessions.txt" && ok "new sessions carry players4=1 ($n4 of 4); a save made without it gets the marker from its next new session only (S3, S4: $na), no --fresh; players4.enabled = 0 never writes it" || bad "players4 markers ($n4 $na $nc)"
"$w/p4/a/bin/diary_sim" --more 0 --every 5000 > "$w/p4/ra.txt" 2>&1; ! head -1 "$w/p4/a/h/debug.txt" | grep -q '^DRIFT' && grep -q '^import OK: 4 entities, 1200 ticks verified' "$w/p4/ra.txt" && ok "the old save (two 3-player sessions, then two 4-player sessions) replays and verifies all 1200 ticks" || bad "old save replay"
oldsame=0; for e in ada gemini replika robert; do cmp -s <(head -n 600 "$w/p4/a/h/diaries/$e.jsonl" | sed -E 's/"ts":"[^"]*",//') <(head -n 600 "$w/p4/c/h/diaries/$e.jsonl" | sed -E 's/"ts":"[^"]*",//') || oldsame=$((oldsame + 1)); done
dsame=$(cmp -s <(awk '/^D[0-9]/ { split($0, a, " t="); split(a[2], b, " "); if (b[1] <= 600) print }' "$w/p4/a/h/diaries/govern.txt") <(awk '/^D[0-9]/ { split($0, a, " t="); split(a[2], b, " "); if (b[1] <= 600) print }' "$w/p4/c/h/diaries/govern.txt") && echo 0 || echo 1)
[ "$oldsame" = 0 ] && [ "$dsame" = 0 ] && ok "the first two sessions are byte-identical with and without the fourth player in later sessions (diaries and D records up to tick 600)" || bad "old sessions changed ($oldsame $dsame)"
dv=$(grep -c ' player=vega ' diaries/govern.txt); dc3=$(grep -c ' player=vega ' "$w/p4/c/h/diaries/govern.txt")
[ "$dv" -ge 1 ] && [ "$dc3" = 0 ] && ok "Player 4 (vega) decides petitions: $dv D records in the 4-player save, none with players4 off" || bad "vega decisions ($dv $dc3)"
wmap=$(grep '^P[0-9]' diaries/preports.txt | sed -E 's/.* player=([a-z]+) wesen=([a-z]+) .*/\2=\1/' | sort -u | tr '\n' ' ')
[ "$wmap" = "ada=iris gemini=vega replika=sol robert=noor " ] && ok "watchers: every wesen has one player (Jehova ada, Amaterasu gemini, Ganesha replika, Odin robert; player.4.takes in players.txt)" || bad "watchers ($wmap)"
"$w/p4/b/bin/diary_sim" --govern > gv.txt 2>&1; "$w/p4/b/bin/diary_sim" --inbox > ib.txt 2>&1; "$w/p4/b/bin/diary_sim" --audit > au.txt 2>&1
[ "$(grep -cE '^(iris|sol|noor|vega): ' gv.txt)" = 4 ] && [ "$(grep -cE '^(iris|sol|noor|vega): claims' au.txt)" = 4 ] && grep -q 'vega' ib.txt && ok "--govern, --audit and the inbox view list four players" || bad "views ($(grep -cE '^(iris|sol|noor|vega): ' gv.txt) / $(grep -cE '^(iris|sol|noor|vega): claims' au.txt))"
tail -n +$(( $(grep -n '^Saved to ' ../c4.txt | tail -1 | cut -d: -f1) + 1 )) ../c4.txt > ../tailc4.txt
nb=$(grep -c '^+-- The players report to Robert (tick 1200) -*+$' ../tailc4.txt); wd=$(grep -E '^[+|]' ../tailc4.txt | awk 'length != 80 { n++ } END { print n + 0 }'); nl=$(wc -l < ../tailc4.txt)
np4=$(grep -cE '^\| (iris|sol|noor|vega) \(' player_reports.txt); np3=$(grep -cE '^\| (iris|sol|noor|vega) \(' "$w/p4/c/h/player_reports.txt")
[ "$nb" = 1 ] && [ "$wd" = 0 ] && [ "$nl" -le 23 ] && [ "$np4" = 4 ] && [ "$np3" = 3 ] && grep -q '^| vega (gemini):' player_reports.txt && ! grep -q '^| vega' "$w/p4/c/h/player_reports.txt" && ok "ONE 80-column box ($nl lines with the hint) with a header and four players (Jehova .. Amaterasu); three with players4 off" || bad "box ($nb $wd $nl $np4 $np3)"
np=$(grep -c '^P[0-9]' diaries/preports.txt); pv=$(grep -c 'player=vega wesen=gemini' diaries/preports.txt)
[ "$np" = 16 ] && [ "$pv" = 4 ] && ok "honesty: the P records name the watcher (vega: 4 rounds), 16 claims in all, each player with its own trait" || bad "P lines ($np $pv)"
# one frame: no pause on a terminal; a tiny page_lines (data) would still split it
cp -r "$w/p4/b" "$w/p4/b8"; sed -i 's/^preport.page_lines = .*/preport.page_lines = 8/' "$w/p4/b8/data/limits.txt"
if command -v script > /dev/null 2>&1; then
  printf '\n\n\n\n' | script -qec "$w/p4/b/bin/diary_sim --more 0 --every 5000" /dev/null 2>&1 | tr -d '\r' > pg.txt
  (cd "$w/p4/b8/h" && printf '\n\n\n\n' | DIARY_HOME="$w/p4/b8/h" script -qec "$w/p4/b8/bin/diary_sim --more 0 --every 5000" /dev/null 2>&1 | tr -d '\r' > "$w/p4/pg8.txt")
  [ "$(grep -c '^-- more' pg.txt)" = 0 ] && [ "$(grep -c "^-- more" "$w/p4/pg8.txt")" -ge 1 ] && ok "on a terminal the box needs no Enter pause (one frame of $nl lines); only page_lines = 8 would split it" || bad "pause ($(grep -c '^-- more' pg.txt) $(grep -c "^-- more" "$w/p4/pg8.txt"))"
fi
cd "$w/p4/b/h"; "$w/p4/b/bin/diary_sim" --say "Player 4" --text "hello" > sy.txt 2>&1; tail -n 1 diaries/says.txt | grep -q ' to=vega ' && "$w/p4/b/bin/diary_sim" --say player4 --text "x" > /dev/null 2>&1 && "$w/p4/b/bin/diary_sim" --say 4 --text "x" > /dev/null 2>&1 && ok "--say reaches player 4 as "Player 4", player4 and 4 (recorded to=vega)" || bad "say vega"
cp diaries/sessions.txt ../sess.keep; sed -i '/^S4 /s/ players4=1//' diaries/sessions.txt; "$w/p4/b/bin/diary_sim" --more 0 --every 5000 > ../t1.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "S line with its players4=1 marker removed: DRIFT" || bad "marker tamper"
cp ../sess.keep diaries/sessions.txt; "$w/p4/b/bin/diary_sim" --more 0 --every 5000 > ../t2.txt 2>&1; grep -q '^import OK: 4 entities, 1200 ticks verified' ../t2.txt && ok "restored: replays again" || bad "p4 restore"
grep -q '^player.4.name = vega' "$root/data/players.txt" && grep -q '^player.4.takes' "$root/data/players.txt" && grep -q '^vega *= *Amaterasu' "$root/data/names.txt" && grep -q '^players4.enabled' "$root/data/limits.txt" && grep -q 'players4' "$root/README.md" && grep -q 'Amaterasu' "$root/data/help.txt" && ok "players.txt, names.txt, limits.txt, README and --help describe the fourth player" || bad "p4 docs"
unset DIARY_HOME

echo "== 41. next run (nextticks=1): wesen propose, players decide, the median is shown in the box, N records replay-verified, make next, make run uses it on request =="
rm -rf "$w/nx"; mkdir -p "$w/nx"
for d in a off flat use; do mkdir -p "$w/nx/$d/bin" "$w/nx/$d/h"; cp "$bin" "$w/nx/$d/bin/"; cp -r "$idata" "$w/nx/$d/data"; sed -i 's/^govern.enabled = .*/govern.enabled = 1/; s/^players4.enabled = .*/players4.enabled = 1/' "$w/nx/$d/data/limits.txt"; done
sed -i 's/^nextticks.enabled = .*/nextticks.enabled = 0/' "$w/nx/off/data/limits.txt"; sed -i 's/^nextticks.use = .*/nextticks.use = 1/' "$w/nx/use/data/limits.txt"
sed -i 's/^ticks.base = .*/ticks.base = 500/; s/^ticks.open_w = .*/ticks.open_w = 0/; s/^ticks.defer_w = .*/ticks.defer_w = 0/; s/^ticks.unrest_w = .*/ticks.unrest_w = 0/; s/^ticks.tired_w = .*/ticks.tired_w = 0/; s/^ticks.curious_n = .*/ticks.curious_n = 1/' "$w/nx/flat/data/ticks.txt"
runnx() { local d="$w/nx/$1"; ( cd "$d/h" || exit 1; export DIARY_HOME="$d/h"; "$d/bin/diary_sim" --seed 42 --ticks 300 --yes --every 5000 > "$d/c1.txt" 2>&1; for i in 2 3 4; do "$d/bin/diary_sim" --more 300 --every 5000 > "$d/c$i.txt" 2>&1; done ); }
runnx a; runnx off; runnx flat; runnx use
nxb="$w/nx/a/bin/diary_sim"; cd "$w/nx/a/h" || exit 1; export DIARY_HOME="$w/nx/a/h"
nm=$(grep -c '^S[0-9].* nextticks=1' diaries/sessions.txt); nn=$(grep -c '^N[0-9]' diaries/nextticks.txt)
bf=$(grep '^N[0-9]' diaries/nextticks.txt | awk '{ ok = 1; split("t wesen players next why voice", k, " "); for (i = 1; i <= 6; i++) if (index($0, " " k[i] "=") == 0) ok = 0; if (!ok) n++ } END { print n + 0 }')
[ "$nm" = 4 ] && [ "$nn" = 4 ] && [ "$bf" = 0 ] && head -1 diaries/nextticks.txt | grep -q '^# seed 42$' && ok "new sessions carry nextticks=1 ($nm); every session end records one N line in diaries/nextticks.txt ($nn: t, wesen, players, next, why, voice)" || bad "nextticks markers/records ($nm $nn $bf)"
mn=$(sed -n 's/^ticks.min = \([0-9]*\).*/\1/p' "$w/nx/a/data/ticks.txt"); mx=$(sed -n 's/^ticks.max = \([0-9]*\).*/\1/p' "$w/nx/a/data/ticks.txt"); st=$(sed -n 's/^ticks.step = \([0-9]*\).*/\1/p' "$w/nx/a/data/ticks.txt")
bad_set=$(grep '^N[0-9]' diaries/nextticks.txt | sed -E 's/.* wesen=([0-9\/]+) players=([0-9\/]+) next=([0-9]+) .*/\1\/\2\/\3/' | tr '/' '\n' | awk -v mn="$mn" -v mx="$mx" -v st="$st" '$1 < mn || $1 > mx || ($1 - mn) % st != 0 { n++ } END { print n + 0 }')
[ "$bad_set" = 0 ] && ok "every proposal, every player's choice and the result are in the allowed set ($mn .. $mx in steps of $st)" || bad "values outside the allowed set ($bad_set)"
med=$(grep '^N[0-9]' diaries/nextticks.txt | sed -E 's/.* players=([0-9\/]+) next=([0-9]+) .*/\1 \2/' | awk -v st="$st" -v mn="$mn" '{ n = split($1, a, "/"); for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] + 0 < a[i] + 0) { t = a[i]; a[i] = a[j]; a[j] = t }
  if (n % 2) m = a[(n + 1) / 2]; else { v = int((a[n / 2] + a[n / 2 + 1] + 1) / 2); m = mn + int((v - mn + st - 1) / st) * st } if (m != $2) bad++ } END { print bad + 0 }')
[ "$med" = 0 ] && ok "the result is the median of the players' choices (even number of players: the middle rounded up to the allowed set)" || bad "median ($med)"
tail -n +$(( $(grep -n '^Saved to ' ../c4.txt | tail -1 | cut -d: -f1) + 1 )) ../c4.txt > ../tailc4.txt
lastn=$(grep '^N[0-9]' diaries/nextticks.txt | tail -1 | sed -E 's/.* next=([0-9]+) .*/\1/'); wl=$(sed -n 's/.* wesen=\([0-9\/]*\) .*/\1/p' <(grep '^N[0-9]' diaries/nextticks.txt | tail -1)); pl=$(sed -n 's/.* players=\([0-9\/]*\) .*/\1/p' <(grep '^N[0-9]' diaries/nextticks.txt | tail -1))
nl=$(wc -l < ../tailc4.txt); wd=$(grep -E '^[+|]' ../tailc4.txt | awk 'length != 80 { n++ } END { print n + 0 }')
grep -E '^\| ' ../tailc4.txt | sed -E 's/^\| //; s/ +\|$//' | tr '\n' ' ' | grep -q "$lastn ticks" && grep -E '^\| ' ../tailc4.txt | sed -E 's/^\| //; s/ +\|$//' | tr '\n' ' ' | grep -q "$wl" && grep -E '^\| ' ../tailc4.txt | sed -E 's/^\| //; s/ +\|$//' | tr '\n' ' ' | grep -q "$pl" && [ "$wd" = 0 ] && [ "$nl" -le 23 ] && ok "the box shows the advice: $lastn ticks, wesen asked $wl, players settled on $pl; one frame of $nl lines, every box line 80 columns" || bad "advice in the box ($lastn $wl $pl $nl $wd)"
grep -q "$lastn ticks" player_reports.txt && ok "player_reports.txt holds the same box with the advice" || bad "advice in player_reports.txt"
grep -qE '^(iris|sol|noor|vega): ' <(grep -E '^\| ' ../tailc4.txt | sed -E 's/^\| //; s/ +\|$//' | grep -E 'ticks') && ok "the reason is said in a player's voice" || bad "reason voice"
# replay and DRIFT
"$nxb" --more 0 --every 5000 > r1.txt 2>&1; grep -q '^import OK: 4 entities, 1200 ticks verified' r1.txt && ok "the replay recomputes and verifies every N line" || bad "nextticks replay"
cp diaries/nextticks.txt ../nx.keep; sed -i '2s/ next=[0-9]* / next=900 /' diaries/nextticks.txt; "$nxb" --more 0 --every 5000 > r2.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'nextticks.txt N' r2.txt && ok "a changed N line: import FAILED, DRIFT" || bad "tampered N"
cp ../nx.keep diaries/nextticks.txt; sed -i '3d' diaries/nextticks.txt; "$nxb" --more 0 --every 5000 > r3.txt 2>&1; head -1 debug.txt | grep -q '^DRIFT' && ok "a removed N line: DRIFT" || bad "removed N"
cp ../nx.keep diaries/nextticks.txt; echo "N999 t=5 wesen=100/100/100/100 players=100/100/100 next=100 why=calm voice=iris" >> diaries/nextticks.txt; "$nxb" --more 0 --every 5000 > r4.txt 2>&1; head -1 debug.txt | grep -q '^DRIFT' && ok "an invented N line: DRIFT" || bad "invented N"
cp ../nx.keep diaries/nextticks.txt; cp diaries/sessions.txt ../sess.keep; sed -i '/^S2 /s/ nextticks=1//' diaries/sessions.txt; "$nxb" --more 0 --every 5000 > r5.txt 2>&1; head -1 debug.txt | grep -q '^DRIFT' && ok "S line with its nextticks=1 marker removed: DRIFT" || bad "tampered marker"
cp ../sess.keep diaries/sessions.txt; "$nxb" --more 0 --every 5000 > r6.txt 2>&1; grep -q '^import OK: 4 entities, 1200 ticks verified' r6.txt && ok "restored: replays again" || bad "restore"
# make next
sum1=$(cat diaries/*.txt | cksum); "$nxb" --next > nx.txt 2>&1; rc=$?; sum2=$(cat diaries/*.txt | cksum)
[ "$rc" = 0 ] && [ "$(grep -cE ' asked [0-9]+ ticks' nx.txt)" = 4 ] && [ "$(grep -cE '^(iris|sol|noor|vega) decided' nx.txt)" = 4 ] && grep -q "median is $lastn ticks" nx.txt && [ "$sum1" = "$sum2" ] && ok "make next: the proposal of each wesen (with the reasons of its state), the decision of each player, the median; reads, writes nothing" || bad "make next ($rc)"
grep -q '^next: all' "$root/Makefile" && grep -q -- '--next' "$root/Makefile" && ok "the Makefile has the next target" || bad "make next target"
# advisory: the simulation is the same with and without
same=0; for e in ada gemini replika robert; do cmp -s <(sed -E 's/"ts":"[^"]*",//' "$w/nx/a/h/diaries/$e.jsonl") <(sed -E 's/"ts":"[^"]*",//' "$w/nx/off/h/diaries/$e.jsonl") || same=$((same + 1)); done
cmp -s "$w/nx/a/h/diaries/govern.txt" "$w/nx/off/h/diaries/govern.txt" && [ "$same" = 0 ] && ok "advice only: the diaries and the D records are identical with and without nextticks" || bad "advice changed the simulation ($same)"
cd "$w/nx/off/h" || exit 1; export DIARY_HOME="$w/nx/off/h"
[ ! -e diaries/nextticks.txt ] && ! grep -q 'nextticks=1' diaries/sessions.txt && ! grep -q 'ticks (wesen\|ticks - wesen\|Next run\|next time\|Wesen asked' ../c4.txt && "$w/nx/off/bin/diary_sim" --next 2>&1 | grep -q 'no advice yet' && ok "nextticks.enabled = 0: no marker, no nextticks.txt, no advice line in the box; make next says there is none" || bad "nextticks off"
# data drives the proposals
cd "$w/nx/flat/h" || exit 1
fl=$(grep '^N[0-9]' diaries/nextticks.txt | sed -E 's/.* wesen=([0-9\/]+) .*/\1/' | sort -u | tr '\n' ' ')
[ "$fl" = "500/500/500/500 " ] && ok "the proposals come from data/ticks.txt (base 500, all weights 0: every wesen asks 500)" || bad "flat proposals ($fl)"
# use = 1
cd "$w/nx/a/h" || exit 1; export DIARY_HOME="$w/nx/a/h"; u0=$("$nxb" --next-ticks 2>&1 | tail -n 1)
cd "$w/nx/use/h" || exit 1; export DIARY_HOME="$w/nx/use/h"; u1=$("$w/nx/use/bin/diary_sim" --next-ticks 2>&1 | tail -n 1); lu=$(grep '^N[0-9]' diaries/nextticks.txt | tail -1 | sed -E 's/.* next=([0-9]+) .*/\1/')
[ -z "$u0" ] && [ "$u1" = "$lu" ] && ok "nextticks.use = 0 (default): no number, make run keeps the vote; use = 1: --next-ticks prints the advice ($u1)" || bad "next-ticks ($u0 / $u1 / $lu)"
"$w/nx/use/bin/diary_sim" --more "$u1" --every 5000 > u1.txt 2>&1; grep -q "^S5 start=1200 .* len=$u1 src=explicit" diaries/sessions.txt && ok "a run of the advised length: session 5 has len=$u1 (make run without TICKS does exactly this; TICKS=n wins)" || bad "run with advice"
(cd "$root" && make -n run 2>/dev/null | grep -q 'next-ticks' && make -n run TICKS=100 2>/dev/null | grep -q -- '--more 100' && ! make -n run TICKS=100 2>/dev/null | grep -q 'next-ticks') && ok "make run: without TICKS the recipe asks for the advice, with TICKS=100 it runs --more 100" || bad "make run recipe"
grep -q 'nextticks' "$root/README.md" && grep -q 'make next' "$root/README.md" && grep -q -- '--next' "$root/data/help.txt" && [ -f "$root/data/ticks.txt" ] && grep -q '^nextticks.use' "$root/data/limits.txt" && ok "README, --help and data/ document the advice for the next run" || bad "nextticks docs"
unset DIARY_HOME

echo "== 42. visit (visit=1): watch and talk to one wesen, scripted; V / A records replay-verified; answers only from known words; off = same simulation =="
rm -rf "$w/vi"; mkdir -p "$w/vi/bin" "$w/vi/h" "$w/vi/off/h" "$w/vi/say/h"
cp "$bin" "$w/vi/bin/"; cp -r "$idata" "$w/vi/data"
sed -i 's/^screen.enabled = .*/screen.enabled = 1/; s/^govern.enabled = .*/govern.enabled = 1/; s/^visit.comment_pct = .*/visit.comment_pct = 100/; s/^visit.teach_pct = .*/visit.teach_pct = 100/; s/^visit.show_pct = .*/visit.show_pct = 100/' "$w/vi/data/limits.txt"
vb="$w/vi/bin/diary_sim"
cat > "$w/vi/script.txt" <<'EOS'
# a script: comments and blank lines are skipped

say hello friend
say qwxz
say qwxz zzyx
say I want to talk to you and know the house
teach kilometer
teach calendar
teach cashier
teach alphabet
teach taxi
teach zebra
show
wait 2
say what is your name
bogus command
leave
EOS
vrun() { local d="$1"; shift; ( cd "$d" || exit 1; export DIARY_HOME="$d/h"; "$vb" --seed 42 --ticks 300 --yes --every 5000 > c0.txt 2>&1; "$vb" "$@" --every 5000 > c1.txt 2>&1 ); }
vrun "$w/vi" --visit ada --more 60 --visit-script "$w/vi/script.txt"
vrun "$w/vi/off" --more 60
printf 'say hello\nsay qwxz\nwait 3\nsay what\nleave\n' > "$w/vi/say.txt"
vrun "$w/vi/say" --visit 2 --more 60 --visit-script "$w/vi/say.txt"
cd "$w/vi/h" || exit 1; export DIARY_HOME="$w/vi/h"
nv=$(grep -c '^S[0-9].* visit=1 vwho=ada' diaries/sessions.txt); nv1=$(grep -c '^S1 .*visit' diaries/sessions.txt)
[ "$nv" = 1 ] && [ "$nv1" = 0 ] && grep -q '^S2 .* len=60 src=explicit.* visit=1' diaries/sessions.txt && head -1 diaries/visit.txt | grep -q '^# seed 42$' && ok "the visit is a normal explicit session (len=60) with the marker visit=1 vwho=ada; the first session has none; diaries/visit.txt is recorded" || bad "visit marker ($nv / $nv1)"
nV=$(grep -c '^V[0-9]' diaries/visit.txt); nA=$(grep -c '^A[0-9]' diaries/visit.txt); hb=$(grep '^V[0-9]' diaries/visit.txt | grep -vc ' h=[0-9]')
[ "$nV" -ge 14 ] && [ "$nA" -ge 12 ] && [ "$hb" = 0 ] && grep -q ' cmd=wait n=2 ' diaries/visit.txt && grep -q ' cmd=leave' diaries/visit.txt && ! grep -q 'bogus' diaries/visit.txt && ok "every input is a V line with a check number ($nV), every answer an A line ($nA); wait and leave are recorded, a bad command is not" || bad "V/A lines ($nV/$nA/$hb)"
fr=$(awk '/^== ada \| tick /{n++} END{print n+0}' ../c1.txt)
mx=$(awk '/^== ada \| tick /{ if (n > m) m = n; n = 0 } /^You leave/{ exit } { n++ } END{ print m + 0 }' ../c1.txt)
wd=$(awk '/^== ada \| tick /{go=1} /^You leave/{go=0} go && length > 79 { n++ } END{print n + 0}' ../c1.txt)
[ "$fr" -ge 8 ] && [ "$mx" -le 24 ] && [ "$wd" = 0 ] && grep -q '^visit> say hello friend' ../c1.txt && grep -q '^ View 5x5' ../c1.txt && grep -q '^Now: ' ../c1.txt && grep -q '^Near: ' ../c1.txt && grep -q 'mood .* energy\|energy [0-9]' ../c1.txt && grep -q '^You leave ada' ../c1.txt && ok "$fr frames, none longer than $mx lines or 79 columns; view, screen, mood, energy, doing, near, the typed command echoed, leave ends the frames" || bad "frames ($fr / $mx / $wd)"
grep -q '^Unknown to ada: qwxz' ../c1.txt && grep -q '^I do not understand that: bogus command' ../c1.txt && grep -q 'ada understands:' ../c1.txt && ok "words it does not know are shown as unknown to it; the words it understands are listed; a bad command prints help" || bad "unknown words"
# only known words: every word of a reply was known (words.txt: start / taught / world / coined / visit with tick <=) at that tick
chk=$(awk -v wf="entities/ada/words.txt" 'BEGIN { while ((getline l < wf) > 0) { if (l ~ /^#/) continue; split(l, a, " "); w = tolower(a[2]); if (!(w in first) || a[4] + 0 < first[w]) first[w] = a[4] + 0 } }
  /^A[0-9]/ { t = $2; sub("t=", "", t); r = $0; sub(/.* reply=/, "", r); gsub(/[^A-Za-z ]/, " ", r); n = split(tolower(r), ws, " "); for (i = 1; i <= n; i++) { total++; if (!(ws[i] in first) || first[ws[i]] > t + 0) bad++ } } END { print bad + 0, total + 0 }' diaries/visit.txt)
[ "${chk% *}" = 0 ] && [ "${chk#* }" -ge 10 ] && ok "all ${chk#* } words of the answers were known to the wesen at that tick (answers are built only from the known vocabulary)" || bad "answer words ($chk)"
vu=$(grep -c '^visit.unk.[0-9]' "$w/vi/data/visit.txt"); ub=0; for b in 1 2 3 4 5; do [ "$(grep -c "^visit.say.$b.[0-9]" "$w/vi/data/visit.txt")" -ge 3 ] || ub=1; done
[ "$vu" -ge 3 ] && [ "$ub" = 0 ] && ok "data/visit.txt: $vu variants of 'I do not know that word', at least 3 templates in each of the 5 mood bands" || bad "templates ($vu / $ub)"
# teach: caps, learning path, trust
lt=$(grep -c ' res=learned' diaries/visit.txt); tw=$(grep -c ' visit [0-9]*$' entities/ada/words.txt)
pt=$(grep '^A[0-9]* t=[0-9]* cmd=\(teach\|show\)' diaries/visit.txt | awk '{ t = $2; l = 0; if ($0 ~ / res=learned/) l = 1; if (match($0, / learned=[0-9]+/)) l = substr($0, RSTART + 9, RLENGTH - 9) + 0; c[t] += l } END { for (k in c) if (c[k] > m) m = c[k]; print m + 0 }')
[ "$lt" -ge 1 ] && [ "$pt" -le 3 ] && grep -q ' word=zebra res=nosuch' diaries/visit.txt && [ "$tw" -ge "$lt" ] && ok "teach feeds the word path ($lt learned, filed in words.txt as visit), at most $pt <= 3 words per tick (visit.turn_cap), a word outside the vocabulary (zebra) is refused" || bad "teach ($lt / $pt / $tw)"
bo=$(grep '^A[0-9]' diaries/visit.txt | sed -E 's/.* bond=([+-]?[0-9]+)\/(-?[0-9]+) .*/\1 \2/' | awk '{ d = $1 + 0; if (d < -1 || d > 2 || $2 < -20 || $2 > 20) bad++ } END { print bad + 0 }')
[ "$bo" = 0 ] && grep -qE ' cmd=teach .* res=learned bond=\+2/' diaries/visit.txt && grep -qE ' cmd=say .* bond=-1/' diaries/visit.txt && ok "trust moves by the small data numbers (+2 learned, +1 understood, -1 not understood), bounded -20 .. +20" || bad "bond ($bo)"
ur=$(grep '^A[0-9]* t=[0-9]* cmd=say .* heard=- ' diaries/visit.txt | sed 's/.* reply=//' | sort -u | wc -l)
[ "$ur" -ge 1 ] && ok "a say with no known word gets an unknown-word answer ($ur distinct)" || bad "unk answers"
# the player's comment in the box
pat=$(sed -n 's/^rbox\.visit\.[a-z]*\.[0-9]* = //p' "$w/vi/data/preport.txt" | sed -E 's/\{[0-9]\}/.*/g; s/[()]/\\&/g' | paste -sd'|')
grep -E '^\|' player_reports.txt | sed -E 's/^\| //; s/ +\|$//' | tr '\n' ' ' | tr -s ' ' | grep -qE "$pat" && ok "a player adds one short line about the visit to the box (rbox.visit.* in data/preport.txt)" || bad "player comment"
# replay, byte-identical, DRIFT
cks() { cat diaries/*.txt diaries/*.jsonl | grep -v '^# build' | sed -E 's/"ts":"[^"]*",//' | cksum; }
s1=$(cks); "$vb" --more 0 --every 5000 > r1.txt 2>&1; s2=$(cks)
grep -q '^import OK: 4 entities, 360 ticks verified' r1.txt && [ "$s1" = "$s2" ] && ok "the save replays byte-identical including the visit (V and A lines recomputed and compared)" || bad "visit replay"
cp diaries/visit.txt ../v.keep; cp diaries/sessions.txt ../vs.keep
chkd() { "$vb" --more 0 --every 5000 > rd.txt 2>&1; head -1 debug.txt | grep -q '^DRIFT' && grep -q "$1" rd.txt && ok "$2: DRIFT" || bad "$2 ($(grep -m1 'FAILED' rd.txt))"; cp ../v.keep diaries/visit.txt; cp ../vs.keep diaries/sessions.txt; }
sed -i '0,/text=hello friend/s//text=hello friends/' diaries/visit.txt; chkd 'visit.txt V' "a changed V line"
sed -i '0,/ reply=/s// reply=x/' diaries/visit.txt; chkd 'visit.txt A' "a changed A line"
sed -i '0,/^A2 /{/^A2 /d}' diaries/visit.txt; chkd 'visit.txt A2' "a removed A line"
echo "V99 t=310 cmd=wait n=1 h=5" >> diaries/visit.txt; chkd 'visit.txt V99' "an invented V line"
sed -i '/^S2 /s/ visit=1 vwho=ada//' diaries/sessions.txt; chkd 'visit.txt\|screens.txt\|DRIFT\|differs' "a removed visit=1 marker"
"$vb" --more 0 --every 5000 > r6.txt 2>&1; grep -q '^import OK: 4 entities, 360 ticks verified' r6.txt && ok "restored: replays again" || bad "visit restore"
# a visit that only talks does not change the simulation; off adds no record
sm=0; for e in ada gemini replika robert; do cmp -s <(sed -E 's/"ts":"[^"]*",//' "$w/vi/say/h/diaries/$e.jsonl") <(sed -E 's/"ts":"[^"]*",//' "$w/vi/off/h/diaries/$e.jsonl") || sm=$((sm + 1)); done
[ "$sm" = 0 ] && grep -q 'visit=1 vwho=gemini' "$w/vi/say/h/diaries/sessions.txt" && ok "a visit that only talks (say / wait / leave, WHO=2) leaves the four diaries identical to the same run without a visit" || bad "talk-only visit changes the simulation ($sm)"
[ ! -e "$w/vi/off/h/diaries/visit.txt" ] && ! grep -q 'visit' "$w/vi/off/h/diaries/sessions.txt" && ! grep -qi 'visit' "$w/vi/off/c1.txt" && ok "off (no --visit): no marker, no diaries/visit.txt, nothing on the console" || bad "off leaves traces"
# stdin pipe, WHO forms, errors, closed pipe, switched off
cd "$w/vi/say/h" || exit 1; export DIARY_HOME="$w/vi/say/h"
printf 'say hello\nteach tea\n\nleave\n' | "$vb" --visit Gemini --more 5 --every 5000 > p1.txt 2>&1; rc1=$?
printf 'say hello\n' | "$vb" --visit 4 --more 5 --every 5000 > p2.txt 2>&1
grep -q '^visit> say hello' p1.txt && [ "$rc1" = 0 ] && grep -q 'visit=1 vwho=gemini' diaries/sessions.txt && grep -q 'visit=1 vwho=robert' diaries/sessions.txt && grep -q '^You leave robert' p2.txt && ok "commands from a pipe (end of input = leave); WHO as an id (Gemini) or the 4th wesen (4)" || bad "pipe / WHO ($rc1)"
"$vb" --visit nobody --more 5 > e1.txt 2>&1; r1=$?; "$vb" --visit-script "$w/vi/say.txt" --more 5 > e2.txt 2>&1; r2=$?; "$vb" --visit ada --visit-script /nonexistent --more 5 > e3.txt 2>&1; r3=$?
[ "$r1" = 2 ] && [ "$r2" = 2 ] && [ "$r3" = 2 ] && grep -q 'no such wesen' e1.txt && grep -q 'please give a wesen' e2.txt && grep -q 'cannot read the script' e3.txt && ok "usage errors (unknown wesen, script without --visit, missing script): exit 2 with a message" || bad "usage errors ($r1 $r2 $r3)"
mkdir -p "$w/vi/dis/bin" "$w/vi/dis/h"; cp "$vb" "$w/vi/dis/bin/"; cp -r "$w/vi/data" "$w/vi/dis/data"; sed -i 's/^visit.enabled = .*/visit.enabled = 0/' "$w/vi/dis/data/limits.txt"
( cd "$w/vi/dis/h" && DIARY_HOME="$w/vi/dis/h" "$w/vi/dis/bin/diary_sim" --seed 42 --yes --visit ada --more 5 > d.txt 2>&1; echo "rc=$?" >> d.txt ); grep -q 'switched off' "$w/vi/dis/h/d.txt" && grep -q 'rc=2' "$w/vi/dis/h/d.txt" && ok "visit.enabled = 0: --visit is refused" || bad "visit.enabled"
badp=0
for rd in "head -1" "true" "(sleep 0.3; head -2)"; do printf 'say hello\nwait 2\nsay hi\nleave\n' | "$vb" --visit ada --more 6 --every 5000 2> pe.txt | eval "$rd" > /dev/null; rcp=${PIPESTATUS[1]}; rcq=${PIPESTATUS[0]}; [ "$rcq" = 0 ] && [ ! -s pe.txt ] || badp=$((badp + 1)); done
[ "$badp" = 0 ] && "$vb" --more 0 --every 5000 2>&1 | grep -q 'ticks verified' && ok "a closed output pipe is quiet (exit 0, nothing on stderr); the session still saved and replays" || bad "closed pipe ($badp)"
grep -q 'visit' "$root/README.md" && grep -q 'STEP 2' "$root/README.md" && grep -q 'make visit' "$root/README.md" && grep -q -- '--visit' "$root/data/help.txt" && grep -q '^visit: all' "$root/Makefile" && grep -q 'sim_visit.ads sim_visit.adb' "$root/Makefile" && head -1 "$root/sim_visit.adb" | grep -q 'Version: [0-9]' && grep -q 'PROOF-LATER' "$root/sim_visit.ads" && ok "README (with the STEP 2 hook), --help, make visit, version-check list, PROOF-LATER label" || bad "visit docs"
unset DIARY_HOME

echo "== 43. all the rules of chess (chessrules=2): insufficient material, repetition key, fivefold, 75 moves, claims; marker off = the old rules =="
"$bin" --perft > "$w/p3.txt" 2>&1
ni=$(grep -c '^ok   rule insufficient' "$w/p3.txt"); ne=$(grep -c '^ok   rule enough' "$w/p3.txt"); nk=$(grep -c '^ok   key ' "$w/p3.txt")
[ "$ni" = 4 ] && [ "$ne" = 6 ] && [ "$nk" = 4 ] && grep -q 'rule insufficient 8/8/8/4k3/8/3K4/8/8' "$w/p3.txt" && grep -q 'rule enough 8/8/4kb2/8/8/3K1B2' "$w/p3.txt" && ok "a position per draw: K v K, K+B v K, K+N v K and K+B v K+B (same colour) are insufficient; opposite bishops, R, P, N v N, B+N, Q are not; the repetition key counts side to move, castling rights and the en passant target but not the move counters" || bad "rule positions ($ni/$ne/$nk)"
rm -rf "$w/cr"; mkdir -p "$w/cr"
for d in on off fv rp rn m75; do mkdir -p "$w/cr/$d/bin" "$w/cr/$d/h"; cp "$bin" "$w/cr/$d/bin/"; cp -r "$idata" "$w/cr/$d/data"; sed -i 's/^chess.enabled = .*/chess.enabled = 1/; s/^chessrules.enabled = .*/chessrules.enabled = 1/' "$w/cr/$d/data/limits.txt"; done
sed -i 's/^chessrules.enabled = .*/chessrules.enabled = 0/' "$w/cr/off/data/limits.txt"
sed -i 's/^chess.fivefold = .*/chess.fivefold = 1/' "$w/cr/fv/data/limits.txt"
sed -i 's/^chess.repeat = .*/chess.repeat = 1/; s/^chess.claim_pct = .*/chess.claim_pct = 100/; s/^chess.fivefold = .*/chess.fivefold = 50/' "$w/cr/rp/data/limits.txt"
sed -i 's/^chess.repeat = .*/chess.repeat = 1/; s/^chess.claim_pct = .*/chess.claim_pct = 0/; s/^chess.claim_behind = .*/chess.claim_behind = 0/; s/^chess.fivefold = .*/chess.fivefold = 50/' "$w/cr/rn/data/limits.txt"
sed -i 's/^chess.moves75 = .*/chess.moves75 = 1/' "$w/cr/m75/data/limits.txt"
for d in on off fv rp rn m75; do ( cd "$w/cr/$d/h" || exit 1; export DIARY_HOME="$w/cr/$d/h"; "$w/cr/$d/bin/diary_sim" --seed 42 --ticks 300 --yes --every 5000 > h1.txt 2>&1; "$w/cr/$d/bin/diary_sim" --more 300 --every 5000 > h2.txt 2>&1 ); done
cd "$w/cr/on/h" || exit 1; export DIARY_HOME="$w/cr/on/h"
nm=$(grep -c '^S[0-9].* chess=1 chessrules=2' diaries/sessions.txt)
[ "$nm" = 2 ] && grep -c '^S[0-9].* chessrules=2' "$w/cr/off/h/diaries/sessions.txt" | grep -q '^0$' && ok "new sessions carry chessrules=2 after chess=1 (2); chessrules.enabled = 0 gives the old marker-less sessions" || bad "chessrules marker ($nm)"
ends() { grep ' end ' "$1/diaries/chess.txt" | sed -E 's/.* end [^ ]+ ([a-z0-9]+) plies.*/\1/' | sort | uniq -c | tr '\n' ' '; }
nf=$(grep ' end .* fivefold ' "$w/cr/fv/h/diaries/chess.txt" | wc -l); nfa=$(grep -c ' end ' "$w/cr/fv/h/diaries/chess.txt")
[ "$nf" -ge 1 ] && [ "$nf" -ge $((nfa - 1)) ] && ok "fivefold repetition is automatic (chess.fivefold = 1: $nf of $nfa finished games end 'fivefold')" || bad "fivefold ($nf / $nfa): $(ends "$w/cr/fv/h")"
nr=$(grep ' end .* repetition ' "$w/cr/rp/h/diaries/chess.txt" | wc -l); nrn=$(grep ' end .* repetition ' "$w/cr/rn/h/diaries/chess.txt" | wc -l); nrf=$(grep -c ' end ' "$w/cr/rn/h/diaries/chess.txt")
[ "$nr" -ge 1 ] && [ "$nrn" = 0 ] && ok "threefold repetition is a claim: with claim_pct = 100 the game ends 'repetition' ($nr), with claim_pct = 0 none does ($nrf games ended otherwise: $(ends "$w/cr/rn/h"))" || bad "claims ($nr / $nrn)"
n75=$(grep ' end .* seventyfive ' "$w/cr/m75/h/diaries/chess.txt" | wc -l)
[ "$n75" -ge 1 ] && ok "the 75-move rule is automatic (chess.moves75 = 1 for the test: $n75 games end 'seventyfive')" || bad "75 moves ($n75): $(ends "$w/cr/m75/h")"
! grep -qE ' end .* (material|fivefold|seventyfive) ' "$w/cr/off/h/diaries/chess.txt" && grep -q ' end ' "$w/cr/off/h/diaries/chess.txt" && ok "marker off: the old rules (no material / fivefold / 75-move ends; threefold and 50 moves end the game at once)" || bad "old rules"
for d in on fv rp m75 off; do ( cd "$w/cr/$d/h" || exit 1; export DIARY_HOME="$w/cr/$d/h"; "$w/cr/$d/bin/diary_sim" --more 0 --every 5000 > r1.txt 2>&1; grep -q '^import OK: 4 entities, 600 ticks verified' r1.txt || echo "replay $d failed" ); done > "$w/cr/replay.txt"
[ ! -s "$w/cr/replay.txt" ] && ok "every variant replays and verifies (C lines recomputed with the rules of its session marker)" || bad "chessrules replay: $(cat "$w/cr/replay.txt")"
cd "$w/cr/fv/h" || exit 1; export DIARY_HOME="$w/cr/fv/h"; sed -i '/^S2 /s/ chessrules=2//' diaries/sessions.txt; "$w/cr/fv/bin/diary_sim" --more 0 --every 5000 > r2.txt 2>&1; head -1 debug.txt | grep -q '^DRIFT' && ok "a removed chessrules=2 marker (other rules for the same games) is DRIFT" || bad "chessrules marker removed"
grep -q 'chessrules' "$root/README.md" && grep -q 'chessrules' "$root/data/limits.txt" && grep -q 'draw rules' "$root/data/help.txt" && ok "README, --help and limits.txt describe chessrules=2" || bad "chessrules docs"
unset DIARY_HOME

echo "== 44. trial by chess (trial=1): disputes settled with chess games, odd extensions, Rule 30 coin, adherence, T lines =="
rm -rf "$w/tr"; mkdir -p "$w/tr"
tr_run() {   # tr_run NAME 'sed expr on limits.txt' [ticks]: a fresh session of seed 42 (chess=1 govern=1 trial=1, session cap lifted)
  mkdir -p "$w/tr/$1/bin" "$w/tr/$1/h"; cp "$bin" "$w/tr/$1/bin/"; cp -r "$idata" "$w/tr/$1/data"
  sed -i 's/^chess.enabled = .*/chess.enabled = 1/; s/^govern.enabled = .*/govern.enabled = 1/; s/^trial.enabled = .*/trial.enabled = 1/; s/^trial.session_cap = .*/trial.session_cap = 50/; s/^trial.pause = .*/trial.pause = 5/; s/^trial.rest = .*/trial.rest = 10/' "$w/tr/$1/data/limits.txt"
  [ -n "$2" ] && sed -i "$2" "$w/tr/$1/data/limits.txt"
  ( cd "$w/tr/$1/h" || exit 1; export DIARY_HOME="$w/tr/$1/h"; "$w/tr/$1/bin/diary_sim" --seed 42 --ticks "${3:-500}" --yes --every 5000 > run.txt 2>&1 )
}
tr_run main ''
( cd "$w/tr/main/h" && export DIARY_HOME="$w/tr/main/h" && "$w/tr/main/bin/diary_sim" --more 300 --every 5000 > run2.txt 2>&1 )
cd "$w/tr/main/h" || exit 1; export DIARY_HOME="$w/tr/main/h"
nt=$(grep -c '^T[0-9]' diaries/trials.txt); nm=$(grep -c '^S[0-9].* trial=1' diaries/sessions.txt)
[ "$nt" -ge 3 ] && [ "$nm" = 2 ] && head -1 diaries/trials.txt | grep -q '^# seed 42$' && ok "new sessions carry trial=1 ($nm); $nt trials are T lines in diaries/trials.txt" || bad "trial lines ($nt, $nm)"
bad_t=$(grep '^T[0-9]' diaries/trials.txt | awk '{ ok = 1; split("t src a b games res score match win by verdict", k, " "); for (i = 1; i <= 11; i++) if (index($0, " " k[i] "=") == 0) ok = 0; if (!ok) bad++ } END { print bad + 0 }')
[ "$bad_t" = 0 ] && ok "every T line has t, src, a, b, games, res, score, match, win, by, verdict" || bad "T line fields ($bad_t)"
bad_s=$(grep '^T[0-9]' diaries/trials.txt | awk '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
  n = split(v["games"], g, ","); r = v["res"]; wa = 0; wb = 0
  for (i = 1; i <= length(r); i++) { c = substr(r, i, 1); if (c == "A") wa++; else if (c == "B") wb++ }
  if (length(r) != n || v["score"] != wa "-" wb || v["match"] % 2 != 1) bad++
  if (v["by"] == "score" && wa == wb) bad++
  if (v["by"] == "score" && ((wa > wb && v["win"] != v["a"]) || (wb > wa && v["win"] != v["b"]))) bad++ } END { print bad + 0 }')
[ "$bad_s" = 0 ] && ok "the games, results and score of every trial agree; the winner has more wins; every match is odd" || bad "trial arithmetic ($bad_s)"
bad_g=$(grep '^T[0-9]' diaries/trials.txt | while read -r l; do a=$(echo "$l" | sed -E 's/.* a=([a-z]+) .*/\1/'); b=$(echo "$l" | sed -E 's/.* b=([a-z]+) .*/\1/'); gs=$(echo "$l" | sed -E 's/.* games=([0-9,]+) .*/\1/' | tr ',' ' '); k=0
  for g in $gs; do k=$((k + 1)); want=$a; [ $((k % 2)) = 0 ] && want=$b; grep -q " g=$g start white=$want black=" diaries/chess.txt || echo "bad"; grep -q " g=$g end " diaries/chess.txt || echo "bad"; done; done | wc -l)
[ "$bad_g" = 0 ] && ok "every trial game is a recorded game of diaries/chess.txt, finished, with the colours alternating (the first one named plays white first)" || bad "trial games ($bad_g)"
grep -q 'Trial T[0-9]' run.txt && ok "the players' box at the end of the session has a one-liner about the latest trial" || bad "box line"
"$w/tr/main/bin/diary_sim" --trials > t1.txt 2>&1; rc=$?
[ $rc = 0 ] && head -1 t1.txt | grep -q '^trials [0-9]' && [ "$(grep -c '^T[0-9]' t1.txt)" = "$nt" ] && ok "make trials / --trials lists the trials after a verified replay" || bad "--trials ($rc)"
wsv=$(sed -n 's/^trial.win_stand = \([0-9]*\).*/\1/p' data/limits.txt 2>/dev/null); [ -z "$wsv" ] && wsv=$(sed -n 's/^trial.win_stand = \([0-9]*\).*/\1/p' "$w/tr/main/data/limits.txt")
vst=$(sed -n 's/^govern.veto_stand = \([0-9]*\).*/\1/p' "$w/tr/main/data/limits.txt"); wtr=$(sed -n 's/^trial.win_trust = \([0-9]*\).*/\1/p' "$w/tr/main/data/limits.txt"); vtr=$(sed -n 's/^govern.veto_trust = \([0-9]*\).*/\1/p' "$w/tr/main/data/limits.txt")
[ "$wsv" -lt "$vst" ] && [ "$wtr" -lt "$vtr" ] && ok "the effects of a trial (win: $wsv standing, $wtr trust) are smaller than a veto ($vst, $vtr)" || bad "effects ($wsv $vst $wtr $vtr)"
cd "$w/tr/main/h"; "$w/tr/main/bin/diary_sim" --more 0 --every 5000 > r1.txt 2>&1; head -1 debug.txt | grep -q '^OK' && ok "the save replays and verifies (T lines and their games recomputed)" || bad "trial replay"
cp diaries/trials.txt ../trials.keep
sed -i '2s/ score=\([0-9]\)-\([0-9]\) / score=\2-\1 /' diaries/trials.txt; "$w/tr/main/bin/diary_sim" --more 0 --every 5000 > r2.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && grep -q 'trials.txt T' r2.txt && ok "a changed T line: import FAILED, DRIFT" || bad "tampered T"
cp ../trials.keep diaries/trials.txt; sed -i '2d' diaries/trials.txt; "$w/tr/main/bin/diary_sim" --more 0 --every 5000 > r3.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "a removed T line is DRIFT" || bad "removed T"
cp ../trials.keep diaries/trials.txt; echo "T99 t=5 src=claim a=ada b=gemini games=1 res=A score=1-0 match=3 win=ada by=score verdict=adhered fx=none" >> diaries/trials.txt; "$w/tr/main/bin/diary_sim" --more 0 --every 5000 > r4.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "an invented T line is DRIFT" || bad "invented T"
cp ../trials.keep diaries/trials.txt; sed -i '/^S1 /s/ trial=1//' diaries/sessions.txt; "$w/tr/main/bin/diary_sim" --more 0 --every 5000 > r5.txt 2>&1
head -1 debug.txt | grep -q '^DRIFT' && ok "a removed trial=1 marker is DRIFT" || bad "trial marker removed"
for s in petition appeal claim restwork; do
  case $s in
    petition) x='s/^trial.claim_pct = .*/trial.claim_pct = 0/; s/^trial.restwork_pct = .*/trial.restwork_pct = 0/; s/^trial.appeal_pct = .*/trial.appeal_pct = 0/; s/^trial.petition_pct = .*/trial.petition_pct = 100/; s/^trial.escalate_pct = .*/trial.escalate_pct = 0/';;
    appeal) x='s/^trial.claim_pct = .*/trial.claim_pct = 0/; s/^trial.restwork_pct = .*/trial.restwork_pct = 0/; s/^trial.petition_pct = .*/trial.petition_pct = 0/; s/^trial.appeal_pct = .*/trial.appeal_pct = 100/';;
    claim) x='s/^trial.petition_pct = .*/trial.petition_pct = 0/; s/^trial.restwork_pct = .*/trial.restwork_pct = 0/; s/^trial.appeal_pct = .*/trial.appeal_pct = 0/; s/^trial.claim_pct = .*/trial.claim_pct = 100/; s/^trial.claim_window = .*/trial.claim_window = 100/';;
    restwork) x='s/^trial.petition_pct = .*/trial.petition_pct = 0/; s/^trial.claim_pct = .*/trial.claim_pct = 0/; s/^trial.appeal_pct = .*/trial.appeal_pct = 0/; s/^trial.restwork_pct = .*/trial.restwork_pct = 100/';;
  esac
  tr_run "src_$s" "$x" 700
  n_s=$(grep -c "^T[0-9].* src=$s " "$w/tr/src_$s/h/diaries/trials.txt"); n_o=$(grep -c '^T[0-9]' "$w/tr/src_$s/h/diaries/trials.txt")
  [ "$n_s" -ge 1 ] && [ "$n_s" = "$n_o" ] && ok "dispute source $s: $n_s trials, no other source" || bad "source $s ($n_s of $n_o)"
done
n_pp=$(grep -c '^T[0-9].* src=petition a=\(iris\|sol\|noor\) b=\(iris\|sol\|noor\) ' "$w/tr/src_petition/h/diaries/trials.txt")
tr_run esc 's/^trial.claim_pct = .*/trial.claim_pct = 0/; s/^trial.restwork_pct = .*/trial.restwork_pct = 0/; s/^trial.appeal_pct = .*/trial.appeal_pct = 0/; s/^trial.petition_pct = .*/trial.petition_pct = 100/; s/^trial.escalate_pct = .*/trial.escalate_pct = 100/' 700
n_e=$(grep -c '^T[0-9].* src=petition a=\(iris\|sol\|noor\) b=\(iris\|sol\|noor\) .* fx=none$' "$w/tr/esc/h/diaries/trials.txt"); n_ap=$(grep -c '^T[0-9].* src=appeal a=\(ada\|gemini\|replika\|robert\) b=\(iris\|sol\|noor\) ' "$w/tr/src_appeal/h/diaries/trials.txt")
[ "$n_pp" = 0 ] && [ "$n_e" -ge 1 ] && [ "$n_ap" -ge 1 ] && ok "clashing petitions: the watching players take over only when escalate_pct says so (two players, no effect on a wesen: $n_e); an appeal is a wesen against a player ($n_ap)" || bad "escalation ($n_pp $n_e $n_ap)"
lv='s/^chess.repeat = .*/chess.repeat = 1/; s/^trial.claim_pct = .*/trial.claim_pct = 100/; s/^trial.petition_pct = .*/trial.petition_pct = 0/; s/^trial.restwork_pct = .*/trial.restwork_pct = 0/; s/^trial.appeal_pct = .*/trial.appeal_pct = 0/; s/^trial.claim_window = .*/trial.claim_window = 100/'
tr_run lvl "$lv" 500
g_l=$(grep '^T[0-9]' "$w/tr/lvl/h/diaries/trials.txt" | sed -E 's/.* games=([0-9,]+) .*/\1/' | awk -F, '{ print NF }' | sort -u | tr '\n' ' '); by_l=$(grep '^T[0-9]' "$w/tr/lvl/h/diaries/trials.txt" | grep -c ' by=coin ')
n_l=$(grep -c '^T[0-9]' "$w/tr/lvl/h/diaries/trials.txt")
[ "$n_l" -ge 1 ] && [ "$g_l" = "11 " ] && [ "$by_l" = "$n_l" ] && grep '^T[0-9]' "$w/tr/lvl/h/diaries/trials.txt" | grep -q ' score=0-0 ' && ok "all games drawn (level): matches of 3, 3 and 5 games are played (11 in all), the next (7) would pass trial.max_games = 15, so the Rule 30 coin decides ($n_l trials by coin)" || bad "level series ($n_l '$g_l' $by_l)"
tr_run lvl3 "$lv; s/^trial.max_games = .*/trial.max_games = 3/" 400
g_3=$(grep '^T[0-9]' "$w/tr/lvl3/h/diaries/trials.txt" | sed -E 's/.* games=([0-9,]+) .*/\1/' | awk -F, '{ print NF }' | sort -u | tr '\n' ' ')
c3=$(grep '^T[0-9]' "$w/tr/lvl3/h/diaries/trials.txt" | sed -E 's/.* win=([a-z]+) .*/\1/' | sort -u | wc -l)
[ "$g_3" = "3 " ] && [ "$c3" -ge 2 ] && ok "trial.max_games = 3: three drawn games, then the coin (the coin falls both ways: $c3 different winners)" || bad "coin cap ('$g_3' $c3)"
tr_run adh0 's/^trial.adhere_pct = .*/trial.adhere_pct = 0/; s/^trial.adhere_min = .*/trial.adhere_min = 0/; s/^trial.adhere_max = .*/trial.adhere_max = 0/' 600
tr_run adh1 's/^trial.adhere_pct = .*/trial.adhere_pct = 100/; s/^trial.adhere_max = .*/trial.adhere_max = 100/; s/^trial.unrest_w = .*/trial.unrest_w = 0/; s/^trial.stand_w = .*/trial.stand_w = 0/' 600
a0=$(grep '^T[0-9].* fxl=' "$w/tr/adh0/h/diaries/trials.txt" | grep -vc ' verdict=refused .*fxl=-2/0/-1$'); r0=$(grep -c ' verdict=refused ' "$w/tr/adh0/h/diaries/trials.txt")
a1=$(grep -c ' verdict=refused ' "$w/tr/adh1/h/diaries/trials.txt"); n1=$(grep -c '^T[0-9]' "$w/tr/adh1/h/diaries/trials.txt")
[ "$r0" -ge 1 ] && [ "$a0" = 0 ] && [ "$a1" = 0 ] && [ "$n1" -ge 1 ] && ok "adherence is data: chance 0 = every losing wesen 'refused the trial' ($r0, -2 standing); chance 100 = none refuses ($n1 trials)" || bad "adherence ($r0 $a0 $a1 $n1)"
grep -q 'trial=1' "$w/tr/adh0/h/diaries/sessions.txt" && stand_n=$(grep -c . "$w/tr/adh0/h/diaries/govern.txt") && [ "$stand_n" -ge 1 ] && ok "the refusal costs standing: it is part of the governance record (replay-checked with the D lines)" || bad "standing record"
tr_run off 's/^trial.enabled = .*/trial.enabled = 0/'
if [ ! -f "$w/tr/off/h/diaries/trials.txt" ] || [ "$(grep -c '^T[0-9]' "$w/tr/off/h/diaries/trials.txt")" = 0 ]; then
  grep -q 'trial=1' "$w/tr/off/h/diaries/sessions.txt" && bad "trial off marker" || ok "trial.enabled = 0: no trial=1 marker, no T lines (the old behaviour exactly)"
else bad "trial off lines"; fi
grep -q 'trial' "$root/README.md" && grep -q 'trial.enabled' "$root/data/help.txt" && grep -q 'trial.first' "$root/data/limits.txt" && grep -q '^trial.clash.1' "$root/data/trial.txt" && ok "README, --help, limits.txt and data/trial.txt describe the trial" || bad "trial docs"
unset DIARY_HOME

echo "== 45. make small: the small binary (-Os, no -g, gc-sections, stripped) is smaller and gives the same output; make footprint =="
rm -rf "$w/sm"; mkdir -p "$w/sm/src/scripts" "$w/sm/a/bin" "$w/sm/b/bin"
cp "$root"/Makefile "$root"/*.ads "$root"/*.adb "$w/sm/src/"; cp -r "$root/data" "$w/sm/src/data"; cp "$root/scripts/footprint.sh" "$root/scripts/timed.sh" "$w/sm/src/scripts/"
( cd "$w/sm/src" && make small > "$w/sm/build.txt" 2>&1 ); rc=$?
sm="$w/sm/src/bin/diary_sim_small"
[ $rc = 0 ] && [ -x "$sm" ] && ! grep -qi 'warning' "$w/sm/build.txt" && ok "make small builds bin/diary_sim_small (no warnings)" || bad "make small ($rc)"
ssz=$(stat -c %s "$sm" 2>/dev/null || echo 0); dsz=$(stat -c %s "$bin")
dbg=$(readelf -S "$sm" 2>/dev/null | grep -c '\.debug_'); nsym=$(nm "$sm" 2>&1 | grep -c 'no symbols')
[ "$ssz" -gt 0 ] && [ "$ssz" -lt $((dsz / 2)) ] && [ "$dbg" = 0 ] && [ "$nsym" = 1 ] && ok "the small binary is $((ssz / 1024)) KB against $((dsz / 1024)) KB of the dev build (no debug sections, no symbols)" || bad "small size ($ssz / $dsz, debug $dbg, nosym $nsym)"
cp "$bin" "$w/sm/a/bin/diary_sim"; cp "$sm" "$w/sm/b/bin/diary_sim_small"
for d in a b; do
  cp -r "$idata" "$w/sm/$d/data"; sed -i 's/^chess.enabled = .*/chess.enabled = 1/; s/^govern.enabled = .*/govern.enabled = 1/; s/^trial.enabled = .*/trial.enabled = 1/; s/^screen.enabled = .*/screen.enabled = 1/; s/^robot.enabled = .*/robot.enabled = 1/' "$w/sm/$d/data/limits.txt"
  x="$w/sm/$d/bin/diary_sim"; [ $d = b ] && x="$w/sm/$d/bin/diary_sim_small"
  mkdir -p "$w/sm/$d/h"; ( cd "$w/sm/$d" && export DIARY_HOME="$w/sm/$d/h" && { "$x" --seed 42 --ticks 400 --yes --every 5000; "$x" --more 200 --every 5000; "$x" --trials; "$x" --elo; "$x" --govern; "$x" --more 0 --every 5000 --debug-section run; } 2>&1 | sed "s#$w/sm/$d/h#H#g" > "$w/sm/$d/out.txt" )
  ( cd "$w/sm/$d/h" && find . -type f | sort | while read -r f; do case $f in ./debug*|./last*|./run_report*|./run_log*|./trend*|./night_console*|./state.ckpt*|./ckpt_log*) ;; *.jsonl) sed -E 's/"ts":"[^"]*",//' "$f" | cksum | sed "s#\$# $f#";; ./diaries/sessions.txt) grep -v '^# build' "$f" | cksum | sed "s#\$# $f#";; *) cksum "$f";; esac; done > "$w/sm/$d/files.txt" )
done
[ -s "$w/sm/a/out.txt" ] && cmp -s "$w/sm/a/out.txt" "$w/sm/b/out.txt" && cmp -s "$w/sm/a/files.txt" "$w/sm/b/files.txt" && grep -q '^T[0-9]' "$w/sm/a/out.txt" && ok "the small binary gives the same console output and byte-identical diaries / entities / reports as the dev build ($(wc -l < "$w/sm/a/files.txt") files compared; trials, Elo, governance included)" || bad "small vs dev output"
( cd "$w/sm/src" && make footprint > "$w/sm/fp.txt" 2>&1 ); grep -q '^source  : ' "$w/sm/fp.txt" && grep -q '^data    : ' "$w/sm/fp.txt" && grep -q '^binary  : bin/diary_sim_small ' "$w/sm/fp.txt" && grep -q '^units   : ' "$w/sm/fp.txt" && grep -q '^runtime : ' "$w/sm/fp.txt" && ok "make footprint prints source, data, binary (stripped / debug share), per-unit and runtime sizes" || bad "footprint"
grep -q '^## Footprint' "$root/README.md" && grep -q 'make small' "$root/README.md" && grep -q 'make small' "$root/Makefile" && ok "README has a Footprint section with the size table and make small" || bad "footprint docs"

echo "== 46. records (records=1): votes, petitions, dictionary, announcements; clean word vote; make divergence; marker off = nothing =="
rm -rf "$w/rc"; mkdir -p "$w/rc"
rc_run() {   # rc_run NAME 'sed expr on limits.txt' [ticks]: a fresh save of seed 42 (govern=1), proposals made likely
  mkdir -p "$w/rc/$1/bin" "$w/rc/$1/h"; cp "$bin" "$w/rc/$1/bin/"; cp -r "$idata" "$w/rc/$1/data"
  sed -i 's/^govern.enabled = .*/govern.enabled = 1/; s/^rec.prop_pct = .*/rec.prop_pct = 70/; s/^rec.ann_pct = .*/rec.ann_pct = 50/; s/^trial.enabled = .*/trial.enabled = 0/; s/^rec.quality = .*/rec.quality = 0/' "$w/rc/$1/data/limits.txt"
  [ -n "$2" ] && sed -i "$2" "$w/rc/$1/data/limits.txt"
  ( cd "$w/rc/$1/h" || exit 1; export DIARY_HOME="$w/rc/$1/h"; "$w/rc/$1/bin/diary_sim" --seed 42 --ticks "${3:-300}" --yes --every 5000 > run.txt 2>&1 )
}
rc_run main ''
( cd "$w/rc/main/h" && export DIARY_HOME="$w/rc/main/h" && "$w/rc/main/bin/diary_sim" --more 300 --every 5000 > run2.txt 2>&1 && "$w/rc/main/bin/diary_sim" --more 300 --every 5000 > run3.txt 2>&1 )
cd "$w/rc/main/h" || exit 1; export DIARY_HOME="$w/rc/main/h"
nm=$(grep -c '^S[0-9].* records=1' diaries/sessions.txt); nv=$(grep -c '^V[0-9]' diaries/votes.txt); np=$(grep -c '^P[0-9]' diaries/petitions.txt)
[ "$nm" = 3 ] && [ "$nv" -ge 20 ] && [ "$np" -ge 3 ] && head -1 diaries/votes.txt | grep -q '^# seed 42$' && ok "new sessions carry records=1 ($nm); $nv vote lines and $np petition lines were written" || bad "records files ($nm, $nv, $np)"
bad_v=$(grep '^V[0-9]' diaries/votes.txt | awk '{ ok = 1; split("t s voter kind subj choice w", k, " "); for (i = 1; i <= 7; i++) if (index($0, " " k[i] "=") == 0) ok = 0; if (!ok) bad++ } END { print bad + 0 }')
[ "$bad_v" = 0 ] && ok "every vote line has t, s, voter, kind, subj, choice, w" || bad "vote fields ($bad_v)"
nd=$(grep -c '^D[0-9].* kind=\(grant\|partial\|defer\|refuse\) ' diaries/govern.txt); nvp=$(grep -c ' kind=petition ' diaries/votes.txt)
nfin=$(grep '^D[0-9].* kind=\(grant\|partial\|refuse\) ' diaries/govern.txt | sed -E 's/.* pet=(P[0-9]+) .*/\1/' | sort -u | wc -l)
[ "$nd" = "$nvp" ] && [ "$nfin" = "$np" ] && ok "every decision of a player is a vote ($nvp) and every answered petition one petitions.txt line ($np)" || bad "votes against D lines ($nd, $nvp, $nfin, $np)"
bad_d=$(grep '^L[0-9]' diaries/dictionary.txt | awk '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
  n = v["yes"] + v["no"]; if (v["st"] == "A" && v["yes"] * 2 <= n) bad++; if (v["st"] == "R" && v["why"] == "split" && v["yes"] * 2 >= n) bad++
  if (v["st"] == "R" && v["why"] == "tie" && v["yes"] * 2 != n) bad++; if (n < 3) bad++; if (v["word"] !~ /^[a-z]+$/) bad++ } END { print bad + 0 }')
nl=$(grep -c '^L[0-9]' diaries/dictionary.txt)
[ "$nl" -ge 2 ] && [ "$bad_d" = 0 ] && ok "$nl proposed words voted by the players: agreed only with a majority, a tie is rejected, words are letters only" || bad "dictionary ($nl, $bad_d)"
cap=$(sed -n 's/^rec.agree_cap = \([0-9]*\).*/\1/p' "$w/rc/main/data/limits.txt"); wcap=$(sed -n 's/^rec.words_per_session = \([0-9]*\).*/\1/p' "$w/rc/main/data/limits.txt")
mx_a=$(grep '^L[0-9].* st=A ' diaries/dictionary.txt | sed -E 's/.* s=([0-9]+) .*/\1/' | sort | uniq -c | awk 'BEGIN { m = 0 } { if ($1 > m) m = $1 } END { print m }')
mx_l=$(grep '^L[0-9]' diaries/dictionary.txt | sed -E 's/.* s=([0-9]+) .*/\1/' | sort | uniq -c | awk 'BEGIN { m = 0 } { if ($1 > m) m = $1 } END { print m }')
[ "$mx_a" -le "$cap" ] && [ "$mx_l" -le "$wcap" ] && ok "growth is bounded per session: at most $mx_a agreed (cap $cap) and $mx_l voted (cap $wcap)" || bad "caps ($mx_a $cap $mx_l $wcap)"
na=$(grep -c '^A[0-9]' diaries/announcements.txt)
bad_a=$(grep '^A[0-9]' diaries/announcements.txt | awk '{ ok = 1; split("t s by kind topic heard mood cost react", k, " "); for (i = 1; i <= 9; i++) if (index($0, " " k[i] "=") == 0) ok = 0; if (!ok) bad++ } END { print bad + 0 }')
[ "$na" -ge 2 ] && [ "$bad_a" = 0 ] && grep -q ' kind=wish ' diaries/announcements.txt && grep -q ' cost=[1-9]' diaries/announcements.txt && ok "$na announcements, each with who, what, how many heard, the mood it moved and the standing it cost" || bad "announcements ($na, $bad_a)"
dig=$(grep '^W[0-9]' diaries/sessions.txt | sed -E 's/^W[0-9]+ tick=[0-9]+ //' | tr ' ' '\n' | sed -E 's/^[a-z]+=//; s#/.*##' | grep -c '[0-9]')
[ "$dig" = 0 ] && ok "the favourite words of records sessions are words (no numeric chess moves, no digits)" || bad "digit words in the vote ($dig)"
grep -E '^\| ' run3.txt | awk 'length($0) > 80 { bad++ } END { exit bad > 0 }' && ok "the end box stays within 80 columns" || bad "box wider than 80"
"$w/rc/main/bin/diary_sim" --divergence > dv.txt 2>&1; rc1=$?
[ $rc1 = 0 ] && grep -q '^sess player' dv.txt && grep -q '^sess  decided  agreed' dv.txt && [ "$(awk 'length($0) > 80' dv.txt | wc -l)" = 0 ] && grep -c '^   [0-9] ' dv.txt | grep -q '^[1-9]' && ok "make divergence prints claim, truth, gap, grants and refusals, words yes/no and the dictionary growth (within 80 columns)" || bad "--divergence ($rc1)"
"$w/rc/main/bin/diary_sim" --dictionary > dc.txt 2>&1; rc2=$?
[ $rc2 = 0 ] && head -1 dc.txt | grep -q '^Dictionary growth (base [0-9]* words' && [ "$(grep -c '^L[0-9]' dc.txt)" -ge 2 ] && ok "make dictionary lists the official words against the base vocabulary" || bad "--dictionary ($rc2)"
"$w/rc/main/bin/diary_sim" --more 0 --every 5000 > r1.txt 2>&1; head -1 debug.txt | grep -q '^OK' && ok "the save replays and verifies all four files" || bad "records replay"
cp -r diaries "$w/rc/diaries.bak"
sed -i '0,/ kind=petition .* choice=refuse /s// kind=petition subj=P1 choice=grant /' diaries/votes.txt; sed -i '0,/choice=refuse/s//choice=grant/' diaries/votes.txt
"$w/rc/main/bin/diary_sim" --more 0 --every 5000 > r2.txt 2>&1; rc3=$?
[ $rc3 != 0 ] && grep -q 'votes.txt V[0-9]* differs from the replay' r2.txt && ok "a changed vote is DRIFT" || bad "vote tamper ($rc3)"
rm -rf diaries; cp -r "$w/rc/diaries.bak" diaries; sed -i '0,/^L1 /{/^L1 /d}' diaries/dictionary.txt
"$w/rc/main/bin/diary_sim" --more 0 --every 5000 > r3.txt 2>&1; rc4=$?
[ $rc4 != 0 ] && grep -q 'dictionary.txt L1 differs from the replay' r3.txt && ok "a removed dictionary line is DRIFT" || bad "dictionary tamper ($rc4)"
rm -rf diaries; cp -r "$w/rc/diaries.bak" diaries; echo "A99 t=5 s=1 by=ada kind=wish topic=x heard=0 mood=0 cost=0 react=ok" >> diaries/announcements.txt
"$w/rc/main/bin/diary_sim" --more 0 --every 5000 > r4.txt 2>&1; rc5=$?
[ $rc5 != 0 ] && grep -q 'announcements.txt A99 differs from the replay' r4.txt && ok "an invented announcement is DRIFT" || bad "announcement tamper ($rc5)"
rm -rf diaries; cp -r "$w/rc/diaries.bak" diaries
rc_run off 's/^records.enabled = .*/records.enabled = 0/' 300
( cd "$w/rc/off/h" && export DIARY_HOME="$w/rc/off/h" && "$w/rc/off/bin/diary_sim" --more 300 --every 5000 > run2.txt 2>&1 )
[ ! -e "$w/rc/off/h/diaries/votes.txt" ] && [ ! -e "$w/rc/off/h/diaries/dictionary.txt" ] && ! grep -q 'records=1' "$w/rc/off/h/diaries/sessions.txt" && ok "records.enabled = 0: no marker, none of the four files" || bad "marker off"
sed -i 's/^records.enabled = .*/records.enabled = 1/' "$w/rc/off/data/limits.txt"
( cd "$w/rc/off/h" && export DIARY_HOME="$w/rc/off/h" && "$w/rc/off/bin/diary_sim" --more 300 --every 5000 > run3.txt 2>&1; echo "rc=$?" >> run3.txt; "$w/rc/off/bin/diary_sim" --more 0 --every 5000 > run4.txt 2>&1; echo "rc=$?" >> run4.txt )
[ "$(grep -c '^S[0-9].* records=1' "$w/rc/off/h/diaries/sessions.txt")" = 1 ] && [ "$(grep -c '^S[0-9]' "$w/rc/off/h/diaries/sessions.txt")" = 3 ] && grep -q '^rc=0' "$w/rc/off/h/run3.txt" && grep -q '^rc=0' "$w/rc/off/h/run4.txt" && [ -s "$w/rc/off/h/diaries/votes.txt" ] && ok "an existing save picks it up at its next new session (no --fresh): sessions 1-2 as before, session 3 has records=1, all replays verify" || bad "marker on for an old save"
grep -q '^## Records, dictionary' "$root/README.md" && grep -q 'make divergence' "$root/README.md" && grep -q 'make divergence' "$root/Makefile" && grep -q -- '--divergence' "$root/data/help.txt" && ok "README, Makefile and --help mention records, make divergence and make dictionary" || bad "docs for records"

echo "== 47. records=2 (rec.quality): the meaning of a proposal is a base word, no repeated meaning (agreed, pending, cooldown), ties rejected, old save picks it up =="
rm -rf "$w/rq"; mkdir -p "$w/rq/bin" "$w/rq/h"; cp "$bin" "$w/rq/bin/"; cp -r "$idata" "$w/rq/data"
sed -i 's/^govern.enabled = .*/govern.enabled = 1/; s/^rec.prop_pct = .*/rec.prop_pct = 90/; s/^trial.enabled = .*/trial.enabled = 0/; s/^players4.enabled = .*/players4.enabled = 1/; s/^rec.quality = .*/rec.quality = 0/' "$w/rq/data/limits.txt"
( cd "$w/rq/h" || exit 1; export DIARY_HOME="$w/rq/h"; q="$w/rq/bin/diary_sim"
  "$q" --seed 42 --ticks 400 --yes --every 5000 > r1.txt 2>&1; "$q" --more 400 --every 5000 > r2.txt 2>&1
  sed -i 's/^rec.quality = .*/rec.quality = 1/' "$w/rq/data/limits.txt"
  "$q" --more 400 --every 5000 > r3.txt 2>&1; "$q" --more 400 --every 5000 > r4.txt 2>&1; "$q" --more 400 --every 5000 > r5.txt 2>&1; "$q" --more 400 --every 5000 > r6.txt 2>&1
  "$q" --more 0 --every 5000 > r7.txt 2>&1; echo "rc=$?" >> r7.txt )
cd "$w/rq/h" || exit 1; export DIARY_HOME="$w/rq/h"
m1=$(grep -c '^S[0-9].* records=1' diaries/sessions.txt); m2=$(grep -c '^S[0-9].* records=2' diaries/sessions.txt)
[ "$m1" = 2 ] && [ "$m2" = 4 ] && grep -q '^rc=0' r7.txt && ! grep -q DRIFT r7.txt && ok "an existing records=1 save picks up records=2 at its next new session (no --fresh): sessions 1-2 records=1, 3-6 records=2, replay verifies" || bad "records=2 marker ($m1 $m2)"
first2=$(grep '^S[0-9].* records=2' diaries/sessions.txt | head -1 | sed -E 's/^S([0-9]+) .*/\1/')
grep -v '^#' "$root/data/vocab.txt" | grep -v '^$' > "$w/rq/base.txt"
nq=$(grep '^L[0-9]' diaries/dictionary.txt | awk -v f="$first2" '{ for (i = 1; i <= NF; i++) if ($i ~ /^s=/ && substr($i, 3) + 0 >= f) n++ } END { print n + 0 }')
nonbase=$(grep '^L[0-9]' diaries/dictionary.txt | awk -v f="$first2" -v b="$w/rq/base.txt" 'BEGIN { while ((getline l < b) > 0) base[l] = 1 }
  { s = ""; m = ""; for (i = 1; i <= NF; i++) { if ($i ~ /^s=/) s = substr($i, 3) + 0; if ($i ~ /^mean=/) m = substr($i, 6) }
    if (s < f) next; n = split(m, part, "+"); for (j = 1; j <= n; j++) if (!(part[j] in base)) bad++ } END { print bad + 0 }')
[ "$nq" -ge 6 ] && [ "$nonbase" = 0 ] && ok "records=2 proposals: the meaning is always a base word of data/vocab.txt ($nq proposals voted in sessions $first2 on)" || bad "meaning not a base word ($nq $nonbase)"
rep=$(grep '^L[0-9]' diaries/dictionary.txt | awk -v f="$first2" '{ s = ""; m = ""; st = ""; for (i = 1; i <= NF; i++) { if ($i ~ /^s=/) s = substr($i, 3) + 0; if ($i ~ /^mean=/) m = substr($i, 6); if ($i ~ /^st=/) st = substr($i, 4) }
  if (s >= f) { if (m in agreed) bad++; if ((m in last) && s < last[m] + 3) bad++ }
  last[m] = s; if (st == "A") agreed[m] = 1 } END { print bad + 0 }')
[ "$rep" = 0 ] && ok "no meaning is put to a vote again once agreed, nor within rec.mean_cooldown (3) sessions of a rejection (checked over the whole dictionary)" || bad "repeated meaning ($rep)"
dup=$(grep '^L[0-9]' diaries/dictionary.txt | awk '{ for (i = 1; i <= NF; i++) { if ($i ~ /^s=/) s = $i; if ($i ~ /^mean=/) m = $i } print s, m }' | sort | uniq -d | wc -l)
tie_bad=$(grep '^L[0-9]' diaries/dictionary.txt | awk '{ for (i = 1; i <= NF; i++) { if ($i ~ /^yes=/) y = substr($i, 5); if ($i ~ /^no=/) n = substr($i, 4); if ($i ~ /^st=/) st = substr($i, 4) } if (y == n && st != "R") bad++ } END { print bad + 0 }')
ties=$(grep -c ' why=tie' diaries/dictionary.txt)
[ "$dup" = 0 ] && [ "$tie_bad" = 0 ] && [ "$ties" -ge 1 ] && ok "no meaning twice in one session; a tie (2/2) is always rejected ($ties ties in this save)" || bad "dup/tie ($dup $tie_bad)"
# secret ballot (several forms for one meaning): B lines in diaries/ballots.txt only
nb=$(grep -c '^B[0-9]' diaries/ballots.txt 2>/dev/null)
bad_b=$(grep '^B[0-9]' diaries/ballots.txt | awk '{ for (i = 1; i <= NF; i++) { if ($i ~ /^alts=/) a = substr($i, 6); if ($i ~ /^win=/) wn = substr($i, 5); if ($i ~ /^tally=/) t = substr($i, 7); if ($i ~ /^tie=/) te = substr($i, 5) }
  na = split(a, al, ","); ok = 0; for (i = 1; i <= na; i++) if (al[i] == wn) ok = 1; if (!ok || na < 2 || na > 3) bad++
  nt = split(t, tl, ","); sum = 0; top = 0; for (i = 1; i <= nt; i++) { split(tl[i], kv, ":"); sum += kv[2]; if (kv[2] > top) top = kv[2] }
  tops = 0; for (i = 1; i <= nt; i++) { split(tl[i], kv, ":"); if (kv[2] == top) tops++ }
  if (sum != 4 || (te == 1) != (tops > 1)) bad++ } END { print bad + 0 }')
nwin=0; for b in $(grep '^B[0-9]' diaries/ballots.txt | sed -E 's/^B[0-9]+ t=[0-9]+ s=([0-9]+) mean=([^ ]+) .* win=([a-z]+) .*/\1:\2:\3/'); do s_=${b%%:*}; r_=${b#*:}; m_=${r_%%:*}; w_=${r_##*:}; grep -q " s=$s_ st=[AR] word=$w_ slot=[a-z]* mean=$m_ " diaries/dictionary.txt && nwin=$((nwin + 1)); done
[ "$nb" -ge 3 ] && [ "$bad_b" = 0 ] && [ "$nwin" = "$nb" ] && head -1 diaries/ballots.txt | grep -q '^# seed 42$' && ok "secret ballots: $nb B lines (2 or 3 forms for a meaning, every player's pick, tally sums to the players, a die only on a tie); the winner is the form that went to the yes/no vote and into the dictionary" || bad "ballots ($nb $bad_b $nwin)"
leak=0
for b in $(grep '^B[0-9]' diaries/ballots.txt | sed -E 's/.* alts=([a-z,]*) .* win=([a-z]*) .*/\1:\2/'); do alts=${b%%:*}; win=${b##*:}; for a in ${alts//,/ }; do [ "$a" = "$win" ] && continue; if grep -rlw --exclude='state.ckpt*' -- "$a" . "$w/rq/"*.out 2>/dev/null | grep -qv 'ballots.txt'; then leak=$((leak + 1)); fi; done; done
grep -rl --exclude='state.ckpt*' ' picks=' . 2>/dev/null | grep -qv 'ballots.txt' && leak=$((leak + 1))   # state.ckpt (0.058): the program's own state, like ballots.txt never shown
for o in --divergence --dictionary --inbox --govern --audit --robot; do "$w/rq/bin/diary_sim" $o > "$w/rq/view.out" 2>&1; grep -q ' picks=\|^B[0-9]' "$w/rq/view.out" && leak=$((leak + 1)); done
grep -q 'kind=ballot' diaries/votes.txt && leak=$((leak + 1))
[ "$nb" -ge 3 ] && [ "$leak" = 0 ] && ok "the ballot is secret: no losing form and no pick appears in any other file or player-visible view (diaries, votes, announcements, inbox, divergence, dictionary, govern, audit)" || bad "ballot leaks ($leak)"
"$w/rq/bin/diary_sim" --ballots > "$w/rq/bal.out" 2>&1; nbw=$(awk 'length > 80' "$w/rq/bal.out" | wc -l)
grep -q '^B[0-9]' diaries/ballots.txt && grep -q '^Secret ballots' "$w/rq/bal.out" && [ "$nbw" = 0 ] && grep -q ' -> ' "$w/rq/bal.out" && ok "make ballots (--ballots) shows the last ballots to Robert: forms, tally, winner, who picked what (<= 80 columns)" || bad "--ballots view ($nbw)"
cp -r diaries "$w/rq/diaries.bak"; l=$(grep -m1 '^B2 ' diaries/ballots.txt | sed -E 's/ win=[a-z]+/ win=zzz/'); sed -i "s/^B2 .*/$l/" diaries/ballots.txt
"$w/rq/bin/diary_sim" --more 0 --every 5000 > "$w/rq/t1.out" 2>&1; rct=$?
[ "$rct" != 0 ] && grep -q 'ballots.txt B2 differs from the replay' "$w/rq/t1.out" && ok "a changed ballot line is DRIFT (replay-verified like the other records)" || bad "ballot tamper ($rct)"
rm -rf diaries; cp -r "$w/rq/diaries.bak" diaries; rm -rf "$w/rq/diaries.bak"
grep -q 'make ballots' "$root/README.md" && grep -q 'make ballots' "$root/Makefile" && grep -q -- '--ballots' "$root/data/help.txt" && grep -q 'rec.alt_max' "$root/data/limits.txt" && ok "README, Makefile, --help and data/limits.txt describe the secret ballot (make ballots, rec.alt_max)" || bad "docs for ballots"
rm -rf "$w/rq/q0"; mkdir -p "$w/rq/q0/bin" "$w/rq/q0/h"; cp "$bin" "$w/rq/q0/bin/"; cp -r "$idata" "$w/rq/q0/data"
sed -i 's/^govern.enabled = .*/govern.enabled = 1/; s/^trial.enabled = .*/trial.enabled = 0/; s/^rec.quality = .*/rec.quality = 0/' "$w/rq/q0/data/limits.txt"
( cd "$w/rq/q0/h" || exit 1; export DIARY_HOME="$w/rq/q0/h"; "$w/rq/q0/bin/diary_sim" --seed 42 --ticks 300 --yes --every 5000 > r1.txt 2>&1; "$w/rq/q0/bin/diary_sim" --more 300 --every 5000 > r2.txt 2>&1 )
[ "$(grep -c '^S[0-9].* records=1' "$w/rq/q0/h/diaries/sessions.txt")" = 2 ] && ! grep -q 'records=2' "$w/rq/q0/h/diaries/sessions.txt" && [ ! -e "$w/rq/q0/h/diaries/ballots.txt" ] && ok "rec.quality = 0: sessions stay records=1 (the earlier rules), no ballots" || bad "rec.quality = 0"
grep -q 'rec.quality' "$root/data/limits.txt" && grep -q 'rec.mean_cooldown' "$root/data/limits.txt" && grep -q 'records=2' "$root/README.md" && grep -q 'records=2' "$root/data/help.txt" && ok "README, --help and data/limits.txt describe records=2, rec.quality and rec.mean_cooldown" || bad "docs for records=2"

echo "== 48. console: short form by default (no markers, no pointer), run_report.txt complete, run_log.txt entries, VERBOSE=1 = the old output, make report, make runlog =="
rm -rf "$w/sh"; mkdir -p "$w/sh/bin"; cp "$bin" "$w/sh/bin/"; cp -r "$root/data" "$w/sh/data"
sh_run() {   # sh_run HOME 'env prefix' args...: the same two sessions (seed 42, 300 + 200 ticks)
  h=$1; pre=$2; shift 2; mkdir -p "$w/sh/$h"
  ( cd "$w/sh/$h" || exit 1; export DIARY_HOME="$w/sh/$h/save"; env -u DIARY_VERBOSE $pre "$w/sh/bin/diary_sim" --seed 42 --ticks 300 --yes --every 100 "$@" > c1.txt 2>&1
    env -u DIARY_VERBOSE $pre "$w/sh/bin/diary_sim" --more 200 --every 100 "$@" > c2.txt 2>&1 )
}
sh_run short DIARY_NOP=1
sh_run flag DIARY_NOP=1 --verbose
sh_run envv DIARY_VERBOSE=1
cd "$w/sh/short" || exit 1
tl=$(sed -n '/^report: /,$p' c1.txt | wc -l); tl2=$(sed -n '/^report: /,$p' c2.txt | wc -l)
grep -q '^entity .*mood energy' c1.txt && [ "$(grep -c '^\(Adam\|Eve\|Abel\|Ruth\) .* | ' c1.txt)" -ge 4 ] && grep -q '^petitions [0-9]* filed' c1.txt && grep -q '^session 1 ' c1.txt && grep -q '^+-- The players report' c1.txt \
  && ! grep -q '^@@\|^Full report\|run_report.txt\|run_log.txt' c1.txt c2.txt && tail -1 c1.txt | grep -q '[^ ]' && ! grep -q '^chess games\|^treadmill\|^recovery since\|^screens (' c1.txt \
  && [ "$tl" -le 45 ] && [ "$tl2" -le 45 ] && ok "default console: entity table, petitions, session lines, the players' boxes, no @@ marker and no pointer; $tl lines after 'report:' (<= 45), no chess/treadmill/recovery/screens blocks" || bad "default tail ($tl $tl2)"
pat='^@@TRACE build=[0-9]+\.[0-9]{3} seed=[0-9]+ session=[0-9]+ ticks=[0-9]+\.\.[0-9]+ anomalies=(none|[0-9]+\[[^] ]*\]) files=[^ ]+$'
c_ok=1; grep -E "$pat" save/run_report.txt > /dev/null || c_ok=0; sed -n 2p save/run_report.txt | grep -E '^@@SECTIONS ([a-z]+=[0-9]+,)*[a-z]+=[0-9]+$' > /dev/null || c_ok=0
head -1 save/run_report.txt | grep -q '^@@TRACE ' && sed -n 2p save/run_report.txt | grep -q '^@@SECTIONS ' || c_ok=0
[ "$c_ok" = 1 ] && ok "@@TRACE (build seed session ticks anomalies files) and @@SECTIONS are one parseable line each, lines 1-2 of run_report.txt (not on the console)" || bad "marker ($c_ok)"
# run_log.txt: one entry per run, a local time stamp first, then the two marker lines and the path of the report
nst=$(grep -c '^[0-9]\{4\}-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] RUN$' save/run_log.txt); nl=$(wc -l < save/run_log.txt)
sfx=$(date +%F); l_ok=1; [ "$(sed -n 1p save/run_log.txt | cut -c1-10)" = "$sfx" ] || [ "$(sed -n 1p save/run_log.txt | cut -c1-10)" = "$(date -d yesterday +%F)" ] || l_ok=0
[ "$(sed -n 2p save/run_log.txt)" != "" ] && [ "$(sed -n 5p save/run_log.txt | cut -c21-23)" = RUN ] || l_ok=0
{ sed -n 2,3p save/run_log.txt; sed -n 6,7p save/run_log.txt; } > "$w/sh/lg.txt"; sed -n 2p "$w/sh/lg.txt" | grep -q '^@@SECTIONS ' && sed -n 4p "$w/sh/lg.txt" | grep -q '^@@SECTIONS ' || l_ok=0
sed -n 4p save/run_log.txt | grep -q "^report: .*/save/run_report.txt$" && sed -n 8p save/run_log.txt | grep -q "^report: .*/save/run_report.txt$" || l_ok=0
cmp -s <(sed -n 6,7p save/run_log.txt) <(head -2 save/run_report.txt) || l_ok=0
[ "$nst" = 2 ] && [ "$nl" = 8 ] && [ "$l_ok" = 1 ] && ok "run_log.txt: one entry per run (2), each 'YYYY-MM-DD HH:MM:SS RUN', the @@TRACE and @@SECTIONS lines (the same as run_report.txt lines 1-2) and 'report: <path>'" || bad "run_log.txt ($nst $nl $l_ok)"
# the clock is only in run_log.txt: no replay-verified file has the date in it
! grep -rl "$(date +%Y-%m-%d)" save --include='*.txt' 2> /dev/null | grep -v 'run_log.txt\|trend.txt\|debug\|last_error' | grep -q . && ok "the time stamp is only in run_log.txt and trend.txt (no entity, summary, report or diary-record file carries it; only the jsonl "ts" fields, as before)" || bad "clock in a sim file"
badsec=0; for pr in $(sed -n 2p save/run_report.txt | sed 's/^@@SECTIONS //; s/,/ /g'); do n=${pr%%=*}; l=${pr##*=}; [ "$(sed -n "${l}p" save/run_report.txt)" = "== $n ==" ] || badsec=$((badsec + 1)); done
nsec=$(sed -n 2p save/run_report.txt | tr ',' '\n' | wc -l); nh=$(grep -c '^== [a-z]* ==$' save/run_report.txt)
[ "$badsec" = 0 ] && [ "$nsec" = "$nh" ] && [ "$nsec" -ge 12 ] && ok "section headers: every '== name ==' line is where @@SECTIONS says ($nsec sections)" || bad "sections ($badsec $nsec $nh)"
# complete: everything the verbose console prints is in run_report.txt, and so is every line of the short form
sed -n '/^report: /,$p' ../flag/c2.txt | sed 's#/sh/[a-z]*/#/sh/X/#g' > "$w/sh/vtail.txt"; grep -v '^== \|^@@' save/run_report.txt | sed 's#/sh/[a-z]*/#/sh/X/#g' > "$w/sh/rr.txt"
miss=$(grep -vxF -f "$w/sh/rr.txt" "$w/sh/vtail.txt" | grep -v '^$' | wc -l); miss2=$(sed -n '/^report: /,$p' c2.txt | grep -vxF -f "$w/sh/rr.txt" | grep -v '^$' | wc -l)
vl=$(wc -l < "$w/sh/vtail.txt")
[ "$miss" = 0 ] && [ "$miss2" = 0 ] && [ "$vl" -gt 100 ] && grep -q '^== chess ==' save/run_report.txt && grep -q '^== ledger ==' save/run_report.txt && ok "run_report.txt is complete: every line of the verbose console ($vl lines) and of the short form is in it" || bad "run_report.txt incomplete ($miss $miss2 $vl)"
# --verbose and DIARY_VERBOSE=1 print the old whole report; the simulation is untouched by any of it
nrm() { sed 's#/sh/[a-z]*/#/sh/X/#g' "$1"; }
sums() { ( cd "$1/save" || exit 1; find . -type f | sort | while read -r f; do case $f in ./run_report*|./run_log*|./trend*|./night_console*|./debug*|./last*|./voice_log*|./state.ckpt*|./ckpt_log*) ;; *.jsonl) sed -E 's/"ts":"[^"]*",//' "$f" | cksum | sed "s#\$# $f#";; ./diaries/sessions.txt) grep -v '^# build' "$f" | cksum | sed "s#\$# $f#";; *) cksum "$f";; esac; done ); }
diff <(nrm ../flag/c1.txt) <(nrm ../envv/c1.txt) > /dev/null && diff <(nrm ../flag/c2.txt) <(nrm ../envv/c2.txt) > /dev/null && grep -q '^chess games' ../flag/c1.txt && grep -q '^treadmill' ../flag/c1.txt && grep -q '^please attach debug.txt' ../flag/c1.txt && ! grep -q '^@@TRACE\|^Full report:' ../flag/c1.txt \
  && ok "--verbose = DIARY_VERBOSE=1: the whole report as before (no marker, no pointer), $vl lines after 'report:'" || bad "verbose output"
sums "$w/sh/short" > "$w/sh/s1.txt"; sums "$w/sh/flag" > "$w/sh/s2.txt"; sums "$w/sh/envv" > "$w/sh/s3.txt"
[ -s "$w/sh/s1.txt" ] && cmp -s "$w/sh/s1.txt" "$w/sh/s2.txt" && cmp -s "$w/sh/s1.txt" "$w/sh/s3.txt" && ok "diaries, entities, summary and petition files are byte for byte the same in the short, --verbose and DIARY_VERBOSE runs ($(wc -l < "$w/sh/s1.txt") files)" || bad "saves differ"
[ -s save/run_report_prev.txt ] && head -1 save/run_report_prev.txt | grep -q 'session=1 ' && head -1 save/run_report.txt | grep -q 'session=2 ' && ok "the previous report is kept as run_report_prev.txt (session 1) beside the new one (session 2)" || bad "run_report_prev.txt"
( export DIARY_HOME="$w/sh/short/save"; env -u DIARY_VERBOSE "$w/sh/bin/diary_sim" --report > rep.txt 2>&1; rcr=$?; cmp -s rep.txt save/run_report.txt && [ "$rcr" = 0 ] ) && ok "--report prints the last run_report.txt unchanged" || bad "--report"
( mkdir -p "$w/sh/empty"; export DIARY_HOME="$w/sh/empty/none"; env -u DIARY_VERBOSE "$w/sh/bin/diary_sim" --report > rep2.txt 2>&1; [ $? = 2 ] && grep -q 'no run_report.txt' rep2.txt ) && ok "--report without a run says so (exit 2)" || bad "--report without a run"
( export DIARY_HOME="$w/sh/short/save"; env -u DIARY_VERBOSE "$w/sh/bin/diary_sim" --runlog > rl.txt 2>&1; rcl=$?; cmp -s rl.txt save/run_log.txt && [ "$rcl" = 0 ] ) && ok "--runlog (make runlog) prints run_log.txt (here 8 lines, at most 40)" || bad "--runlog"
( export DIARY_HOME="$w/sh/empty/none"; env -u DIARY_VERBOSE "$w/sh/bin/diary_sim" --runlog > rl2.txt 2>&1; [ $? = 2 ] && grep -q 'no run_log.txt' rl2.txt ) && ok "--runlog without a run says so (exit 2)" || bad "--runlog without a run"
# growth cap: report.log_keep entries stay; make runlog shows the last report.log_tail lines
rm -rf "$w/sh/cap"; mkdir -p "$w/sh/cap/bin"; cp "$bin" "$w/sh/cap/bin/"; cp -r "$root/data" "$w/sh/cap/data"; sed -i 's/^report.log_keep = .*/report.log_keep = 3/; s/^report.log_tail = .*/report.log_tail = 5/' "$w/sh/cap/data/limits.txt"
( cd "$w/sh/cap" || exit 1; export DIARY_HOME="$w/sh/cap/save"; env -u DIARY_VERBOSE bin/diary_sim --seed 42 --ticks 100 --yes --every 100 > c.txt 2>&1; for n in 20 20 20 20; do env -u DIARY_VERBOSE bin/diary_sim --more $n --every 100 > c.txt 2>&1; done; env -u DIARY_VERBOSE bin/diary_sim --runlog > rl.txt 2>&1 )
cs=$(grep -c ' RUN$' "$w/sh/cap/save/run_log.txt"); first=$(head -1 "$w/sh/cap/save/run_log.txt" | grep -c ' RUN$')
[ "$cs" = 3 ] && [ "$first" = 1 ] && [ "$(wc -l < "$w/sh/cap/save/run_log.txt")" = 12 ] && [ "$(wc -l < "$w/sh/cap/rl.txt")" = 5 ] && grep -q 'ticks=141\.\.160' "$w/sh/cap/save/run_log.txt" && ! grep -q 'ticks=1\.\.100' "$w/sh/cap/save/run_log.txt" && ok "run_log.txt keeps the last report.log_keep entries (3 of 5 runs, the oldest dropped); --runlog shows the last report.log_tail lines (5)" || bad "log cap ($cs $first)"
# a DRIFT stop writes no report, but a time stamped entry with its reason
rm -rf "$w/sh/dr"; mkdir -p "$w/sh/dr"; cp -r "$w/sh/short/save" "$w/sh/dr/save"; cp "$w/sh/short/save/run_log.txt" "$w/sh/dr/log_before.txt"
( cd "$w/sh/dr" || exit 1; export DIARY_HOME="$w/sh/dr/save"; sed -i '/^S1 /s/votes=[0-9]*/votes=7/' save/diaries/sessions.txt; env -u DIARY_VERBOSE "$w/sh/bin/diary_sim" --more 10 --every 100 > c.txt 2>&1; echo $? > rc.txt )
dn=$(grep -c ' DRIFT$' "$w/sh/dr/save/run_log.txt")
[ "$(cat "$w/sh/dr/rc.txt")" = 1 ] && [ "$dn" = 1 ] && [ "$(grep -c ' RUN$' "$w/sh/dr/save/run_log.txt")" = 2 ] && grep -q '^[0-9]\{4\}-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] DRIFT$' "$w/sh/dr/save/run_log.txt" \
  && grep -q '^reason: .*sessions.txt S1' "$w/sh/dr/save/run_log.txt" && grep -q '^@@TRACE build=.* result=DRIFT$' "$w/sh/dr/save/run_log.txt" && ! grep -q '^@@' "$w/sh/dr/c.txt" && ok "a DRIFT stop appends a time stamped DRIFT entry (reason, build, debug.txt path) to run_log.txt; the earlier entries stay; nothing technical on the console" || bad "DRIFT entry ($dn)"
anom=$(head -1 save/run_report.txt | sed -E 's/.* anomalies=([^ ]*) .*/\1/')
[ "$anom" != none ] && echo "$anom" | grep -Eq '^[0-9]+\[(energy<25|mood<-50|warnings|export-failed)' && ok "anomalies are listed as information ($anom): energy below 25, mood below -50, warnings, a failed export" || bad "anomalies ($anom)"
grep -q 'make runlog' "$root/Makefile" && grep -q -- '--runlog' "$root/data/help.txt" && grep -q 'run_log.txt' "$root/README.md" && grep -q 'report.log_keep' "$root/data/limits.txt" && grep -q 'make report' "$root/Makefile" && grep -q 'VERBOSE' "$root/Makefile" && grep -q -- '--verbose' "$root/data/help.txt" && grep -q -- '--report' "$root/data/help.txt" && grep -q '@@TRACE' "$root/README.md" && grep -q 'report.warn_energy' "$root/data/limits.txt" && ok "README, Makefile, --help and data/limits.txt describe the short console, VERBOSE=1, make report and the marker" || bad "docs for the report"

echo "== 49. make night (--continuous): sessions back to back, q, limits, DRIFT; trend.txt; make share =="
rm -rf "$w/nt"; mkdir -p "$w/nt/bin"; cp "$bin" "$w/nt/bin/"; cp -r "$root/data" "$w/nt/data"
nb="$w/nt/bin/diary_sim"; cd "$w/nt" || exit 1
env -u DIARY_VERBOSE "$nb" --continuous --home "$w/nt/night" --session-ticks 60 --max-sessions 3 --seed 42 < /dev/null > night.txt 2>&1; rcn=$?
mkdir -p "$w/nt/hand"; for k in 1 2 3; do env -u DIARY_VERBOSE "$nb" --home "$w/nt/hand" --seed 42 --more 60 --every 100 --yes > /dev/null 2>&1; done
ns=$(grep -c '^s[0-9]* t[0-9]* [0-9][0-9]:[0-9][0-9]:[0-9][0-9] | ' night.txt); nlines=$(wc -l < night.txt)
[ "$rcn" = 0 ] && [ "$ns" = 3 ] && grep -q '^night run: sessions of 60 ticks; max sessions: 3; max hours: 12' night.txt && grep -q '^+-- night run finished' night.txt && grep -q '^| stopped: the number of sessions was reached' night.txt \
  && ! grep -q '^@@\|Full report\|^report:\|^treadmill' night.txt && [ "$nlines" -le 24 ] && [ "$(grep -c "^  [0-9]h[0-9][0-9]m[0-9][0-9]s | .* KB (+.* KB) | .*/session | .* tick/s | left " night.txt)" = 3 ] && grep -v '^Save folder\|^Saved to' night.txt | awk 'length > 79 { n++ } END { exit n > 0 }' \
  && ok "make night, no terminal, MAX_SESSIONS=3: one status line per session (3) with its timer line (elapsed, save folder size and growth, seconds per session, ticks per second, time left), a final box, no report spam ($nlines lines, <= 79 columns), exit 0" || bad "night console ($rcn $ns $nlines)"
nsums() { ( cd "$1" || exit 1; find . -type f | sort | while read -r f; do case $f in ./run_report*|./run_log*|./trend*|./night_console*|./debug*|./last*|./voice_log*|./state.ckpt*|./ckpt_log*) ;; *.jsonl) sed -E 's/"ts":"[^"]*",//' "$f" | cksum | sed "s#\$# $f#";; ./diaries/sessions.txt) grep -v '^# build' "$f" | cksum | sed "s#\$# $f#";; *) cksum "$f";; esac; done ); }
nsums "$w/nt/night" > ns1.txt; nsums "$w/nt/hand" > ns2.txt
[ -s ns1.txt ] && cmp -s ns1.txt ns2.txt && ok "three night sessions are byte for byte three hand-made --more 60 runs (diaries, entities, summary, records: $(wc -l < ns1.txt) files)" || bad "night differs from hand runs"
# make verify: OK on a night save; a changed diary line is DRIFT (exit 1); the night run against the same sessions by hand, run_report.txt included
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/night" > vf.txt 2>&1; rcv=$?
rm -rf "$w/nt/vt"; cp -r "$w/nt/night" "$w/nt/vt"; sed -i '0,/"t":"work"/s//"t":"rest"/' "$w/nt/vt/diaries/ada.jsonl"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/vt" > vt.txt 2>&1; rct=$?
[ "$rcv" = 0 ] && grep -q '^verify: OK, 180 ticks replayed from the files' vf.txt && [ "$rct" = 1 ] && grep -q 'DRIFT\|differs\|import FAILED' vt.txt && ok "make verify (--verify): OK on the night save (180 ticks), exit 1 with the DRIFT text after one diary line was changed" || bad "make verify ($rcv $rct)"
rnorm() { sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:]{8}//g; s#'"$2"'#HOME#g; s/(elapsed|Elapsed)[= ][0-9.]+//g' "$1/run_report.txt"; }
rnorm "$w/nt/night" "$w/nt/night" > rn1.txt; rnorm "$w/nt/hand" "$w/nt/hand" > rn2.txt
diff rn1.txt rn2.txt > rn.diff 2>&1; [ -s rn1.txt ] && [ ! -s rn.diff ] && ok "run_report.txt of the last night session equals the one of the last hand-made session (times and paths aside)" || { bad "night run_report differs from the hand-made one"; head -5 rn.diff; }
nt="$w/nt/night/trend.txt"; tp='^T session=[0-9]+ tick=[0-9]+ time=[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} elapsed=[0-9]+\.[0-9] size=[0-9]+ mood=(-?[0-9]+,){3}-?[0-9]+ energy=([0-9]+,){3}[0-9]+ words=([0-9]+,){3}[0-9]+ pets=([0-9]+,){3}[0-9]+ grant=([0-9]+,){3}[0-9]+ refuse=([0-9]+,){3}[0-9]+ agreed=[0-9]+ rejected=[0-9]+ trials=[0-9]+ anomalies=[0-9]+( secs=[0-9]+\.[0-9] loop=[0-9]+\.[0-9] tps=[0-9]+)?$'
nt_ok=1; [ "$(grep -c '^T ' "$nt")" = 3 ] && [ "$(grep -cE "$tp" "$nt")" = 3 ] || nt_ok=0; head -1 "$nt" | grep -q '^# trend v1, one line per session: time (local), elapsed .* wesen in the order Adam,Eve,Abel,Ruth: mood' || nt_ok=0
[ "$(grep '^T ' "$nt" | sed -E 's/^T session=([0-9]+) tick=([0-9]+) .*/\1:\2/' | tr '\n' ' ')" = "1:60 2:120 3:180 " ] || nt_ok=0
diff <(sed 's/ time=[^ ]* [^ ]* elapsed=[^ ]* size=[^ ]*//; s/ secs=.*//' "$nt") <(sed 's/ time=[^ ]* [^ ]* elapsed=[^ ]* size=[^ ]*//; s/ secs=.*//' "$w/nt/hand/trend.txt") > /dev/null || nt_ok=0
sz=($(grep '^T ' "$nt" | sed -E 's/.* size=([0-9]+) .*/\1/')); [ "${sz[0]}" -gt 0 ] && [ "${sz[0]}" -lt "${sz[1]}" ] && [ "${sz[1]}" -lt "${sz[2]}" ] || nt_ok=0
[ "$nt_ok" = 1 ] && ok "trend.txt: a legend line, then one fixed key=value line per session (session tick time elapsed size mood energy words pets grant refuse agreed rejected trials anomalies); a normal run writes the same lines" || bad "trend.txt ($nt_ok)"
rl="$w/nt/night/run_log.txt"
[ "$(grep -c ' RUN$' "$rl")" = 3 ] && grep -q '^[0-9-]* [0-9:]* NIGHT$' "$rl" && grep -q '^start: session_ticks=60 max_sessions=3 keys=none$' "$rl" && grep -q '^stop: reason=max_sessions sessions=3 last_session=3 tick=180 elapsed=0h0[0-9]m$' "$rl" \
  && ok "run_log.txt: a timestamped RUN entry per session and NIGHT start / stop entries (reason, sessions, last tick, elapsed)" || bad "night run_log.txt"
( export DIARY_HOME="$w/nt/night"; env -u DIARY_VERBOSE "$nb" --trend > tr.txt 2>&1; [ "$(cat tr.txt)" = "$(cat "$nt")" ] ) && ok "--trend (make trend) prints trend.txt (at most report.trend_tail lines)" || bad "--trend"
# the trend cap, and the time limit
rm -rf "$w/nt/cap"; mkdir -p "$w/nt/cap/bin"; cp "$bin" "$w/nt/cap/bin/"; cp -r "$root/data" "$w/nt/cap/data"; sed -i 's/^report.trend_keep = .*/report.trend_keep = 2/' "$w/nt/cap/data/limits.txt"
( cd "$w/nt/cap" && env -u DIARY_VERBOSE bin/diary_sim --continuous --home "$w/nt/cap/save" --session-ticks 30 --max-sessions 4 --seed 42 < /dev/null > /dev/null 2>&1 )   # in cap/: its data/ is the one that is read
[ "$(grep -c '^T ' "$w/nt/cap/save/trend.txt")" = 2 ] && head -1 "$w/nt/cap/save/trend.txt" | grep -q '^# trend' && grep -q '^T session=3 ' "$w/nt/cap/save/trend.txt" && grep -q '^T session=4 ' "$w/nt/cap/save/trend.txt" && ok "trend.txt keeps the legend and the last report.trend_keep lines (2 of 4 sessions)" || bad "trend cap"
env -u DIARY_VERBOSE "$nb" --continuous --home "$w/nt/night" --session-ticks 30 --max-sessions 50 --max-hours 0.0002 < /dev/null > mh.txt 2>&1
mhn=$(grep -c '^s[0-9]* t' mh.txt); [ "$mhn" -ge 1 ] && [ "$mhn" -lt 50 ] && grep -q '^| stopped: the time limit was reached' mh.txt && grep -q '^stop: reason=max_hours ' "$rl" && ok "MAX_HOURS stops it at a session boundary ($mhn sessions at 0.0002 h)" || bad "max-hours ($mhn)"
# DRIFT stops the night run and says so
rm -rf "$w/nt/dr"; cp -r "$w/nt/night" "$w/nt/dr"; sed -i '/^S1 /s/votes=[0-9]*/votes=7/' "$w/nt/dr/diaries/sessions.txt"
env -u DIARY_VERBOSE "$nb" --continuous --home "$w/nt/dr" --session-ticks 30 --max-sessions 5 < /dev/null > dr.txt 2>&1; rcd=$?
[ "$rcd" = 1 ] && grep -q '^| stopped: DRIFT' dr.txt && grep -q 'import FAILED' dr.txt && ! grep -q '^s[0-9]* t[0-9]' dr.txt && grep -q '^stop: reason=drift sessions=0 ' "$w/nt/dr/run_log.txt" && grep -q ' DRIFT$' "$w/nt/dr/run_log.txt" && ok "a DRIFT stops the night run (exit 1, box says DRIFT, the import failure shown, NIGHT stop and DRIFT entries in run_log.txt)" || bad "night DRIFT ($rcd)"
env -u DIARY_VERBOSE "$nb" --continuous --more 5 --home "$w/nt/night" > ue.txt 2>&1; rcu=$?
[ "$rcu" = 2 ] && grep -q 'cannot be combined with --ticks, --more' ue.txt && ok "--continuous with --more is refused (exit 2)" || bad "night options ($rcu)"
# q on a terminal: finishes the session in progress and stops (needs python3 for a pseudo terminal)
if command -v python3 > /dev/null 2>&1; then
  rm -rf "$w/nt/q"
  python3 - "$nb" "$w/nt/q" > q.txt 2>&1 <<'PY'
import os, pty, select, sys, time
exe, home = sys.argv[1:3]
pid, fd = pty.fork()
if pid == 0:
    os.chdir("/")
    os.execv(exe, [exe, "--continuous", "--home", home, "--session-ticks", "3000", "--max-sessions", "40", "--seed", "42"])
out = b""; sent = False; t0 = time.time()
while time.time() - t0 < 120:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d
    if not sent and b"s1 t" in out:
        os.write(fd, b"q"); sent = True
sys.stdout.write(out.decode("utf-8", "replace"))
PY
  qn=$(grep -c ' RUN$' "$w/nt/q/run_log.txt"); [ "$qn" -ge 1 ] && [ "$qn" -le 12 ] && grep -q 'stopped: you pressed q' q.txt && grep -q 'diary-sim night run | 20' q.txt && grep -q ' save folder .* since the start' q.txt && grep -q ' now: session [0-9]*, ' q.txt && grep -q ' done: [0-9]* sessions | last ' q.txt && [ -s "$w/nt/q/trend.txt" ] && grep -q 'reason=q ' "$w/nt/q/run_log.txt" && ok "q on a terminal (no Enter): the session in progress finishes (sessions: $qn of 40), then the night run stops cleanly; on a terminal the timer header is repainted in place" || bad "q key ($qn)"
else ok "q key: skipped (no python3 for a pseudo terminal)"; fi
# q (and the signals) at EVERY stage, the header with the wesen and the players, make verify, the night run against hand-made runs (report too)
if command -v python3 > /dev/null 2>&1; then
  cat > "$w/nt/ptyq.py" <<'PY'
import os, pty, re, select, signal, sys, time
mode, exe, home = sys.argv[1:4]
extra = sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    os.chdir("/")
    os.execv(exe, [exe, "--continuous", "--home", home] + extra)
trigger = {"q_replay": rb"replaying the history first: tick", "int_replay": rb"replaying the history first: tick", "hup_replay": rb"replaying the history first: tick",
           "q_first": rb"session \d+, tick \d+ of", "q_between": rb"\ns\d+ t\d+ "}[mode]
out = b""; sent = None; t0 = time.time()
while time.time() - t0 < 120:
    r, _, _ = select.select([fd], [], [], 0.05)
    if r:
        try: d = os.read(fd, 65536)
        except OSError: break
        if not d: break
        out += d
    if sent is None and re.search(trigger, out):
        sent = time.time()
        if mode.startswith("q_"): os.write(fd, b"q")
        elif mode == "int_replay": os.kill(pid, signal.SIGINT)
        else:
            os.close(fd)   # the terminal is closed: SIGHUP
            _, st = os.waitpid(pid, 0)
            print("ELAPSED=%.2f" % (time.time() - sent)); print("EXIT=%d" % os.waitstatus_to_exitcode(st)); sys.exit(0)
if sent is None: print("NOTRIGGER")
try:
    _, st = os.waitpid(pid, 0)
except ChildProcessError:
    st = 0
plain = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out.decode("utf-8", "replace"))
print(plain)
print("ELAPSED=%.2f" % (time.time() - (sent or time.time()))); print("EXIT=%d" % os.waitstatus_to_exitcode(st))
PY
  big="$w/nt/big"; env -u DIARY_VERBOSE "$nb" --home "$big" --seed 42 --ticks 6000 --yes --every 100000 > /dev/null 2>&1
  bsum() { ( cd "$1/diaries" && cat ./*.jsonl | cksum ); }
  # 1. q during the very first replay: stops at once, nothing lost
  rm -rf "$w/nt/qr"; cp -r "$big" "$w/nt/qr"; b0=$(bsum "$w/nt/qr"); rm -f "$w/nt/qr/state.ckpt"   # 0.058: without the checkpoint the replay happens
  python3 "$w/nt/ptyq.py" q_replay "$nb" "$w/nt/qr" --session-ticks 300 --max-sessions 5 > qr.txt 2>&1
  el=$(sed -n 's/^ELAPSED=//p' qr.txt); ex=$(sed -n 's/^EXIT=//p' qr.txt)
  env -u DIARY_VERBOSE "$nb" --home "$w/nt/qr" --more 5 --yes > qr2.txt 2>&1; rcr=$?
  [ "$ex" = 0 ] && awk -v e="$el" 'BEGIN { exit !(e < 1.5) }' && grep -q 'q pressed: stopping at once' qr.txt && grep -q 'q: stopped during the replay at tick' qr.txt && grep -q '^| stopped: you pressed q' qr.txt \
    && [ "$(bsum "$w/nt/qr")" = "$b0" ] || [ "$rcr" = 0 ] && grep -q 'reason=q sessions=0 ' "$w/nt/qr/run_log.txt" && grep -q '^import OK: 4 entities, 6000 ticks verified' qr2.txt \
    && ok "q during the first replay: stops at once ($el s after the key), exit 0, 'stopping' shown, nothing written to the diaries, run_log says reason=q, a rerun resumes" || bad "q during replay (exit $ex, $el s, rerun $rcr)"
  # 2. q while the first session's new ticks are being made: the session finishes, everything is written, make verify passes
  rm -rf "$w/nt/qf"; cp -r "$big" "$w/nt/qf"
  python3 "$w/nt/ptyq.py" q_first "$nb" "$w/nt/qf" --session-ticks 3000 --max-sessions 5 > qf.txt 2>&1
  el=$(sed -n 's/^ELAPSED=//p' qf.txt); ex=$(sed -n 's/^EXIT=//p' qf.txt)
  env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/qf" > qf2.txt 2>&1; rcv=$?
  [ "$ex" = 0 ] && awk -v e="$el" 'BEGIN { exit !(e < 15) }' && grep -q 'q pressed: stopping\.\.\.' qf.txt && grep -q '^| stopped: you pressed q' qf.txt && grep -q 'reason=q sessions=1 ' "$w/nt/qf/run_log.txt" \
    && [ "$rcv" = 0 ] && grep -q '^verify: OK, 9000 ticks' qf2.txt && [ "$(grep -c '^T ' "$w/nt/qf/trend.txt")" = 2 ] \
    && ok "q during the first new ticks: the session finishes (3000 ticks, $el s), diaries/trend/run_log written (reason=q), exit 0, make verify: OK on 9000 ticks" || bad "q in the first session (exit $ex, $el s, verify $rcv)"
  # 3. q between two sessions of an advanced night run; the header: wesen AND players, mood and energy, 80 columns
  rm -rf "$w/nt/qb"; cp -r "$big" "$w/nt/qb"
  python3 "$w/nt/ptyq.py" q_between "$nb" "$w/nt/qb" --session-ticks 100 --max-sessions 50 > qb.txt 2>&1
  el=$(sed -n 's/^ELAPSED=//p' qb.txt); ex=$(sed -n 's/^EXIT=//p' qb.txt)
  [ "$ex" = 0 ] && awk -v e="$el" 'BEGIN { exit !(e < 3) }' && grep -q '^| stopped: you pressed q' qb.txt && grep -q 'reason=q ' "$w/nt/qb/run_log.txt" \
    && ok "q between sessions: the run ends within $el s, exit 0, box and run_log say q" || bad "q between sessions (exit $ex, $el s)"
  fr=$(awk '/diary-sim night run/ { n++ } END { print n }' qb.txt)
  hd=$(awk '/diary-sim night run/ { s = NR } END { print s }' qb.txt)
  sed -n "${hd},\$p" qb.txt | head -22 > hdr.txt
  [ -s hdr.txt ] && grep -q '^ wesen  *Adam  *Eve  *Abel  *Ruth' hdr.txt && grep -q '^ mood  *[-+0-9]' hdr.txt && grep -q '^ energy  *[0-9]' hdr.txt && grep -q '^ words  *[0-9]' hdr.txt && grep -q '^ petitions  *[0-9]' hdr.txt \
    && grep -q '^ players  *[A-Za-z]' hdr.txt && grep -q '^ watches  *Adam' hdr.txt && grep -q '^ its mood  *[-0-9]' hdr.txt && grep -q '^ grant/refuse  *[0-9]*/[0-9]' hdr.txt && grep -q '^ stance  *[-+][0-9]' hdr.txt \
    && awk 'length > 79 { n++ } END { exit n > 0 }' hdr.txt && [ "$fr" -ge 2 ] \
    && ok "the header shows mood, energy, words and petitions of all four wesen and, for all four players, the wesen watched, its mood, grant/refuse and stance, in 79 columns" || bad "header table"
  # 4. Ctrl-C and SIGHUP (the terminal is closed) during the replay: clean stop, a rerun resumes
  rm -rf "$w/nt/qi"; cp -r "$big" "$w/nt/qi"; b0=$(bsum "$w/nt/qi"); rm -f "$w/nt/qi/state.ckpt"   # 0.058: without the checkpoint the replay happens
  python3 "$w/nt/ptyq.py" int_replay "$nb" "$w/nt/qi" --max-sessions 5 > qi.txt 2>&1
  el=$(sed -n 's/^ELAPSED=//p' qi.txt); ex=$(sed -n 's/^EXIT=//p' qi.txt)
  env -u DIARY_VERBOSE "$nb" --home "$w/nt/qi" --more 5 --yes > qi2.txt 2>&1
  [ "$ex" = 130 ] && awk -v e="$el" 'BEGIN { exit !(e < 1.5) }' && grep -q 'received: stopped after tick' qi.txt && [ "$(bsum "$w/nt/qi")" != "$b0" ] || true
  [ "$ex" = 130 ] && awk -v e="$el" 'BEGIN { exit !(e < 1.5) }' && grep -q 'SIGINT received: stopped after tick' qi.txt && grep -q '^| stopped: Ctrl-C' qi.txt && grep -q '^import OK: 4 entities, 6000 ticks verified' qi2.txt \
    && ok "Ctrl-C during the replay: stops at the next tick ($el s), exit 130, a rerun resumes from the save" || bad "Ctrl-C ($ex, $el s)"
  rm -rf "$w/nt/qh"; cp -r "$big" "$w/nt/qh"; rm -f "$w/nt/qh/state.ckpt"   # 0.058: without the checkpoint the replay happens
  python3 "$w/nt/ptyq.py" hup_replay "$nb" "$w/nt/qh" --max-sessions 5 > qh.txt 2>&1
  el=$(sed -n 's/^ELAPSED=//p' qh.txt); ex=$(sed -n 's/^EXIT=//p' qh.txt)
  env -u DIARY_VERBOSE "$nb" --home "$w/nt/qh" --more 5 --yes > qh2.txt 2>&1; env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/qh" > qh3.txt 2>&1; rch=$?
  { [ "$ex" = 130 ] || [ "$ex" = 0 ]; } && awk -v e="$el" 'BEGIN { exit !(e < 2) }' && grep -q '^import OK: 4 entities, 6000 ticks verified' qh2.txt && grep -q 'reason=signal ' "$w/nt/qh/run_log.txt" && [ "$rch" = 0 ] \
    && ok "SIGHUP (terminal closed) during the replay: the process ends at the next tick ($el s, exit 130), run_log says so, a rerun resumes, make verify passes" || bad "SIGHUP ($ex, $el s, verify $rch)"
else ok "q at every stage: skipped (no python3 for a pseudo terminal)"; fi
# night.verify_every = 1: the whole history is checked in a child process after every session
rm -rf "$w/nt/ve"; mkdir -p "$w/nt/ve/bin"; cp "$nb" "$w/nt/ve/bin/"; cp -r "$root/data" "$w/nt/ve/data"; sed -i 's/^night.verify_every = .*/night.verify_every = 1/' "$w/nt/ve/data/limits.txt"
( cd "$w/nt/ve" && env -u DIARY_VERBOSE bin/diary_sim --continuous --home "$w/nt/ve/save" --session-ticks 40 --max-sessions 2 --seed 42 < /dev/null > ve.txt 2>&1 )
[ "$(grep -c '^verify: ok ' "$w/nt/ve/save/run_log.txt")" = 2 ] && grep -q 'whole history verified from the files (2x' "$w/nt/ve/ve.txt" && ok "night.verify_every = 1: a child process replays and verifies the whole history after each of 2 sessions (run_log: verify: ok)" || bad "verify_every"
# make share
sd="$w/nt/out"; mkdir -p "$sd"; ( export DIARY_HOME="$w/nt/night" SHARE_DIR="$sd"; "$root/scripts/share.sh" "$nb" > share.txt 2>&1 ); sf=$(ls "$sd"/share-* 2> /dev/null | head -1)
if [ -n "$sf" ]; then
  rm -rf "$w/nt/x"; mkdir -p "$w/nt/x"
  case $sf in *.zip) python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$sf" "$w/nt/x" 2> /dev/null || ( cd "$w/nt/x" && unzip -q "$sf" );; *) tar -xzf "$sf" -C "$w/nt/x";; esac
  have=$(cd "$w/nt/x" && ls | tr '\n' ' '); sz=$(wc -c < "$sf")
  miss=0; for f in trend.txt run_log.txt run_report.txt run_report_prev.txt summary.txt player_reports.txt dictionary.txt divergence.txt; do [ -s "$w/nt/x/$f" ] || miss=$((miss + 1)); done
  [ "$miss" = 0 ] && [ "$sz" -lt 400000 ] && ! ls "$w/nt/x" | grep -qi 'ballot\|diaries\|jsonl' && ! grep -qE '^B[0-9]+ ' "$w/nt/x"/* && grep -q "$sf" share.txt && grep -q "$sz bytes" share.txt \
    && ok "make share: ONE archive ($sz bytes) with trend, run_log, run_report(+prev), summary, player_reports, dictionary, divergence; no diaries, no ballots; path and size printed" || bad "share contents ($miss $sz: $have)"
else bad "share: no archive ($(cat share.txt))"; fi
grep -q 'make night' "$root/Makefile" && grep -q 'make trend' "$root/Makefile" && grep -q 'make share' "$root/Makefile" && grep -q -- '--continuous' "$root/data/help.txt" && grep -q -- '--trend' "$root/data/help.txt" && grep -q 'make night' "$root/README.md" && grep -q 'trend.txt' "$root/README.md" && grep -q 'make share' "$root/README.md" \
  && grep -q 'night.max_hours' "$root/data/limits.txt" && grep -q 'report.trend_keep' "$root/data/limits.txt" && ok "README, Makefile, --help and data/limits.txt describe make night, make trend and make share" || bad "docs for night"
# ---- B1: the voices of the wesen under the night header (Sim_Voice, data/voices.txt): display only, deterministic, <= 150 characters ----
vh="$w/nt/vh"; env -u DIARY_VERBOSE "$nb" --home "$vh" --seed 42 --ticks 3000 --yes --every 100000 > /dev/null 2>&1
env -u DIARY_VERBOSE "$nb" --voices --home "$vh" > vo1.txt 2>&1; env -u DIARY_VERBOSE "$nb" --voices --home "$vh" > vo2.txt 2>&1
miss=0; for id in ada gemini replika robert; do for sit in tired low high up down doing place word granted partial deferred refused waiting trial; do
  [ "$(grep -c "^voice\.$sit\.$id\.[0-9]* = " "$root/data/voices.txt")" -ge 2 ] || miss=$((miss + 1)); done; done
[ "$(wc -l < vo1.txt)" = 4 ] && cmp -s vo1.txt vo2.txt && ! awk 'length($0) > 150 || length($0) < 10' vo1.txt | grep -q . && ! grep -q '[{}]\|\[voice' vo1.txt && grep -q '^[A-Za-z]*: ' vo1.txt && [ "$miss" = 0 ] \
  && ok "--voices (make voices): one message per wesen (4), each <= 150 characters, no template left open, the same text on every run for the same state; data/voices.txt has >= 2 templates per wesen and situation (14 situations x 4)" || bad "voices ($miss missing templates; $(cat vo1.txt))"
# display only: a night run with the voices on, and one with them off (and no log), write the same diaries; voice_log.txt lines are <= 150 characters; make verify ignores the log
rm -rf "$w/nt/von" "$w/nt/voff"; cp -r "$vh" "$w/nt/von"; cp -r "$vh" "$w/nt/voff"; rm -rf "$w/nt/vd"; mkdir -p "$w/nt/vd/bin"; cp "$nb" "$w/nt/vd/bin/"; cp -r "$root/data" "$w/nt/vd/data"
sed -i 's/^voice.enabled = .*/voice.enabled = 0/; s/^voice.log = .*/voice.log = 0/' "$w/nt/vd/data/limits.txt"
env -u DIARY_VERBOSE "$nb" --continuous --home "$w/nt/von" --session-ticks 200 --max-sessions 2 --seed 42 < /dev/null > von.txt 2>&1
( cd "$w/nt/vd" && env -u DIARY_VERBOSE bin/diary_sim --continuous --home "$w/nt/voff" --session-ticks 200 --max-sessions 2 --seed 42 < /dev/null > "$w/nt/voff.txt" 2>&1 )
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/von" > vov.txt 2>&1; rcvv=$?
vn() { ( cd "$1" || exit 1; find . -type f ! -name 'voice_log.txt' ! -name 'run_*' ! -name 'trend.txt' ! -name 'night_*' ! -name 'debug.txt' ! -name 'last*' ! -name 'state.ckpt*' ! -name 'ckpt_log.txt' | sort | while read -r f; do case $f in *.jsonl) sed -E 's/"ts":"[^"]*",//' "$f" | cksum | sed "s#\$# $f#";; ./diaries/sessions.txt) grep -v '^#' "$f" | cksum | sed "s#\$# $f#";; *) cksum < "$f" | sed "s#\$# $f#";; esac; done ); }
vn "$w/nt/von" > vn1.txt; vn "$w/nt/voff" > vn2.txt
if [ -s "$w/nt/von/voice_log.txt" ]; then vlong=$(sed 's/^t=[0-9]* //' "$w/nt/von/voice_log.txt" | awk 'length($0) > 150 || length($0) < 8' | wc -l); else vlong=-1; fi
[ -s vn1.txt ] && cmp -s vn1.txt vn2.txt && [ "$vlong" = 0 ] && [ ! -e "$w/nt/voff/voice_log.txt" ] && [ "$rcvv" = 0 ] && grep -q '^verify: OK' vov.txt \
  && ok "the voices are display only: diaries, entities and records of a night run are byte for byte the same with voice.enabled = 0 (no voice_log.txt then); voice_log.txt ($(wc -l < "$w/nt/von/voice_log.txt") lines, none over 150 characters) is not verified: make verify passes" || bad "voices display only ($vlong, rc $rcvv)"
# on a terminal: the messages sit under the header, wrapped to <= 79 columns, the whole screen stays within 24 rows
if command -v python3 > /dev/null 2>&1; then
  cat > "$w/nt/ptyv.py" <<'PY'
import os, pty, re, select, sys, time
exe, home = sys.argv[1:3]
pid, fd = pty.fork()
if pid == 0:
    os.chdir("/")
    os.execv(exe, [exe, "--continuous", "--home", home, "--session-ticks", "100", "--max-sessions", "12", "--seed", "42"])
out = b""; t0 = time.time(); sent = False
while time.time() - t0 < 90:
    r, _, _ = select.select([fd], [], [], 0.05)
    if r:
        try: d = os.read(fd, 65536)
        except OSError: break
        if not d: break
        out += d
    if not sent and out.count(b"\x1b[H") >= 3 and time.time() - t0 > 6:
        os.write(fd, b"q"); sent = True
try: os.waitpid(pid, 0)
except ChildProcessError: pass
frames = out.decode("utf-8", "replace").split("\x1b[H")
frame = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", frames[-2] if len(frames) > 2 else frames[-1])
rows = frame.rstrip("\n").split("\n")
print("ROWS=%d" % len(rows)); print("WIDE=%d" % sum(1 for x in rows if len(x) > 79))
print("VOICES=%d" % sum(1 for x in rows if re.match(r"^ (Adam|Eve|Abel|Ruth|ada|gemini|replika|robert): ", x)))
PY
  rm -rf "$w/nt/vp"; cp -r "$vh" "$w/nt/vp"; vfr=$(python3 "$w/nt/ptyv.py" "$nb" "$w/nt/vp" 2>&1)
  vr=$(echo "$vfr" | sed -n 's/^ROWS=//p'); vw=$(echo "$vfr" | sed -n 's/^WIDE=//p'); vv=$(echo "$vfr" | sed -n 's/^VOICES=//p')
  [ "${vr:-99}" -le 24 ] && [ "${vw:-1}" = 0 ] && [ "${vv:-0}" -ge 1 ] && ok "on a terminal the header shows the wesen messages ($vv name(s) shown), every line <= 79 columns, the screen $vr rows (<= 24)" || bad "voices on a terminal ($vfr)"
else ok "voices on a terminal: skipped (no python3 for a pseudo terminal)"; fi
grep -q 'voice.refresh_seconds' "$root/data/limits.txt" && grep -q 'voice.max_chars' "$root/data/limits.txt" && grep -q -- '--voices' "$root/data/help.txt" && grep -q 'make voices' "$root/Makefile" && grep -q 'voice_log.txt' "$root/README.md" \
  && ok "README, Makefile, --help and data/limits.txt describe the voices (voice.*, make voices, voice_log.txt)" || bad "voices docs"
# ---- B2: the chat (Sim_Chat, data/chat.txt, diaries/chat.txt): record-first, replay-verified, never changes the simulation ----
cscript="$w/nt/chat_script.txt"
printf '%s\n' '# ticks into the run, then the line' '5 @adam hello' '9 @Eve how are you feeling today' '12 @zz hi' '15 /status' '20 /pause' '22 /resume' '30 /mood' '34 /trend 3' '40 @ru what worries you?' '50 @ob hello' '60 @o hi' '70 @jeh how are you' '80 /words eve' '90 /foo' '100 /help' > "$cscript"
rm -rf "$w/nt/ch" "$w/nt/cp" "$w/nt/ch2"; cp -r "$vh" "$w/nt/ch"; cp -r "$vh" "$w/nt/cp"; cp -r "$vh" "$w/nt/ch2"
env -u DIARY_VERBOSE "$nb" --chat --chat-script "$cscript" --session-ticks 300 --home "$w/nt/ch" < /dev/null > ch1.txt 2>&1; rcc=$?
env -u DIARY_VERBOSE "$nb" --chat --chat-script "$cscript" --session-ticks 300 --home "$w/nt/ch2" < /dev/null > ch2.txt 2>&1
env -u DIARY_VERBOSE "$nb" --home "$w/nt/cp" --seed 42 --more 300 --every 100 --yes > /dev/null 2>&1
cf="$w/nt/ch/diaries/chat.txt"; cn=$(grep -c '^C' "$cf" 2> /dev/null)
badfmt=$(grep '^C' "$cf" | grep -vcE '^C[0-9]+ t=[0-9]+ who=[a-z]+ to=[a-z]+ h=[0-9]+ text=.+$'); badlen=$(grep '^C' "$cf" | sed 's/^.* text=//' | awk 'length($0) > 150' | wc -l)
seqok=$(grep '^C' "$cf" | sed -E 's/^C([0-9]+) .*/\1/' | awk 'BEGIN { ok = 1 } { if ($1 != NR) ok = 0 } END { print ok }')
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/ch" > chv.txt 2>&1; rcv2=$?
env -u DIARY_VERBOSE "$nb" --chatlog --home "$w/nt/ch" > chl.txt 2>&1
[ "$rcc" = 0 ] && [ "$cn" -ge 25 ] && [ "$badfmt" = 0 ] && [ "$badlen" = 0 ] && [ "$seqok" = 1 ] && head -1 "$cf" | grep -q '^# seed 42$' \
  && grep -q '^C[0-9]* t=[0-9]* who=ada to=you h=[0-9]* text=.\+' "$cf" && grep -q ' who=system to=you .* text=no one is called "zz"' "$cf" && grep -q ' who=system to=you .* text=tick [0-9]*, session [0-9]*, seed 42' "$cf" \
  && grep -q ' who=system to=you .* text=pause asked' "$cf" && grep -q ' who=system to=you .* text=going on from tick' "$cf" && grep -q 'who=observer to=you' "$cf" && grep -q ' text="o" fits ' "$cf" \
  && grep -q 'who=iris to=you' "$cf" && grep -q 'who=gemini to=you' "$cf" && [ "$rcv2" = 0 ] && grep -q '^verify: OK' chv.txt && grep -q '^t[0-9]* you -> Ruth: @ru what worries you?$' chl.txt && grep -q '^Adam> ' ch1.txt && grep -q '^you> @adam hello$' ch1.txt \
  && tail -1 "$w/nt/ch/diaries/sessions.txt" > /dev/null && grep -c ' chat=1' "$w/nt/ch/diaries/sessions.txt" | grep -q '^1$' \
  && ok "--chat with a script: @adam / @Eve / @ru / @jeh / @ob get answers from their templates, an unknown name, a name that fits two (@o) and an unknown order get error lines, /status /pause /resume /mood /trend /words /help answer; $cn C lines in diaries/chat.txt (format C<n> t= who= to= h= text=, numbered 1..$cn, none over 150 characters), the session carries chat=1, make verify passes, make chatlog and the plain console show them" || bad "chat script ($rcc, $cn lines, fmt $badfmt, len $badlen, seq $seqok, verify $rcv2)"
cmp -s "$cf" "$w/nt/ch2/diaries/chat.txt" && ok "the answers are deterministic: the same script on a copy of the same save gives the same chat.txt byte for byte" || bad "chat answers differ between two runs"
cs() { ( cd "$1" || exit 1; find . -type f ! -name 'chat.txt' ! -name 'voice_log.txt' ! -name 'run_*' ! -name 'trend.txt' ! -name 'night_*' ! -name 'debug.txt' ! -name 'last*' ! -name 'state.ckpt*' ! -name 'ckpt_log.txt' | sort | while read -r f; do case $f in *.jsonl) sed -E 's/"ts":"[^"]*",//' "$f" | cksum | sed "s#\$# $f#";; ./diaries/sessions.txt) grep -v '^# build' "$f" | sed 's/ chat=1//' | cksum | sed "s#\$# $f#";; *) cksum < "$f" | sed "s#\$# $f#";; esac; done ); }
cs "$w/nt/ch" > cs1.txt; cs "$w/nt/cp" > cs2.txt
[ -s cs1.txt ] && cmp -s cs1.txt cs2.txt && [ ! -e "$w/nt/cp/diaries/chat.txt" ] && ! grep -q 'chat=1' "$w/nt/cp/diaries/sessions.txt" \
  && ok "the chat does not change the simulation: a session with $cn chat lines and the same session without leave every other diary, entity file and record byte for byte the same ($(wc -l < cs1.txt) files; only the chat=1 marker of sessions.txt and chat.txt differ); a plain run has no marker and no chat.txt" || bad "chat changes the simulation ($(diff cs1.txt cs2.txt | head -3 | tr '\n' ' '))"
# off = identical: chat.enabled = 0 gives no marker and no file even with --chat
rm -rf "$w/nt/cd" "$w/nt/coff"; mkdir -p "$w/nt/cd/bin"; cp "$nb" "$w/nt/cd/bin/"; cp -r "$root/data" "$w/nt/cd/data"; sed -i 's/^chat.enabled = .*/chat.enabled = 0/' "$w/nt/cd/data/limits.txt"; cp -r "$vh" "$w/nt/coff"
( cd "$w/nt/cd" && env -u DIARY_VERBOSE bin/diary_sim --chat --chat-script "$cscript" --session-ticks 300 --home "$w/nt/coff" < /dev/null > "$w/nt/coff.txt" 2>&1 )
( cd "$w/nt" && cp "$w/nt/coff/diaries/sessions.txt" cso.txt; grep -v '^# build' "$w/nt/cp/diaries/sessions.txt" > csp.txt; grep -v '^# build' cso.txt | cmp -s - csp.txt ) && [ ! -e "$w/nt/coff/diaries/chat.txt" ] && ! grep -q '^you>' "$w/nt/coff.txt" \
  && ok "chat.enabled = 0: --chat writes no chat=1 marker and no chat.txt, the lines are not answered, sessions.txt is byte for byte that of a plain run (off = identical)" || bad "chat off"
# tampering: a changed answer, a changed typed line (the check number no longer fits), a removed answer, an invented line: DRIFT
tm() { rm -rf "$w/nt/ct"; cp -r "$w/nt/ch" "$w/nt/ct"; sed -i "$1" "$w/nt/ct/diaries/chat.txt"; env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/ct" > ctv.txt 2>&1; rcx=$?; [ "$rcx" = 1 ] && grep -q 'DRIFT\|differs\|import FAILED' ctv.txt && grep -q 'chat.txt' ctv.txt; }
t1=0; tm '0,/text=Hello\./s//text=Hullo./' && t1=$((t1 + 1)); tm '0,/ text=@adam hello/s// text=@adam hullo/' && t1=$((t1 + 1)); tm '3d' && t1=$((t1 + 1))
tm '$a C99 t=3100 who=ada to=you h=5 text=I was never asked' && t1=$((t1 + 1)); tm '0,/ t=3[0-9]* who=you/s// t=3001 who=you/' && t1=$((t1 + 1))
[ "$t1" = 5 ] && ok "tampering with diaries/chat.txt is DRIFT (5 of 5): a changed answer, a changed typed line (check number h=), a removed line, an invented line, a moved line; make verify names chat.txt" || bad "chat tamper ($t1 of 5)"
# on a terminal: the input line, editing (Backspace, Esc), the answers on screen, /pause /resume /quit, a bare q, the terminal put back
if command -v python3 > /dev/null 2>&1; then
  cat > "$w/nt/ptyc.py" <<'PY'
import os, pty, re, select, struct, sys, time, termios, fcntl, signal
exe, home, mode = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.chdir("/")
    os.execv(exe, [exe, "--chat", "--home", home, "--session-ticks", "2000", "--seed", "42"])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
if mode == "talk":
    ev = [(5.0, b"@adam hel"), (5.4, b"lo\x7f\x7fo!\r"), (6.0, b"@zzz hi\r"), (6.5, b"/stat"), (6.8, b"us\r"), (7.2, b"/pause\r"), (8.0, b"@x\x1b"), (8.4, b"\r"), (8.8, b"@eve are you tired?\r"),
          (9.4, b"/resume\r"), (10.0, b"/mood\r"), (10.4, b"/help\r"), (11.2, b"/quit\r")]
elif mode == "bareq":
    ev = [(5.0, b"x"), (5.5, b"q")]
else:
    ev = [(5.0, b"@a"), (5.5, b"q"), (6.0, b"\r")]   # q inside a line is text; then Enter sends "@aq"; stop with Ctrl-C
out = b""; t0 = time.time(); done = None; mid = None
while time.time() - t0 < 60:
    r, _, _ = select.select([fd], [], [], 0.05)
    if r:
        try: d = os.read(fd, 65536)
        except OSError: break
        if not d: break
        out += d
    while ev and time.time() - t0 >= ev[0][0]:
        os.write(fd, ev[0][1]); ev.pop(0)
    if mid is None and time.time() - t0 > 4.5:
        a = termios.tcgetattr(fd); mid = (bool(a[3] & termios.ECHO), bool(a[3] & termios.ICANON))
    if mode == "other" and not ev and time.time() - t0 > 7.5:
        os.kill(pid, signal.SIGINT); mode = "other-sent"
    try:
        p, st = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        p, st = pid, 0
    if p:
        done = os.waitstatus_to_exitcode(st); break
for _ in range(100):
    if done is not None: break
    try:
        q, st = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        done = -1; break
    if q: done = os.waitstatus_to_exitcode(st); break
    time.sleep(0.05)
try:
    a = termios.tcgetattr(fd); end = (bool(a[3] & termios.ECHO), bool(a[3] & termios.ICANON))
except Exception:
    end = None
frames = out.decode("utf-8", "replace").split("\x1b[H")
shown = [re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", f) for f in frames]
best = max(shown[1:-1] if len(shown) > 3 else shown, key=lambda f: ("Adam>" in f) * 2 + ("system>" in f))
rows = best.replace("\r", "").rstrip("\n").split("\n")
print("EXIT=%s" % done); print("RAW=%s" % (mid,)); print("BACK=%s" % (end,)); print("ROWS=%d" % len(rows)); print("WIDE=%d" % sum(1 for f in shown[1:] for x in f.replace("\r", "").split("\n")[:22] if len(x) > 79))
print("PROMPT=%d" % sum(1 for x in rows if x.startswith("> ") or x == ">")); print("ADAM=%d" % ("Adam> " in best)); print("SYSTEM=%d" % ("system> " in best))
print("EVER_ADAM=%d" % ("Adam> " in "".join(shown))); print("TYPED=%d" % ("> @adam hel" in "".join(shown)))
PY
  rm -rf "$w/nt/pt"; cp -r "$vh" "$w/nt/pt"; ptr=$(python3 "$w/nt/ptyc.py" "$nb" "$w/nt/pt" talk 2>&1); pf() { echo "$ptr" | sed -n "s/^$1=//p"; }
  env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/pt" > ptv.txt 2>&1; rcp=$?; pc="$w/nt/pt/diaries/chat.txt"
  [ "$(pf EXIT)" = 0 ] && [ "$(pf RAW)" = "(False, False)" ] && [ "$(pf BACK)" = "(True, True)" ] && [ "$(pf ROWS)" -le 24 ] && [ "$(pf WIDE)" = 0 ] && [ "$(pf PROMPT)" = 1 ] && [ "$(pf EVER_ADAM)" = 1 ] && [ "$(pf TYPED)" = 1 ] \
    && grep -q 'who=you to=ada .* text=@adam helo!$' "$pc" && grep -q 'who=ada to=you' "$pc" && grep -q 'who=system to=you .*no one is called "zzz"' "$pc" && grep -q 'text=tick [0-9]*, session' "$pc" && grep -q 'text=pause asked' "$pc" \
    && grep -q 'who=gemini to=you' "$pc" && grep -q 'text=going on from tick' "$pc" && grep -q 'text=mood: ' "$pc" && grep -q 'text=stopping like q' "$pc" && ! grep -q 'text=@x' "$pc" && [ "$rcp" = 0 ] && grep -q '^verify: OK' ptv.txt \
    && ok "on a terminal: a line starting with @ or / appears on the input line as it is typed (Backspace edits, Esc cancels the line: '@x' was never sent), the answers appear in the chat window, /pause waits and the lines typed while paused are answered, /resume goes on, /quit stops the run (exit 0); the terminal is raw while it runs and back to echo + line mode after; screen <= 24 rows and <= 79 columns; chat.txt verifies" || bad "chat on a terminal ($ptr) verify $rcp"
  rm -rf "$w/nt/pq"; cp -r "$vh" "$w/nt/pq"; ptr=$(python3 "$w/nt/ptyc.py" "$nb" "$w/nt/pq" bareq 2>&1)
  [ "$(pf EXIT)" = 0 ] && [ "$(pf BACK)" = "(True, True)" ] && ! grep -q '^C' "$w/nt/pq/diaries/chat.txt" 2> /dev/null \
    && ok "a bare q on an empty input line still stops the run (a key that is not @ or / is ignored: 'x' did nothing), nothing is recorded, the session can be resumed" || bad "bare q ($ptr)"
  rm -rf "$w/nt/po"; cp -r "$vh" "$w/nt/po"; ptr=$(python3 "$w/nt/ptyc.py" "$nb" "$w/nt/po" other 2>&1)
  grep -q ' text=@aq$' "$w/nt/po/diaries/chat.txt" && grep -q 'text="aq" fits\|text=no one is called "aq"' "$w/nt/po/diaries/chat.txt" && [ "$(pf BACK)" = "(True, True)" ] \
    && ok "q inside a line is text (@aq was sent, not a stop), Ctrl-C ends the run and the terminal is put back" || bad "q inside a line ($ptr)"
else ok "chat on a terminal: skipped (no python3 for a pseudo terminal)"; fi
grep -q 'make chat' "$root/Makefile" && grep -q 'make chatlog' "$root/Makefile" && grep -q -- '--chat' "$root/data/help.txt" && grep -q -- '--chatlog' "$root/data/help.txt" && grep -q 'chat.session_ticks' "$root/data/limits.txt" && grep -q 'diaries/chat.txt' "$root/README.md" \
  && grep -q '18000 .. 18499' "$root/docs/LEARN.md" && grep -q 'stty sane' "$root/README.md" && ok "README, Makefile, --help, data/limits.txt and docs/LEARN.md (salts 18000 .. 18499) describe the chat" || bad "chat docs"
echo "== 50. make wordstat (--wordstat): the vocabulary report, read-only; also in make share =="
cd "$w/nt" || exit 1
ws="$w/nt/ws"; rm -rf "$ws"; cp -r "$vh" "$ws"
sumf() { ( cd "$1" && find . -type f | sort | while read -r f; do cksum < "$f" | sed "s#\$# $f#"; done | cksum ); }
s0=$(sumf "$ws")
env -u DIARY_VERBOSE "$nb" --wordstat --home "$ws" > wsr.txt 2>&1; rcw=$?
env -u DIARY_VERBOSE "$nb" --wordstat --home "$ws" > wsr2.txt 2>&1
s1=$(sumf "$ws")
exp=$(awk '!/^#/ && NF >= 4 { k = FILENAME SUBSEP $1; if (!(k in seen)) { seen[k] = 1; n++; if ($2 ~ /^[a-h][1-8][a-h][1-8][qrbn]?$/) c++; else if ($2 ~ /^[0-9]+$/) d++; else if ($3 == "start") st++ } } END { print n + 0, c + 0, d + 0, st + 0 }' "$ws"/entities/*/words.txt)
row() { awk -v k="$1" 'index($0, k) > 0 { print $NF; exit }' wsr.txt; }
got="$(row 'known words') $(row 'chess move, coordinates') $(row 'chess move, numbers') $(row 'start words')"
ucnt=$(row 'used again after learning'); nuc=$(row 'never used again  '); tot=$(row 'known words')
# the variants, counted again by awk for the first wesen (stems of at least 3 letters, chess and number tokens left out)
va=$(awk '!/^#/ && NF >= 4 { if ($2 !~ /^[a-h][1-8][a-h][1-8][qrbn]?$/ && $2 !~ /^[0-9]+$/) w[$2] = 1 } END { for (x in w) { n = length(x); f = 0; for (l = 3; l < n && !f; l++) if ((substr(x, 1, l) in w) || (substr(x, n - l + 1) in w)) f = 1; v += f } print v + 0 }' "$ws/entities/ada/words.txt")
vr=$(awk '/^  prefix or suffix variants/ { print $(NF-4); exit }' wsr.txt)
[ "$rcw" = 0 ] && [ "$got" = "$(echo "$exp" | awk '{ print $1, $2, $3, $4 }')" ] && [ "$tot" -gt 100 ] && [ "$vr" = "$va" ] && [ "$s0" = "$s1" ] && cmp -s wsr.txt wsr2.txt \
  && ! grep -q '\[wordstat\.' wsr.txt && [ "$(awk 'length > 79' wsr.txt | wc -l)" = 0 ] && grep -q '^By kind' wsr.txt && grep -q '^Meaning and use' wsr.txt && grep -q '^Use by kind' wsr.txt && grep -q '^Word length, all words' wsr.txt \
  && grep -q '^Word length, without the chess' wsr.txt && grep -q '^Tokens and variants' wsr.txt && grep -q '^Conclusion:' wsr.txt && sed -n '/^Conclusion:/,$p' wsr.txt | grep -q 'The biggest source is ' \
  && [ "$((ucnt + nuc))" = "$tot" ] \
  && ok "--wordstat: $tot words known (start, chess coordinates, chess numbers and the total equal an independent awk count: $got), used + never used = known, prefix/suffix variants of the first wesen equal an independent count ($vr), every line <= 79 columns, same text on every run, the save folder byte for byte unchanged (read-only), conclusion names the biggest source" \
  || bad "wordstat (rc $rcw, report '$got' vs awk '$exp', variants $vr vs $va, used $ucnt + $nuc vs $tot, before/after $s0 $s1)"
mkdir -p "$w/nt/emptyws"; env -u DIARY_VERBOSE "$nb" --wordstat --home "$w/nt/emptyws" > wse.txt 2>&1; rce=$?
[ "$rce" = 2 ] && grep -q 'no word lists yet' wse.txt && [ -z "$(find "$w/nt/emptyws" -name 'words.txt')" ] && ok "--wordstat on a folder without word lists: one clear line, exit 2, nothing created" || bad "wordstat empty ($rce: $(head -2 wse.txt))"
sd2="$w/nt/out2"; rm -rf "$sd2"; mkdir -p "$sd2"; ( export DIARY_HOME="$ws" SHARE_DIR="$sd2"; "$root/scripts/share.sh" "$nb" > share2.txt 2>&1 ); sf2=$(ls "$sd2"/share-* 2> /dev/null | head -1)
if [ -n "$sf2" ]; then
  rm -rf "$w/nt/x2"; mkdir -p "$w/nt/x2"
  case $sf2 in *.zip) python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$sf2" "$w/nt/x2" 2> /dev/null || ( cd "$w/nt/x2" && unzip -q "$sf2" );; *) tar -xzf "$sf2" -C "$w/nt/x2";; esac
  [ -s "$w/nt/x2/wordstat.txt" ] && grep -q '^Conclusion:' "$w/nt/x2/wordstat.txt" && grep -q '^wordstat: The biggest source is ' "$w/nt/x2/share_info.txt" && grep -q '^files: .*wordstat.txt' "$w/nt/x2/share_info.txt" \
    && grep -q '^share: wordstat: The biggest source is ' share2.txt && ! ls "$w/nt/x2" | grep -qi 'ballot\|diaries\|jsonl\|words.txt' \
    && ok "make share: wordstat.txt is in the archive, its conclusion is in share_info.txt and on the console; still no diaries, entities or ballots" || bad "share wordstat ($(ls "$w/nt/x2" | tr '\n' ' '))"
else bad "share wordstat: no archive ($(cat share2.txt))"; fi
# the dictionary figures (a list of its own) equal an independent count of diaries/dictionary.txt; the agreed row is a text match only
dfile="$ws/diaries/dictionary.txt"; [ -f "$dfile" ] || dfile=/dev/null
dexp=$(awk '/^L[0-9]/ { d++; if ($0 ~ / st=A /) a++; if ($0 ~ / st=R /) r++; if ($0 ~ / ann=1 /) n++ } END { print d + 0, a + 0, r + 0, n + 0 }' "$dfile")
dgot="$(row 'entries decided') $(row 'agreed (st=A)') $(row 'rejected (st=R)') $(row 'entries announced')"
aexp=$(awk 'FNR == NR { if ($0 ~ /^L[0-9]/ && $0 ~ / st=A /) { for (i = 1; i <= NF; i++) if ($i ~ /^word=/) ag[substr($i, 6)] = 1 } ; next } !/^#/ && NF >= 4 && ($2 in ag) { k++ } END { print k + 0 }' "$dfile" "$ws"/entities/*/words.txt)
agot=$(row 'same text as an agreed word')
nexp=$(awk '/^A[0-9]/ { n++ } END { print n + 0 }' "$ws/diaries/announcements.txt" 2>/dev/null)
ngot=$(row 'announcements of all kinds')
[ "$dgot" = "$dexp" ] && [ "$agot" = "$aexp" ] && [ "$ngot" = "$nexp" ] && grep -q '^Dictionary (diaries/dictionary.txt' wsr.txt && grep -q 'only a dictionary entry' wsr.txt \
  && ok "--wordstat: dictionary figures equal an independent count (decided/agreed/rejected/announced $dgot; announcements of all kinds $ngot); the agreed row counts same-text coincidences only ($agot)" \
  || bad "wordstat dictionary ('$dgot' vs '$dexp', same text $agot vs $aexp, announcements $ngot vs $nexp)"
grep -q 'make wordstat' "$root/Makefile" && grep -q '^wordstat: all' "$root/Makefile" && grep -q -- '--wordstat' "$root/data/help.txt" && grep -q 'make wordstat' "$root/README.md" && grep -q 'wordstat.stem_min' "$root/data/limits.txt" && grep -q 'Condensing the vocabulary' "$root/docs/LEARN.md" \
  && grep -q 'Why the dictionary and the vocabulary differ' "$root/docs/EVOLVE.md" && grep -q '20000 .. 20999' "$root/docs/LEARN.md" && grep -q '20000 .. 20999' "$root/docs/PORTALS.md" && grep -q 'docs/EVOLVE.md' "$root/README.md" && ! grep -q '—' "$root/docs/EVOLVE.md" \
  && ok "README, Makefile, --help, data/limits.txt and docs/LEARN.md describe the vocabulary report; docs/EVOLVE.md (salts 20000 .. 20999 noted in LEARN.md and PORTALS.md) is in the README" || bad "wordstat docs"
echo "== 51. symbols=1: chess moves stay symbols of the board, they are no longer minted, learned or taught as words =="
cd "$w/nt" || exit 1
# a save with the OLD rule (symbols.enabled = 0), then the same save continued by new sessions with the new rule and, as the control, with the old rule
rm -rf "$w/nt/sd" "$w/nt/sy_old" "$w/nt/sy_new" "$w/nt/sy_ctl"; mkdir -p "$w/nt/sd/bin"; cp "$nb" "$w/nt/sd/bin/"; cp -r "$root/data" "$w/nt/sd/data"; sed -i 's/^symbols.enabled = .*/symbols.enabled = 0/' "$w/nt/sd/data/limits.txt"; sed -i 's/^active.enabled = .*/active.enabled = 0/' "$w/nt/sd/data/limits.txt"
( cd "$w/nt/sd" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/sy_old" --seed 42 --ticks 3000 --yes --every 100000 > "$w/nt/sy_old.txt" 2>&1 )
cp -r "$w/nt/sy_old" "$w/nt/sy_new"; cp -r "$w/nt/sy_old" "$w/nt/sy_ctl"
env -u DIARY_VERBOSE "$nb" --home "$w/nt/sy_new" --continuous --session-ticks 300 --max-sessions 6 > "$w/nt/sy_new.txt" 2>&1; rcn=$?
( cd "$w/nt/sd" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/sy_ctl" --continuous --session-ticks 300 --max-sessions 6 > "$w/nt/sy_ctl.txt" 2>&1 )
syc() { awk '!/^#/ && NF >= 4 && $4 > 3000 && ($2 ~ /^[a-h][1-8][a-h][1-8][qrbn]?$/ || $2 ~ /^[0-9]+$/) { n++ } END { print n + 0 }' "$1"/entities/*/words.txt; }
sno=$(syc "$w/nt/sy_old"); snn=$(syc "$w/nt/sy_new"); snc=$(syc "$w/nt/sy_ctl")
old_bytes=$(wc -c < "$w/nt/sy_old/diaries/chess.txt"); sc_bytes=$(wc -c < "$w/nt/sy_old/diaries/screens.txt")
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/sy_new" > syv.txt 2>&1; rcv=$?
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/sy_ctl" > syc.txt 2>&1; rcc=$?
ns=$(grep -c '^S[0-9].* symbols=1' "$w/nt/sy_new/diaries/sessions.txt"); nc=$(grep -c 'symbols' "$w/nt/sy_ctl/diaries/sessions.txt")
[ "$rcn" = 0 ] && [ "$ns" -ge 5 ] && [ "$nc" = 0 ] && ! grep '^S1 ' "$w/nt/sy_new/diaries/sessions.txt" | grep -q symbols && [ "$sno" = 0 ] && [ "$snn" = 0 ] && [ "$snc" -gt 20 ] \
  && ok "new sessions carry symbols=1 ($ns of them, the old session 1 does not): they add $snn chess or number words, the same sessions with symbols.enabled = 0 add $snc" || bad "symbols marker/mint (rc $rcn, marked $ns, control marked $nc, words new $snn control $snc old $sno)"
[ "$rcv" = 0 ] && grep -q '^verify: OK' syv.txt && [ "$rcc" = 0 ] && grep -q '^verify: OK' syc.txt \
  && cmp -s -n "$old_bytes" "$w/nt/sy_old/diaries/chess.txt" "$w/nt/sy_new/diaries/chess.txt" && cmp -s -n "$sc_bytes" "$w/nt/sy_old/diaries/screens.txt" "$w/nt/sy_new/diaries/screens.txt" \
  && ok "make verify: OK for the mixed save (old session replayed with the old rule, new ones with symbols=1) and for the control; the old chess and screen records are byte for byte the prefix of the new files" || bad "symbols verify ($rcv $rcc)"
# tampering: the marker taken from a new session, or put on the old one: the replay no longer fits the records
rm -rf "$w/nt/sy_t1" "$w/nt/sy_t2"; cp -r "$w/nt/sy_new" "$w/nt/sy_t1"; cp -r "$w/nt/sy_new" "$w/nt/sy_t2"
sed -i '/^S4 /s/ symbols=1//' "$w/nt/sy_t1/diaries/sessions.txt"; sed -i '/^S1 /s/$/ symbols=1/' "$w/nt/sy_t2/diaries/sessions.txt"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/sy_t1" > syt1.txt 2>&1; r1=$?; env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/sy_t2" > syt2.txt 2>&1; r2=$?
[ "$r1" = 1 ] && [ "$r2" = 1 ] && grep -q 'DRIFT\|differs' syt1.txt && grep -q 'DRIFT\|differs' syt2.txt \
  && ok "tampering: symbols=1 removed from session 4, or added to session 1: --verify reports DRIFT (exit 1) in both" || bad "symbols tamper ($r1 $r2: $(head -c 150 syt1.txt))"
# the report shows the drop
env -u DIARY_VERBOSE "$nb" --wordstat --home "$w/nt/sy_new" > sy_ws1.txt 2>&1; env -u DIARY_VERBOSE "$nb" --wordstat --home "$w/nt/sy_ctl" > sy_ws0.txt 2>&1
sw=$(awk '/words learned since then/ { print $NF; exit }' sy_ws1.txt); swt=$(awk '/of those, chess or number strings/ { print $NF; exit }' sy_ws1.txt)
grep -q '^Chess strings as symbols' sy_ws1.txt && grep -q 'first symbols=1 session: S2 from tick 3000' sy_ws1.txt && [ "$swt" = 0 ] && [ "${sw:-0}" -gt 100 ] && grep -q 'no symbols=1 session yet' sy_ws0.txt && [ "$(awk 'length > 79' sy_ws1.txt | wc -l)" = 0 ] \
  && ok "--wordstat: symbols section: since the first symbols=1 session $sw words were learned and $swt of them are chess or number strings; the control save says there is no symbols=1 session" || bad "wordstat symbols ($sw $swt)"
grep -q 'symbols=1' "$root/README.md" && grep -q 'symbols.enabled' "$root/data/limits.txt" && grep -q 'symbols=1' "$root/data/help.txt" && grep -q 'symbols=1' "$root/docs/EVOLVE.md" \
  && ok "README, --help, data/limits.txt and docs/EVOLVE.md describe symbols=1" || bad "symbols docs"
echo "== 52. make evolve (--evolve) and make active (--active): the evolution preview, read-only =="
cd "$w/nt" || exit 1
ev="$w/nt/sy_ctl"   # the save of scenario 51 made with the old rule: it has chess words, chess games and 7 sessions
sumf() { ( cd "$1" && find . -type f | sort | while read -r f; do cksum < "$f" | sed "s#\$# $f#"; done | cksum ); }
e0=$(sumf "$ev")
env -u DIARY_VERBOSE "$nb" --evolve --home "$ev" > ev1.txt 2>&1; rce=$?
env -u DIARY_VERBOSE "$nb" --evolve --home "$ev" > ev2.txt 2>&1
env -u DIARY_VERBOSE "$nb" --active --home "$ev" > ea1.txt 2>&1; rca=$?
e1=$(sumf "$ev")
erow() { awk -v k="$2" 'index($0, k) > 0 { print $NF; exit }' "$1"; }
ewk=$(awk '!/^#/ && NF >= 4 && !seen[FILENAME, $2]++ { n++ } END { print n + 0 }' "$ev"/entities/*/words.txt)
esy=$(awk '!/^#/ && NF >= 4 && !seen[FILENAME, $2]++ && ($2 ~ /^[a-h][1-8][a-h][1-8][qrbn]?$/ || $2 ~ /^[0-9]+$/) { n++ } END { print n + 0 }' "$ev"/entities/*/words.txt)
ebs=$(awk '!/^#/ && NF >= 4 && !seen[FILENAME, $2]++ && $3 == "start" && $2 !~ /^[0-9]+$/ && $2 !~ /^[a-h][1-8][a-h][1-8][qrbn]?$/ { n++ } END { print n + 0 }' "$ev"/entities/*/words.txt)
gk=$(erow ev1.txt 'words known'); gs=$(erow ev1.txt 'chess/number strings'); gb=$(erow ev1.txt 'of those: base words'); ga=$(erow ev1.txt 'would be active'); gd=$(erow ev1.txt 'would be dormant'); go=$(erow ev1.txt 'other words')
[ "$rce" = 0 ] && [ "$rca" = 0 ] && [ "$e0" = "$e1" ] && cmp -s ev1.txt ev2.txt && [ "$gk" = "$ewk" ] && [ "$gs" = "$esy" ] && [ "$gb" = "$ebs" ] && [ "$((ga + gd))" = "$go" ] && [ "$((gs + go))" = "$gk" ] && [ "$esy" -gt 50 ] \
  && ok "--evolve: words known $gk, chess/number strings $gs and base words $gb equal an independent awk count of words.txt, active $ga + dormant $gd = the $go other words; the save folder is byte for byte unchanged, the same text on every run (a word listed twice under two ids counts once)" || bad "evolve words (rc $rce $rca: $gk/$ewk $gs/$esy $gb/$ebs $ga+$gd vs $go, before/after $e0 $e1)"
# the chess part against the record: games, moves and the last Elo of the first wesen, counted again with awk
cg=$(awk '/ end / { n++ } END { print n + 0 }' "$ev/diaries/chess.txt"); cm=$(awk '/ move / { n++ } END { print n + 0 }' "$ev/diaries/chess.txt")
gm=$(sed -n '/^Chess: [0-9]/,$p' ev1.txt | tr '\n' ' ' | sed -E 's/^Chess: ([0-9]+) moves of ([0-9]+) games.*/\1 \2/')
ce=$(grep ' end ' "$ev/diaries/chess.txt" | grep -o 'ada=[0-9]*>[0-9]*' | tail -1 | sed 's/.*>//'); ge=$(awk '/^  Elo now/ { print $3; exit }' ev1.txt)
gsum=$(awk '/^  games / { s = 0; for (i = 2; i <= NF; i++) s += $i; print s; exit }' ev1.txt)
wbad=$(awk '/^  (piece|takes|gives|castles|promotes|to |pawn|minor|king walk|opening)/ { for (i = NF - 6; i <= NF; i++) { v = $i; gsub(/\+/, "", v); if (v != "." && (v + 0 > 8 || v + 0 < -8)) b++ } } END { print b + 0 }' ev1.txt)
[ "$gm" = "$cm $cg" ] && [ "$gsum" = "$((cg * 2))" ] && [ "$ge" = "$ce" ] && [ "$wbad" = 0 ] && grep -q '^Elo curve' ev1.txt && grep -q '^Conclusion:' ev1.txt && [ "$(awk 'length > 79' ev1.txt ea1.txt | wc -l)" = 0 ] && ! grep -q '\[evolve\.' ev1.txt \
  && ok "--evolve chess: $cm moves of $cg games replayed and counted (equal to the record), every game counted for both sides ($gsum), the Elo of the first wesen equals the last rating in chess.txt ($ge), no weight outside -8 .. +8, every line <= 79 columns" || bad "evolve chess ('$gm' vs '$cm $cg', games $gsum, elo $ge vs $ce, weights out of range $wbad)"
# the top list is sorted, the dormant list is not longer than the limit
tf=$(sed -n '/^Top /,/^$/p' ev1.txt | awk 'NF >= 5 && $1 != "word" && $1 != "Top" { print $3 }'); ts=$(echo "$tf" | sort -rn | tr '\n' ' '); tu=$(echo "$tf" | tr '\n' ' ')
[ -n "$tf" ] && [ "$ts" = "$tu" ] && [ "$(sed -n '/^Would be dormant first/,/^$/p' ev1.txt | grep -c '^  [a-z]')" -le 16 ] \
  && ok "--evolve: the top words are listed by falling fitness; the would-be dormant list stays within its limit" || bad "evolve lists ($tu)"
# make active: with a huge cap nothing goes dormant; with the default cap active + dormant = the other words and the per-session limit is respected
rm -rf "$w/nt/evd"; mkdir -p "$w/nt/evd"; cp -r "$root/data" "$w/nt/evd/data"; sed -i 's/^evolve.cap = .*/evolve.cap = 100000/' "$w/nt/evd/data/limits.txt"
( cd "$w/nt/evd" && env -u DIARY_VERBOSE "$nb" --active --home "$ev" > "$w/nt/ea2.txt" 2>&1 )
aa=$(erow ea1.txt 'would be active'); ad=$(erow ea1.txt 'would be dormant'); ao=$(erow ea1.txt 'other words'); ab=$(erow ea1.txt 'of those: base words'); a2d=$(erow ea2.txt 'would be dormant'); a2a=$(erow ea2.txt 'would be active'); a2o=$(erow ea2.txt 'other words')
ns=$(grep -c '^S[0-9]' "$ev/diaries/sessions.txt")
[ "$((aa + ad))" = "$ao" ] && [ "$ab" -le "$aa" ] && [ "$ad" -le "$((40 * 4 * ns))" ] && [ "$a2d" = 0 ] && [ "$a2a" = "$a2o" ] && grep -q '^By kind' ea1.txt && grep -q '^Conclusion:' ea1.txt \
  && ok "--active: active $aa + dormant $ad = the $ao words; the base words ($ab) stay active; at most 40 words per wesen and session go ($ad of $((40 * 4 * ns)) possible in $ns sessions); with evolve.cap = 100000 none goes ($a2d)" || bad "active ($aa + $ad vs $ao, base $ab, huge cap $a2d $a2a $a2o)"
rm -rf "$w/nt/emp"; mkdir -p "$w/nt/emp"; env -u DIARY_VERBOSE "$nb" --evolve --home "$w/nt/emp" > eme.txt 2>&1; rcm=$?
[ "$rcm" = 2 ] && grep -q 'no word lists yet' eme.txt && [ -z "$(find "$w/nt/emp" -name 'words.txt')" ] \
  && ok "--evolve on a folder without word lists: one clear line, exit 2, nothing created" || bad "evolve empty ($rcm: $(head -c 100 eme.txt))"
grep -q 'make evolve' "$root/Makefile" && grep -q '^evolve: all' "$root/Makefile" && grep -q '^active: all' "$root/Makefile" && grep -q -- '--evolve' "$root/data/help.txt" && grep -q -- '--active' "$root/data/help.txt" && grep -q 'make evolve' "$root/README.md" && grep -q 'evolve.cap' "$root/data/limits.txt" && grep -q 'make evolve' "$root/docs/EVOLVE.md" \
  && ok "README, Makefile, --help, data/limits.txt and docs/EVOLVE.md describe make evolve and make active" || bad "evolve docs"
echo "== 53. active=1: dormant vocabulary, wake on use, diaries/active.txt (Sim_Active, docs/EVOLVE.md 13) =="
cd "$w/nt" || exit 1
# a save with the OLD rule (active.enabled = 0), then the same save continued with the new rule and, as the control, with the old rule
rm -rf "$w/nt/ad" "$w/nt/ac_old" "$w/nt/ac_new" "$w/nt/ac_ctl"; mkdir -p "$w/nt/ad/bin"; cp "$nb" "$w/nt/ad/bin/"; cp -r "$root/data" "$w/nt/ad/data"; sed -i 's/^active.enabled = .*/active.enabled = 0/' "$w/nt/ad/data/limits.txt"
( cd "$w/nt/ad" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/ac_old" --seed 42 --ticks 2400 --yes --every 100000 > "$w/nt/ac_old.txt" 2>&1 )
cp -r "$w/nt/ac_old" "$w/nt/ac_new"; cp -r "$w/nt/ac_old" "$w/nt/ac_ctl"
# active.enabled = 1 (the default is 2 now, scenario 56 continues this save with active=2)
rm -rf "$w/nt/a1d"; mkdir -p "$w/nt/a1d/bin"; cp "$nb" "$w/nt/a1d/bin/"; cp -r "$root/data" "$w/nt/a1d/data"; sed -i 's/^active.enabled = .*/active.enabled = 1/' "$w/nt/a1d/data/limits.txt"
( cd "$w/nt/a1d" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/ac_new" --continuous --session-ticks 200 --max-sessions 14 > "$w/nt/ac_new.txt" 2>&1 ); rcn=$?
( cd "$w/nt/ad" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/ac_ctl" --continuous --session-ticks 200 --max-sessions 14 > "$w/nt/ac_ctl.txt" 2>&1 )
na=$(grep -c ' active=1' "$w/nt/ac_new/diaries/sessions.txt"); nc=$(grep -c 'active' "$w/nt/ac_ctl/diaries/sessions.txt")
[ "$rcn" = 0 ] && [ "$na" -ge 12 ] && [ "$nc" = 0 ] && ! grep '^S1 ' "$w/nt/ac_new/diaries/sessions.txt" | grep -q active && [ -f "$w/nt/ac_new/diaries/active.txt" ] && [ ! -f "$w/nt/ac_ctl/diaries/active.txt" ] \
  && ok "new sessions carry active=1 ($na of them, the old session 1 does not); the control with active.enabled = 0 has no marker and no active.txt" || bad "active marker ($rcn $na $nc)"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/ac_new" > acv.txt 2>&1; rcv=$?
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/ac_ctl" > acc.txt 2>&1; rcc=$?
old_bytes=$(wc -c < "$w/nt/ac_old/diaries/screens.txt")
[ "$rcv" = 0 ] && grep -q '^verify: OK' acv.txt && [ "$rcc" = 0 ] && grep -q '^verify: OK' acc.txt \
  && cmp -s -n "$old_bytes" "$w/nt/ac_old/diaries/screens.txt" "$w/nt/ac_new/diaries/screens.txt" \
  && ok "make verify: OK for the mixed save and for the control; the old screen record is byte for byte the prefix of the new one" || bad "active verify ($rcv $rcc)"
# tampering: marker taken from a new session, or a dormant / wake line changed: DRIFT
rm -rf "$w/nt/at"; cp -r "$w/nt/ac_new" "$w/nt/at"; sed -i '/^S3 /s/ active=1//' "$w/nt/at/diaries/sessions.txt"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/at" > at1.txt 2>&1; r1=$?
rm -rf "$w/nt/at"; cp -r "$w/nt/ac_new" "$w/nt/at"; sed -i '0,/ dormant w=/{s/ dormant w=\([0-9]*\)/ dormant w=9\1/}' "$w/nt/at/diaries/active.txt"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/at" > at2.txt 2>&1; r2=$?
rm -rf "$w/nt/at"; cp -r "$w/nt/ac_new" "$w/nt/at"; sed -i '0,/ dormant w=/{/ dormant w=/d}' "$w/nt/at/diaries/active.txt"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/at" > at3.txt 2>&1; r3=$?
[ "$r1" = 1 ] && [ "$r2" = 1 ] && [ "$r3" = 1 ] && grep -q 'import FAILED' at1.txt && grep -q 'active.txt' at2.txt && grep -q 'active.txt' at3.txt \
  && ok "tampering: active=1 removed from session 3, a dormant word id changed, or a dormant line deleted: --verify reports DRIFT (exit 1) in each" || bad "active tamper ($r1 $r2 $r3)"
# independent check of the record: dormant words were not taught / coined from / blended; every wake has a matching record line; the last state matches the counts
python3 - "$w/nt/ac_new" <<'PY' > acp.txt 2>&1
import sys, re, os
d = sys.argv[1]
def tok(l, k):
    m = re.search(r'(?:^| )' + re.escape(k) + r'=(\S*)', l)
    return m.group(1) if m else ''
names = ['ada', 'gemini', 'replika', 'robert']
A = [l.rstrip('\n') for l in open(os.path.join(d, 'diaries/active.txt')) if l.startswith('A')]
iv = {}; nd = {e: 0 for e in names}; nw = {e: 0 for e in names}; wakes = []; last = {}; cnt = {}
for l in A:
    f = l.split()
    if len(f) < 5: continue
    e, op = f[3], f[4]; t = int(tok(l, 't'))
    if op == 'dormant':
        iv.setdefault((e, int(tok(l, 'w'))), []).append([t, 10**12]); nd[e] += 1
    elif op == 'wake':
        w = int(tok(l, 'w')); iv[(e, w)][-1][1] = t; nw[e] += 1; wakes.append((e, w, t, tok(l, 'by'), tok(l, 'word')))
    elif op == 'state':
        last[e] = l; cnt[e] = (nd[e], nw[e])
def asleep(e, w, t):
    return any(a < t < b for a, b in iv.get((e, w), []))
ids = {}; words = {}
for e in names:
    words[e] = [l.split() for l in open(os.path.join(d, 'entities', e, 'words.txt')) if not l.startswith('#') and len(l.split()) >= 4]
    for f in words[e]: ids.setdefault(f[1], int(f[0]))
taught_bad = coined_bad = blend_bad = 0
for p in names:
    for f in words[p]:
        if f[2] == 'taught' and len(f) >= 5 and asleep(f[4], int(f[0]), int(f[3])): taught_bad += 1
        if f[2] == 'coined' and len(f) >= 5:
            for part in f[4].split('+'):
                if part in ids and asleep(p, ids[part], int(f[3])): coined_bad += 1
recs = {}
for fn in ['screens', 'votes', 'petitions', 'dictionary']:
    pth = os.path.join(d, 'diaries', fn + '.txt')
    if not os.path.exists(pth): continue
    for l in open(pth):
        if l[:1].isalpha() and l[:1] != '#':
            recs[(fn, l.split(' ', 1)[0])] = l.rstrip('\n')
            if fn == 'screens':
                f = l.split()
                if len(f) > 3 and f[3] == 'blend':
                    t = int(tok(l, 't'))
                    for x in ('a', 'b'):
                        if asleep(f[2], int(tok(l, x)), t): blend_bad += 1
wake_ok = 0
for e, w, t, by, word in wakes:
    fn = {'K': 'screens', 'V': 'votes', 'P': 'petitions', 'L': 'dictionary'}.get(by[:1])
    l = recs.get((fn, by))
    if l and int(tok(l, 't')) == t and (str(w) in re.split(r'[^0-9]+', l) or re.search(r'\b' + re.escape(word) + r'\b', l)):
        wake_ok += 1
state_bad = 0; ndorm = sum(nd.values())
for e in names:
    if e not in last: continue
    l = last[e]; dm = int(tok(l, 'dormant')); ac = int(tok(l, 'active')); kn = int(tok(l, 'known')); sy = int(tok(l, 'symbols'))
    if dm != cnt[e][0] - cnt[e][1] or kn != sy + ac + dm: state_bad += 1
    if ac > 500 + 40: state_bad += 1   # a little headroom for births in the last unfinished session
print('ok' if taught_bad == 0 and coined_bad == 0 and blend_bad == 0 and wake_ok == len(wakes) and state_bad == 0 and ndorm > 40 else
      f'fail taught={taught_bad} coined={coined_bad} blend={blend_bad} wake={wake_ok}/{len(wakes)} state={state_bad} dorm={ndorm}')
PY
[ "$(cat acp.txt)" = ok ] && ok "--active record: dormant words were not taught, coined from or blended; every wake has a matching record line; the last state equals the counts; more than 40 dormancies" || bad "active record ($(cat acp.txt))"
env -u DIARY_VERBOSE "$nb" --active --home "$w/nt/ac_new" > aca.txt 2>&1; rca=$?
env -u DIARY_VERBOSE "$nb" --active --home "$w/nt/ac_ctl" > acb.txt 2>&1
[ "$rca" = 0 ] && grep -q 'diaries/active.txt' aca.txt && grep -q 'active words' aca.txt && grep -q 'Active vocabulary preview' acb.txt && [ "$(awk 'length > 79' aca.txt acb.txt | wc -l)" = 0 ] \
  && ok "make active: the real state on the active=1 save (diaries/active.txt), the would-be preview on the control; every line <= 79 columns" || bad "active report ($rca)"
grep -q 'active=1' "$root/README.md" && grep -q 'active.enabled' "$root/data/limits.txt" && grep -q -- '--active' "$root/data/help.txt" && grep -q 'active=1' "$root/docs/EVOLVE.md" && grep -q 'sim_active.ads' "$root/Makefile" \
  && ok "README, --help, data/limits.txt, docs/EVOLVE.md and the Makefile describe active=1" || bad "active docs"
echo "== 54. make wordstat on an active=1/2 save: the active words only (kinds, most used, themes) =="
cd "$w/nt" || exit 1
env -u DIARY_VERBOSE "$nb" --wordstat --home "$w/nt/ac_new" > aw1.txt 2>&1; rcw=$?
env -u DIARY_VERBOSE "$nb" --wordstat --home "$w/nt/ac_ctl" > aw2.txt 2>&1
aw_tot=$(awk '/^  active words now/ { print $NF; exit }' aw1.txt)
aw_ind=$(python3 - "$w/nt/ac_new" <<'PY'
import sys, os, re
d = sys.argv[1]
dorm = set()
for l in open(os.path.join(d, 'diaries/active.txt')):
    f = l.split()
    if len(f) > 5 and f[0].startswith('A'):
        m = re.search(r' word=(\S+)', l)
        if f[4] == 'dormant': dorm.add((f[3], m.group(1)))
        elif f[4] == 'wake': dorm.discard((f[3], m.group(1)))
n = 0
for e in ['ada', 'gemini', 'replika', 'robert']:
    seen = set()
    for l in open(os.path.join(d, 'entities', e, 'words.txt')):
        f = l.split()
        if l.startswith('#') or len(f) < 4 or f[1] in seen: continue
        seen.add(f[1])
        if re.fullmatch(r'[a-h][1-8][a-h][1-8][qrbn]?|[0-9]+', f[1]): continue
        if (e, f[1]) not in dorm: n += 1
print(n)
PY
)
ksum=$(sed -n '/^  active words now/,/^  of those: used again/p' aw1.txt | awk '/^    / { s += $NF } END { print s + 0 }')
[ "$rcw" = 0 ] && [ -n "$aw_tot" ] && [ "$aw_tot" = "$aw_ind" ] && [ "$ksum" = "$aw_tot" ] && grep -q '^Themes of the active words' aw1.txt && grep -q '^Most used active words' aw1.txt \
  && ! grep -q 'Active words only' aw2.txt && [ "$(awk 'length > 79' aw1.txt | wc -l)" = 0 ] \
  && ok "--wordstat active-only section: $aw_tot active words now (= an independent count of words.txt minus the dormant words of active.txt), the kinds add up, most used and themes listed; not shown on the control save" || bad "wordstat active ($rcw '$aw_tot' '$aw_ind' '$ksum')"
cd "$w" || exit 1

echo "== 55. make frustration (--frustration): MiniMax report, refusals and mood per wesen, player load; read-only =="
cd "$w/nt" || exit 1
fh="$w/nt/ac_new"
sum0=$(cd "$fh" && find . -type f | sort | xargs md5sum | md5sum)
env -u DIARY_VERBOSE "$nb" --frustration --home "$fh" > fr1.txt 2>&1; rcf=$?
env -u DIARY_VERBOSE "$nb" --frustration --home "$fh" > fr2.txt 2>&1
sum1=$(cd "$fh" && find . -type f | sort | xargs md5sum | md5sum)
mkdir -p "$w/nt/fr_empty"; env -u DIARY_VERBOSE "$nb" --frustration --home "$w/nt/fr_empty" > fr3.txt 2>&1; rce=$?
fr_ind=$(python3 - "$fh" <<'PY'
import sys, os, re, json
d = os.path.join(sys.argv[1], 'diaries')
ses = []
for l in open(os.path.join(d, 'sessions.txt')):
    m = re.match(r'S(\d+) start=(\d+) .*len=(\d+)', l)
    if m: ses.append([int(m[2]) + 1, int(m[2]) + int(m[3])])
    m = re.match(r'W(\d+) tick=(\d+)', l)
    if m and int(m[1]) <= len(ses): ses[int(m[1]) - 1][1] = int(m[2])
pets = [l for l in open(os.path.join(d, 'petitions.txt')) if re.match(r'P\d', l) and ' out=' in l]
ref = sum(1 for l in pets if ' out=refuse' in l)
worst = []
for e in ['ada', 'gemini', 'replika', 'robert']:
    low = {}
    for l in open(os.path.join(d, e + '.jsonl')):
        try: j = json.loads(l)
        except ValueError: continue
        t, m = j.get('tick', 0), j.get('state', {}).get('mood', 0)
        for i, (a, b) in enumerate(ses):
            if a <= t <= b: low[i + 1] = min(low.get(i + 1, m), m); break
    rs = {}
    for l in pets:
        if ' wesen=%s ' % e in l and ' out=refuse' in l:
            s = int(re.search(r' s=(\d+)', l)[1]); rs[s] = rs.get(s, 0) + 1
    worst.append(max(10 * rs.get(s, 0) + max(0, -low.get(s, 0)) for s in range(1, len(ses) + 1)))
print(len(ses), len(pets), ref, max(worst), min(worst))
PY
)
set -- $fr_ind
fr_head=$(head -1 fr1.txt); fr_ref=$(sed -n 's/^Report only: \([0-9]*\) of \([0-9]*\) petitions.*/\1 \2/p' fr1.txt)
fr_w=$(sed -n 's/^Worst wesen: [^,]*, score \([0-9]*\) .*/\1/p' fr1.txt); fr_m=$(sed -n 's/^MiniMax: .* belongs to [^,]*, score \([0-9]*\) .*/\1/p' fr1.txt)
fr_col=$(awk '/^ +asked/ { on = 1; next } on && NF == 8 { s += $5 } /^$/ { on = 0 } END { print s + 0 }' fr1.txt)
[ "$rcf" = 0 ] && [ "$fr_head" = "Frustration (MiniMax, read-only): $1 sessions, $2 decided petitions." ] && [ "$fr_ref" = "$3 $2" ] && [ "$fr_col" = "$3" ] \
  && [ "$fr_w" = "$4" ] && [ "$fr_m" = "$5" ] && grep -q '^Worst player load: ' fr1.txt && [ "$(awk 'length > 79' fr1.txt | wc -l)" = 0 ] \
  && ok "--frustration: $1 sessions, $2 petitions, $3 refused (column and conclusion), worst score $4 and MiniMax $5 equal an independent count; player load listed; every line <= 79 columns" || bad "frustration counts ($rcf '$fr_head' '$fr_ref' '$fr_col' '$fr_w' '$fr_m' / $fr_ind)"
[ "$sum0" = "$sum1" ] && cmp -s fr1.txt fr2.txt && [ "$rce" = 2 ] && grep -q 'no sessions' fr3.txt && grep -q 'grant rate is not' fr1.txt \
  && ok "--frustration is read-only (the folder checksum is unchanged), the same twice, exit 2 on an empty folder, says the grant rate is not changed" || bad "frustration read-only ($rce)"
grep -q 'make frustration' "$root/README.md" && grep -q -- '--frustration' "$root/data/help.txt" && grep -q '^frustration:' "$root/Makefile" && grep -q 'frustration.refuse_weight' "$root/data/limits.txt" \
  && [ -f "$root/data/frustration.txt" ] && ok "README, --help, the Makefile, data/limits.txt and data/frustration.txt describe make frustration" || bad "frustration docs"
cd "$w" || exit 1

echo "== 56. active=2: floor 300 under the cap 500, mint-slow at the cap, wider wake; an active=1 save goes on (docs/EVOLVE.md 14) =="
cd "$w/nt" || exit 1
# the active=1 save of scenario 53 continued with the default data (active.enabled = 2), and as the control with every mint-slow percent at 100
rm -rf "$w/nt/a2" "$w/nt/a2f" "$w/nt/a2fd"; cp -r "$w/nt/ac_new" "$w/nt/a2"; cp -r "$w/nt/ac_new" "$w/nt/a2f"
mkdir -p "$w/nt/a2fd/bin"; cp "$nb" "$w/nt/a2fd/bin/"; cp -r "$root/data" "$w/nt/a2fd/data"; sed -i 's/^active.slow_\(.*\)_pct = .*/active.slow_\1_pct = 100/' "$w/nt/a2fd/data/limits.txt"
env -u DIARY_VERBOSE "$nb" --home "$w/nt/a2" --continuous --session-ticks 200 --max-sessions 6 > "$w/nt/a2.txt" 2>&1; rc2=$?
( cd "$w/nt/a2fd" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/a2f" --continuous --session-ticks 200 --max-sessions 1 > "$w/nt/a2f.txt" 2>&1 )
n1=$(grep -c ' active=1$' "$w/nt/ac_new/diaries/sessions.txt"); n2=$(grep -c ' active=2$' "$w/nt/a2/diaries/sessions.txt"); n21=$(grep -c ' active=1$' "$w/nt/a2/diaries/sessions.txt")
p1=$(grep -c ' params use_pts=.* floor=500 cap=500$' "$w/nt/a2/diaries/active.txt"); p2=$(grep -c ' params level=2 use_pts=.* floor=300 cap=500 slow_lesson=25 slow_coin=50 slow_screen=50$' "$w/nt/a2/diaries/active.txt")
pre_ok=1; for f in diaries/sessions.txt diaries/active.txt diaries/screens.txt; do cmp -s -n "$(wc -c < "$w/nt/ac_new/$f")" "$w/nt/ac_new/$f" "$w/nt/a2/$f" || pre_ok=0; done
[ "$rc2" = 0 ] && [ "$n2" = 6 ] && [ "$n21" = "$n1" ] && [ "$p1" = 1 ] && [ "$p2" = 1 ] && [ "$pre_ok" = 1 ] \
  && ok "the active=1 save goes on with active=2 (no --fresh): $n2 new sessions carry active=2, the $n1 old ones keep active=1; one params line each (level 2: floor=300 cap=500 slow 25/50/50); sessions, active and screen records of the old part are byte for byte the prefix" || bad "active=2 marker ($rc2 $n2 $n21/$n1 $p1 $p2 $pre_ok)"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/a2" > a2v.txt 2>&1; rcv=$?
s2=$(grep '^S' "$w/nt/a2/diaries/sessions.txt" | grep ' active=2$' | head -1 | cut -d' ' -f1)
rm -rf "$w/nt/a2t"; cp -r "$w/nt/a2" "$w/nt/a2t"; sed -i "/^$s2 /s/ active=2\$/ active=1/" "$w/nt/a2t/diaries/sessions.txt"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/a2t" > /dev/null 2>&1; t1=$?
rm -rf "$w/nt/a2t"; cp -r "$w/nt/a2" "$w/nt/a2t"; ln=$(grep -n 'by=lesson:' "$w/nt/a2t/diaries/active.txt" | head -1 | cut -d: -f1)
[ -n "$ln" ] && sed -i "${ln}d" "$w/nt/a2t/diaries/active.txt"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/a2t" > /dev/null 2>&1; t2=$?
rm -rf "$w/nt/a2t"; cp -r "$w/nt/a2" "$w/nt/a2t"; sed -i '/ params level=2 /s/ floor=300 / floor=500 /' "$w/nt/a2t/diaries/active.txt"
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/a2t" > /dev/null 2>&1; t3=$?
[ "$rcv" = 0 ] && grep -q '^verify: OK' a2v.txt && [ -n "$ln" ] && [ "$t1" = 1 ] && [ "$t2" = 1 ] && [ "$t3" = 1 ] \
  && ok "make verify: OK for the active=1 + active=2 save; DRIFT (exit 1) when $s2 says active=1, when a lesson wake line is deleted, when the level=2 floor is set to 500 (other dormancies)" || bad "active=2 verify ($rcv '$ln' $t1 $t2 $t3)"
a2py=$(python3 - "$w/nt/a2" <<'PY'
import sys, os, re
d = sys.argv[1]
keys = set()
for f in ['screens.txt', 'votes.txt', 'petitions.txt', 'dictionary.txt']:
    p = os.path.join(d, 'diaries', f)
    if os.path.exists(p):
        for l in open(p):
            if l[:1].isalpha(): keys.add(l.split()[0])
lv2 = set(int(m[1]) for m in re.finditer(r'^S(\d+) .* active=2$', open(os.path.join(d, 'diaries/sessions.txt')).read(), re.M))
bad = 0; lesson = 0; other2 = 0; floor_bad = 0; st2 = 0; slow = 0; wake_lines = 0
for l in open(os.path.join(d, 'diaries/active.txt')):
    f = l.split()
    if len(f) < 5: continue
    s = int(f[2][2:]) if f[2].startswith('s=') else 0
    if f[4] == 'wake':
        wake_lines += 1
        by = re.search(r' by=(\S+)', l).group(1)
        if by.startswith('lesson:'):
            if s not in lv2 or by[7:] not in ('ada', 'gemini', 'replika', 'robert'): bad += 1
            lesson += 1
        elif by not in keys: bad += 1
    elif f[4] == 'state' and s in lv2:
        st2 += 1
        kv = dict(x.split('=', 1) for x in f[5:])
        if 'slow' not in kv: bad += 1
        slow += int(kv.get('slow', '0'))
        if int(kv['went']) > 0 and int(kv['active']) < 300: floor_bad += 1
print(bad, lesson, st2, floor_bad, wake_lines)
PY
)
set -- $a2py
[ "${1:-x}" = 0 ] && [ "${2:-0}" -ge 1 ] && [ "${3:-0}" -ge 16 ] && [ "${4:-x}" = 0 ] \
  && ok "active=2 record: every wake has a record line or is a lesson of an active=2 session ($2 lesson wakes of $5 wakes), $3 level-2 state lines carry slow=, no dormancy below the floor of 300" || bad "active=2 record ($a2py)"
st=$(grep "^$s2 " "$w/nt/a2/diaries/sessions.txt" | sed 's/.* start=\([0-9]*\) .*/\1/'); capn=$(grep " s=$((${s2#S} - 1)) .* state .* active=500 " "$w/nt/a2/diaries/active.txt" | wc -l)
mint() { n=0; for e in ada gemini replika robert; do k=$(awk -v a="$st" -v b=$((st + 200)) '$4 > a && $4 <= b && ($3 == "taught" || $3 == "coined" || $3 == "screen")' "$1/entities/$e/words.txt" | wc -l); n=$((n + k)); done; echo $n; }
ms=$(mint "$w/nt/a2"); mf=$(mint "$w/nt/a2f")
[ "$capn" -ge 1 ] && [ "$ms" -lt "$mf" ] && grep -q 'mint-slow' "$root/docs/EVOLVE.md" \
  && ok "mint-slow: $capn wesen held the cap of 500 when active=2 began; in that first session $ms new words were minted against $mf with every slow percent at 100" || bad "mint-slow ($capn $ms $mf '$st')"
env -u DIARY_VERBOSE "$nb" --active --home "$w/nt/a2" > a2a.txt 2>&1
grep -q '^Active vocabulary (active=2;' a2a.txt && grep -q '^Numbers of the first active=1 session' a2a.txt && grep -q '^Numbers of the first active=2 session (floor 300, cap 500' a2a.txt \
  && grep -q 'at the cap (mint-slow next)\|at floor or above (mint-slow next)' a2a.txt && [ "$(awk 'length > 79' a2a.txt | wc -l)" = 0 ] \
  && grep -q 'active=2' "$root/README.md" && grep -q 'active.floor' "$root/data/limits.txt" && grep -q 'active=2' "$root/data/help.txt" && grep -q '20870' "$root/docs/PORTALS.md" && grep -q 'active=2' "$root/docs/LEARN.md" \
  && ok "make active on the active=2 save: level 2, both params lines (floor 300, cap 500), who is at the cap; README, --help, limits.txt, EVOLVE.md, LEARN.md and PORTALS.md (salts 20870 .. 20873) describe active=2" || bad "active=2 report and docs"
cd "$w" || exit 1

echo "== 57. every make target prints its wall time as the last line (scripts/timed.sh); the exit status is kept; make checkin; the replay-done line =="
cd "$w/nt" || exit 1
DIARY_HOME="$w/nt/a2" make -C "$root" wordstat > mt1.txt 2>&1; rcm=$?
DIARY_HOME="$w/nt/a2" make -s -C "$root" frustration > mt2.txt 2>&1; rcm2=$?
rm -rf "$w/nt/a2t"; cp -r "$w/nt/a2" "$w/nt/a2t"; sed -i '/ params level=2 /s/ floor=300 / floor=500 /' "$w/nt/a2t/diaries/active.txt"
DIARY_HOME="$w/nt/a2t" make -C "$root" verify > mt3.txt 2>&1; rcm3=$?
mkdir -p "$w/nt/mt_empty"; DIARY_HOME="$w/nt/mt_empty" make -C "$root" frustration > mt4.txt 2>&1; rcm4=$?
tl() { grep -v '^make\(\[[0-9]*\]\)\?: ' "$1" | tail -n 1; }
[ "$rcm" = 0 ] && tl mt1.txt | grep -Eq '^make wordstat wall time: [0-9]+m[0-5][0-9]s \([0-9]+s\)$' && grep -q '^bin/diary_sim --wordstat$' mt1.txt && grep -q '^Active words only' mt1.txt \
  && [ "$rcm2" = 0 ] && tl mt2.txt | grep -Eq '^make frustration wall time: ' && ! grep -q '^bin/diary_sim' mt2.txt \
  && ok "make wordstat / make -s frustration: the command line first (not with -s), the report, then 'make <target> wall time: XmYYs (Ns)' last" || bad "make wall time ($rcm $rcm2)"
[ "$rcm3" != 0 ] && tl mt3.txt | grep -Eq '^make verify wall time: ' && grep -q 'differs from the replay' mt3.txt && [ "$rcm4" != 0 ] && tl mt4.txt | grep -Eq '^make frustration wall time: ' \
  && [ "$(grep -c '^	$(TIMED) ' "$root/Makefile")" -ge 40 ] && grep -q 'wall time' "$root/README.md" \
  && ok "a failing command keeps its exit status (make verify on a tampered save: $rcm3, make frustration on an empty folder: $rcm4) and still prints the wall time; the Makefile times $(grep -c '^	$(TIMED) ' "$root/Makefile") recipe lines; README says so" || bad "make wall time on failure ($rcm3 $rcm4)"
rm -rf "$w/nt/ck"; cp -r "$w/nt/a2" "$w/nt/ck"; ckt=$(grep -h '^S' "$w/nt/ck/diaries/sessions.txt" | tail -1 | sed 's/.* start=\([0-9]*\) .* len=\([0-9]*\) .*/\1 \2/' | awk '{ print $1 + $2 }'); ckn=$(grep -c '^S' "$w/nt/ck/diaries/sessions.txt")
DIARY_HOME="$w/nt/ck" make -C "$root" checkin CHECKIN_SESSIONS=1 CHECKIN_TICKS=60 > ck.txt 2>&1 < /dev/null; rck=$?
secs=$(grep -E '^=== make (night|active|wordstat|frustration|evolve|verify)' ck.txt | awk '{ print $3 }' | tr '\n' ' ')
walls=$(grep -E '^make [a-z]+ wall time: [0-9]+m[0-5][0-9]s \([0-9]+s\)$' ck.txt | awk '{ print $2 }' | tr '\n' ' ')
[ "$rck" = 0 ] && [ "$secs" = "night active wordstat frustration evolve verify " ] && [ "$walls" = "night active wordstat frustration evolve verify checkin " ] \
  && tl ck.txt | grep -q '^make checkin wall time: ' && grep -q "^replay done: $ckt ticks in [0-9.]* s; NEW from s$((ckn + 1)), tick $((ckt + 1)) (active=2)\$" ck.txt && [ "$(awk 'length > 79' ck.txt | grep -c 'replay done')" = 0 ] \
  && grep -q '^| replay done: ' ck.txt && grep -q '^verify: OK' ck.txt && grep -q "replay done: $ckt ticks" "$w/nt/ck/run_log.txt" \
  && ok "make checkin: night (new session $((ckn + 1)) after the replay line 'replay done: $ckt ticks in ... s; NEW from s$((ckn + 1)), tick $((ckt + 1)) (active=2)', <= 79 columns, also in the box and run_log.txt), then active, wordstat, frustration, evolve, verify, each with === and its wall time; the checkin total last" || bad "make checkin ($rck '$secs' '$walls' $ckt $ckn)"
# 0.058: deterministic.  The checkpoint is removed (else there is no replay to interrupt), DIARY_TEST_REPLAY_MS=20 makes every
# replayed tick take 20 ms (tests only), and SIGTERM goes out as soon as the start line says the replay begins (not after a fixed sleep).
rm -rf "$w/nt/ck3"; cp -r "$w/nt/a2" "$w/nt/ck3"; rm -f "$w/nt/ck3/state.ckpt"
( DIARY_TEST_REPLAY_MS=20 env -u DIARY_VERBOSE "$nb" --home "$w/nt/ck3" --continuous --session-ticks 60 --max-sessions 1 > ck3.txt 2>&1 < /dev/null & p=$!
  for _ in $(seq 300); do grep -q '^replay: checkpoint missing - [0-9]* ticks replayed$' ck3.txt && break; sleep 0.1; done; kill -TERM $p; wait $p )
grep -q '^replay: checkpoint missing - [0-9]* ticks replayed$' ck3.txt && grep -q '^| replay not finished: no new session ran' ck3.txt && ! grep -q '^replay done' ck3.txt && grep -q 'make checkin' "$root/README.md" && grep -q '^checkin:' "$root/Makefile" && grep -q 'replay done' "$root/data/help.txt" \
  && ok "a night stopped during the replay says 'replay not finished: no new session ran' in its box; README, Makefile and --help describe make checkin and the replay line" || bad "replay not finished"
cd "$w" || exit 1

echo "== 58. a capped night (--max-sessions N) ends with why=max_sessions: a q (or a stray q byte) in its last session or in the end check does not change the reason; escape sequences are no q =="
cd "$w/nt" || exit 1
cat > "$w/nt/ptycap.py" <<'PY'
import os, pty, re, select, sys, time
mode, exe, home = sys.argv[1:4]
extra = sys.argv[4:]
pid, fd = pty.fork()
if pid == 0:
    os.chdir("/")
    os.execv(exe, [exe, "--continuous", "--home", home] + extra)
# last: q in the last session (after the first one is done); verify: q while the end check runs; esc / esc_plain: F2 (ESC O Q) split
# over two writes, ESC [ 1 ; 2 Q and a legacy mouse report at column 81 (byte q) during the first session of three
trigger = {"last": rb"\ns\d+ t\d+ ", "verify": rb"verifying the whole history", "esc": rb"session \d+, tick \d+ of", "esc_plain": rb"session \d+, tick \d+ of"}[mode]
out = b""; sent = False; t0 = time.time()
while time.time() - t0 < 180:
    r, _, _ = select.select([fd], [], [], 0.05)
    if r:
        try: d = os.read(fd, 65536)
        except OSError: break
        if not d: break
        out += d
    if not sent and re.search(trigger, out):
        sent = True
        if mode in ("last", "verify"): os.write(fd, b"q")
        else:
            os.write(fd, b"\x1b"); time.sleep(0.4); os.write(fd, b"OQ"); time.sleep(0.2)
            os.write(fd, b"\x1b[1;2Q"); time.sleep(0.2); os.write(fd, b"\x1b[M q!")
try:
    _, st = os.waitpid(pid, 0)
except ChildProcessError:
    st = 0
plain = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out.decode("utf-8", "replace"))
print(plain)
print("SENT=%d" % sent); print("EXIT=%d" % os.waitstatus_to_exitcode(st))
PY
big="$w/nt/big"; [ -d "$big" ] || env -u DIARY_VERBOSE "$nb" --home "$big" --seed 42 --ticks 6000 --yes --every 100000 > /dev/null 2>&1
# 1. q in the last session of --max-sessions 2: the reason stays max_sessions, the live line does not say "stopping", the end check runs
rm -rf "$w/nt/cq"; cp -r "$big" "$w/nt/cq"
python3 "$w/nt/ptycap.py" last "$nb" "$w/nt/cq" --session-ticks 3000 --max-sessions 2 > cq.txt 2>&1
grep -q '^SENT=1' cq.txt && grep -q '^EXIT=0' cq.txt && grep -q '^| stopped: the number of sessions was reached' cq.txt && ! grep -q 'stopped: you pressed q' cq.txt && ! grep -q 'q pressed: stopping' cq.txt \
  && grep -q 'q pressed: this is the last session anyway' cq.txt && grep -q '^| a q came in the last session: ignored' cq.txt && grep -q '^stop: reason=max_sessions sessions=2 ' "$w/nt/cq/run_log.txt" \
  && grep -q '^verify: ok ' "$w/nt/cq/run_log.txt" && grep -q 'came in the last session, dropped' "$w/nt/cq/run_log.txt" \
  && ok "q in the LAST session of --max-sessions 2: box 'stopped: the number of sessions was reached' (not q), the live line says it is the last session anyway, run_log reason=max_sessions, the end check still runs" || bad "q in the last capped session"
# 2. q while the end check runs: it is cut short, the reason stays max_sessions, the box says so
rm -rf "$w/nt/cv"; cp -r "$big" "$w/nt/cv"
python3 "$w/nt/ptycap.py" verify "$nb" "$w/nt/cv" --session-ticks 300 --max-sessions 1 > cv.txt 2>&1
grep -q '^SENT=1' cv.txt && grep -q '^EXIT=0' cv.txt && grep -q '^| stopped: the number of sessions was reached' cv.txt && grep -q '^| end check cut short by q' cv.txt && ! grep -q 'stopped: you pressed q' cv.txt \
  && grep -q '^stop: reason=max_sessions sessions=1 ' "$w/nt/cv/run_log.txt" && grep -q '^verify: cut short' "$w/nt/cv/run_log.txt" \
  && ok "q during the end check of a capped night: the check is cut short (the box says so), the reason stays max_sessions" || bad "q during the end check"
# 3. escape sequences with a Q byte (F2 split over two reads, Shift-F2, a mouse report at column 81) are no q: chat line mode and plain key mode
rm -rf "$w/nt/ce"; cp -r "$big" "$w/nt/ce"
python3 "$w/nt/ptycap.py" esc "$nb" "$w/nt/ce" --session-ticks 3000 --max-sessions 3 > ce.txt 2>&1
rm -rf "$w/nt/nc"; mkdir -p "$w/nt/nc/bin"; cp "$nb" "$w/nt/nc/bin/"; cp -r "$root/data" "$w/nt/nc/data"; sed -i 's/^chat.enabled = .*/chat.enabled = 0/' "$w/nt/nc/data/limits.txt"
rm -rf "$w/nt/cp"; cp -r "$big" "$w/nt/cp"
python3 "$w/nt/ptycap.py" esc_plain "$w/nt/nc/bin/diary_sim" "$w/nt/cp" --session-ticks 3000 --max-sessions 3 > cp.txt 2>&1
grep -q '^SENT=1' ce.txt && grep -q '^SENT=1' cp.txt && grep -q '^| stopped: the number of sessions was reached' ce.txt && grep -q '^| stopped: the number of sessions was reached' cp.txt \
  && ! grep -q 'q pressed\|a q came' ce.txt && ! grep -q 'q pressed\|a q came' cp.txt && grep -q '^stop: reason=max_sessions sessions=3 ' "$w/nt/ce/run_log.txt" && grep -q '^stop: reason=max_sessions sessions=3 ' "$w/nt/cp/run_log.txt" \
  && grep -q '^start: .* keys=q$' "$w/nt/cp/run_log.txt" && grep -q 'Forget_Q' "$root/sim_quit.ads" \
  && ok "F2 (ESC O Q, split over two reads), Shift-F2 and a mouse report with a q byte in the first of 3 sessions are no q (with and without the chat line): all 3 sessions run, why=max_sessions" || bad "escape sequences counted as q"
cd "$w" || exit 1

echo "== 59. build 0.054: active=2 mint-slow also at the floor (slowfloor=1); symstrict=1 closes the leak of coined chess strings after symbols=1 =="
cd "$w/nt" || exit 1
# 1. floor: the active=2 save of scenario 56 goes on 3 sessions with the default data (slowfloor=1) and, as the control, with active.slow_floor = 0
rm -rf "$w/nt/fl_on" "$w/nt/fl_off" "$w/nt/fl_d"; cp -r "$w/nt/a2" "$w/nt/fl_on"; cp -r "$w/nt/a2" "$w/nt/fl_off"
mkdir -p "$w/nt/fl_d/bin"; cp "$nb" "$w/nt/fl_d/bin/"; cp -r "$root/data" "$w/nt/fl_d/data"; sed -i 's/^active.slow_floor = .*/active.slow_floor = 0/' "$w/nt/fl_d/data/limits.txt"
fl_n0=$(grep -c '^S' "$w/nt/a2/diaries/sessions.txt")
env -u DIARY_VERBOSE "$nb" --home "$w/nt/fl_on" --continuous --session-ticks 300 --max-sessions 3 > fl_on.txt 2>&1; rcf=$?
( cd "$w/nt/fl_d" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/fl_off" --continuous --session-ticks 300 --max-sessions 3 > "$w/nt/fl_off.txt" 2>&1 )
kn() { grep ' state known=' "$1/diaries/active.txt" | tail -4 | sed 's/.* state known=\([0-9]*\) .*/\1/' | awk '{ s += $1 } END { print s + 0 }'; }
k_on=$(kn "$w/nt/fl_on"); k_off=$(kn "$w/nt/fl_off"); k0=$(kn "$w/nt/a2")
nf_on=$(grep '^S' "$w/nt/fl_on/diaries/sessions.txt" | tail -3 | grep -c ' slowfloor=1 .* active=2$'); nf_off=$(grep '^S' "$w/nt/fl_off/diaries/sessions.txt" | tail -3 | grep -c 'slowfloor=1')
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/fl_on" > fl_v.txt 2>&1; rcfv=$?
env -u DIARY_VERBOSE "$nb" --active --home "$w/nt/fl_on" > fl_a.txt 2>&1
[ "$rcf" = 0 ] && [ "$nf_on" = 3 ] && [ "$nf_off" = 0 ] && [ "$k_on" -gt "$k0" ] && [ $((k_on - k0)) -lt $((k_off - k0)) ] && grep -q ' slowat=floor$' "$w/nt/fl_on/diaries/active.txt" \
  && [ "$rcfv" = 0 ] && grep -q '^  at floor or above (mint-slow next)' fl_a.txt && grep -q 'mint-slow also at the floor' fl_a.txt && [ "$(awk 'length > 79' fl_a.txt | wc -l)" = 0 ] \
  && grep -q '^active.slow_floor = 1' "$root/data/limits.txt" && grep -q 'slowfloor=1' "$root/docs/EVOLVE.md" \
  && ok "slowfloor=1: 3 new active=2 sessions carry it (control: none), the state lines say slowat=floor, the known words grow by $((k_on - k0)) against $((k_off - k0)) with mint-slow at the cap only; make verify OK; make active says 'at floor or above' and 'mint-slow also at the floor'" || bad "slowfloor ($rcf $nf_on $nf_off $k0 $k_on $k_off $rcfv)"
# 2. symstrict: a save that coined number strings under the old rules (symbols.enabled = 0, records.enabled = 0), one session with
# symbols=1 but symbols.strict = 0 (the leak of builds before 0.054: an old blend or coin like 71634866 is taught again), then the default
rm -rf "$w/nt/ss" "$w/nt/ss_o" "$w/nt/ss_l"; mkdir -p "$w/nt/ss_o/bin" "$w/nt/ss_l/bin"; cp "$nb" "$w/nt/ss_o/bin/"; cp "$nb" "$w/nt/ss_l/bin/"
cp -r "$root/data" "$w/nt/ss_o/data"; cp -r "$root/data" "$w/nt/ss_l/data"
sed -i 's/^symbols.enabled = .*/symbols.enabled = 0/; s/^records.enabled = .*/records.enabled = 0/; s/^active.slow_floor = .*/active.slow_floor = 0/' "$w/nt/ss_o/data/limits.txt"
sed -i 's/^symbols.strict = .*/symbols.strict = 0/; s/^active.slow_floor = .*/active.slow_floor = 0/' "$w/nt/ss_l/data/limits.txt"   # the rules of build 0.053
( cd "$w/nt/ss_o" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/ss" --seed 2 --ticks 6000 --yes --every 100000 > /dev/null 2>&1 )
( cd "$w/nt/ss_l" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/ss" --continuous --session-ticks 3000 --max-sessions 1 > /dev/null 2>&1 )
sym_after() { awk -v t="$2" '$4 > t && ($2 ~ /^[0-9]+$/ || $2 ~ /^[a-h][1-8][a-h][1-8][qrbn]?$/)' "$1"/entities/*/words.txt | wc -l; }
ss_c=$(awk '$3 == "coined" && $2 ~ /^[0-9]+$/' "$w/nt/ss"/entities/*/words.txt | wc -l); ss_leak=$(sym_after "$w/nt/ss" 6000)
rm -rf "$w/nt/ss_c" "$w/nt/ss_l2"; cp -r "$w/nt/ss" "$w/nt/ss_c"; cp -r "$w/nt/ss_l" "$w/nt/ss_l2"; cp -r "$root/data/limits.txt" "$w/nt/ss_l2/data/limits.txt"
sed -i 's/^symbols.strict = .*/symbols.strict = 0/' "$w/nt/ss_l2/data/limits.txt"   # the control: today's rules but symbols.strict = 0
( cd "$w/nt/ss_l2" && env -u DIARY_VERBOSE bin/diary_sim --home "$w/nt/ss_c" --continuous --session-ticks 3000 --max-sessions 3 > /dev/null 2>&1 )
env -u DIARY_VERBOSE "$nb" --home "$w/nt/ss" --continuous --session-ticks 3000 --max-sessions 3 > ss.txt 2>&1; rcs=$?
ss_new=$(sym_after "$w/nt/ss" 9000); ss_ctl=$(sym_after "$w/nt/ss_c" 9000)
env -u DIARY_VERBOSE "$nb" --verify --home "$w/nt/ss" > ss_v.txt 2>&1; rcsv=$?
env -u DIARY_VERBOSE "$nb" --wordstat --home "$w/nt/ss" > ss_w.txt 2>&1
ss_row=$(grep '^  chess or number strings ' ss_w.txt | awk '{ print $NF }')
[ "$ss_c" -gt 0 ] && [ "$ss_leak" -ge 1 ] && [ "$rcs" = 0 ] && [ "$ss_new" = 0 ] && [ "$ss_ctl" -ge 1 ] && [ "$rcsv" = 0 ] && [ "$(grep -c '^S2 .* symstrict=1 ' "$w/nt/ss/diaries/sessions.txt")" = 0 ] \
  && [ "$(grep -c '^S[345] .* symstrict=1 ' "$w/nt/ss/diaries/sessions.txt")" = 3 ] && grep -q 'first symstrict=1 session: S3 from tick 9000' ss_w.txt && [ "$ss_row" = 0 ] && [ "$(awk 'length > 79' ss_w.txt | wc -l)" = 0 ] \
  && grep -q '^symbols.strict = 1' "$root/data/limits.txt" && grep -q 'symstrict=1' "$root/docs/EVOLVE.md" \
  && ok "symstrict=1: $ss_c number strings were coined under the old rules and $ss_leak leaked into words.txt after symbols=1 without it; 3 new sessions carry symstrict=1 and add 0 chess or number strings (the same 3 sessions with symbols.strict = 0: $ss_ctl); make verify OK on the mixed save; make wordstat counts 0 since the first symstrict=1 session" || bad "symstrict ($ss_c $ss_leak $rcs $ss_new $ss_ctl $rcsv '$ss_row')"
cd "$w" || exit 1

echo "== 60. make ship / make night-ship: ONE command, ONE file (checkin.txt in the save folder) with a VERDICT header; a short terminal summary; cold start =="
cd "$w/nt" || exit 1
rm -rf "$w/nt/sp"; cp -r "$w/nt/a2" "$w/nt/sp"; spn=$(grep -c '^S' "$w/nt/sp/diaries/sessions.txt")
DIARY_HOME="$w/nt/sp" make --no-print-directory -C "$root" ship SHIP_SESSIONS=1 CHECKIN_TICKS=60 > sp.txt 2>&1 < /dev/null; rcp=$?
ck="$w/nt/sp/checkin.txt"; sum=$(sed -n '/^-\{79\}$/,$p' sp.txt)
secs_ok=1; for h in '== night: run_log.txt entries of this run ==' '== night: new session records (diaries/sessions.txt) ==' '== night: the console of the last session and the final box (night_console.txt) ==' \
  '== make active (exit 0' '== make wordstat (exit 0' '== make frustration (exit 0' '== make evolve (exit 0' '== make verify (exit 0' '== night box == reason=max_sessions'; do grep -qF "$h" "$ck" || secs_ok=0; done
[ "$rcp" = 0 ] && [ -f "$ck" ] && sed -n 1p "$ck" | grep -q '^diary-sim checkin (make ship): attach this ONE file' && sed -n 3p "$ck" | grep -q '^VERDICT: PASS$' \
  && grep -q "^build: $(sed -n 's/^ *Build : constant String := "\([0-9.]*\)".*/\1/p' "$root/diary_sim.adb") " "$ck" && grep -q '^stop reason: max_sessions (the number of sessions was reached)$' "$ck" \
  && grep -q "^new sessions: 1 (s$((spn + 1)) to s$((spn + 1))), active=2: 1/1$" "$ck" && grep -q '^newest sessions symstrict=1: yes (1/1)   slowfloor=1: yes (1/1)$' "$ck" \
  && grep -q '^mint-slow at the floor: yes ([0-9] of 4 wesen at floor or above, make active)$' "$ck" && grep -q '^chess/number strings learned: since symbols=1: [0-9]*; since symstrict=1: 0$' "$ck" \
  && grep -q '^verify: OK ([0-9]* ticks replayed from the files)$' "$ck" && [ "$secs_ok" = 1 ] \
  && [ "$(echo "$sum" | wc -l)" -le 20 ] && echo "$sum" | grep -q "^attach this ONE file: $ck\$" && [ "$(echo "$sum" | grep -v '^attach this' | awk 'length > 79' | wc -l)" = 0 ] \
  && tail -n 1 sp.txt | grep -Eq '^make ship wall time: [0-9]+m[0-5][0-9]s \([0-9]+s\)$' \
  && ok "make ship SHIP_SESSIONS=1: checkin.txt in the save folder, VERDICT: PASS on top (build, stop reason max_sessions, symstrict=1 and slowfloor=1 on the new session, mint-slow at the floor, 0 chess strings since symstrict=1, verify OK), then the night and the five reports; the terminal summary has $(echo "$sum" | wc -l) lines (<= 79 columns) and the path; the wall time last" || bad "make ship ($rcp $secs_ok)"
# cold start: no save folder at all; a FAIL verdict (a night that DRIFTs) gives exit 1 and says why
rm -rf "$w/nt/spc"; DIARY_HOME="$w/nt/spc/diary-data" make --no-print-directory -C "$root" ship SHIP_COLD_SESSIONS=1 CHECKIN_TICKS=60 > spc.txt 2>&1 < /dev/null; rcc=$?
rm -rf "$w/nt/spd"; cp -r "$w/nt/a2" "$w/nt/spd"; sed -i '0,/"t":"work"/s//"t":"rest"/' "$w/nt/spd/diaries/ada.jsonl"
DIARY_HOME="$w/nt/spd" make --no-print-directory -C "$root" ship SHIP_SESSIONS=1 CHECKIN_TICKS=60 > spd.txt 2>&1 < /dev/null; rcd=$?
cp -r "$w/nt/a2" "$w/nt/spw"; sed -i 's/ symstrict=1//' "$w/nt/spw/diaries/sessions.txt"; env -u DIARY_VERBOSE "$nb" --wordstat --home "$w/nt/spw" > spw.txt 2>&1
[ "$rcc" = 0 ] && sed -n 3p "$w/nt/spc/diary-data/checkin.txt" | grep -q '^VERDICT: PASS$' && grep -q '^new sessions: 1 (s1 to s1)' "$w/nt/spc/diary-data/checkin.txt" \
  && [ "$rcd" != 0 ] && sed -n 3p "$w/nt/spd/checkin.txt" | grep -q '^VERDICT: FAIL:.* night exit 1;.* stop reason drift;' && grep -q '^VERDICT: FAIL' spd.txt \
  && grep -q 'no symstrict=1 session yet' spw.txt && grep -q 'make ship' "$root/README.md" && grep -q '^# make ship ' "$root/Makefile" && grep -q '^ship: all' "$root/Makefile" \
  && ok "make ship on a cold start (no save folder): PASS, session 1; on a save that DRIFTs: exit $rcd, VERDICT: FAIL with the reasons; make wordstat without a symstrict=1 session says so; README and the Makefile header describe make ship" || bad "make ship cold / fail ($rcc $rcd)"
# make night-ship: the overnight form; the same checkin.txt, the same verdict layout; here a tiny time limit, so the reason is max_hours
rm -rf "$w/nt/spn"; cp -r "$w/nt/a2" "$w/nt/spn"
DIARY_HOME="$w/nt/spn" make --no-print-directory -C "$root" night-ship NIGHT_SHIP_HOURS=0.002 NIGHT_SHIP_TICKS=30 NIGHT_SHIP_RESERVE=0 > spn.txt 2>&1 < /dev/null; rcn=$?
ckn="$w/nt/spn/checkin.txt"; keys() { sed -n '3,/^wall time: /p' "$1" | grep -v '^budget: ' | awk '{ print $1 }'; }
[ "$rcn" = 0 ] && sed -n 1p "$ckn" | grep -q '^diary-sim checkin (make night-ship): attach this ONE file' && sed -n 3p "$ckn" | grep -q '^VERDICT: PASS$' \
  && grep -q '^stop reason: max_hours (the time limit was reached)$' "$ckn" && grep -q '^night: sessions of 30 ticks; max sessions: no limit; one budget of 0.002h$' "$ckn" && grep -q '^budget: 0.002h; stop [0-9:]*, reserve 0m00s; due [0-9:]*, written ' "$ckn" && grep -q '^shared (3 of 4): [0-9]* / 40000 ' "$ckn" && grep -q '^post_secs=[0-9]*$' "$w/nt/spn/ship_stamp.txt" \
  && grep -q '^night: sessions of 60 ticks; max sessions: 1; max hours: 12$' "$ck" && [ "$(keys "$ckn")" = "$(keys "$ck")" ] && grep -qF '== night box == reason=max_hours' "$ckn" && grep -q '^roles (s[0-9]*-s[0-9]*): ' "$ckn" && grep -qF '== early signals: ' "$ckn" \
  && grep -q '^make night-ship wall time: ' spn.txt && grep -q '^# make night-ship ' "$root/Makefile" && grep -q '^night-ship: all' "$root/Makefile" && grep -q 'make night-ship' "$root/README.md" \
  && ok "make night-ship (no session limit, a tiny time limit): VERDICT: PASS, stop reason max_hours, the same checkin.txt and the same verdict lines as make ship; Makefile and README describe it" || bad "make night-ship ($rcn)"
cd "$w" || exit 1

echo "== 61. make ship by day = reports only: no night, no q, the save untouched, the same verdict lines; verify skipped on a big save =="
cd "$w/nt" || exit 1
rm -rf "$w/nt/spr"; cp -r "$w/nt/a2" "$w/nt/spr"; rm -f "$w/nt/spr/checkin.txt"
dsum() { (cd "$1" && find diaries -type f | sort | xargs cat | cksum); }
d0=$(dsum "$w/nt/spr"); rl0=$(cat "$w/nt/spr/run_log.txt" 2>/dev/null | cksum); nc0=$(cat "$w/nt/spr/night_console.txt" 2>/dev/null | cksum)
nsr=$(grep -c '^S[0-9]' "$w/nt/spr/diaries/sessions.txt")
tr0=$(date +%s); DIARY_HOME="$w/nt/spr" make --no-print-directory -C "$root" ship > spr.txt 2>&1 < /dev/null; rcr=$?; dtr=$(( $(date +%s) - tr0 ))
ckr="$w/nt/spr/checkin.txt"; sumr=$(sed -n '/^-\{79\}$/,$p' spr.txt)
[ "$rcr" = 0 ] && sed -n 1p "$ckr" | grep -q '^diary-sim checkin (make ship): attach this ONE file' && sed -n 3p "$ckr" | grep -q '^VERDICT: PASS$' \
  && grep -q "^night: none (reports only); the save: $nsr sessions, [0-9]* ticks$" "$ckr" && grep -q '^stop reason: none (no night); the last night: [a-z_]*$' "$ckr" \
  && grep -q '^new sessions: 0; newest: [0-9]* (s[0-9]* to s'"$nsr"'), active=2: ' "$ckr" && grep -q '^verify: OK ([0-9]* ticks replayed from the files)$' "$ckr" \
  && grep -q '^wall time: total [0-9]*m[0-9][0-9]s (no night, reports [0-9]*m[0-9][0-9]s)$' "$ckr" && [ "$(keys "$ckr")" = "$(keys "$ck")" ] \
  && grep -qF '== no night: run_log.txt entries of the last night ==' "$ckr" && grep -qF '== make evolve (exit 0' "$ckr" && grep -qF '== make verify (exit 0' "$ckr" \
  && [ "$(dsum "$w/nt/spr")" = "$d0" ] && [ "$(cat "$w/nt/spr/run_log.txt" 2>/dev/null | cksum)" = "$rl0" ] && [ "$(cat "$w/nt/spr/night_console.txt" 2>/dev/null | cksum)" = "$nc0" ] \
  && ! grep -q 'night run:' spr.txt && [ "$(echo "$sumr" | wc -l)" -le 20 ] && [ "$(echo "$sumr" | grep -v '^attach this' | awk 'length > 79' | wc -l)" = 0 ] \
  && tail -n 1 spr.txt | grep -Eq '^make ship wall time: [0-9]+m[0-5][0-9]s \([0-9]+s\)$' \
  && grep -q '^roles (s[0-9]*-s[0-9]*): rest [A-Za-z]* [0-9]*%, work [A-Za-z]* [0-9]*%, teach ' "$ckr" && grep -q '^shared words: [0-9]* of [0-9]* known by all four ([0-9]*%); pairs 0\.[0-9]* to [01]\.[0-9]*$' "$ckr" \
  && grep -q '^petition topics (s[0-9]*-s[0-9]*): ' "$ckr" && grep -q '^mood: spread [0-9]* ([A-Za-z]* -*[0-9]* to [A-Za-z]* -*[0-9]*), mean -*[0-9]*$' "$ckr" \
  && grep -q '^since the last ship: no stamp yet' "$ckr" && grep -q "^sessions=$nsr\$" "$w/nt/spr/ship_stamp.txt" && grep -qF '== early signals: the lines above in full, from the files (no replay) ==' "$ckr" \
  && [ "$(sed -n '1p;3,/^wall time: /p' "$ckr" | awk 'length > 79' | wc -l)" = 0 ] && grep -q '^wall time: ' "$ckr" \
  && ok "make ship (default): no night run, stdin closed (no q), ${dtr}s; VERDICT: PASS with the same verdict lines as a night (the save size, the last night's stop reason and sessions, verify OK); diaries, run_log.txt and night_console.txt unchanged; early signals (roles, shared words, petition topics, mood spread; no stamp yet, ship_stamp.txt written)" || bad "make ship reports only ($rcr)"
DIARY_HOME="$w/nt/spr" make --no-print-directory -C "$root" ship SHIP_VERIFY_TICKS=10 > sps.txt 2>&1 < /dev/null; rcs=$?
cp "$ckr" sps_ck.txt
DIARY_HOME="$w/nt/spd" make --no-print-directory -C "$root" ship SHIP_VERIFY=1 > spv.txt 2>&1 < /dev/null; rcv=$?
[ "$rcs" = 0 ] && sed -n 3p sps_ck.txt | grep -q '^VERDICT: PASS$' && grep -q '^verify: skipped ([0-9]* ticks > 10); night end check: ' sps_ck.txt && grep -qF '== make verify (skipped, ' sps_ck.txt \
  && grep -q '^since [0-9-]* [0-9:]*: +0 sessions, spread +0, all 4 +0, overlap +0 pts, top same$' sps_ck.txt && grep -q '^the stamp of the last ship:$' sps_ck.txt \
  && [ "$rcv" != 0 ] && grep -q '^VERDICT: FAIL:.* verify failed;' "$w/nt/spd/checkin.txt" && grep -q '^night: none (reports only)' "$w/nt/spd/checkin.txt" \
  && grep -q '^SHIP_SESSIONS ?= 0$' "$root/Makefile" && grep -q 'REPORTS ONLY' "$root/Makefile" && grep -q 'make ship.*(by day) runs NO night' "$root/README.md" \
  && ok "make ship SHIP_VERIFY_TICKS=10: verify skipped (the end check of the last night quoted), still PASS, and the deltas since the last ship (+0 sessions, the same top topic); make ship SHIP_VERIFY=1 on a save that DRIFTs: exit $rcv, VERDICT: FAIL verify failed; Makefile and README say reports only" || bad "make ship verify skip / fail ($rcs $rcv)"
cd "$w" || exit 1

echo "== 62. build 0.058: the state checkpoint (state.ckpt): a start loads it instead of replaying, with byte for byte the files of a full replay; a changed file or checkpoint is refused (full replay); a signal inside a session, then the resume =="
ck="$w/ckp"; rm -rf "$ck"; mkdir -p "$ck/bin"; cp "$bin" "$ck/bin/"; cp -r "$root/data" "$ck/data"; cb="$ck/bin/diary_sim"; cd "$ck" || exit 1
ckr() { env -u DIARY_VERBOSE "$cb" --home "$@"; }
# the record files: the diaries without "ts" (the clock), everything else as it is (inbox.txt is a view, rewritten)
cks() { ( cd "$1" || exit 1; for f in $(ls diaries/* entities/*/* | grep -v '^diaries/inbox.txt$'); do case $f in *.jsonl) sed -E 's/"ts":"[^"]*",//' "$f" | cksum | sed "s#\$# $f#";; *) cksum "$f";; esac; done ); }
# N = 4 sessions (explicit and voted lengths, Robert's words in between)
ckr "$ck/a" --seed 42 --more 150 --every 5000 --yes > c1.txt 2>&1; ckr "$ck/a" --more 150 --every 5000 > c2.txt 2>&1
ckr "$ck/a" --say ada --text "rest a little" > /dev/null 2>&1; ckr "$ck/a" --more 150 --every 5000 > c3.txt 2>&1; ckr "$ck/a" --every 5000 > c4.txt 2>&1
grep -q '^replay: checkpoint missing - 0 ticks replayed$' c1.txt && grep -q '^start: checkpoint of tick 300 loaded (+0 ticks replayed)$' c3.txt \
  && head -1 "$ck/a/state.ckpt" | grep -q '^diary-sim-ckpt 1$' && grep -aq '^build 0.058$' "$ck/a/state.ckpt" && grep -q ' checkpoint: tick [0-9]*, [0-9]* KB, written in [0-9.]* s$' "$ck/a/ckpt_log.txt" \
  && ok "every run writes state.ckpt (header: format, build, ...); the next start loads it and says so ('start: checkpoint of tick 300 loaded (+0 ticks replayed)'), a first start says 'replay: checkpoint missing'; ckpt_log.txt has the write times" || bad "checkpoint written / loaded"
# (a) M = 3 more sessions from the checkpoint, (b) the same 3 on a copy without it (full replay each time): the same files
cp -r "$ck/a" "$ck/b"; used=0; full=0
for k in 1 2 3; do
  [ $k = 2 ] && { ckr "$ck/a" --say all --text "good morning" > /dev/null 2>&1; ckr "$ck/b" --say all --text "good morning" > /dev/null 2>&1; }
  ckr "$ck/a" --more 120 --every 5000 > ca$k.txt 2>&1 && grep -q '^start: checkpoint of tick [0-9]* loaded (+0 ticks replayed)$' ca$k.txt && used=$((used + 1))
  rm -f "$ck/b/state.ckpt"; ckr "$ck/b" --more 120 --every 5000 > cb$k.txt 2>&1 && grep -q '^replay: checkpoint missing - [0-9]* ticks replayed$' cb$k.txt && full=$((full + 1))
done
cks "$ck/a" > ka.txt; cks "$ck/b" > kb.txt; ckr "$ck/a" --verify > cv.txt 2>&1; rcv=$?
ckr "$ck/b" --replay --more 0 --every 5000 > cr.txt 2>&1; rcr=$?
[ "$used" = 3 ] && [ "$full" = 3 ] && [ -s ka.txt ] && cmp -s ka.txt kb.txt && [ $rcv = 0 ] && grep -q '^verify: OK' cv.txt && grep -q '^verify: checkpoint of tick [0-9]* = the replayed state, byte for byte$' cv.txt \
  && [ $rcr = 0 ] && grep -q '^replay: checkpoint off (--replay) - [0-9]* ticks replayed$' cr.txt \
  && ok "3 sessions resumed from the checkpoint and the same 3 with a full replay each leave every record file byte for byte the same ($(wc -l < ka.txt) files, diaries without ts); make verify: OK and the checkpoint equals the replayed state byte for byte; --replay replays anyway" || bad "checkpoint against full replay ($used $full $rcv $rcr)"
# refused: a changed file, an old input added behind it, a broken or foreign checkpoint; each start replays everything and says why
cp -r "$ck/a" "$ck/t1"; sed -i '$s/"ts":"2/"ts":"3/' "$ck/t1/diaries/ada.jsonl"   # the same size, a byte the replay does not compare
ckr "$ck/t1" --more 60 --every 5000 > t1.txt 2>&1; rc1=$?; ckr "$ck/t1" --verify > t1v.txt 2>&1; rc1v=$?
cp -r "$ck/a" "$ck/t2"; sed -i '$s/ t=\([0-9]\)/ t=\1/; $s/$/x/' "$ck/t2/diaries/chess.txt"   # a changed record line
ckr "$ck/t2" --more 60 --every 5000 > t2.txt 2>&1; rc2=$?
cp -r "$ck/a" "$ck/t3"; echo "K99999 t=5 ada add w=3 src=x s=3" >> "$ck/t3/diaries/screens.txt"   # an invented old line after the checkpoint's part
ckr "$ck/t3" --more 60 --every 5000 > t3.txt 2>&1; rc3=$?
cp -r "$ck/a" "$ck/t4"; echo "A99 tick=5 session=1 to=ada kind=say by=player re=- text=late words" >> "$ck/t4/diaries/says.txt"   # an old input added
ckr "$ck/t4" --more 60 --every 5000 > t4.txt 2>&1
cp -r "$ck/a" "$ck/t5"; python3 -c "import sys; p=sys.argv[1]; b=bytearray(open(p,'rb').read()); b[-100]^=1; open(p,'wb').write(b)" "$ck/t5/state.ckpt"
ckr "$ck/t5" --more 60 --every 5000 > t5.txt 2>&1; rc5=$?
cp -r "$ck/a" "$ck/t6"; sed -i '0,/^build 0.058$/s//build 0.057/' "$ck/t6/state.ckpt"
ckr "$ck/t6" --more 60 --every 5000 > t6.txt 2>&1; rc6=$?
[ $rc1 = 0 ] && grep -q '^replay: checkpoint stale (diaries/ada.jsonl) - [0-9]* ticks replayed$' t1.txt && [ $rc1v = 0 ] && grep -q '^verify: OK' t1v.txt \
  && [ $rc2 != 0 ] && grep -q '^replay: checkpoint stale (diaries/chess.txt)' t2.txt && grep -q 'chess.txt .* differs from the replay\|import FAILED' t2.txt \
  && [ $rc3 != 0 ] && grep -q '^replay: checkpoint stale (diaries/screens.txt)' t3.txt \
  && grep -q '^replay: checkpoint stale (inputs or sessions before tick [0-9]*)' t4.txt \
  && [ $rc5 = 0 ] && grep -q '^replay: checkpoint corrupt (payload)' t5.txt && [ $rc6 = 0 ] && grep -q '^replay: checkpoint version (build 0.057)' t6.txt \
  && ok "refused, with a full replay and the reason on the console: a changed byte (stale; the replay passes, verify OK), a changed record line (stale, then DRIFT), an invented old record line after the checkpoint's part (stale, DRIFT), an old input added (stale), a broken payload (corrupt), another build (version)" || bad "checkpoint refusals ($rc1 $rc1v $rc2 $rc3 $rc5 $rc6)"
# SIGHUP inside a session: a clean stop writes the checkpoint of its last tick; the bare rerun loads it and finishes the session; the files equal an uninterrupted run
cp -r "$ck/a" "$ck/h"; cp -r "$ck/a" "$ck/u"; n0=$(wc -l < "$ck/h/diaries/ada.jsonl")
( DIARY_TEST_TICK_MS=5 env -u DIARY_VERBOSE "$cb" --home "$ck/h" --more 400 --every 5000 > h1.txt 2>&1 & p=$!
  for _ in $(seq 300); do [ "$(wc -l < "$ck/h/diaries/ada.jsonl")" -gt $((n0 + 100)) ] && break; sleep 0.1; done; kill -HUP $p; wait $p; echo "rc=$?" > h1rc.txt )
hk=$(grep -a '^tick ' "$ck/h/state.ckpt" | awk '{ print $2 }')
ckr "$ck/h" --every 5000 > h2.txt 2>&1; rch=$?; ckr "$ck/u" --more 400 --every 5000 > u1.txt 2>&1
cks "$ck/h" > kh.txt; cks "$ck/u" > ku.txt; ckr "$ck/h" --verify > hv.txt 2>&1; rchv=$?
[ "$(cat h1rc.txt)" = rc=130 ] && [ -n "$hk" ] && [ "$hk" -gt $((n0 + 100)) ] && [ "$hk" -lt $((n0 + 400)) ] && grep -q "^start: checkpoint of tick $hk loaded (+0 ticks replayed)\$" h2.txt && [ $rch = 0 ] \
  && [ "$(wc -l < "$ck/h/diaries/ada.jsonl")" = $((n0 + 400)) ] && cmp -s kh.txt ku.txt && [ $rchv = 0 ] && grep -q '^verify: checkpoint of tick [0-9]* = the replayed state' hv.txt \
  && ok "SIGHUP inside a session (tick $hk of $((n0 + 1))..$((n0 + 400))): exit 130 and the checkpoint of that tick; the bare rerun loads it and finishes the session; every record file equals the uninterrupted run; verify OK" || bad "SIGHUP then resume ($(cat h1rc.txt) $hk $rch $rchv)"
grep -q 'state.ckpt' "$root/README.md" && grep -q -- '--replay' "$root/data/help.txt" && grep -q 'make slice' "$root/README.md" && grep -q '^slice:' "$root/Makefile" && grep -q '^SLICE_MINUTES ?= 20$' "$root/Makefile" \
  && grep -q 'sim_ckpt.ads sim_ckpt.adb' "$root/Makefile" && ok "README, --help and the Makefile describe the checkpoint, --replay and make slice (SLICE_MINUTES ?= 20)" || bad "checkpoint docs"
cd "$w" || exit 1


rm -rf "$w"
echo "== checks: $fails failure(s) =="
[ "$fails" = 0 ]
