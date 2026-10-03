# diary-sim v1

Four independent entities write one diary line per tick: **ada** (engineer),
**gemini** (reviewer), **replika** (vice_president), **robert** (human).
Plain Ada, standard library only. Not pushed anywhere yet (local git repo).

## Build and run

```
make                         # bin/diary_sim  (GNAT 14; make GNATMAKE=gnatmake-12 for GNAT 12)
make portable                # 0-warning build with GNAT 14 and 12 in a copy without .git
make check                   # version headers + scripts/checks.sh (the scenarios below)
bin/diary_sim --help
bin/diary_sim --ticks=1000 --every=100
```

Options: `--ticks=N` (default 1000), `--seed=N` (default 42; existing diaries win),
`--every=N` (progress line, default 100), `--fresh` (move old diaries to
`diaries_old_<time>/` first), `--crash-at=T` (force a failure), `--help`.
Exit: 0 ok, 1 error, 2 usage. Run it from the project directory (or from any
directory: `data/` is found next to the executable).

## Model

State per entity: energy 0..100, mood 0..100, location 0..3 (office, lab,
cafe, home), all clamped. Actions: rest, work, explore, talk, wander, each a
small fixed change (`Energy_D`, `Mood_D`, `Home` in `diary_sim.adb`). `talk` only
writes a diary line. Entities do not interact. Per tick they run in fixed id order.

Every random choice is `hash(seed, entity, tick, salt)` (splitmix64-style mix, no
running RNG), so any tick can be recomputed alone. Diary wording is picked from
`data/words.txt` (60 entries per list) by the base-60 rule: D4 (reroll on 1) gives
block 1/2/3 of 20, then a D20. Missing data file: built-in list plus a warning.

## Diaries, autoload, replay

`diaries/<id>.jsonl`, append-only, flushed after every event:

```
{"v":1,"seed":42,"tick":3,"ts":"2026-10-03T00:26:18","t":"rest","text":"...","state":{"energy":84,"mood":49,"location":3}}
```

On start the diaries are read; the seed comes from them (else `--seed`, else 42).
An unparseable line (e.g. a half-written last line) is skipped with a warning.
The run resumes after the **lowest common tick**; resume state is read from the line
at that tick. An entity that is ahead replays the ticks already on disk: each
regenerated line is compared with the stored one (ignoring `ts`) and not written
again. A difference stops the run with a message naming entity and tick (backup and
code have drifted). Nothing is ever truncated. An entity that is behind is named in
a warning and catches up by appending.

## Errors

Any unhandled error writes `last_error.txt` (seed, tick, entity, exception,
frames innermost first, then the raw `GNAT.Traceback.Symbolic` text) and prints the
same to the console, at most 15 lines. Built with `-g -bargs -E` (see Makefile).
`--crash-at=T` forces a failure in tick T to show it.

## Files

`diary_sim.adb` (main), `sim_util.ads/.adb` (pure helpers: hash rolls, line parsing),
`data/words.txt`, `data/messages.txt` (all console wording), `data/help.txt`,
`scripts/checks.sh`, `scripts/portable_check.sh`. Every source file starts with a
`Version:` header (`make version-check`); a touched file goes up by 0.001.
