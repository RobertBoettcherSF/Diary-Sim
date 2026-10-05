#!/bin/sh
# Version: 0.002
# make ship (by day) and make night-ship (overnight): Robert's ONE command; both write ONE file, checkin.txt in the save folder
# (../diary-data next to the source folder, or --home / $DIARY_HOME: bin/diary_sim --folder says where), with the same VERDICT header
# on top, and print a short summary and the path of that file.  Exit status 0 = PASS, 1 = FAIL.
# make ship: REPORTS ONLY by default (no night, no q, seconds): make active, wordstat, frustration, evolve on the save as it is, and
#   make verify only if the save has at most <verify ticks> ticks (verify replays the whole history; a big save would take minutes;
#   the end check of the last night is quoted instead).  <sessions> > 0 adds that many new sessions of <ticks> ticks first (the run
#   replays the whole history once before the first new one, so that costs replay time too).  An empty save (cold start) gets
#   <cold sessions> sessions first, so there is something to report.
# make night-ship: a night of <sessions> sessions (0 = no limit) of <ticks> ticks, at most <hours> hours, on the terminal (the live
#   screen of make night; no q needed), then the same reports, verify always.
# Usage (from the source folder):
#   scripts/ship.sh <ship|night-ship> <sessions> <ticks> <hours or ""> <make start, seconds since 1970> <seed or ""> \
#                   <verify: 1, 0 or auto> <verify ticks> <cold sessions>
exe=bin/diary_sim
mode=${1:-ship}; sessions=${2:-0}; ticks=${3:-300}; hours=$4; t0=${5:-$(date +%s)}; seed=$6
vmode=${7:-auto}; vmax=${8:-150000}; cold=${9:-10}
build=$(sed -n 's/^ *Build : constant String := "\([0-9.]*\)".*/\1/p' diary_sim.adb)
folder=$("$exe" --folder) || { echo "ship: cannot find the save folder" >&2; exit 1; }
mkdir -p "$folder" || exit 1
out="$folder/checkin.txt"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'stopped=1' INT   # Ctrl-C stops a night cleanly (it gets the signal too); checkin.txt is still written
stopped=0
cnt() { if [ -f "$1" ]; then grep -c "$2" "$1"; else echo 0; fi; }   # a count, 0 without the file
secs() { s=$1; printf '%dm%02ds' $((s / 60)) $((s % 60)); }
ses="$folder/diaries/sessions.txt"; rl="$folder/run_log.txt"; con="$folder/night_console.txt"; tr="$folder/trend.txt"
s0=$(cnt "$ses" '^S[0-9]'); r0=$(if [ -f "$rl" ]; then wc -l < "$rl"; else echo 0; fi); t_0=$(if [ -f "$tr" ]; then wc -l < "$tr"; else echo 0; fi)
touch "$tmp/stamp"

# ---- a night, or reports only -----------------------------------------------------------------------------------------------------
night=1; coldtxt=""
if [ "$mode" = ship ]; then
  if [ "$sessions" = 0 ] && [ "$s0" = 0 ]; then sessions=$cold; coldtxt=" (cold start)"; fi
  [ "$sessions" = 0 ] && night=0
fi
if [ "$sessions" = 0 ]; then n_txt="no limit"; else n_txt="$sessions"; fi
if [ "$night" = 1 ]; then night_txt="sessions of $ticks ticks; max sessions: $n_txt; max hours: ${hours:-12}$coldtxt"
  echo "=== make $mode (build $build): $night_txt ==="
else echo "=== make $mode (build $build): reports only, no night (SHIP_SESSIONS=N adds N sessions) ==="; fi
echo "save folder: $folder"
tn=$(date +%s); rcn=0
if [ "$night" = 1 ]; then
  set -- --continuous --session-ticks "$ticks" --max-sessions "$sessions"
  [ -n "$hours" ] && set -- "$@" --max-hours "$hours"
  [ -n "$seed" ] && set -- "$@" --seed "$seed"
  "$exe" "$@"; rcn=$?
fi
dn=$(( $(date +%s) - tn ))

