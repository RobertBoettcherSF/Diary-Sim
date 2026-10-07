#!/bin/sh
# Version: 0.001
# The Albanian report (build 0.064, alb=1 sessions; REPORT time only, the simulation never reads it):
#   scripts/alb_report.sh <save folder> <first session> <last session>
# Scores the sentences the wesen said in the window (diaries/albanian.txt U and J lines) against the genders of
# data/sq_nouns.txt and prints ONE line for checkin.txt (at most 79 columns, a second line only when the first is full):
#   agreement of the article with the noun's gender, against the shuffle baseline (the same articles shuffled over the same
#   nouns: share_i x share_m + share_e x share_f), and on the held-back nouns (never heard) against always-masculine on those
#   nouns, the feminine held-back nouns alone, and the first-person sentences "jam i/e ..." (wesen with gender m or f).
# The full breakdown per wesen and the last 20 sentences go to albanian_report.txt in the save folder (overwritten each run).
folder=$1; lo=${2:-0}; hi=${3:-999999999}
root=$(cd "$(dirname "$0")/.." && pwd)
f="$folder/diaries/albanian.txt"
[ -f "$f" ] || { echo "albanian: no alb=1 session yet (diaries/albanian.txt)"; exit 0; }
awk -F'\t' '!/^#/ && NF >= 2 { print $1, $2 }' "$root/data/sq_nouns.txt" > "${TMPDIR:-/tmp}/alb_g.$$"
awk -v lo="$lo" -v hi="$hi" -v rep="$folder/albanian_report.txt" -v names="$root/data/names.txt" -v gf="${TMPDIR:-/tmp}/alb_g.$$" '
  BEGIN { while ((getline l < gf) > 0) { split(l, a, " "); g[a[1]] = a[2] }
          while ((getline l < names) > 0) if (l !~ /^#/ && split(l, a, " = ") == 2) { gsub(/ /, "", a[1]); dn[a[1]] = a[2] } }
  function nm(x) { return (x in dn) ? dn[x] : x }
  function pc(a, b) { return b > 0 ? sprintf("%d%%", 100 * a / b + 0.5) : "-" }
  /^[UJHB] S[0-9]/ { s = substr($2, 2) + 0; if (s < lo || s > hi) next }
  /^B S/ { book = $0 }
  /^H S/ { w = $3; sub(/heard=/, "", $4); heard[w] += $4; sub(/cues=/, "", $5); cues[w] += $5 }
  /^U S/ { w = $3; n = $4; art = $5; ge = g[n]; if (ge != "m" && ge != "f") next
           ok = (art == "i" && ge == "m") || (art == "e" && ge == "f")
           N++; C += ok; if (art == "i") I++; if (ge == "m") Mn++
           wn[w]++; wc[w] += ok
           if ($0 ~ /held=1/) { HN++; HC += ok; if (ge == "m") HM++; if (ge == "f") { HF++; HFC += ok }; whn[w]++; whc[w] += ok }
           src = $0; sub(/.* src=/, "", src); sub(/ .*/, "", src); sn[src]++; sc[src] += ok
           last[++nl] = $2 " " nm(w) ": " n " " art " " $6 " (" ge (ok ? ", ok" : ", WRONG") ", " src ($0 ~ /held=1/ ? ", held back" : "") ")" }
  /^J S/ { w = $3; ge = $NF; sub(/g=/, "", ge); ok = ($5 == "i" && ge == "m") || ($5 == "e" && ge == "f"); JN++; JC += ok; jn[w]++; jc[w] += ok
           last[++nl] = $2 " " nm(w) ": jam " $5 " " $6 " (own gender " ge (ok ? ", ok" : ", WRONG") ")" }
  END {
    if (N == 0) { print "albanian: no sentence said in the window"; exit }
    sh = (I * Mn + (N - I) * (N - Mn)) / (N * N)
    l1 = sprintf("albanian: agree %s n=%d (shuffle %s); held-back %s n=%d (all-m %s),", pc(C, N), N, pc(sh * 100, 100), pc(HC, HN), HN, pc(HM, HN))
    l2 = sprintf(" fem %s n=%d; jam %d/%d", pc(HFC, HF), HF, JC, JN)
    if (length(l1 l2) <= 79) print l1 l2; else { print l1; print "  albanian:" l2 }
    printf "# diary-sim albanian report (scripts/alb_report.sh, overwritten each run): sessions %s to %s\n", lo, hi > rep
    print "# scored against data/sq_nouns.txt (Wiktionary genders); neuter / unknown nouns are left out" > rep
    print book > rep
    printf "all: %d sentences, article right %d (%s); shuffle baseline %s (articles i %d, nouns m %d)\n", N, C, pc(C, N), pc(sh * 100, 100), I, Mn > rep
    printf "held-back nouns (never heard): %d, right %d (%s); always-m %s; feminine %d, right %d (%s)\n", HN, HC, pc(HC, HN), pc(HM, HN), HF, HFC, pc(HFC, HF) > rep
    printf "first person (jam i/e): %d of %d right\n", JC, JN > rep
    for (x in sn) printf "  by source %s: %d, right %d (%s)\n", x, sn[x], sc[x], pc(sc[x], sn[x]) > rep
    for (w in wn) printf "wesen %s: heard %d sentences (%d cues); said %d, right %d (%s); held-back %d, right %d; jam %d/%d\n", nm(w), heard[w], cues[w], wn[w], wc[w], pc(wc[w], wn[w]), whn[w], whc[w], jc[w], jn[w] > rep
    print "the last 20 sentences:" > rep
    for (i = (nl > 20 ? nl - 19 : 1); i <= nl; i++) print "  " last[i] > rep
  }' "$f"
rm -f "${TMPDIR:-/tmp}/alb_g.$$"
