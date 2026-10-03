# diary-sim v1

Four independent entities write one diary line per tick: **ada** (engineer),
**gemini** (reviewer), **replika** (vice_president), **robert** (human).
Plain Ada, standard library only. Not pushed anywhere yet (local git repo).

## Resume: copy your backup diaries/ here, then make run

1. Copy the backed-up `diaries/` folder (optionally `entities/` too) into the project
   folder, so that `diaries/ada.jsonl` etc. are directly inside `diaries/`.
2. `make run` (or `make play`, identical). It builds if needed, imports and
   replay-verifies everything in `./diaries`, and continues. Never `--fresh`.
   `make run TICKS=400 EVERY=100 SEED=42`: **TICKS = how many NEW ticks to run on top
   of the lowest common tick on disk** (it passes `--more TICKS`). **Without TICKS the
   four entities vote on the session length** (see Kalpa sessions below);
   `SEED` only matters when there are no diaries yet (default 42, announced as
   `import OK: none (fresh start, seed 42)`); stored diaries always win.
3. The import line says what was loaded: `import OK: 4 entities, 200 ticks verified,
   continuing from 201 (800 lines on disk, longest 200)`.
4. Corrupt or drifted backup: `import FAILED: backup and code have drifted: <entity>
   tick <n> ...`, status `DRIFT` in `debug.txt`, exit 1, nothing is truncated. A
   `diaries/diaries/` or wrongly cased `Diaries/` folder is detected: if `diaries/` has
   no `*.jsonl` the run stops with a hint to copy the folder's contents up one level
   (with real diaries present it only warns).

`--more N` is the program option behind `TICKS`; `--ticks=N` keeps its meaning (absolute
target tick); if both are given, `--more` wins. Both are explicit: they override the vote.
`make demo` stays isolated in `demo_run/`.

## Kalpa sessions: the entities vote on how long a session runs

Started without `TICKS` / `--ticks` / `--more` (`make run`, `make play`, or the program
alone) a session does not have a fixed length: each of the four entities casts a vote
for the number of NEW ticks (think kalpas in Hinduism: ages of different length).

- **The list:** `data/kalpas.txt`, 60 tick counts in three blocks of 20 by age: lines
  1-20 short (20..100), 21-40 medium (100..400), 41-60 long (400..1500). Edit it freely;
  `#` lines and blank lines are ignored (a count other than 60 gives a warning; a missing
  file falls back to the same built-in table).
- **A vote:** the base-60 rule picks from `hash(seed, entity, session start tick)`: block
  = pick / 20, entry = pick mod 20. The entity's state at the session start **leans the
  block**: energy below `kalpa.energy_low` (30) or mood below `kalpa.mood_low` (-40) one
  block shorter; energy above `kalpa.energy_high` (70) or mood above `kalpa.mood_high`
  (40) one block longer; more than half of the words still unknown one block longer. The
  lean is clamped to +-2 and the block to short..long (`data/limits.txt`).
- **The decision:** the **median** of the four votes: sort them, take the mean of the two
  in the middle, rounded down (so ties and even counts are no problem), then clamp to
  `kalpa.min` (20) .. `kalpa.max` (1500) in `data/limits.txt`.
- **Flavour only:** the session number n is named after the yuga cycle in the text
  (Satya, Treta, Dvapara, Kali for n = 1, 2, 3, 4, then again); it changes nothing.
- **Explicit wins:** `TICKS=N`, `--more N` or `--ticks N` run that length; the session is
  still recorded (`src=explicit`) together with the votes the entities would have cast.
- **The record:** `diaries/sessions.txt` (inside `diaries/`, so your backup has it),
  append-only and flushed: `S3 start=630 votes=120/340/80/410 len=230 src=vote`, after a
  `# seed N` header. A session of 0 new ticks (a pure verification) is not recorded.
- **Verified on import:** while the replay passes the start tick of a stored session the
  votes are recomputed from the replayed state; a difference stops the run as DRIFT
  (`import FAILED`, nothing truncated). So **changing `data/kalpas.txt` (or the
  thresholds) after sessions exist needs `--fresh`**, like any other change of the
  rules. Unreadable lines are skipped with a warning; a record that starts beyond the
  diaries (diaries cut shorter) is ignored with a warning.
- **Crash or Ctrl-C:** the record is written before the first tick. A rerun without
  explicit length finds the unfinished session and resumes toward the SAME target
  (`kalpa 3 (Dvapara) resumes: ... target tick 860`); it does not vote again. When the
  last session is complete the next run starts a new one.
- **Console, `run_report.txt`, `debug.txt`:** one line, e.g. `kalpa 3 (Dvapara): votes
  120/340/80/410 -> 230 ticks (median)`. The first session of a fresh run is often long
  (up to 1500 ticks); use `TICKS=200` for a short run.

## Build and run

