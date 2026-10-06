#!/bin/sh
# Version: 0.006
# make ship (by day) and make night-ship (overnight): Robert's ONE command; both write ONE file, checkin.txt in the save folder
# (../diary-data next to the source folder, or --home / $DIARY_HOME: bin/diary_sim --folder says where), with the same VERDICT header
# on top, and print a short summary and the path of that file.  Exit status 0 = PASS, 1 = FAIL.
# make ship: REPORTS ONLY by default (no night, no q, seconds): make active, wordstat, frustration, evolve on the save as it is, and
#   make verify only if the save has at most <verify ticks> ticks (verify replays the whole history; a big save would take minutes;
#   the end check of the last night is quoted instead).  <sessions> > 0 adds that many new sessions of <ticks> ticks first (the run
#   replays the whole history once before the first new one, so that costs replay time too).  An empty save (cold start) gets
#   <cold sessions> sessions first, so there is something to report.
# make night-ship: ONE wall-clock budget of <hours> hours (decimals allowed) from the start of make for the WHOLE job: the night, the
#   reports and checkin.txt.  The night stops starting sessions at budget minus a reserve; the reserve is the measured time after the
#   last night's planned stop (post_secs in ship_stamp.txt) x NIGHT_SHIP_RESERVE_FACTOR (1.5) + NIGHT_SHIP_RESERVE_MARGIN (120 s); with no
#   history an estimate from the save size (NIGHT_SHIP_RESERVE=<seconds> sets it by hand).  The night runs on the terminal (the live
#   screen of make night; no q needed).  Its end check (a full replay) and the verify step follow the same cap as make ship (auto:
#   at most <verify ticks> ticks); the full check of a big save is make verify by hand.
# Terminal closed (SIGHUP): the night ends cleanly (the program does that), the reports still run and checkin.txt is still written:
#   this script ignores HUP and PIPE from then on, and every line it prints also goes to ship_log.txt in the save folder.
#   NIGHT_SHIP_DETACH=1: the whole job runs detached (setsid nohup), the console goes to ship_console.txt; no live screen.
# make slice (build 0.058, by day): make night-ship with a budget in MINUTES (<hours> is minutes here, SLICE_MINUTES 20): the same
#   night, reserve, reports and checkin.txt.  Its start loads the state checkpoint (state.ckpt) instead of replaying the history; the
#   script says beforehand whether there is one, and the verdict line "checkpoint:" says how the start went (loaded, or a full replay and
#   why) and how long it took, and what the end wrote.  Its reserve is kept apart (slice_post_secs in ship_stamp.txt).
# The reports cover the sessions since the last ship stamp (or the newest window); SHIP_FULL=1: the whole save.
# Usage (from the source folder):
#   scripts/ship.sh <ship|night-ship|slice> <sessions> <ticks> <hours (slice: minutes) or ""> <make start, seconds since 1970> <seed or ""> \
#                   <verify: 1, 0 or auto> <verify ticks> <cold sessions>
exe=bin/diary_sim
mode=${1:-ship}; sessions=${2:-0}; ticks=${3:-300}; hours=$4; t0=${5:-$(date +%s)}; seed=$6
vmode=${7:-auto}; vmax=${8:-150000}; cold=${9:-10}
minutes=""; pkey=post_secs
if [ "$mode" = slice ]; then minutes=${hours:-20}; hours=$(awk -v m="$minutes" 'BEGIN { printf "%.4f", m / 60 }'); pkey=slice_post_secs; fi
build=$(sed -n 's/^ *Build : constant String := "\([0-9.]*\)".*/\1/p' diary_sim.adb)
folder=$("$exe" --folder) || { echo "ship: cannot find the save folder" >&2; exit 1; }
mkdir -p "$folder" || exit 1
if [ "$mode" = night-ship ] && [ "${NIGHT_SHIP_DETACH:-0}" = 1 ] && [ -z "$SHIP_DETACHED" ]; then   # the whole job away from the terminal
  SHIP_DETACHED=1; export SHIP_DETACHED
  setsid nohup "$0" "$@" > "$folder/ship_console.txt" 2>&1 < /dev/null &
  echo "make night-ship runs detached (pid $!); the terminal may be closed.  Watch: tail -f $folder/ship_log.txt"
  echo "checkin.txt appears in $folder when it is done (budget ${hours}h from now)."
  exit 0
