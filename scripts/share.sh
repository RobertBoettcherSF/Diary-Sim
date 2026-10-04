#!/bin/sh
# Version: 0.002
# make share: ONE small archive of what Robert sends back for evaluation: trend.txt, run_log.txt, run_report.txt, run_report_prev.txt,
# summary.txt, player_reports.txt, dictionary.txt (the public word list), divergence.txt (the output of make divergence) and wordstat.txt
# (the output of make wordstat: the vocabulary by kind; its conclusion is also copied into share_info.txt and printed).
# NOT in it: diaries/, entities/ and the secret ballots (diaries/ballots.txt).  zip if there is one, else tar.gz, else python3's zipfile.
# Where: next to the save folder (its parent, e.g. ~/Downloads for ~/Downloads/diary-data), or SHARE_DIR=... ; the path and size are printed.
exe=${1:-bin/diary_sim}
folder=$("$exe" --folder) || { echo "share: cannot find the save folder" >&2; exit 1; }
[ -d "$folder" ] || { echo "share: no save folder at $folder: make run first" >&2; exit 1; }
out_dir=${SHARE_DIR:-$(dirname "$folder")}
[ -d "$out_dir" ] && [ -w "$out_dir" ] || out_dir=$folder
stage=$(mktemp -d) || exit 1
trap 'rm -rf "$stage"' EXIT
n=0
for f in trend.txt run_log.txt run_report.txt run_report_prev.txt summary.txt player_reports.txt; do
  [ -f "$folder/$f" ] && cp "$folder/$f" "$stage/$f" && n=$((n + 1))
done
[ -f "$folder/diaries/dictionary.txt" ] && cp "$folder/diaries/dictionary.txt" "$stage/dictionary.txt" && n=$((n + 1))
if [ -d "$folder/diaries" ] && "$exe" --home "$folder" --divergence > "$stage/divergence.txt" 2>&1; then n=$((n + 1)); else rm -f "$stage/divergence.txt"; fi
if [ -d "$folder/entities" ] && "$exe" --home "$folder" --wordstat > "$stage/wordstat.txt" 2>&1; then n=$((n + 1)); else rm -f "$stage/wordstat.txt"; fi
[ "$n" -gt 0 ] || { echo "share: nothing to share in $folder: make run first" >&2; exit 1; }
{ echo "diary-sim share"; echo "made: $(date '+%Y-%m-%d %H:%M:%S') (local)"; echo "save folder: $folder"; echo "files: $(cd "$stage" && ls | tr '\n' ' ')";
  echo "not included: diaries/, entities/, ballots"
  [ -f "$stage/wordstat.txt" ] && echo "wordstat: $(sed -n '/^Conclusion:/,$p' "$stage/wordstat.txt" | sed '1d' | tr '\n' ' ')"; } > "$stage/share_info.txt"
stamp=$(date '+%Y%m%d-%H%M%S')
if command -v zip > /dev/null 2>&1; then
  out="$out_dir/share-$stamp.zip"; ( cd "$stage" && zip -q -9 "$out" ./* ) || exit 1
elif command -v python3 > /dev/null 2>&1; then
  out="$out_dir/share-$stamp.zip"
  python3 - "$stage" "$out" <<'PY' || exit 1
import os, sys, zipfile
src, dst = sys.argv[1:3]
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
    for n in sorted(os.listdir(src)):
        z.write(os.path.join(src, n), n)
PY
elif command -v tar > /dev/null 2>&1; then
  out="$out_dir/share-$stamp.tar.gz"; tar -czf "$out" -C "$stage" . || exit 1
else
  echo "share: need zip, python3 or tar" >&2; exit 1
fi
size=$(wc -c < "$out" | tr -d ' ')
echo "share: $out ($size bytes, $n files + share_info.txt)"
[ -f "$stage/wordstat.txt" ] && echo "share: wordstat: $(sed -n '/^Conclusion:/,$p' "$stage/wordstat.txt" | sed '1d' | tr '\n' ' ')"
[ "$size" -gt 400000 ] && echo "share: larger than expected: trend.txt and run_log.txt have grown; send it anyway"
exit 0