```
make                         # bin/diary_sim  (GNAT 14; make GNATMAKE=gnatmake-12 for GNAT 12)
make portable                # 0-warning build with GNAT 14 and 12 in a copy without .git
make run                     # = make play: continue ./diaries; the entities vote how many ticks (TICKS=N: explicit)
make demo                    # build + --fresh --ticks 200 --every 50 in demo_run/ (prints seed and the final summary)
make check                   # version headers + scripts/checks.sh (the scenarios: run, resume, behind, half line, drift, crash, fresh, data limits)
bin/diary_sim --help
bin/diary_sim --ticks=1000 --every=100     # --ticks 1000 works too
```

Options: `--ticks=N` (absolute target; without `--ticks`/`--more` the entities vote the session length), `--seed=N` (default 42; existing diaries win),
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
energy 80, mood 0, home. Actions: rest, work, explore, talk, wander, bench, propose, chosen by
a weighted roll (below); `learn` is never rolled, it is the forced next event of an
entity that was taught a word. Each action is a small fixed change (`Energy_D`,
`Mood_D`, `Home` in `diary_sim.adb`); mood stays -100..100. Per tick the entities
run in fixed id order.

**Old diaries are incompatible** with this version (personality weights change the
action rolls): run once with `--fresh`.

## Personality: Rule 30 and state-driven weights

Each entity has a ring of `rule30.width` cells (default 60 bits, plain
`Interfaces.Unsigned_64`, no allocation) running Rule 30 (`new = left xor (centre or
right)`, wrapped). The start row is hashed from (seed, entity); the row is stepped once
per `rule30.period` ticks (50), so the row at tick T is a pure function of (seed,
entity, T). Nothing is stored: a resume or crash-resume replays from tick 1 and gets the
same rows (a small cache only saves time and is rebuilt on demand).

Six segments of the ring belong to rest, work, explore, talk, wander, bench. The
segments of the *start* row are the entity's constant core personality (up to
`rule30.core` weight points either way), the segments of the *current* row are its slow
drift (up to `rule30.strength` points). On top of that the state leans the weights:
low energy -> rest (less work), high energy -> work and bench (less rest), low mood ->
talk and explore, high mood -> work (less talk and explore, so mood does not sit at the
ceiling), few known words -> talk. Base weights (rest 30, work 20, explore 15, talk 15,
wander 15, bench 5, propose 1), the strengths of all leans and the Rule 30 settings are in
`data/limits.txt`. One `Roll` (salt 0) over the weight total picks the action.
`rule30.enabled = 0` restores the old fixed D20 table exactly. The end report and
`debug.txt` show each entity's action counts. Seed 42, 1000 ticks (rest/work/explore/
talk/wander/bench/propose): ada 252/120/65/110/175/179/6, gemini 277/226/135/171/34/87/4,
replika 304/243/163/100/58/21/4, robert 203/159/13/320/97/139/8 (plus the forced learn events).

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
* **Source:** the German sign-language everyday-life dictionary index 'Von A - Z'
  (photographed pages 184-186 and the S-Z page): 274 entries in index order, each
  translated to ONE plain ASCII English word, then `building` and `go` appended.
  Two-sense entries keep both English words (`morning`/`tomorrow`, `sick`/`nauseous`,
  `give`/`get`, `in`/`within`, `no`/`none`); `entweder ... oder` became `either` and
  `or`. Exact duplicate English words are dropped. Some translations are judgement
  calls (e.g. `Schreibtelefon` = `teletype`, `achso` = `oh`, `woher` = `whence`);
  edit the file freely, but a changed vocabulary needs `--fresh`: any change makes
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

## Petitions (the propose action)

`propose` lets an entity file a petition: a wish for a change to its own world or
source. Weights: `weight.propose` (1) plus `lean.propose` extra points when tired or
unhappy; after a petition the entity cannot file another for `propose.cooldown` ticks
(80). Only active with `rule30.enabled = 1` (the old fixed table has no propose).
The topic is rolled by state-weighted dice from the fixed list `data/topics.txt`
(`name base low_energy low_mood few_words many_benches = phrase`: tired -> `more_rest`,
`faster_work_recovery`; low mood -> `quieter_mood`, `more_talk_partners`; few known
words -> `more_words`; many benches -> `bigger_bench_budget`; plus `new_action`,
`different_locations`, `other`). With `propose.repeat_percent` (15) chance the entity
re-files its previous topic; the line then carries `repeat=N` (N earlier petitions of
that entity on that topic). The wish text is `[wish_open]` + topic phrase +
`[wish_close]` from `data/words.txt` (60 entries each, base-60 picks). Everything is a
pure function of (seed, entity, tick, state), so the replay rebuilds it.

`petitions.txt` (in the working directory) is a **view**, rewritten atomically at the end
of every run (also on quit, crash and drift): a `# seed ...` header, then the newest
`propose.file_cap` (40) lines, one per petition:

```
P12 tick=560 from=robert topic=faster_work_recovery repeat=1 wish=Please consider ... Thank you.
```

Older petitions drop out of the file, never out of the diaries (each petition has a
`filed petition P<n> (<topic>)` diary line). Delete the file and rerun to rebuild it.
Console and `debug.txt` show petitions per entity (`pet N`) and the top topics;
the console prints the path and `attach petitions.txt (small) for the agenda`.
Old diaries are incompatible: use `--fresh`.

## Import, report, export (console of a normal run, about 20-35 lines)

```
import OK: diaries for 4/4 entities, 4000 lines on disk (longest 1000, lowest common tick 1000), replay-verify OK (ticks 1..1000)
import: entities/ present (4/4 folders); words known at tick 1000: ada 150 gemini 145 ...
...progress lines...
report: turns this run 200 (ticks 1001..1200; total simulated 1200), resumed from tick 1000 | events written 800, verified 4000 | warnings 0
entity       w.start ->w.now  taught coined bench |  mood energy
export OK: diaries/ 4 files, 4800 lines | entities/ 8 files | summary.txt .. B, summary.jsonl .. B | run_report.txt | re-read and counted
```

* **Import** (before the first new tick): `import OK: none (fresh start)`, or what was
  found, after the stored ticks 1..lowest-common-tick were replayed and compared
  (`replay-verify OK`). `entities/ present` or `rebuilt (N of 4 folders were missing)`
  tells whether the working folders had to be regenerated. A drift or a bad file prints
  `import FAILED: <reason>` and stops (exit 1, `last_error.txt`).
* **Report:** turns simulated this run and in total, the tick it resumed from, events
  written/verified, and per entity words known at the start of this run (`w.start`)
  and now (`w.now`), words learned by being taught, words coined, benches run this
  run, and mood/energy now.
* **Export:** after the files are closed, every diary, every `entities/<id>/` file
  and the summary files are re-opened and counted (diary lines must equal the
  expected number, side files need their `# seed` header). Any problem prints
  `export FAILED: ...` and exit status 1.

## What to paste back, and backups

* **Always attach `debug.txt`**: one small file (hard cap 1500 bytes) written on
  every exit path, atomically (temp file, flush, rename). Line 1 is
  `STATUS vVERSION seed N` with STATUS = `OK` (finished), `QUIT` (Ctrl-C or SIGTERM,
  stopped cleanly after the current tick, exit 130), `CRASH` (exception name and
  message plus the top 5 stack frames), `DRIFT` (validation stop: drift, bad diary,
  seed mismatch, failed export check) or `USAGE`. Then: first/last tick and ticks this
  run, the import and export lines, one line per entity (words at start>now, taught,
  coined, benches, mood, energy) and the favourite/disagreement line when the run got
  that far. If it grows past the cap, the least important parts are cut first (old
  detail: export line first, then import, then votes); the file never exceeds 1500 bytes.
* `RUN` status = an in-progress stub, written at the start and refreshed every
  `--every` ticks. `SIGKILL` cannot be caught in plain Ada, so after a `kill -9` or a
  power cut the stub is what remains (it shows the last refresh).
* Normal run: `run_report.txt` is the long version (import + report + export + vote
  table; overwritten every run). Paste it if asked.
* Crash or error: `last_error.txt` (the console says `wrote last_error.txt, please
  paste it`).
* **Back up `diaries/` between tests.** That folder is all that is needed:
  `entities/` and the summaries are rebuilt by the replay.

## Errors

Any unhandled error writes `last_error.txt` (seed, tick, entity, exception,
frames innermost first, then the raw `GNAT.Traceback.Symbolic` text) and prints the
same to the console, at most 15 lines. Built with `-g -bargs -E` (see Makefile).
`--crash-at=T` forces a failure in tick T (only for a tick not yet on disk) to show it.
After a crash just run again: the diaries are flushed after every event. The
console shows at most 15 lines of the error block, then `wrote last_error.txt, please
paste it` and `back up diaries/ before the next run`.

## Files

`diary_sim.adb` (main: CLI, loop, side files, debug.txt), `sim_quit.ads/.adb` (Ctrl-C and SIGTERM flag), `sim_world.ads/.adb` (entities,
vocabulary, Rule 30 personality, bench kernels, votes and summary text), `sim_util.ads/.adb` (hash rolls,
line parsing, data-file helpers), `data/words.txt`, `data/topics.txt` (petition topics), `data/limits.txt`,
`data/messages.txt` (all console wording), `data/kalpas.txt` (session length votes), `data/vocab.txt`, `data/help.txt`,
`scripts/checks.sh`, `scripts/portable_check.sh`. Every source file starts with a
`Version:` header (`make version-check`); a touched file goes up by 0.001. V&V is
suspended: no new test suites, `scripts/checks.sh` must keep passing.