fi
out="$folder/checkin.txt"
log="$folder/ship_log.txt"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
trap 'stopped=1' INT   # Ctrl-C stops a night cleanly (it gets the signal too); checkin.txt is still written
trap 'hup=1' HUP       # terminal closed: the program ends the night by itself (it gets the signal too); the reports still run
trap '' PIPE           # a dead terminal or pipe must not kill the report phase
stopped=0; hup=0
: > "$log" 2>/dev/null
say() { printf '%s\n' "$*" >> "$log" 2>/dev/null; printf '%s\n' "$*" 2>/dev/null; }   # the terminal (if it is still there) and ship_log.txt
hm() { date -d "@$1" '+%H:%M' 2>/dev/null || date -r "$1" '+%H:%M' 2>/dev/null || echo "?"; }
cnt() { if [ -f "$1" ]; then grep -c "$2" "$1"; else echo 0; fi; }   # a count, 0 without the file
secs() { s=$1; printf '%dm%02ds' $((s / 60)) $((s % 60)); }
ses="$folder/diaries/sessions.txt"; rl="$folder/run_log.txt"; con="$folder/night_console.txt"; tr="$folder/trend.txt"
stampf="$folder/ship_stamp.txt"
sv() { sed -n "s/^$1=//p" "$stampf" 2>/dev/null | head -n 1; }
dlt() { if [ -n "$1" ] && [ -n "$2" ] && [ "$1" != - ] && [ "$2" != - ]; then d=$(( $1 - $2 )); [ "$d" -ge 0 ] && d="+$d"; echo "$d"; else echo "?"; fi; }
p_post_keep=$(sv post_secs)   # carried over by a day ship (and by a slice)
p_spost_keep=$(sv slice_post_secs)   # the same for make slice (carried over by a day ship and by a night)
ckl="$folder/ckpt_log.txt"
s0=$(cnt "$ses" '^S[0-9]'); r0=$(if [ -f "$rl" ]; then wc -l < "$rl"; else echo 0; fi); t_0=$(if [ -f "$tr" ]; then wc -l < "$tr"; else echo 0; fi)
touch "$tmp/stamp"; t0_date=$(date '+%Y-%m-%d %H:%M:%S' -d "@$t0" 2>/dev/null || echo 0)

# ---- a night, or reports only -----------------------------------------------------------------------------------------------------
night=1; coldtxt=""
if [ "$mode" = ship ]; then
  if [ "$sessions" = 0 ] && [ "$s0" = 0 ]; then sessions=$cold; coldtxt=" (cold start)"; fi
  [ "$sessions" = 0 ] && night=0
fi
if [ "$sessions" = 0 ]; then n_txt="no limit"; else n_txt="$sessions"; fi
# the size of the save before the night (for the reserve estimate and the end check cap)
lastS0=$(grep '^S[0-9]' "$ses" 2>/dev/null | tail -n 1)
st0=$(echo "$lastS0" | sed -n 's/.* start=\([0-9]*\) .*/\1/p'); ln0=$(echo "$lastS0" | sed -n 's/.* len=\([0-9]*\) .*/\1/p')
ticks0=$(( ${st0:-0} + ${ln0:-0} ))
mb0=$(du -sm "$folder" 2>/dev/null | cut -f1); mb0=${mb0:-0}
budget_txt=""; plan_stop=0; deadline=0; reserve=0
night_hours=$hours
if [ "$mode" != ship ]; then   # ONE budget for the whole job: the night stops starting sessions at deadline - reserve
  budget=$(awk -v h="${hours:-9}" 'BEGIN { printf "%d", h * 3600 }')
  deadline=$((t0 + budget))
  fac=${NIGHT_SHIP_RESERVE_FACTOR:-1.5}; mar=${NIGHT_SHIP_RESERVE_MARGIN:-120}
  p_post=$(sv $pkey)
  # the end check of the night replays the whole history when the save is under the verify cap: about 300 ticks/s
  chk=0; case $vmode in 1) chk=$((ticks0 / 300)) ;; 0) chk=0 ;; *) [ "$ticks0" -le "$vmax" ] && chk=$((ticks0 / 300)) ;; esac
  if [ -n "$NIGHT_SHIP_RESERVE" ]; then reserve=$NIGHT_SHIP_RESERVE; rtxt="set by hand (NIGHT_SHIP_RESERVE)"
  elif [ -n "$p_post" ]; then
    reserve=$(awk -v p="$p_post" -v f="$fac" -v m="$mar" 'BEGIN { printf "%d", p * f + m + 0.5 }'); rtxt="the last night needed ${p_post}s after its stop, x$fac + ${mar}s"
  else reserve=$((90 + mb0 / 10 + chk + mar)); rtxt="no history yet: estimate 90s + ${mb0} MB/10 + end check ${chk}s + ${mar}s"; fi
  now=$(date +%s); night_secs=$((deadline - reserve - now))
  floor=$((budget / 2)); [ "$floor" -gt 60 ] && floor=60; [ "$floor" -ge 1 ] || floor=1
  if [ "$night_secs" -lt "$floor" ]; then night_secs=$floor; rtxt="$rtxt; budget too small: the night gets ${floor}s"; fi
  plan_stop=$((now + night_secs))
  night_hours=$(awk -v s="$night_secs" 'BEGIN { printf "%.4f", s / 3600 }')
  btxt="${hours}h"; [ "$mode" = slice ] && btxt="$minutes min"
  budget_txt="budget $btxt: new sessions until $(hm $plan_stop), then reports; checkin.txt by $(hm $deadline); reserve $(secs $reserve): $rtxt"