# the size of the save: the last S line (start + len) is the tick count
lastS=$(grep '^S[0-9]' "$ses" 2>/dev/null | tail -n 1)
n_all=$(cnt "$ses" '^S[0-9]')
st=$(echo "$lastS" | sed -n 's/.* start=\([0-9]*\) .*/\1/p'); ln=$(echo "$lastS" | sed -n 's/.* len=\([0-9]*\) .*/\1/p')
n_ticks=$(( ${st:-0} + ${ln:-0} ))
case $vmode in
  1) dov=1 ;; 0) dov=0 ;;
  *) if [ "$n_ticks" -le "$vmax" ]; then dov=1; else dov=0; fi ;;
esac
[ "$stopped" = 1 ] && dov=0

echo "=== make $mode: reports (active, wordstat, frustration, evolve, verify) into checkin.txt ==="
for x in active wordstat frustration evolve verify; do
  ts=$(date +%s)
  if [ "$x" = verify ] && [ "$stopped" = 1 ]; then echo "skipped: the night was stopped with Ctrl-C" > "$tmp/$x.txt"; echo 130 > "$tmp/$x.rc"
  elif [ "$x" = verify ] && [ "$dov" = 0 ]; then
    echo "skipped: the save has $n_ticks ticks (more than SHIP_VERIFY_TICKS=$vmax); make verify replays them all (SHIP_VERIFY=1 here)" > "$tmp/$x.txt"; echo skip > "$tmp/$x.rc"
  else "$exe" --"$x" > "$tmp/$x.txt" 2>&1; echo $? > "$tmp/$x.rc"; fi
  echo $(( $(date +%s) - ts )) > "$tmp/$x.secs"
done

# ---- what this run is about: the new sessions, or (reports only) the sessions of the last night ------------------------------------
if [ "$night" = 1 ]; then
  tail -n +$((r0 + 1)) "$rl" 2>/dev/null > "$tmp/runlog.txt"
  grep '^S[0-9]' "$ses" 2>/dev/null | tail -n +$((s0 + 1)) > "$tmp/new.txt"
  [ -f "$tr" ] && tail -n +$((t_0 + 1)) "$tr" | grep '^T ' > "$tmp/trend.txt"
else
  # the last night in run_log.txt: from its "start:" entry (the date line above it) to the end
  sl=$(grep -n '^start: session_ticks=' "$rl" 2>/dev/null | tail -n 1 | cut -d: -f1)
  if [ -n "$sl" ]; then tail -n +$((sl - 1)) "$rl" > "$tmp/runlog.txt"; else tail -n 120 "$rl" 2>/dev/null > "$tmp/runlog.txt"; fi
  stopl=$(grep '^stop: reason=' "$rl" 2>/dev/null | tail -n 1)
  lnn=$(echo "$stopl" | sed -n 's/.* sessions=\([0-9]*\) last_session=\([0-9]*\) .*/\1 \2/p')
  set -- $lnn
  if [ -n "$2" ] && [ "$1" -gt 0 ]; then lo=$(( $2 - $1 + 1 )); hi=$2
  else hi=$n_all; lo=$(( n_all - 39 )); fi
  [ "$lo" -ge 1 ] || lo=1
  grep '^S[0-9]' "$ses" 2>/dev/null | awk -v lo="$lo" -v hi="$hi" '{ n = substr($1, 2) + 0; if (n >= lo && n <= hi) print }' > "$tmp/new.txt"
  [ -f "$tr" ] && grep '^T session=' "$tr" | awk -v lo="$lo" -v hi="$hi" '{ n = substr($2, 9) + 0; if (n >= lo && n <= hi) print }' > "$tmp/trend.txt"
fi
touch "$tmp/new.txt" "$tmp/trend.txt" "$tmp/runlog.txt"

