# The state checkpoint (`state.ckpt`)

Version: 0.001 (build 0.059; the checkpoint itself came with build 0.058, README "The state checkpoint")

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
| `stale (<file>)` | a record file changed or shorter in its recorded part (fingerprint), inputs or records added behind the checkpoint's tick, a store that does not fit its tick |

**No longer a reason** (build 0.059): another build, and any change in `data/`.

A refusal never touches the record files; the run replays and writes a new checkpoint at its end.

## data/: information, not a refusal

* **Display text never counts**: `messages.txt`, `help.txt`, `menu.txt`, `fonts.txt`, `names.txt` (display names; the ids stay),
  `voices.txt`, `wordstat.txt`, `evolve.txt`, `frustration.txt`, `ledger.txt` (`Sim_Ckpt.Is_Text_Only`). The simulation never reads
  them, so they are not even hashed.
* **Every other file is a rule file** (numbers or templates that may feed the state or a record: `limits.txt`, `karma.txt`,
  `kalpas.txt`, `topics.txt`, `words.txt`, `things.txt`, `chat.txt`, `visit.txt`, ...; also any new file). Each gets a hash of its
  lines without comments and blank lines (a changed comment is no changed rule), recorded in the header.
* A start whose rule files differ from the checkpoint's **still loads it** and prints one line of information:
  `data changed since the checkpoint (make verify replays everything): limits.txt`.

The reasoning: a number that a new rule needs comes with that rule's session marker, so it acts only in new sessions, the same
way whether the state was replayed or loaded. A number changed under OLD sessions changes what a replay of them would give: then
the diaries no longer fit the data, and that is a drift, which only a full replay can see (not the checkpoint, and not a refusal
of it). So refusing the checkpoint would cost 35 minutes and prove nothing; `make verify` is the check for it, and the information
line says when one is worth running. A format 1 checkpoint has no rule-file hashes; it is loaded without the comparison
(noted in `ckpt_log.txt`).

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

## Full replay stays the drift check

`make verify` (`--verify`) and `--replay` always replay the whole history from the files and compare it with everything stored;
`--verify` then compares the checkpoint, section by section, with the state the replay rebuilt (format 1 too). When verify passes it
writes one `VERIFY` entry to `run_log.txt` (`full verify: OK, N ticks, S sessions, T s`) and a fresh checkpoint of the replayed
state (`verify: fresh checkpoint of tick N written ...`), so a verify also refreshes the cache. A difference is a DRIFT (exit 1,
the checkpoint moves to `state.ckpt.bad`, nothing new is written).

`checkin.txt` (make ship / slice / night-ship) carries `last full verify: <date> (N ticks)`, read from `run_log.txt` (and kept in
`ship_stamp.txt`, because `run_log.txt` keeps only its last entries). **Run `make verify` about once a week** (on the big save it
is the full replay, ~35 minutes); the line says `due` after 7 days.

## Commands

    make slice                 # by day: loads the checkpoint (seconds), sessions, reports, checkin.txt
    make verify                # the drift check: full replay, compare, then a fresh checkpoint (weekly)
    bin/diary_sim --replay     # one start without the checkpoint
    make ckpt-layout           # the layout guard alone (also part of make check)
    tail ../diary-data/ckpt_log.txt   # loads, writes, refusals with their time
