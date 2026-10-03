# diary-sim v1

Four independent entities write one diary line per tick: **ada** (engineer),
**gemini** (reviewer), **replika** (vice_president), **robert** (human).
Plain Ada, standard library only. Not pushed anywhere yet (local git repo).

## Build and run

```
make                         # bin/diary_sim  (GNAT 14; make GNATMAKE=gnatmake-12 for GNAT 12)
make portable                # 0-warning build with GNAT 14 and 12 in a copy without .git
make demo                    # build + --fresh --ticks 200 --every 50 in demo_run/ (prints seed and the final summary)
make check                   # version headers + scripts/checks.sh (the scenarios: run, resume, behind, half line, drift, crash, fresh, data limits)
bin/diary_sim --help
bin/diary_sim --ticks=1000 --every=100     # --ticks 1000 works too
```

Options: `--ticks=N` (default 1000), `--seed=N` (default 42; existing diaries win),
`--every=N` (progress line, default 100), `--fresh` (move old diaries to
`diaries_old_<time>/` first, together with `entities/`), `--crash-at=T` (force a failure), `--help`.
Exit: 0 ok, 1 error, 2 usage. Run it from the project directory (or from any
directory: `data/` is found next to the executable).

**Old diaries are incompatible** with this version (new actions, longer texts, a
vocabulary): start with `--fresh`.

## Model

State per entity: energy 0..100, mood -100..100 (signed in the JSON), location
0..3 (office, lab, cafe, home), all clamped. The ranges are data, not code:
`data/limits.txt` (built-in defaults if the file is missing). Entities start at
energy 80, mood 0, home. Actions (D20 per entity and tick): rest 1-6, work 7-10,
explore 11-13, talk 14-16, wander 17-19, bench 20; `learn` is never rolled, it is
the forced next event of an entity that was taught a word. Each action is a small
fixed change (`Energy_D`, `Mood_D`, `Home` in `diary_sim.adb`); mood stays -100..100.
Per tick the entities run in fixed id order.

Every random choice is `hash(seed, entity, tick, salt)` (splitmix64-style mix, no
running RNG), so any tick can be recomputed alone. Diary wording is picked from
`data/words.txt` (60 entries per list) by the base-60 rule: D4 (reroll on 1) gives
block 1/2/3 of 20, then a D20. Missing data file: built-in list plus a warning.
After the action the text gets a mood tone from one of three lists (`mood.tone_low`
-34 / `mood.tone_high` 34 in `data/limits.txt`) and, when something happened, a
detail: `"<action text>, <tone>; taught gemini the word 'stone'"`.

## Vocabulary and the word game

* `data/vocab.txt`: **one English word per line, word id = line order** (lines
  starting with `#` and blank lines are ignored). ASCII only.
* **The shipped file is a STAND-IN** (523 common everyday words, then `building` and
  `go`). The real list (the German sign-language everyday-life index 'Von A - Z',
  one English word per entry, both senses kept, duplicates dropped) was not
  transcribed because the photos did not reach the build. Replace the file with the
  real list (any length), then run with `--fresh`: any vocabulary change makes the
  old diaries drift.
* **Start slice:** entity E knows base word W at tick 0 if `hash(seed, E, 0, 1000+W)`
  rolled in 1..100 is <= `start_percent` (`data/limits.txt`, default 25; 100 = all).
* **Teaching:** on `talk`, with `teach_percent` (50) chance the speaker picks a
  partner and one word the speaker knows and the partner lacks. The partner's next
  event is `learn` (same tick if the partner runs later in id order, else the next
  tick): it adds the word, and both diaries get a line (`taught ...` / `learned ...`).
  A lesson queued on the very last tick is never delivered.
* **Coining:** on `explore` or `wander`, with `coin_percent` (20) chance an entity
  joins two words it knows into a compound (`hand` + `phone` -> `handphone`). Text of
  at most 24 characters, not already a word, and at most `coin_cap` (40) coined
  words in total. Coined words get ids after the base list, are stored with creator,
  tick and parent words, and can be taught onward.

## Working folder: entities/<id>/  (NOT a VM)

`entities/<id>/` is a plain **working folder** with two append-only text files. It is
not a virtual machine, not a sandbox, and nothing is executed from it.