# ---- the verdict ----------------------------------------------------------------------------------------------------------------
reason=$(sed -n 's/^stop: reason=\([a-z_]*\) .*/\1/p' "$tmp/runlog.txt" | tail -n 1)
box_why=""; [ -f "$con" ] && { [ "$night" = 0 ] || [ "$con" -nt "$tmp/stamp" ]; } && box_why=$(sed -n 's/^stopped: //p' "$con" | tail -n 1)
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
lastchk=$(sed -n 's/^verify: \(ok ticks=[0-9]*\)$/\1/p' "$rl" 2>/dev/null | tail -n 1)
if [ "$vrc" = 0 ]; then ver="OK (${vt:-?} ticks replayed from the files)"
elif [ "$vrc" = skip ]; then ver="skipped ($n_ticks ticks > $vmax); night end check: ${lastchk:-none}"
else ver="FAILED (exit $vrc) $(grep -m 1 -i 'drift\|differs\|failed\|skipped' "$tmp/verify.txt" | cut -c1-60)"; fi
# ---- early signals (cheap, from the files of the save; no replay) ---------------------------------------------------------------
# the window: the sessions of this night, or (reports only) of the last night; the diaries of at most its last 30000 ticks
nm() { v=$(sed -n "s/^$1 = \([A-Za-z]*\).*/\1/p" data/names.txt 2>/dev/null | head -n 1); echo "${v:-$1}"; }
ids="ada gemini replika robert"
win=""; [ "$nn" -gt 0 ] && win="s$first-s$last"
fst=$(head -n 1 "$tmp/new.txt" | sed -n 's/.* start=\([0-9]*\) .*/\1/p'); lt=$(tail -n 1 "$tmp/new.txt")
l_st=$(echo "$lt" | sed -n 's/.* start=\([0-9]*\) .*/\1/p'); l_ln=$(echo "$lt" | sed -n 's/.* len=\([0-9]*\) .*/\1/p'); hit=$(( ${l_st:-0} + ${l_ln:-0} ))
lot=${fst:-0}; [ $((hit - lot)) -gt 30000 ] && lot=$((hit - 30000))
: > "$tmp/roles.txt"
for e in $ids; do
  j="$folder/diaries/$e.jsonl"; [ -f "$j" ] || continue
  tail -n $((hit - lot + 5)) "$j" | awk -v lo="$lot" -v e="$e" -v nme="$(nm $e)" '
    { t = $0; sub(/.*"tick":/, "", t); t = t + 0; if (t <= lo) next
      a = $0; if (!sub(/.*"t":"/, "", a)) next; sub(/".*/, "", a); n++; if (a == "rest") r++; if (a == "work") w++ }
    END { if (n > 0) printf "%s %s %d %d %d\n", e, nme, n, int(100 * r / n + 0.5), int(100 * w / n + 0.5) }' >> "$tmp/roles.txt"
done
for e in $ids; do   # words taught by e (as the teacher) in the window, and petitions filed by e
  tw=$(cat "$folder"/entities/*/words.txt 2>/dev/null | awk -v e="$e" -v lo="$lot" -v hi="$hit" '$3 == "taught" && $5 == e && $4 > lo && $4 <= hi { n++ } END { print n + 0 }')
  pw=$(awk -v e="$e" -v lo="${first:-0}" -v hi="${last:-0}" '/^P[0-9]/ { s = $0; sub(/.* s=/, "", s); s = s + 0; if (s >= lo && s <= hi && index($0, " wesen=" e " ")) n++ } END { print n + 0 }' "$folder/diaries/petitions.txt" 2>/dev/null)
  echo "$e $(nm $e) ${tw:-0} ${pw:-0}" >> "$tmp/teach.txt"
done
touch "$tmp/teach.txt"
best() { sort -k"$2" -n -r "$1" | head -n 1 | awk -v k="$2" -v u="$3" '{ if ($k > 0) printf "%s %s%s", $2, $k, u; else printf "-" }'; }
roles_txt="rest $(best "$tmp/roles.txt" 4 %), work $(best "$tmp/roles.txt" 5 %), teach $(best "$tmp/teach.txt" 3 ""), petition $(best "$tmp/teach.txt" 4 "")"
[ -s "$tmp/roles.txt" ] || roles_txt="no diaries yet"
# shared words: known by all four of the union, and the pairwise Jaccard (shared / union of two)
shared_txt=$(for e in $ids; do f="$folder/entities/$e/words.txt"; [ -f "$f" ] && awk -v e="$e" '!/^#/ && NF >= 2 { print e, $2 }' "$f"; done | sort -u | awk '
  { k[$1] = 1; has[$1, $2] = 1; w[$2] = 1 }
  END { ne = 0; for (e in k) id[++ne] = e; if (ne < 2) { print "none"; exit }
    for (x in w) { u++; c = 0; for (i = 1; i <= ne; i++) if (has[id[i], x]) c++; if (c == ne) a++ }
    lo = 2; hi = -1
    for (i = 1; i < ne; i++) for (j = i + 1; j <= ne; j++) { in2 = 0; un = 0
      for (x in w) { p = has[id[i], x]; q = has[id[j], x]; if (p || q) un++; if (p && q) in2++ }
      jj = (un > 0) ? in2 / un : 0; if (jj < lo) lo = jj; if (jj > hi) hi = jj }
    printf "%d %d %d %.2f %.2f\n", a, u, int(100 * a / u + 0.5), lo, hi }')
set -- $shared_txt
if [ -n "$5" ]; then sh_all=$1; sh_pct=$3; shared_line="shared words: $1 of $2 known by all four ($3%); pairs $4 to $5"; sh_pairs="$4-$5"
else sh_all=0; sh_pct=0; sh_pairs="-"; shared_line="shared words: none yet"; fi
# petition topics of the window
awk -v lo="${first:-0}" -v hi="${last:-0}" '/^P[0-9]/ { s = $0; sub(/.* s=/, "", s); s = s + 0; if (s < lo || s > hi) next
  t = $0; sub(/.* topic=/, "", t); sub(/ .*/, "", t); n[t]++ } END { for (t in n) print n[t], t }' "$folder/diaries/petitions.txt" 2>/dev/null | sort -k1,1nr -k2 > "$tmp/topics.txt"