fi
if [ "$night" = 1 ]; then
  if [ "$mode" = night-ship ]; then night_txt="sessions of $ticks ticks; max sessions: $n_txt; one budget of ${hours}h"
  elif [ "$mode" = slice ]; then night_txt="sessions of $ticks ticks; max sessions: $n_txt; one budget of $minutes min"
  else night_txt="sessions of $ticks ticks; max sessions: $n_txt; max hours: ${hours:-12}$coldtxt"; fi
  say "=== make $mode (build $build): $night_txt ==="
  [ -n "$budget_txt" ] && say "$budget_txt"
else say "=== make $mode (build $build): reports only, no night (SHIP_SESSIONS=N adds N sessions) ==="; fi
say "save folder: $folder"
if [ "$night" = 1 ]; then   # 0.058: the start loads the state checkpoint when it fits the files, else it replays the whole history once
  if [ -f "$folder/state.ckpt" ]; then
    say "checkpoint: state.ckpt of tick $(head -c 4096 "$folder/state.ckpt" | grep -a '^tick ' | cut -d' ' -f2), $(( $(wc -c < "$folder/state.ckpt") / 1048576 )) MB: the start loads it if it fits the files"
  else say "checkpoint: none yet: the start replays the whole history once (minutes on a big save); the end writes one"; fi
fi
tn=$(date +%s); rcn=0
if [ "$night" = 1 ]; then
  set -- --continuous --session-ticks "$ticks" --max-sessions "$sessions"
  [ -n "$night_hours" ] && set -- "$@" --max-hours "$night_hours"
  if [ "$mode" != ship ]; then   # never a full replay of a big save after the night
    case $vmode in 1) ;; 0) set -- "$@" --end-check-ticks 0 ;; *) set -- "$@" --end-check-ticks "$vmax" ;; esac
  fi
  [ -n "$seed" ] && set -- "$@" --seed "$seed"
  "$exe" "$@"; rcn=$?
fi
trap '' HUP   # from here on nothing stops the reports: checkin.txt is always written (the programs below inherit it)
[ "$hup" = 1 ] && say "SIGHUP (terminal closed?): the night ended; the reports run on, see $log"
night_end=$(date +%s); dn=$((night_end - tn))
[ "$night" = 1 ] && say "night done: $(secs $dn); reports next ($(date '+%H:%M:%S'))"

# the size of the save: the last S line (start + len) is the tick count
lastS=$(grep '^S[0-9]' "$ses" 2>/dev/null | tail -n 1)
st=$(echo "$lastS" | sed -n 's/.* start=\([0-9]*\) .*/\1/p'); ln=$(echo "$lastS" | sed -n 's/.* len=\([0-9]*\) .*/\1/p')
n_ticks=$(( ${st:-0} + ${ln:-0} ))
case $vmode in
  1) dov=1 ;; 0) dov=0 ;;
  *) if [ "$n_ticks" -le "$vmax" ]; then dov=1; else dov=0; fi ;;
esac
[ "$stopped" = 1 ] && dov=0
[ "$hup" = 1 ] && dov=0   # after a SIGHUP: checkin.txt first; make verify by hand
# the night's own end check of this run (run_log.txt): when it passed, it is the verify of this run (no second full replay)
# 0.058: run_log.txt keeps only the last report.log_keep entries (a night writes one per session), so after a long night the line
# count from before it can point past the end: this run's part starts at the first entry stamped at or after the start of make
rs=$((r0 + 1))
if [ "$night" = 1 ]; then
  sl=$(awk -v t="$t0_date" '/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] [A-Z]/ && substr($0, 1, 19) >= t { print NR; exit }' "$rl" 2>/dev/null)
  [ -n "$sl" ] && rs=$sl
fi
nightchk=""
if [ "$mode" != ship ]; then nightchk=$(tail -n +$rs "$rl" 2>/dev/null | sed -n 's/^verify: \(ok ticks=[0-9]*\)$/\1/p' | tail -n 1); fi
[ -n "$nightchk" ] && dov=0

