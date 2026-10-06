# The state checkpoint (`state.ckpt`)

Version: 0.003 (build 0.060; the checkpoint itself came with build 0.058, README "The state checkpoint")

A start used to replay the whole history to rebuild the state in memory: 13 minutes for 300000 ticks, about 35 minutes on Robert's
774600-tick save, growing every night. `state.ckpt` in the save folder holds the end state of the last run, so a start loads it in
seconds and replays only the ticks after it. Build 0.058 tied the checkpoint to the build and to a hash of every `data/*.txt`, so
every new zip forced the full replay again. Build 0.059 ties it to the **state format** instead.

## Why the build is no reason to replay

The rules of new behaviour are gated per session by markers on the `S` line of `diaries/sessions.txt` (`symstrict=1`,
`slowfloor=1`, `active=2`, ...): a new build replays the old sessions exactly as the build that wrote them did, and only sessions
that carry the new marker behave the new way. So the end state of the last session is the same whichever build computed it. A
saved end state stays correct across builds; it only stops fitting when the **layout of the state in memory** changes (a field
added, removed or retyped in a `State_IO`). That is what the format number tracks.

## The file (format 2)

A text header, one `key value` per line, up to the line `end`, then the binary payload.

* `diary-sim-ckpt 2` - the format = the state layout number (`Ckpt_Format` in `diary_sim.adb`).
* `build 0.059` - information only (which build wrote it).
* `data <hash>` and one `datafile <name> <hash>` per rule file of `data/` - information only (see "data/" below).
* one `startkey <key> <text>` per number of `data/` that the start read before the restore point (`-`: not in `data/`, the
  default) - compared (see "data/" below).
* `seed`, `tick`, `written`, `diary1..4` (bytes of each diary up to the tick), `counts` (sessions, votes and Robert's inputs up to
  the tick), `store1..15` (lines of each record store), `world`, `eff`, `section<K>` (information), `payload <bytes> <hash>`, and one
  `file <size> <fingerprint> <path>` per record file.
* The payload: 16 sections in a row, one per module (`world dharma things screen games robot govern preport next trial records visit
  active ledger main`, then `end`). Each section is **self-describing**: a 24-byte head (the tag = the section name in 8 characters,
  the byte length of the body, the FNV-1a hash of the body; both 8 bytes little-endian) and the body, which is that module's
  `State_IO` stream.

**Format 1** (build 0.058) has the same bodies without heads: a 4-byte marker before each section and the section offsets in the
header. Its state layout is the same as format 2, so build 0.059 reads it (`Ckpt_Layout_Since = 1`): a checkpoint written by 0.058
(for example by a long first `make slice`) is loaded without a replay, and the next write is format 2 (`ckpt_log.txt`:
`checkpoint: format 1 (build 0.058) loaded, the same state layout; the next write is format 2`).

## What a start checks, and what makes it replay

The start loads the checkpoint only if all of this holds; otherwise it replays everything and its first line says why
(`replay: checkpoint <why> - N ticks replayed`):

| why | when |
|---|---|
| `missing` | no `state.ckpt` |
| `off (--replay)`, `off (ckpt.enabled = 0)` | asked for a full replay |
| `version (format N, newer than this build's 2)` | written by a newer build |
| `layout (state layout changed: format N, ...)` | a format older than `Ckpt_Layout_Since` (the layout changed since) |
| `layout (state layout changed: <section>)` | a section whose tag is not the one this build expects there, sections after `end`, or a section that does not read back with exactly its byte length (the module streams more or fewer bytes than were written) |
| `corrupt (payload)`, `corrupt (section <name>)` | a payload or section hash that does not fit (a damaged file) |
| `data (a start value changed: <key> <old> -> <new>)` | a number of `data/` that the writer's start read (module `Init`, `Load_*`) has another text now |
| `stale (<file>)` | a record file changed or shorter in its recorded part (fingerprint), inputs or records added behind the checkpoint's tick, a store that does not fit its tick |

**No longer a reason** (build 0.059): another build, display text in `data/`, comments, and every rule-data change except a
start value (below).

A refusal never touches the record files; the run replays and writes a new checkpoint at its end.

## data/: start values refuse, everything else is information

* **Display text never counts**: `messages.txt`, `help.txt`, `menu.txt`, `fonts.txt`, `names.txt` (display names; the ids stay),
  `voices.txt`, `wordstat.txt`, `evolve.txt`, `frustration.txt`, `ledger.txt` (`Sim_Ckpt.Is_Text_Only`). The simulation never reads
  them, so they are not even hashed.