np=$(awk '{ s += $1 } END { print s + 0 }' "$tmp/topics.txt")
for k in 3 2 1; do   # as many of the top 3 as fit on one 79-column verdict line
  topics=$(head -n $k "$tmp/topics.txt" | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }')
  [ $(printf '%s' "petition topics${win:+ ($win)}: $topics (of $np)" | wc -c) -le 79 ] && break
done
top=$(head -n 1 "$tmp/topics.txt" | awk '{ print $2 }')
topics_all=$(awk '{ printf "%s%s:%s", (NR > 1 ? "," : ""), $2, $1 }' "$tmp/topics.txt")
# mood: the last trend line, the names from its header
tnames=$(head -n 1 "$tr" 2>/dev/null | sed -n 's/.*in the order \([A-Za-z,]*\):.*/\1/p')
moods=$(grep '^T ' "$tr" 2>/dev/null | tail -n 1 | sed -n 's/.* mood=\([-0-9,]*\) .*/\1/p')
mood_info=$(echo "$tnames $moods" | awk '{ nn = split($1, nm, ","); nm2 = split($2, m, ","); if (nm2 < 1 || $2 == "") { print "-"; exit }
  lo = 1; hi = 1; s = 0; for (i = 1; i <= nm2; i++) { s += m[i]; if (m[i] + 0 < m[lo] + 0) lo = i; if (m[i] + 0 > m[hi] + 0) hi = i }
  printf "%d %s %d %s %d %d\n", m[hi] - m[lo], (lo <= nn ? nm[lo] : lo), m[lo], (hi <= nn ? nm[hi] : hi), m[hi], int(s / nm2) }')