# ---- the window of the reports: the sessions since the last ship stamp, or the newest window; SHIP_FULL=1: the whole save
n_all=$(cnt "$ses" '^S[0-9]')
if [ "$night" = 1 ]; then lo=$((s0 + 1)); hi=$n_all
else
  p_ses=$(sv sessions)
  if [ -n "$p_ses" ] && [ "$p_ses" -lt "$n_all" ] 2>/dev/null; then lo=$((p_ses + 1)); hi=$n_all
  else   # nothing new since the stamp: the last night in run_log.txt
    stopl=$(grep '^stop: reason=' "$rl" 2>/dev/null | tail -n 1)
    lnn=$(echo "$stopl" | sed -n 's/.* sessions=\([0-9]*\) last_session=\([0-9]*\) .*/\1 \2/p')
    set -- $lnn
    if [ -n "$2" ] && [ "$1" -gt 0 ]; then lo=$(( $2 - $1 + 1 )); hi=$2
    else hi=$n_all; lo=$(( n_all - 39 )); fi
  fi
fi
[ "$lo" -ge 1 ] 2>/dev/null || lo=1
if [ "${SHIP_FULL:-0}" = 1 ]; then wopt=""; wtxt="the whole save (SHIP_FULL=1)"
elif [ "$lo" -le 1 ]; then wopt=""; wtxt="the whole save (s1 to s$hi)"
elif [ "$lo" -gt "$hi" ]; then wopt="--since-session $hi"; wtxt="no new session: the newest one (s$hi)"
else wopt="--since-session $lo"; wtxt="sessions s$lo to s$hi (new since the last ship)"; fi

say "=== make $mode: reports (active, wordstat, frustration, evolve, verify) into checkin.txt; window: $wtxt ==="
tr0=$(date +%s)
for x in active wordstat frustration evolve verify; do
  ts=$(date +%s)
  if [ "$x" = verify ] && [ "$stopped" = 1 ]; then echo "skipped: the night was stopped with Ctrl-C" > "$tmp/$x.txt"; echo 130 > "$tmp/$x.rc"
  elif [ "$x" = verify ] && [ -n "$nightchk" ]; then echo "done by the night's end check: $nightchk (the whole history replayed from the files)" > "$tmp/$x.txt"; echo night > "$tmp/$x.rc"
  elif [ "$x" = verify ] && [ "$hup" = 1 ]; then echo "skipped: the terminal was closed (SIGHUP); make verify replays the whole history by hand" > "$tmp/$x.txt"; echo skip > "$tmp/$x.rc"
  elif [ "$x" = verify ] && [ "$dov" = 0 ]; then
    echo "skipped: the save has $n_ticks ticks (more than SHIP_VERIFY_TICKS=$vmax); make verify replays them all (SHIP_VERIFY=1 here)" > "$tmp/$x.txt"; echo skip > "$tmp/$x.rc"
  else
    printf '  %s %-12s ...' "$(date '+%H:%M:%S')" "$x" 2>/dev/null
    # shellcheck disable=SC2086
    "$exe" --"$x" $wopt > "$tmp/$x.txt" 2>&1; echo $? > "$tmp/$x.rc"
    printf ' %s\n' "$(secs $(( $(date +%s) - ts )))" 2>/dev/null
    echo "  $x: exit $(cat "$tmp/$x.rc"), $(secs $(( $(date +%s) - ts )))" >> "$log" 2>/dev/null
  fi
  echo $(( $(date +%s) - ts )) > "$tmp/$x.secs"
done
drep=$(( $(date +%s) - tr0 ))

# ---- what this run is about: the new sessions, or (reports only) the sessions of the last night ------------------------------------
if [ "$night" = 1 ]; then
  tail -n +$rs "$rl" 2>/dev/null > "$tmp/runlog.txt"
  grep '^S[0-9]' "$ses" 2>/dev/null | tail -n +$((s0 + 1)) > "$tmp/new.txt"
  [ -f "$tr" ] && tail -n +$((t_0 + 1)) "$tr" | grep '^T ' > "$tmp/trend.txt"