* **Start values refuse the checkpoint.** While a start runs up to the restore point (module `Init`, the `Load_*` of the record
  files), `Sim_Util.Limit` records every key it reads with its text; the checkpoint header keeps them as `startkey <key> <text>`
  (about 150 keys: the world's `R30`/`Lean`/`Base_W`, things, dharma, games, robot, screen, trial, preport, the `active.*`
  parameters, ...). These numbers are copied into the module state, so the checkpoint holds them. If one of them has another text
  in `data/` now, the start refuses: `replay: checkpoint data (a start value changed: active.slow_coin_pct 50 -> 100)`, and the full
  replay rebuilds the state with the new number, exactly as a run without the checkpoint would.
* **Every other change of a rule file** (`limits.txt` keys read later, `karma.txt`, `kalpas.txt`, `topics.txt`, `words.txt`,
  `things.txt`, `chat.txt`, `visit.txt`, ...; also any new file) is information: each rule file has a hash of its lines without
  comments and blank lines (a changed comment is no changed rule) in the header, and a start whose rule files differ **still loads
  the checkpoint** and prints one line: `data changed since the checkpoint (make verify-full replays everything): limits.txt`.

The reasoning. The suggestion was "record the data hash, say so, still load". That holds for everything the simulation reads
**while it runs**: such a number is read fresh from `data/` at every use, the same way whether the state was replayed or loaded,
and a new rule's number comes with that rule's session marker, so it acts only in new sessions. A number changed under OLD sessions
changes what a replay of them would give: the diaries no longer fit the data, and that is a drift that only a full replay can see
(not the checkpoint, and not a refusal of it), so refusing would cost 35 minutes and prove nothing: `make verify` is that check,
and the information line says when one is worth running.

It does not hold for numbers read **at the start**: the modules copy them into their state (and `State_IO` streams them), so a
loaded checkpoint would bring back the OLD number and keep using it in every new session, forever, silently, while a full replay
uses the new one. `make check` caught exactly that (scenario 56: a raised `active.slow_coin_pct` was ignored after the load). So
those keys, and only those, are compared one by one; the check proves that a refused start gives byte for byte the files of a run
without the checkpoint. A format 1 checkpoint (0.058) has neither rule-file hashes nor start values; it is loaded without the
comparison (0.059 changes no number in `data/`, and the check proves the 0.058 checkpoint gives the files of a full replay).

## The layout guard (make check)

The runtime section heads catch a changed layout at the load, but only as a refusal. So that a forgotten bump is caught before a
zip goes out, `scripts/ckpt_layout.sh` hashes what decides the payload bytes: the `State_IO` bodies of all modules, `Main_State_IO`,
`Sect_IO`, `All_State_Write`, `All_State_Read`, the section list (`Sect_Name`), and every package-level declaration they reach by
name (the streamed variables, their types, the element types of the vectors, the constants of array bounds; comments and spacing
do not count). The recorded value, next to the format number, is:

ckpt_layout: 2 0b775a42d23f534b

`make check` (scenario 63) and `make ckpt-layout` compare it with the code: when the code changed and this line did not, the check
FAILS with `bump Ckpt_Format`. Then:

1. `diary_sim.adb`: `Ckpt_Format := N + 1` and `Ckpt_Layout_Since := N + 1` (older checkpoints are refused once: full replay).
2. `scripts/ckpt_layout.sh` prints the new line; put it here in place of the old one.

Only if the bytes are truly unchanged (a rename, a reordered declaration) record the new hash without a bump. The guard may also
fire for a declaration that only shares a name with a streamed one; that is a false alarm to look at, never a reason to skip the
look.

## Verify: incremental by default, full monthly (build 0.060)

**`make verify`** (`--verify`) is incremental: it loads the last *verified* checkpoint, `state.verified.ckpt`, replays only the
ticks after it from the files and compares them with everything stored, then compares `state.ckpt` with the replayed state, section
by section (`verify: OK (incremental), ticks A to B replayed from the verified checkpoint of tick A-1 ...`). Without a verified
checkpoint (or when it does not fit the files: the same checks as a start) it replays from tick 1 and says why. **`make
verify-full`** (`--verify-full`) and `--replay` always replay the whole history. A passed verify of either kind writes:

* one `VERIFY` entry in `run_log.txt` (`full verify: OK, N ticks, S sessions, T s` or `incremental verify: OK, ticks A to B, ...`);
* a fresh `state.ckpt` of the replayed state, copied to `state.verified.ckpt` (the next `make verify` starts there; the copy is
  made only from a state that a replay produced and compared, never from a run's own checkpoint);
* `verify_stamp.txt`: `full=<date> <ticks> <simulation fingerprint> <state format>` and `incr=<date> <from tick> <to tick>`.

A difference is a DRIFT (exit 1, the checkpoint moves to `state.ckpt.bad`, nothing new is written). A night's end check (when the
save is under the cap) is a `--verify-full` child and writes the same files.

**Why a full one is still needed.** The incremental verify proves that the new ticks follow from the verified state. It cannot see a
code change that alters how OLD sessions replay: the verified checkpoint already holds the old result. So `checkin.txt` (make ship /
slice / night-ship) has two lines:

* `last full verify: <date> (N ticks), <age>`; it says `verify-full due` (and on the next line why) **after 30 days**, or when the
  **simulation fingerprint** or the **state format** differs from the one of that verify. The fingerprint (`scripts/sim_print.sh`,
  `make sim-print`) hashes `diary_sim.adb` and the `sim_*` units the tick loop runs, without comments, spacing and the `Build`
  constant, and the rule files of `data/` without comments (not the display text). Reports, the menu, the voices, the checkpoint
  and ledger code, the scripts and the docs do not count, so a build that only touches those does not make it due. (Limit:
  `diary_sim.adb` also holds report code; a change there counts.) A full verify from before 0.060 has no fingerprint on record:
  due once.
* `last verify: <date> (ticks A-B)`; `make verify due (weekly)` after 7 days.

Timing (build 0.060, this box): the full replay of a 388500-tick save takes ~180 s (0.059: ~1250 s); an incremental verify of 900
new ticks on a small save 0.3 s, of 36000 new ticks 12 s; on Robert's save it is the checkpoint load (~7.6 s with 0.059's
measurement) plus the new ticks at ~1500 ticks/s.

`make ship` (auto) runs `--verify-full` when the save has at most `SHIP_VERIFY_TICKS` ticks, else the incremental verify when the
verified checkpoint is at most that many ticks behind, else none (the line says so).

**Proposal, not built: old windows.** Keep up to 3 older verified checkpoints spaced across the save (~70 MB each on Robert's save)
and let the weekly `make verify` also replay one random old window (from one of them to the next, at most 20000 ticks) and compare
it with the next one and the files. That would catch most code changes that alter old sessions within a week at a cost of a few
seconds, without the monthly full replay. It needs a rotation rule for the old checkpoints and a window replay that stops at a
tick and compares the state there; with the fingerprint rule above, a full verify after every simulation change already covers
the case, so it was left out of 0.060.

## Derived indices (build 0.060)

Build 0.060 keeps lookup indices next to the state (sessions and votes by tick, the dharma lines by tick, the first running chess
game, a text index and bit masks of the word table). They are derived data, never written to the checkpoint: after a load,
`Sim_Games.Reindex` and `Sim_World.Reindex` rebuild them from the loaded state, so the layout (and the guard line below) did not
change and a 0.059 checkpoint loads. `DIARY_CHECK_INDEX=1` cross-checks every indexed lookup against the old full scan (tests).

## The replay estimate and the budget (build 0.060)

When a run has no valid checkpoint and more than 1000 ticks to replay (a night, a slice, a verify), it prints first `replay
estimate: N ticks, about M min (...)`, from the last measured full replay in `ckpt_log.txt` (`replay done: N ticks in S s`; scaled
by (N/n)^1.5, the replay gets slower with the history) or 1500 ticks a second. With `--deadline` (make slice / night-ship pass the
absolute end of the budget, counted from the start of make) it adds `the budget cannot hold: replay first (~N min), then sessions;
checkin.txt late by ~M min` when the replay plus the reserve ends past it, and goes on: the replay comes first, then at least one
session.

## Commands

    make slice                 # by day: loads the checkpoint (seconds), sessions, reports, checkin.txt
    make verify                # weekly: incremental from state.verified.ckpt, compare, then fresh checkpoints
    make verify-full           # monthly or when due: the whole history from tick 1
    make sim-print             # the simulation fingerprint (LIST=1: the files it covers)
    bin/diary_sim --replay     # one start without the checkpoint
    make ckpt-layout           # the layout guard alone (also part of make check)
    tail ../diary-data/ckpt_log.txt   # loads, writes, refusals with their time