set -- $mood_info
if [ -n "$6" ]; then spread=$1; mood_line="mood: spread $1 ($2 $3 to $4 $5), mean $6"; else spread=-; mood_line="mood: no trend line yet"; fi
# deltas since the last ship (its stamp in the save folder), then the new stamp
stampf="$folder/ship_stamp.txt"
sv() { sed -n "s/^$1=//p" "$stampf" 2>/dev/null | head -n 1; }
dlt() { if [ -n "$1" ] && [ -n "$2" ] && [ "$1" != - ] && [ "$2" != - ]; then d=$(( $1 - $2 )); [ "$d" -ge 0 ] && d="+$d"; echo "$d"; else echo "?"; fi; }
if [ -f "$stampf" ]; then
  p_made=$(sv made); p_mode=$(sv mode); p_top=$(sv top)
  if [ "$top" = "$p_top" ]; then tt="top topic the same"; ts="top same"; else tt="top topic ${top:--} (was ${p_top:--})"; ts="top ${top:--} (was ${p_top:--})"; fi
  delta_full="since the last ship ($p_made, make $p_mode): $(dlt "$n_all" "$(sv sessions)") sessions, mood spread $(dlt "$spread" "$(sv spread)"), shared words $(dlt "$sh_pct" "$(sv shared_pct)")%, $tt; moods $(sv moods) -> ${moods:--}"
  for ts in "$ts" "top ${top:--}" "top changed"; do   # the first form that fits on a 79-column line
    delta_line="since $(echo "$p_made" | cut -c6-16) ($p_mode): $(dlt "$n_all" "$(sv sessions)") sessions, spread $(dlt "$spread" "$(sv spread)"), shared $(dlt "$sh_pct" "$(sv shared_pct)")%, $ts"
    [ $(printf '%s' "$delta_line" | wc -c) -le 79 ] && break
  done
else delta_full="since the last ship: no stamp yet (ship_stamp.txt is written now; the next ship compares with it)"; delta_line="since the last ship: no stamp yet (written now, the next ship compares)"; fi

why=""
for x in active wordstat frustration evolve; do [ "$(cat "$tmp/$x.rc")" = 0 ] || why="$why make $x exit $(cat "$tmp/$x.rc");"; done
if [ "$night" = 1 ]; then
  [ "$rcn" = 0 ] || why="$why night exit $rcn;"
  case $reason in max_sessions|max_hours) ;; *) why="$why stop reason ${reason:-none};" ;; esac
  [ "$nn" -gt 0 ] || why="$why no new session;"
else
  [ "$reason" = drift ] && why="$why the last night stopped with drift;"
  [ "$n_all" -gt 0 ] || why="$why no session in the save;"
fi
[ "$vrc" = 0 ] || [ "$vrc" = skip ] || why="$why verify failed;"
[ -z "$ws_str" ] || [ "$ws_str" = 0 ] || why="$why $ws_str chess strings since symstrict=1;"
if [ -z "$why" ]; then verdict=PASS; else verdict="FAIL:$why"; fi
total=$(( $(date +%s) - t0 ))
{
  echo "VERDICT: $verdict"
  echo "build: $build   made: $(date '+%Y-%m-%d %H:%M:%S') (local)   make $mode"
  if [ "$night" = 1 ]; then
    echo "night: $night_txt"
    echo "stop reason: ${reason:-none}${box_why:+ ($box_why)}"
    if [ "$nn" -gt 0 ]; then echo "new sessions: $nn (s$first to s$last), active=2: $n_a2/$nn"; else echo "new sessions: 0"; fi
  else
    echo "night: none (reports only); the save: $n_all sessions, $n_ticks ticks"
    echo "stop reason: none (no night); the last night: ${reason:-none}"
    if [ "$nn" -gt 0 ]; then echo "new sessions: 0; newest: $nn (s$first to s$last), active=2: $n_a2/$nn"; else echo "new sessions: 0"; fi
  fi
  echo "newest sessions symstrict=1: $(yn "$n_strict")   slowfloor=1: $(yn "$n_floor")"
  echo "mint-slow at the floor: $floor"
  echo "chess/number strings learned: since symbols=1: ${ws_sym:--}; $strict_txt"
  echo "verify: $ver"
  echo "roles${win:+ ($win)}: $roles_txt" | cut -c1-79
  echo "$shared_line" | cut -c1-79
  if [ "$np" -gt 0 ]; then echo "petition topics${win:+ ($win)}: $topics (of $np)" | cut -c1-79; else echo "petition topics${win:+ ($win)}: none"; fi
  echo "$mood_line" | cut -c1-79
  echo "$delta_line" | cut -c1-79
  if [ "$night" = 1 ]; then echo "wall time: total $(secs $total) (night $(secs $dn))"; else echo "wall time: total $(secs $total) (no night)"; fi
} > "$tmp/verdict.txt"