else
  # the last night in run_log.txt: from its "start:" entry (the date line above it) to the end
  sl=$(grep -n '^start: session_ticks=' "$rl" 2>/dev/null | tail -n 1 | cut -d: -f1)
  if [ -n "$sl" ]; then tail -n +$((sl - 1)) "$rl" > "$tmp/runlog.txt"; else tail -n 120 "$rl" 2>/dev/null > "$tmp/runlog.txt"; fi
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
# the table rows only: the label, four wesen and the total (a wrapped sentence that starts with the same words is no row)
row5='( +[0-9]+){5} *$'
ws_sym=$(grep -E "^  of those, chess or number strings$row5" "$tmp/wordstat.txt" | tail -n 1 | awk '{ print $NF }')
ws_str=$(grep -E "^  chess or number strings$row5" "$tmp/wordstat.txt" | tail -n 1 | awk '{ print $NF }')
if [ -n "$ws_str" ]; then strict_txt="since symstrict=1: $ws_str"; elif grep -q 'no symstrict=1 session yet' "$tmp/wordstat.txt"; then strict_txt="no symstrict=1 session yet"; else strict_txt="since symstrict=1: -"; fi
vrc=$(cat "$tmp/verify.rc"); vt=$(sed -n 's/^verify: OK, \([0-9]*\) ticks.*/\1/p' "$tmp/verify.txt" | head -n 1)
lastchk=$(sed -n 's/^verify: \(ok ticks=[0-9]*\)$/\1/p' "$rl" 2>/dev/null | tail -n 1)
if [ "$vrc" = 0 ]; then ver="OK (${vt:-?} ticks replayed from the files)"
elif [ "$vrc" = night ]; then ver="OK by the night's end check ($nightchk)"
elif [ "$vrc" = skip ] && [ "$hup" = 1 ]; then ver="skipped (terminal closed); last end check: ${lastchk:-none}"
elif [ "$vrc" = skip ]; then ver="skipped ($n_ticks ticks > $vmax); night end check: ${lastchk:-none} (make verify by hand)"
else ver="FAILED (exit $vrc) $(grep -m 1 -i 'drift\|differs\|failed\|skipped' "$tmp/verify.txt" | cut -c1-60)"; fi
# 0.059: the last PASSED full replay (make verify, a ship's verify, the night's end check): the newest "full verify: OK, N ticks" entry
# (VERIFY) or "verify: ok ticks=N" entry (NIGHT) of run_log.txt with the time stamp of its entry, else the one kept in ship_stamp.txt
# (run_log.txt keeps only its last report.log_keep entries; a night writes one per session).  Due after 7 days (weekly drift check).
lv=$(awk '/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] [A-Z]/ { st = substr($0, 1, 16); next }
  /^full verify: OK, [0-9]+ ticks/ { t = $4; sub(/,$/, "", t); if (st != "") v = st " " t }
  /^verify: ok ticks=[0-9]+$/ { t = $2; sub(/^ticks=/, "", t); if (st != "") v = st " " t }
  END { print v }' "$rl" 2>/dev/null)
p_lv=$(sv last_verify)
if [ -n "$p_lv" ] && { [ -z "$lv" ] || [ "$(printf '%s\n%s\n' "$p_lv" "$lv" | sort | tail -n 1)" = "$p_lv" ]; }; then lv=$p_lv; fi
if [ -n "$lv" ]; then
  lv_d=${lv% *}; lv_t=${lv##* }
  lv_s=$(date -d "$lv_d" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M' "$lv_d" +%s 2>/dev/null)
  if [ -n "$lv_s" ]; then
    lv_n=$(( ($(date +%s) - lv_s) / 86400 ))
    case $lv_n in 0) lv_ago="today" ;; 1) lv_ago="1 day ago" ;; *) lv_ago="$lv_n days ago" ;; esac
    [ "$lv_n" -ge 7 ] && lv_ago="$lv_ago - due: make verify (weekly)"
  else lv_ago="age unknown"; fi
  lv_line="last full verify: $lv_d ($lv_t ticks), $lv_ago"
