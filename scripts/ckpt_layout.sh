#!/bin/bash
# Version: 0.001
# The guard against a forgotten checkpoint format bump (build 0.059, docs/CHECKPOINT.md "The layout guard").
# A hash over everything that decides the bytes of the state checkpoint's payload: the State_IO procedures of the modules, the
# section list and Main_State_IO / Sect_IO / All_State_Write / All_State_Read of diary_sim.adb, and the package-level declarations
# they reach (the streamed variables, their types, the element types of the vectors, the constants of the array bounds, followed
# from name to name).  Comments and spacing do not count.
#   scripts/ckpt_layout.sh [ROOT]          prints "ckpt_layout: <Ckpt_Format> <hash>"
#   scripts/ckpt_layout.sh --list [ROOT]   also lists the declarations the hash covers
#   scripts/ckpt_layout.sh --check [ROOT]  compares with the line recorded in docs/CHECKPOINT.md; exit 1 = FAIL:
#     the code changed and the recorded hash did not -> "bump Ckpt_Format"; the format was bumped but not recorded -> "record ...".
mode=print; case $1 in --check) mode=check; shift ;; --list) mode=list; shift ;; esac
root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
line=$(cd "$root" && perl -e '
  use strict; use warnings; use Digest::MD5 qw(md5_hex);
  my $list = $ARGV[0] eq "list"; my (%decl, @bodies);
  sub norm { my $t = shift; $t =~ s/--[^\n]*//g; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; return lc $t; }
  for my $f (sort glob("*.ads *.adb")) {
    open my $h, "<", $f or die "$f: $!"; my $src = do { local $/; <$h> }; close $h;
    while ($src =~ /^(\s*procedure\s+(State_IO|Main_State_IO|Sect_IO|All_State_Write|All_State_Read)\s*\(.*?\bend\s+\2\s*;)/msg) {
      push @bodies, "$f: " . norm($1);
    }
    push @bodies, "$f: " . norm($1) while $src =~ /^(   function Sect_Name\b.*?\);)\s*$/msg;
    my @l = split /\n/, $src;
    for (my $i = 0; $i < @l; $i++) {
      my @names; my $rec = 0;
      if ($l[$i] =~ /^   (?:sub)?type (\w+)\b/) { @names = ($1); $rec = 1; }
      elsif ($l[$i] =~ /^   package (\w+) is new\b/) { @names = ($1); }
      elsif ($l[$i] =~ /^   (\w+(?:\s*,\s*\w+)*)\s*:(?!=)/) { @names = split /\s*,\s*/, $1; }
      next unless @names;
      my $t = ""; my $j = $i; my $isrec = 0;
      while ($j < @l) {
        my $x = $l[$j]; $x =~ s/--.*//; $t .= "$x\n";
        $isrec = 1 if $rec && $x =~ /\brecord\b/ && $x !~ /\bnull\s+record\b/ && $x !~ /\bend\s+record\b/;
        last if $isrec ? $x =~ /\bend\s+record\s*;/ : $x =~ /;/;
        $j++;
      }
      push @{ $decl{lc $_} }, "$f: " . norm($t) for @names;
    }
  }
  my (%seen, %took); my @queue;
  my $push = sub { for my $w ($_[0] =~ /[a-z_][a-z0-9_]*/g) { push @queue, $w unless $seen{$w}++ } };
  $push->($_) for @bodies;
  while (defined(my $w = shift @queue)) {
    next unless $decl{$w};
    for my $d (@{ $decl{$w} }) { next if $took{$d}++; $push->($d) }
  }
  my @all = (@bodies, sort keys %took);
  if ($list) { print "  $_\n" for @all; }
  print "HASH ", substr(md5_hex(join("\n", @all)), 0, 16), " ", scalar(@bodies), " ", scalar(keys %took), "\n";
' "$mode")
hash=$(echo "$line" | sed -n 's/^HASH \([0-9a-f]*\) .*/\1/p'); nb=$(echo "$line" | sed -n 's/^HASH [0-9a-f]* \([0-9]*\) .*/\1/p')
fmt=$(sed -n 's/^ *Ckpt_Format : constant := \([0-9]*\);.*/\1/p' "$root/diary_sim.adb" | head -n 1)
[ -n "$hash" ] && [ -n "$fmt" ] && [ "${nb:-0}" -ge 16 ] || { echo "ckpt_layout: FAIL - could not read the State_IO bodies or Ckpt_Format ($line)"; exit 2; }
[ "$mode" = list ] && echo "$line" | grep -v '^HASH '
now="ckpt_layout: $fmt $hash"
[ "$mode" = check ] || { echo "$now"; exit 0; }
rec=$(grep -E '^ckpt_layout: [0-9]+ [0-9a-f]+$' "$root/docs/CHECKPOINT.md" 2>/dev/null | tail -n 1)
rfmt=$(echo "$rec" | cut -d' ' -f2); rhash=$(echo "$rec" | cut -d' ' -f3)
if [ "$rec" = "$now" ]; then echo "ckpt_layout: PASS (format $fmt, layout hash $hash = docs/CHECKPOINT.md)"; exit 0; fi
if [ -z "$rec" ]; then echo "ckpt_layout: FAIL - no 'ckpt_layout: <format> <hash>' line in docs/CHECKPOINT.md (now: $now)"; exit 1; fi
if [ "$rfmt" = "$fmt" ]; then
  echo "ckpt_layout: FAIL - the streamed state changed (State_IO or a streamed declaration: layout hash $hash, recorded $rhash) but Ckpt_Format is still $fmt: bump Ckpt_Format"
  echo "  in diary_sim.adb: Ckpt_Format := $((fmt + 1)) and Ckpt_Layout_Since := $((fmt + 1)) (older checkpoints then replay once), then record"
  echo "  'ckpt_layout: $((fmt + 1)) <hash>' in docs/CHECKPOINT.md (scripts/ckpt_layout.sh prints it).  Only if the bytes are truly the same"
  echo "  (a rename, a reorder of declarations): record '$now' without a bump."
  exit 1
fi
echo "ckpt_layout: FAIL - Ckpt_Format is $fmt but docs/CHECKPOINT.md records format $rfmt: record the line '$now' there"
exit 1