# a long night (make night-ship) keeps checkin.txt small: the first 40 and the last 240 lines of a section, the rest is in the save
clip() { n=$(wc -l < "$1" | tr -d ' ')
  if [ "$n" -le 300 ]; then cat "$1"
  else head -n 40 "$1"; echo "... $((n - 280)) lines left out here (all of them are in $2) ..."; tail -n 240 "$1"; fi; }
if [ "$night" = 1 ]; then w1="night: run_log.txt entries of this run"; w2="night: new session records"; w3="night: trend.txt lines of the new sessions"
  w4="night: the console of the last session and the final box"
else w1="no night: run_log.txt entries of the last night"; w2="no night: the sessions of the last night"
  w3="no night: trend.txt lines of those sessions"; w4="no night: the console of the last night and its final box"; fi

# ---- checkin.txt: the verdict, then everything ----------------------------------------------------------------------------------
{
  echo "diary-sim checkin (make $mode): attach this ONE file"
  echo "save folder: $folder"
  cat "$tmp/verdict.txt"
  echo "================================================================================"
  echo "== early signals: the lines above in full, from the files (no replay) =="
  echo "window: sessions ${win:-none}, diaries of ticks $((lot + 1)) to $hit (at most the last 30000)"
  echo "roles, per wesen: id name ticks rest% work%"; cat "$tmp/roles.txt"
  echo "roles, per wesen: id name words-taught petitions-filed"; cat "$tmp/teach.txt"
  echo "$shared_line"
  echo "petition topics: ${topics_all:-none} (of $np)"
  echo "$mood_line   (moods ${tnames:-?}: ${moods:--})"
  echo "$delta_full"
  if [ -f "$stampf" ]; then echo "the stamp of the last ship:"; sed 's/^/  /' "$stampf"; fi
  echo "== $w1 =="
  clip "$tmp/runlog.txt" run_log.txt
  echo "== $w2 (diaries/sessions.txt) =="
  clip "$tmp/new.txt" diaries/sessions.txt
  echo "== $w3 =="
  [ -f "$tr" ] && head -n 1 "$tr" && clip "$tmp/trend.txt" trend.txt
  echo "== $w4 (night_console.txt) =="
  if [ -f "$con" ] && { [ "$night" = 0 ] || [ "$con" -nt "$tmp/stamp" ]; }; then cat "$con"; else echo "(not written by this night)"; fi
  for x in active wordstat frustration evolve verify; do
    rc=$(cat "$tmp/$x.rc"); if [ "$rc" = skip ]; then rc=skipped; else rc="exit $rc"; fi
    echo "== make $x ($rc, $(secs "$(cat "$tmp/$x.secs")")) =="
    cat "$tmp/$x.txt"
  done
  echo "== end of checkin.txt =="
} > "$out"

# the new stamp: the next make ship / make night-ship compares with it
{
  echo "# diary-sim ship stamp (make ship / make night-ship write it; the next one compares with it)"
  echo "made=$(date '+%Y-%m-%d %H:%M:%S')"; echo "mode=$mode"; echo "build=$build"; echo "sessions=$n_all"; echo "ticks=$n_ticks"
  echo "moods=${moods:--}"; echo "spread=$spread"; echo "shared_all=$sh_all"; echo "shared_pct=$sh_pct"; echo "jaccard=$sh_pairs"
  echo "top=${top:--}"; echo "topics=${topics_all:--}"
} > "$stampf"

echo "-------------------------------------------------------------------------------"
cat "$tmp/verdict.txt"
echo "attach this ONE file: $out"
[ "$verdict" = PASS ]
