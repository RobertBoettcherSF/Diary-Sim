#!/bin/sh
# Version: 0.001
# make ship (day, ~40 sessions) and make night-ship (overnight, a time limit): Robert's ONE command.  A night of <sessions> sessions
# (0 = no limit) of <ticks> ticks, at most <hours> hours (empty = night.max_hours, 12), on the terminal (the live screen as with make
# night; no q needed), then make active, wordstat, frustration, evolve and verify into files; everything goes into ONE file, checkin.txt in the
# save folder (../diary-data next to the source folder, or --home / $DIARY_HOME: bin/diary_sim --folder says where), with a VERDICT
# header at the top; the terminal gets a short summary and the path of the one file to attach.  Exit status 0 = PASS, 1 = FAIL.
# Both write the same checkin.txt with the same verdict header (only the length of the night differs).
# Usage (from the source folder): scripts/ship.sh <ship|night-ship> <sessions> <ticks> <hours or ""> <make start, seconds since 1970> [seed]
exe=bin/diary_sim
mode=${1:-ship}; sessions=${2:-40}; ticks=${3:-300}; hours=$4; t0=${5:-$(date +%s)}; seed=$6
build=$(sed -n 's/^ *Build : constant String := "\([0-9.]*\)".*/\1/p' diary_sim.adb)
folder=$("$exe" --folder) || { echo "ship: cannot find the save folder" >&2; exit 1; }
mkdir -p "$folder" || exit 1
out="$folder/checkin.txt"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'stopped=1' INT   # Ctrl-C stops the night cleanly (it gets the signal too); checkin.txt is still written
stopped=0
cnt() { if [ -f "$1" ]; then grep -c "$2" "$1"; else echo 0; fi; }   # a count, 0 without the file
secs() { s=$1; printf '%dm%02ds' $((s / 60)) $((s % 60)); }
ses="$folder/diaries/sessions.txt"; rl="$folder/run_log.txt"; con="$folder/night_console.txt"; tr="$folder/trend.txt"
s0=$(cnt "$ses" '^S[0-9]'); r0=$(if [ -f "$rl" ]; then wc -l < "$rl"; else echo 0; fi); t_0=$(if [ -f "$tr" ]; then wc -l < "$tr"; else echo 0; fi)
touch "$tmp/stamp"

if [ "$sessions" = 0 ]; then n_txt="no limit"; else n_txt="$sessions"; fi
night_txt="sessions of $ticks ticks; max sessions: $n_txt; max hours: ${hours:-12}"
echo "=== make $mode (build $build): $night_txt ==="
echo "save folder: $folder"
tn=$(date +%s)
set -- --continuous --session-ticks "$ticks" --max-sessions "$sessions"
[ -n "$hours" ] && set -- "$@" --max-hours "$hours"
[ -n "$seed" ] && set -- "$@" --seed "$seed"
"$exe" "$@"; rcn=$?
dn=$(( $(date +%s) - tn ))
echo "=== make $mode: reports (active, wordstat, frustration, evolve, verify) into checkin.txt ==="
for x in active wordstat frustration evolve verify; do
  ts=$(date +%s)
  if [ "$x" = verify ] && [ "$stopped" = 1 ]; then echo "skipped: the night was stopped with Ctrl-C" > "$tmp/$x.txt"; echo 130 > "$tmp/$x.rc"
  else "$exe" --"$x" > "$tmp/$x.txt" 2>&1; echo $? > "$tmp/$x.rc"; fi
  echo $(( $(date +%s) - ts )) > "$tmp/$x.secs"
done

# ---- the verdict ----------------------------------------------------------------------------------------------------------------
tail -n +$((r0 + 1)) "$rl" 2>/dev/null > "$tmp/runlog.txt"
reason=$(sed -n 's/^stop: reason=\([a-z_]*\) .*/\1/p' "$tmp/runlog.txt" | tail -n 1)
box_why=""; [ -f "$con" ] && [ "$con" -nt "$tmp/stamp" ] && box_why=$(sed -n 's/^stopped: //p' "$con" | tail -n 1)
grep '^S[0-9]' "$ses" 2>/dev/null | tail -n +$((s0 + 1)) > "$tmp/new.txt"
nn=$(wc -l < "$tmp/new.txt" | tr -d ' ')
first=$(head -n 1 "$tmp/new.txt" | cut -d' ' -f1 | tr -d S); last=$(tail -n 1 "$tmp/new.txt" | cut -d' ' -f1 | tr -d S)
n_strict=$(grep -c ' symstrict=1' "$tmp/new.txt"); n_floor=$(grep -c ' slowfloor=1' "$tmp/new.txt"); n_a2=$(grep -c ' active=2' "$tmp/new.txt")
yn() { if [ "$nn" -gt 0 ] && [ "$1" = "$nn" ]; then echo "yes ($1/$nn)"; elif [ "$1" -gt 0 ]; then echo "partly ($1/$nn)"; else echo "no (0/$nn)"; fi; }
act=$(tr '\n' ' ' < "$tmp/active.txt" | tr -s ' ')
if echo "$act" | grep -q 'mint-slow also at the floor'; then
  nf=$(echo "$act" | sed -n 's/.*the same percents): \([0-9]*\) of the four wesen held at least the floor.*/\1/p')
  floor="yes ($nf of 4 wesen at floor or above, make active)"