else lv_line="last full verify: none on record - due: make verify (weekly)"; fi
# ---- early signals (cheap, from the files of the save; no replay) ---------------------------------------------------------------
# the window: the sessions of this night, or (reports only) of the last night; the diaries of at most its last 30000 ticks
nm() { v=$(sed -n "s/^$1 = \([A-Za-z]*\).*/\1/p" data/names.txt 2>/dev/null | head -n 1); echo "${v:-$1}"; }
ids="ada gemini replika robert"
names=$(for e in $ids; do printf '%s ' "$(nm $e)"; done); names=${names% }   # the wesen names for the lines (data/names.txt)
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
# the vocabulary goal (Robert: a shared vocabulary of 40000 words).  HEADLINE: plain words (no chess move, no number) known by at least
# ceiling(3/4 of the wesen) (3 of 4 today; from $ids, no fixed count); beside it the stricter all-wesen count, the overlap (all /
# every distinct plain word known by anyone, in percent; a count can grow while the overlap falls), the known words per wesen and who is missing most often among the words known by all but one.  One read of entities/*/words.txt.  "used" (spoken or
# written by each knower) is not recorded per word in the files yet.
goal=${SHIP_VOCAB_GOAL:-40000}
voc=$(for e in $ids; do f="$folder/entities/$e/words.txt"; [ -f "$f" ] && awk -v e="$e" '!/^#/ && NF >= 2 { print e, $2 }' "$f"; done | sort -u | awk -v ids="$ids" '
  function chess(t) { return t ~ /^[a-h][1-8][a-h][1-8][qrbn]?$/ } function num(t) { return t ~ /^[0-9]+$/ }
  BEGIN { ne = split(ids, ord, " "); th = int((3 * ne + 3) / 4) }   # the threshold: ceiling(3/4 of the wesen), 3 of 4 today
  { if (chess($2) || num($2)) next; n[$1]++; c[$2]++; has[$1, $2] = 1; seen[$1] = 1 }
  END { k = 0; for (e in seen) k++; if (k < ne || ne < 2) { print "none"; exit }
    u = 0; for (x in c) { u++; if (c[x] >= th) s3++; if (c[x] == ne) s4++
      if (c[x] == ne - 1) for (i = 1; i <= ne; i++) if (!has[ord[i], x]) miss[ord[i]]++ }
    s = 0; per = ""; mi = ""; best = ord[1]
    for (i = 1; i <= ne; i++) { e = ord[i]; s += n[e]; per = per (i > 1 ? "," : "") n[e]; mi = mi (i > 1 ? "," : "") miss[e] + 0; if (miss[e] + 0 > miss[best] + 0) best = e }
    printf "%d %d %d %s %s %s %d %d %d\n", s3 + 0, s4 + 0, int(1000 * s4 / u + 0.5), per, mi, best, miss[best] + 0, th, ne }')
set -- $voc
if [ -n "$9" ]; then voc_sh=$1; voc_s4=$2; voc_ov=$(awk -v x="$3" 'BEGIN { printf "%.1f", x / 10 }'); voc_per=$4; voc_miss=$5; miss_e=$6; miss_n=$7; v_th=$8; v_ne=$9
  voc_pct=$(awk -v a="$1" -v g="$goal" 'BEGIN { printf "%.1f", 100 * a / g }')
  p_vsh=$(sv vocab_shared); p_vs4=$(sv vocab_all); p_vov=$(sv vocab_overlap)
  [ -n "$p_vsh" ] || p_vsh=-; [ -n "$p_vs4" ] || p_vs4=-
  voc_d=$(dlt "$voc_sh" "$p_vsh"); voc_d4=$(dlt "$voc_s4" "$p_vs4")
  if [ -n "$p_vov" ]; then voc_od=$(awk -v a="$voc_ov" -v b="$p_vov" 'BEGIN { d = a - b; printf "%s%.1f", (d >= 0 ? "+" : ""), d }'); else voc_od="?"; fi
  if [ "$voc_d" = "?" ]; then vtail="no count in the last stamp"; else vtail="$voc_d since last ship"; fi
  voc_line="shared ($v_th of $v_ne): $voc_sh / $goal ($voc_pct%), $vtail"
  voc_line2="  all $v_ne: $voc_s4 ($voc_d4); overlap $voc_ov% ($voc_od); known per wesen: $voc_per"
  voc_line3="  most often missing: $(nm "$miss_e") ($miss_n words); used: not tracked yet"
  voc_full="vocabulary goal: shared ($v_th of $v_ne) $voc_sh / $goal ($voc_pct%), $voc_d since the last ship = plain words (no chess move, no number) known by at least $v_th wesen; all $v_ne: $voc_s4 ($voc_d4); overlap $voc_ov% (all $v_ne / every distinct plain word, $voc_od points); known per wesen ($names): $voc_per; missing among the words known by all but one ($names): $voc_miss; used: not tracked yet (the files keep no per-word record of who said or wrote a word)"
else voc_sh=0; voc_s4=0; voc_ov=0; voc_per=-; voc_miss=-; voc_line="shared: no word lists of every wesen yet (goal $goal)"; voc_line2=""; voc_line3=""; voc_full=$voc_line; fi
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
if [ -f "$stampf" ]; then
  p_made=$(sv made); p_mode=$(sv mode); p_top=$(sv top)
  if [ "$top" = "$p_top" ]; then tt="top topic the same"; ts="top same"; else tt="top topic ${top:--} (was ${p_top:--})"; ts="top ${top:--} (was ${p_top:--})"; fi
  # COUNTS and the OVERLAP apart (a count can grow while the overlap falls when the vocabulary grows faster): the shared (3 of 4)
  # count, the all-wesen count and the overlap in percentage points.  A 0.056 stamp has no vocab_* keys: then the all-four count
  # and the percent of the "shared words" line (shared_all, shared_pct; the same definition in both builds); no 3-of-4 delta.
  nw=$(echo $ids | wc -w)
  pts() { awk -v a="$1" -v b="$2" 'BEGIN { if (a == "" || b == "" || a == "-" || b == "-") { print "?"; exit }; d = a - b
    if (d > -0.05 && d < 0.05) print "+0"; else if (d >= 1 || d <= -1) printf "%+.0f\n", d; else printf "%+.1f\n", d }'; }
  if [ -n "$(sv vocab_shared)" ] && [ "$(sv vocab_shared)" != - ]; then
    d_sh=$(dlt "$voc_sh" "$(sv vocab_shared)"); d_all=$(dlt "$voc_s4" "$(sv vocab_all)"); d_ov=$(pts "$voc_ov" "$(sv vocab_overlap)")
    ov_txt="plain words, was $(sv vocab_overlap)%, now $voc_ov%"
  else
    d_sh="?"; d_all=$(dlt "$sh_all" "$(sv shared_all)"); d_ov=$(pts "$sh_pct" "$(sv shared_pct)")
    ov_txt="all words of the shared words line, was $(sv shared_pct)%, now $sh_pct%; the last stamp has no 3-of-$nw count"
  fi
  delta_full="since the last ship ($p_made, make $p_mode): $(dlt "$n_all" "$(sv sessions)") sessions, mood spread $(dlt "$spread" "$(sv spread)"), shared (${v_th:-?} of $nw) $d_sh, all $nw $d_all, overlap $d_ov pts ($ov_txt), $tt; moods $(sv moods) -> ${moods:--}"
  for ts in ", $ts" ", top changed" ""; do   # the first form that fits on a 79-column line
    delta_line="since $(echo "$p_made" | cut -c6-16): $(dlt "$n_all" "$(sv sessions)") sessions, spread $(dlt "$spread" "$(sv spread)"), all $nw $d_all, overlap $d_ov pts$ts"
    [ $(printf '%s' "$delta_line" | wc -c) -le 79 ] && break
  done
else delta_full="since the last ship: no stamp yet (ship_stamp.txt is written now; the next ship compares with it)"; delta_line="since the last ship: no stamp yet (written now, the next ship compares)"; fi

# 0.058: the checkpoint: how this run's night started (loaded, or a full replay and why; ready after the replay line's seconds) and
# what its end wrote (ckpt_log.txt lines of this run); a day ship names the checkpoint the save has
# (both logs are capped, so the lines are picked by their time stamp; the start line and the replay time come from the night's box)
awk -v t="$t0_date" 'substr($0, 1, 19) >= t' "$ckl" 2>/dev/null > "$tmp/ckpt.txt"; touch "$tmp/ckpt.txt"
if [ -f "$con" ] && [ "$con" -nt "$tmp/stamp" ]; then sed -n '/^== night box ==/,$p' "$con" > "$tmp/box.txt"; else : > "$tmp/box.txt"; fi
rdy=$(cat "$tmp/box.txt" "$tmp/runlog.txt" | sed -n 's/^replay done: [0-9]* ticks in \([0-9.]*\) s;.*/\1/p' | head -n 1)
st_l=$( { grep -E '^(start|replay): ' "$tmp/box.txt"; grep -E '^[0-9-]+ [0-9:]+ (start|replay): ' "$tmp/ckpt.txt" | cut -d' ' -f3-; } | head -n 1)
wr_l=$(grep -E '^[0-9-]+ [0-9:]+ checkpoint: tick ' "$tmp/ckpt.txt" | tail -n 1 | sed -E 's/.* checkpoint: tick ([0-9]+), ([0-9]+) KB, written in ([0-9.]+) s$/t\1 \2 \3/' | awk '{ printf "%s %.1f MB %s s", $1, $2 / 1024, $3 }')
case $st_l in
  start:*) st_t="loaded t$(echo "$st_l" | sed -n 's/.*checkpoint of tick \([0-9]*\) loaded in \([0-9.]*\) s.*/\1 in \2 s/p')" ;;
  replay:*) st_t="full replay ($(echo "$st_l" | sed -n 's/^replay: checkpoint \([a-z]*\).* - [0-9]* ticks replayed$/\1/p'))${rdy:+ in $rdy s}" ;;
  *) st_t="" ;;