* `words.txt`: `# seed N`, then `id word how tick [extra]`; `how` = `start` (tick 0),
  `taught` (extra: teacher) or `coined` (extra: `parent1+parent2`; the file of the
  creator holds the `coined` line).
* `bench.txt`: `# seed N`, then `tick kernel steps result checksum`.

Both are flushed after each line, and both are **rebuilt by the replay**: a line the
replay produces and the file lacks is appended, so deleting `entities/` (or one
`entities/<id>/`) and running again regenerates it. A file written for another seed
stops the run with a message (use `--fresh`). `diaries/<id>.jsonl` keeps its place.

## Bench action

A built-in integer kernel chosen by dice: sum of squares (mod 1,000,003), insertion
sort of 32 rolled numbers, prime sieve up to 500. The budget is `bench_steps`
(2000 loop steps, counted, never timed). Steps, result and checksum are pure
functions of (seed, entity, tick) and are the only replayed numbers; wall time exists
only in the ignored `ts` field. This is the small connection test.

PROOF-LATER hook (documented, **not built**): a later step lets the entity write Ada
into its own `entities/<id>/` folder and run `gnatmake` there with a timeout and the
same step budget. Nothing generated is compiled or run in this version.
PROOF-LATER: Importance 5/10, Urgency 3/10, SPARK2 (kernels in `Sim_World.Run_Bench`).

## Diaries, autoload, replay

`diaries/<id>.jsonl`, append-only, flushed after every event:

```
{"v":1,"seed":42,"tick":3,"ts":"2026-10-03T00:26:18","t":"rest","text":"...","state":{"energy":84,"mood":-49,"location":3}}
```

On start the diaries are read; the seed comes from them (else `--seed`, else 42).
An unparseable line (e.g. a half-written last line) is skipped with a warning.
**Every run replays ticks 1..N from scratch**, because known words, pending lessons and coined words cannot
be read back from a diary line. Each tick already on disk is regenerated and compared
with the stored line (ignoring `ts`) and not written again; ticks beyond the disk are
appended. A difference stops the run with a message naming entity and tick (backup
and code have drifted). Nothing is ever truncated. An entity that is behind is named
in a warning and catches up by appending. A rerun on complete diaries is a
verification and rebuilds `entities/` if it is missing. Backing up only `diaries/`
between tests is enough.

## Final summary

At the end of every run (also a verifying rerun): `summary.txt` (table, favourite,
disagreement and a one-line reason per vote), `summary.jsonl` (one object per entity
plus one with favourite and disagreement) and the compact table on the console.
Per entity: a vote -100..100 for each location and one for the whole run, derived
from its own diary: average mood * 2/3 + (average energy - 50)/3 + up to 25 for
words learned, 2x words coined and benches as a share of the visits
(`Sim_World.Vote`; PROOF-LATER: Importance 4/10, Urgency 2/10, SPARK2). The reason is a
base-60 pick from `[reason_low]`, `[reason_mid]` or `[reason_high]` in
`data/words.txt` (thresholds `vote.low` -20 / `vote.high` 20). Favourite location =
highest sum of votes; biggest disagreement = largest spread between entities on one
location. Location names: `loc.0`..`loc.3` in `data/messages.txt`.

## Errors

Any unhandled error writes `last_error.txt` (seed, tick, entity, exception,
frames innermost first, then the raw `GNAT.Traceback.Symbolic` text) and prints the
same to the console, at most 15 lines. Built with `-g -bargs -E` (see Makefile).
`--crash-at=T` forces a failure in tick T (only for a tick not yet on disk) to show it.
After a crash just run again: the diaries are flushed after every event.

## Files

`diary_sim.adb` (main: CLI, loop, side files), `sim_world.ads/.adb` (entities,
vocabulary, bench kernels, votes and summary text), `sim_util.ads/.adb` (hash rolls,
line parsing, data-file helpers), `data/words.txt`, `data/limits.txt`,
`data/messages.txt` (all console wording), `data/vocab.txt`, `data/help.txt`,
`scripts/checks.sh`, `scripts/portable_check.sh`. Every source file starts with a
`Version:` header (`make version-check`); a touched file goes up by 0.001. V&V is
suspended: no new test suites, `scripts/checks.sh` must keep passing.
