#!/bin/bash
# Version: 0.001
# make footprint: where the kilobytes are.  Read-only; measures what exists (run make, make small first).
# Source and data bytes, the binaries (unstripped / stripped / debug share), and the code size per unit (size -t text+data+bss of obj/*.o).
cd "$(dirname "$0")/.." || exit 1
kb() { awk -v b="$1" 'BEGIN { printf "%d KB", (b + 512) / 1024 }'; }
echo "source  : $(cat ./*.ad[sb] | wc -c) bytes in $(ls ./*.ad[sb] | wc -l) files; README $(wc -c < README.md); scripts $(cat scripts/* | wc -c)"
echo "data    : $(cat data/*.txt | wc -c) bytes in $(ls data/*.txt | wc -l) files"
ls -l data/*.txt | awk '{ print $5, $9 }' | sort -n -r | head -8 | awk '{ printf "          %7d  %s\n", $1, $2 }'
for b in bin/diary_sim bin/diary_sim_small; do
  [ -x "$b" ] || continue
  full=$(stat -c %s "$b"); t=$(mktemp); strip -o "$t" "$b" 2>/dev/null; st=$(stat -c %s "$t"); rm -f "$t"
  echo "binary  : $b $full bytes ($(kb "$full")), stripped $st ($(kb "$st")), symbols + debug info $((full - st)) ($(( (full - st) * 100 / full )) %)"
  size "$b" | tail -1 | awk '{ printf "          text %d  data %d  bss %d\n", $1, $2, $3 }'
done
for d in obj obj_small; do
  ls $d/*.o > /dev/null 2>&1 || continue
  echo "units   : $d/*.o  (text, data, bss in bytes; obj/ is built with -g: its debug sections are not counted by size)"
  size $d/*.o | awk 'NR > 1 && $6 !~ /b~/ { n = $6; sub(/.*\//, "", n); printf "          %-16s %9d %7d %6d\n", n, $1, $2, $3 }' | sort -k2 -n -r
done
for b in bin/diary_sim bin/diary_sim_small; do
  [ -x "$b" ] || continue
  echo "runtime : libgnat / libgnarl are shared libraries, NOT inside $b: $(ldd "$b" 2>/dev/null | awk '/libgnat/ { print $3 }' | xargs -r stat -L -c %s) bytes on disk"
  break
done