esac
if [ "$night" = 1 ]; then ck_line="checkpoint: start ${st_t:-?}; end ${wr_l:-not written}"
elif [ -f "$folder/state.ckpt" ]; then ck_line="checkpoint: no night; state.ckpt of tick $(head -c 4096 "$folder/state.ckpt" | grep -a '^tick ' | cut -d' ' -f2) ($(( $(wc -c < "$folder/state.ckpt") / 1024 )) KB)"
else ck_line="checkpoint: no night; none yet (the next run writes one)"; fi
why=""
for x in active wordstat frustration evolve; do [ "$(cat "$tmp/$x.rc")" = 0 ] || why="$why make $x exit $(cat "$tmp/$x.rc");"; done
if [ "$night" = 1 ]; then
  # a closed terminal after real sessions ends the night with a signal exit; that is the WARN below, not a FAIL
  [ "$rcn" = 0 ] || { [ "$hup" = 1 ] && [ "$reason" = signal ] && [ "$nn" -gt 0 ]; } || why="$why night exit $rcn;"
  case $reason in max_sessions|max_hours) ;;
    signal) [ "$hup" = 1 ] && [ "$nn" -gt 0 ] || why="$why stop reason signal;" ;;   # a closed terminal after real sessions: WARN below
    *) why="$why stop reason ${reason:-none};" ;; esac
  [ "$nn" -gt 0 ] || why="$why no new session;"
