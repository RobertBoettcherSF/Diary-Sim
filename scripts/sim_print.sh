#!/bin/sh
# Version: 0.001
# The fingerprint of what decides the replay of OLD sessions (build 0.060, docs/CHECKPOINT.md "Incremental verify"): the simulation
# sources (diary_sim.adb and the sim_* units the tick loop runs; NOT the reports, the menu, the voices, the checkpoint code, the
# scripts) without comments, spacing and the Build constant, and the rule files of data/ without comments and blank lines (not the display text).  A
# different fingerprint than at the last passed make verify-full makes it due (checkin.txt), because an incremental make verify only
# checks the ticks after its checkpoint and cannot see a change that alters how old sessions replay.
#   scripts/sim_print.sh [ROOT]          prints the 16-hex-digit fingerprint
#   scripts/sim_print.sh --list [ROOT]   also lists the files it covers
list=0; [ "$1" = --list ] && { list=1; shift; }
root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$root" || exit 1
sim="diary_sim.adb"
for u in util world dharma things screen chess games robot govern preport next visit chat trial records active store; do
  for x in ads adb; do [ -f "sim_$u.$x" ] && sim="$sim sim_$u.$x"; done
done
rules=""
for f in data/*.txt; do
  case ${f#data/} in messages.txt|help.txt|menu.txt|fonts.txt|names.txt|voices.txt|wordstat.txt|evolve.txt|frustration.txt|ledger.txt) ;;
    *) rules="$rules $f" ;; esac
done
[ "$list" = 1 ] && for f in $sim $rules; do echo "  $f"; done
perl -e '
  use strict; use warnings; use Digest::MD5 qw(md5_hex);
  my $all = "";
  for my $f (@ARGV) {
    open my $h, "<", $f or die "$f: $!"; my @l = <$h>; close $h;
    $all .= "== $f\n";
    for my $x (@l) {
      if ($f =~ /\.ad[bs]$/) { next if $x =~ /^\s*Build : constant String :=/;   # the build number is no simulation
        $x =~ s/^((?:[^"\n-]|"[^"\n]*"|-(?!-))*)--.*$/$1/; }
      else { next if $x =~ /^\s*#/; }
      $x =~ s/\s+/ /g; $x =~ s/^ | $//g; next if $x eq "";
      $all .= "$x\n";
    }
  }
  print substr(md5_hex($all), 0, 16), "\n";
' $sim $rules