elif echo "$act" | grep -q 'mint-slow'; then floor="no (mint-slow at the cap only, make active)"
else floor="no (no active=2 state yet, make active)"; fi
ws_sym=$(grep '^  of those, chess or number strings ' "$tmp/wordstat.txt" | awk '{ print $NF }')
ws_str=$(grep '^  chess or number strings ' "$tmp/wordstat.txt" | awk '{ print $NF }')
if [ -n "$ws_str" ]; then strict_txt="since symstrict=1: $ws_str"; elif grep -q 'no symstrict=1 session yet' "$tmp/wordstat.txt"; then strict_txt="no symstrict=1 session yet"; else strict_txt="since symstrict=1: -"; fi
vrc=$(cat "$tmp/verify.rc"); vt=$(sed -n 's/^verify: OK, \([0-9]*\) ticks.*/\1/p' "$tmp/verify.txt" | head -n 1)
if [ "$vrc" = 0 ]; then ver="OK (${vt:-?} ticks replayed from the files)"; else ver="FAILED (exit $vrc) $(grep -m 1 -i 'drift\|differs\|failed\|skipped' "$tmp/verify.txt" | cut -c1-60)"; fi
why=""
[ "$rcn" = 0 ] || why="$why night exit $rcn;"
case $reason in max_sessions|max_hours) ;; *) why="$why stop reason ${reason:-none};" ;; esac
[ "$nn" -gt 0 ] || why="$why no new session;"
[ "$vrc" = 0 ] || why="$why verify failed;"
[ -z "$ws_str" ] || [ "$ws_str" = 0 ] || why="$why $ws_str chess strings since symstrict=1;"
if [ -z "$why" ]; then verdict=PASS; else verdict="FAIL:$why"; fi
total=$(( $(date +%s) - t0 ))
{
  echo "VERDICT: $verdict"
  echo "build: $build   made: $(date '+%Y-%m-%d %H:%M:%S') (local)   make $mode"
  echo "night: $night_txt"
  echo "stop reason: ${reason:-none}${box_why:+ ($box_why)}"
  if [ "$nn" -gt 0 ]; then echo "new sessions: $nn (s$first to s$last), active=2: $n_a2/$nn"; else echo "new sessions: 0"; fi
  echo "newest sessions symstrict=1: $(yn "$n_strict")   slowfloor=1: $(yn "$n_floor")"
  echo "mint-slow at the floor: $floor"
  echo "chess/number strings learned: since symbols=1: ${ws_sym:--}; $strict_txt"
  echo "verify: $ver"
  echo "wall time: total $(secs $total) (night $(secs $dn))"
} > "$tmp/verdict.txt"

# a long night (make night-ship) keeps checkin.txt small: the first 40 and the last 240 lines of a section, the rest is in the save
clip() { n=$(wc -l < "$1" | tr -d ' ')
  if [ "$n" -le 300 ]; then cat "$1"
  else head -n 40 "$1"; echo "... $((n - 280)) lines left out here (all of them are in $2) ..."; tail -n 240 "$1"; fi; }
[ -f "$tr" ] && tail -n +$((t_0 + 1)) "$tr" | grep '^T ' > "$tmp/trend.txt"; touch "$tmp/trend.txt"

# ---- checkin.txt: the verdict, then everything ----------------------------------------------------------------------------------
{
  echo "diary-sim checkin (make $mode): attach this ONE file"
  echo "save folder: $folder"
  cat "$tmp/verdict.txt"
  echo "================================================================================"
  echo "== night: run_log.txt entries of this run =="
  clip "$tmp/runlog.txt" run_log.txt
  echo "== night: new session records (diaries/sessions.txt) =="
  clip "$tmp/new.txt" diaries/sessions.txt
  echo "== night: trend.txt lines of the new sessions =="
  [ -f "$tr" ] && head -n 1 "$tr" && clip "$tmp/trend.txt" trend.txt
  echo "== night: the console of the last session and the final box (night_console.txt) =="
  if [ -f "$con" ] && [ "$con" -nt "$tmp/stamp" ]; then cat "$con"; else echo "(not written by this night)"; fi
  for x in active wordstat frustration evolve verify; do
    echo "== make $x (exit $(cat "$tmp/$x.rc"), $(secs "$(cat "$tmp/$x.secs")")) =="
    cat "$tmp/$x.txt"
  done
  echo "== end of checkin.txt =="
} > "$out"

echo "-------------------------------------------------------------------------------"
cat "$tmp/verdict.txt"
echo "attach this ONE file: $out"
[ "$verdict" = PASS ]