else
  [ "$reason" = drift ] && why="$why the last night stopped with drift;"
  [ "$n_all" -gt 0 ] || why="$why no session in the save;"
fi
[ "$vrc" = 0 ] || [ "$vrc" = skip ] || [ "$vrc" = night ] || why="$why verify failed;"
warn=""
if [ -n "$ws_str" ] && [ "$ws_str" != 0 ]; then
  if [ "$n_strict" -gt 0 ]; then why="$why $ws_str chess strings since symstrict=1;"
  else warn="$warn $ws_str chess strings since symstrict=1, but the window has no symstrict=1 session (older than build 0.054);"; fi
fi
[ "$hup" = 1 ] && warn="$warn the terminal was closed (SIGHUP) during the run;"
if [ -z "$why" ] && [ -z "$warn" ]; then verdict=PASS; elif [ -z "$why" ]; then verdict="PASS, WARN:$warn"; else verdict="FAIL:$why${warn:+ WARN:$warn}"; fi
total=$(( $(date +%s) - t0 ))
{
  echo "VERDICT: $verdict"
  echo "$voc_line" | cut -c1-79
  [ -n "$voc_line2" ] && echo "$voc_line2" | cut -c1-79
  [ -n "$voc_line3" ] && echo "$voc_line3" | cut -c1-79
  echo "build: $build   made: $(date '+%Y-%m-%d %H:%M:%S') (local)   make $mode"
  if [ "$night" = 1 ]; then
    echo "night: $night_txt"
    [ "$mode" != ship ] && echo "budget: $( [ "$mode" = slice ] && echo "$minutes min" || echo "${hours}h"); stop $(hm $plan_stop), reserve $(secs $reserve); due $(hm $deadline), written $(date '+%H:%M') ($( [ "$(date +%s)" -le "$deadline" ] && echo on time || echo "late $(secs $(( $(date +%s) - deadline )))"))"
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
  echo "$lv_line" | cut -c1-79
  echo "$ck_line" | cut -c1-79
  echo "reports window: $wtxt" | cut -c1-79
  echo "roles${win:+ ($win)}: $roles_txt" | cut -c1-79
  echo "$shared_line" | cut -c1-79
  if [ "$np" -gt 0 ]; then echo "petition topics${win:+ ($win)}: $topics (of $np)" | cut -c1-79; else echo "petition topics${win:+ ($win)}: none"; fi
  echo "$mood_line" | cut -c1-79
  echo "$delta_line" | cut -c1-79
  if [ "$night" = 1 ]; then echo "wall time: total $(secs $total) (night $(secs $dn), reports $(secs $drep))"; else echo "wall time: total $(secs $total) (no night, reports $(secs $drep))"; fi
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
  echo "$voc_full"
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
    rc=$(cat "$tmp/$x.rc"); if [ "$rc" = skip ]; then rc=skipped; elif [ "$rc" = night ]; then rc="by the night"; else rc="exit $rc"; fi
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
  echo "reports_secs=$drep"
  [ -n "$lv" ] && echo "last_verify=$lv"
  echo "vocab_shared=$voc_sh"; echo "vocab_all=$voc_s4"; echo "vocab_overlap=$voc_ov"; echo "vocab_known=$voc_per"; echo "vocab_missing=$voc_miss"
  # make night-ship: the time after the planned stop of the night (the last session, the end check, the reports): the next reserve
  if [ "$mode" != ship ] && [ "$plan_stop" -gt 0 ] && [ "$stopped" = 0 ] && [ "$hup" = 0 ]; then
    ref=$plan_stop; [ "$night_end" -lt "$ref" ] && ref=$night_end
    echo "$pkey=$(( $(date +%s) - ref ))"
    if [ "$pkey" = post_secs ]; then other=slice_post_secs; ov=$p_spost_keep; else other=post_secs; ov=$p_post_keep; fi
    if [ -n "$ov" ]; then echo "$other=$ov"; fi
  else
    if [ -n "$p_post_keep" ]; then echo "post_secs=$p_post_keep"; fi
    if [ -n "$p_spost_keep" ]; then echo "slice_post_secs=$p_spost_keep"; fi
  fi
} > "$stampf.tmp" && mv "$stampf.tmp" "$stampf"

say "-------------------------------------------------------------------------------"
# the terminal: the verdict without its detail lines (they are in checkin.txt): the vocabulary details and the reports window
while IFS= read -r l; do case $l in "  "*|"reports window:"*) printf '%s\n' "$l" >> "$log" 2>/dev/null ;; *) say "$l" ;; esac; done < "$tmp/verdict.txt"
say "attach this ONE file: $out"
case $verdict in PASS*) exit 0 ;; *) exit 1 ;; esac
