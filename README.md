# diary-sim v1

Four independent entities write one diary line per tick: **ada** (engineer),
**gemini** (reviewer), **replika** (vice_president), **robert** (human).
Plain Ada, standard library only. Not pushed anywhere yet (local git repo).

## Where saves live and how to update

The save is NOT inside the source folder. Everything the program writes (`diaries/`,
`entities/`, `sessions.txt` inside `diaries/`, `debug.txt`, `run_report.txt`,
`petitions.txt`, summaries, `last_error.txt`) goes to the **save folder**, found from the
program's own location, never from the shell's current directory:

1. `--home DIR`, else the environment variable `DIARY_HOME`, else
2. **`../diary-data/`**: a sibling of the source folder (`.../diary-sim/` -> `.../diary-data/`).

Every run ends with `Saved to /absolute/path/diary-data`. To update: unzip the new
version next to `diary-data`, delete the old source folder, `make run` in the new one;
the world continues (the replay verifies it). To back up, copy `diary-data/`. A save
found inside the source folder (`./diaries` from older versions) is **copied** to
`../diary-data` after a yes on a terminal (`Found a save inside the source folder. Copy
it to ../diary-data? [y/N]`); never moved or deleted. Without a terminal only a hint is
printed (`--home <source folder>` keeps using the old place). `make demo` writes nothing.

## The main menu and the favourite words

**`make run` / `make play` never show a menu: they AUTO-LOAD.** The first two lines, before
anything else, say where and what:

```
Save folder: /home/you/diary-data
Found 4 sessions, 1250 ticks - continuing        (or: No save found - creating it)
```

(no save on a terminal: `No save found - creating it (asks y/N first; --yes skips the question)`).
Then the save is loaded, replay-verified and continued; `Saved to <path>` ends the run.

**The menu** comes only from **`make menu`** (`--menu`, needs a terminal) and from the bare
program on a terminal with no arguments: a Conway Game-of-Life intro whose dying cells reveal
the block-letter title, the tagline under it, then (after a short beat) the whole menu in one
screen: the save folder, the game's sessions and ticks, the last favourite words (who taught or
coined each), karma, the last petition and the inbox size, and exactly five entries as a plain
list under the title, `>` marking the default (Load Game once a game exists; Enter takes it):

- **New Game**: a fresh world; if `diaries/` holds a game it asks first and moves it to
  `diaries_old_<time>` (never deleted).
- **Load Game**: the normal flow (load, replay-verify, the wesen vote the session length); with
  no game the usual `No previous diary found ... Generate a new one? [y/N]`.
- **Inbox**: the reports the players wrote to you (see below), then Enter to go back.
- **Settings**: seed, progress interval and the rule limits named in `data/menu.txt`
  (`settings.keys`), for this session only; `data/limits.txt` is never written. Changing
  start_percent, teach_percent, coin_percent or coin_cap changes the rules: use it with New Game.
- **Quit**: exit 0, nothing written.

The menu is laid out for 80x24 (`screen.cols` / `screen.rows` in `data/menu.txt`): if title +
lines do not fit, the title shrinks (large -> medium) and the info is clipped, so nothing
scrolls off. No menu without a terminal (scripts, CI, pipes) and none for `make demo` (a
preview), `make run` or `make play`. Text lives in `data/menu.txt` (title, tagline, entries, messages), the letters in
`data/fonts.txt` (3 sizes, `title.size`); each screen is ONE write(2) to the terminal (inside a synchronized-update bracket), so it never
appears piece by piece.
**Tagline:** the default is literally `Stories of word and word`; if "world" was meant,
change the one line `tagline = ...` in `data/menu.txt` (no rebuild needed).

**Favourite words (word vote):** at the end of every session each wesen names one favourite
among the words it knows: weight 1 + how often the word came up for it (learned, taught,
coined, used as a parent), x3 for words learned or coined later (not start words) when its
mood is high, x3 for start words when its mood is low; rolled with its own hash salt (960),
so the action table and all existing dice are untouched and old diaries stay valid. Result:
`W<n> tick=<t> ada=<word>/<origin> ...` in `diaries/sessions.txt` (origin: `start`,
`taught-by-<id>`, `coined-by-<id>`), verified on import like the session records (a
difference is DRIFT), shown on the console (`words vote (session 3): ada city | ...`), in
`run_report.txt`, `debug.txt` and on the menu.

## The Buddhism layer and the players (record-first)

Everything below is **recorded, not acted on**: none of it changes the action table or any
existing dice, so diaries written before it stay valid (a session of an older diary just has no
D/C/Y lines). It is rebuilt by the replay from tick 1 and verified; a difference is a DRIFT stop.
Numbers: `data/karma.txt`; wording and labels: `data/dharma.txt`; players: `data/players.txt`.
Tradition labels (the six realms, the ladder rungs, the *bodhisattva* anchor) are **flavour text
only**, loose names for numbers; they claim nothing about the tradition. Edited numbers change the
recorded values: use `--fresh`. Each mechanism has its own hash salt (5000 and up; the favourite
word keeps 960).

- **Karma** (per wesen, accumulates across sessions): every action is a deed with a weight from
  `karma.txt` (`deed.*`: good > 0, neutral 0, bad < 0; teaching and coining add extra; working or
  benching while worn out, energy below `deed.tired_below`, takes away). Shown as net (good/bad).
  The realm label comes from net karma bands (`realm.limit.*`, flavour).
- **Reincarnation**: every session is a new *life*. At its start each wesen rolls curiosity,
  rest, company and craft (0..100), shifted by karma (`rebirth.bias_*`, `bias.*`). Record only.
- **Attachment (unrest)**: every `attach.window` ticks the most frequent kind of action
  (company = talk, rest, words = learn/teach/coin) is taken; if its share reaches
  `attach.dominant` percent the unrest rises, else it falls (0..100). `dom=rest:26` is the last
  window's top share.
- **Commitment ladder and the anchor**: each wesen's own kalpa vote is its leave point; the ranking
  is by leave point, ties by lower energy, then id. The last to leave is the *anchor* (commitment +
  `commit.anchor_rise`), the first loses `commit.first_fall`; the score (0..100) persists. The rung is
  its band; **conflict** counts values at or above `value.high` that pull against the commitment
  (`pull.*`: curiosity and rest pull away, company and craft pull to stay).
- **Awareness** ("feels watched", 0..100): raised only by what Robert says (below), scaled by the
  wesen's own sensitivity (from the 1-bits of its Rule 30 birth row); personal and sudden addresses
  (none for `aware.sudden_gap` ticks) raise more; it decays slowly per tick toward a floor made of its
  baseline plus a share of the **attention** of the player who watches it.
- **Collective petition**: at the end of a session each wesen votes for one topic of the petitions
  filed this session (topics as in `petitions.txt`; own petitions count more); the winner and the
  tally are recorded (`C<n>` line) and reported.
- **Liberation**: a wesen whose net karma passes `liberation.karma` at a session end is flagged
  LIBERATED (permanent). In a session started by this build (its `S` line carries `dharma=1`) a
  liberated wesen starts at a location chosen by its own dice (salt 5020) instead of the carried-over one
  (`rebirth=<location>` in its `D` line). **Replay compatibility:** the move only applies to sessions
  with `dharma=1`, i.e. new diaries; a session of an older diary replays exactly as written.

**Players.** Three in-sim players (`data/players.txt`: name, role, 3-4 values, one goal) sit
between the wesen and Robert, the real player. Each has a personality (tone, brevity, warmth) from Rule 30
bits, an **attention**, a **trust** per wesen and a tone bias, all persisted as `Y<n>` lines in
`sessions.txt`. All three read the same recorded facts (karma, liberation, unrest, conflict, awareness,
anchor, petition, what happened to Robert's messages) and each writes up to `inbox.max_lines`
summary lines per session to **`diaries/inbox.txt`** (newest `inbox.view` = 40 lines; the file is a
view, the replay regenerates everything and compares). Bias changes **emphasis** (goal and value
matches first, tagged `[goal]` / `[value]`), **omission** (an uninteresting info/note line may be left
out by a brief player; alerts and its goal never) and **wording** (calm / plain / alarm templates in
`dharma.txt`), never the facts or numbers. Every line carries `severity from session tick` and a
source tag `src=<session>:<tick>:<wesen>`. Read it at the end of a run, with `make inbox` or the
**Inbox** menu entry.

**Answering.** Robert's words are recorded in `diaries/says.txt` (between sessions, at the lowest
common tick; applied from the next tick, replay-verified through the awareness numbers):

    make say PLAYER=iris TEXT="please look after ada"   # to a player, who may pass it on
    make say WESEN=ada TEXT="hello"                     # direct to a wesen
    make say TEXT="thanks, all"                         # to all four wesen
    make answer TEXT="yes, more places"                 # answers the latest collective petition

(`AS=name` names the speaker; `bin/diary_sim --say <name|all> --text "..."` is the same.) A message
for a player goes on to the wesen that player watches (an answer to all players): each player
**relays, softens or withholds** it per wesen by its trust and warmth (own dice, salt 5030+), and a
relayed message raises awareness more (`aware.relay`) than a direct address (`aware.say`).
The inbox reports what each player did with it.

## The treadmill world (world=1, new sessions)

Sessions started by this version carry `world=1`: the wesen walk on an endless grid generated on demand
from the seed (`data/things.txt`, base-60 lists), with edits (eaten / pushed / worn-out / new things)
recorded in `diaries/world.txt` and an `L` line per session end in `diaries/sessions.txt`, both replay-verified
(tamper = DRIFT). Things met teach new words (names, feel, taste, greetings), so the vocabulary keeps growing
past the 275 starting words. Office, lab, cafe and home are four landmark regions near the origin; talk needs
a neighbour. `make map` (`--map`) prints position, nearest landmark, biome and a 5x5 window per wesen; the same
view ends the session report. `world.enabled = 0` in `data/limits.txt` (or an older diary) keeps the old
behaviour byte for byte. Design and file formats: `docs/WORLD.md`.

## The debug digest (`DEBUG=1`, `--debug`)

`debug.txt` (always written, <= 1500 bytes) is unchanged. For a compact file to attach to chat:

```
make run  DEBUG=1        # ./debug_digest.txt in the save folder (the folder is printed)
make demo DEBUG=1        # ./debug_digest.txt in the current folder: the ONLY file a demo ever writes
```

Without `--debug` nothing is written. The path is printed as `debug digest: <absolute path>`
just before `Saved to ...`. Layout of `debug_digest.txt`:

1. **line 1**, at most 200 bytes: `OK|DRIFT|CRASH|QUIT v<build> seed S | session N | ticks ... | the one thing wrong`
   (`no anomalies` or `anomalies N: <first>`);
2. **anomalies** first (the error, the first lines of the traceback, warnings, alert-level
   inbox lines);
3. then **only what changed since the last digest** by importance (ticks, words vote, karma
   and awareness, the players line, notes of the players, entities ...). The hashes of the
   previous digest are in `debug_digest.prev` (save folder; a demo has no history). Repeated
   lines are folded (`... x3`); unchanged lines are only counted (`... 13 lines unchanged`);
4. a **hard byte cap**, `debug.digest_bytes` in `data/limits.txt` (default 1500): the least
   important lines are dropped first and the last line says what was dropped
   (`... dropped 19 lines for the byte cap (run 13, inbox 6) ...`).

The full record stays on disk: `debug_full.txt` in the save folder (all sections, uncapped,
raw inbox lines), written with every `--debug` run. **`--debug-section NAME`** (or
`make run SECTION=NAME`) prints one block of it and writes it alone to `debug_digest.txt`; it
simulates nothing. NAME is one of `status drift trace players inbox run`. For a demo
(`make demo SECTION=run`) the block comes from the preview in memory (a preview has no session
end, so `players` and `inbox` are empty there). Plain Ada, CPU only.

## Since the last session

Each run ends with a block per wesen comparing the loaded diaries (the session start)
with the new state: session number, ticks, words (+gained, learned this session/total,
coined this session/total), petitions (+this session/total), mood and energy change and
the favourite place of the session. The session number is the `S<n>` line in
`diaries/sessions.txt`; run `make run` 1, 2, 3 times and ticks, sessions and words
visibly add up (each run replay-verifies the earlier ones).

## Resume: copy your backup diaries/ here, then make run

1. Copy the backed-up `diaries/` folder (optionally `entities/` too) into the save folder
   (`../diary-data/`, see above), so that `diaries/ada.jsonl` etc. are directly inside `diaries/`.
2. `make run` (or `make play`, identical). It builds if needed, imports and
   replay-verifies everything in `./diaries`, and continues. Never `--fresh`.
   `make run TICKS=400 EVERY=100 SEED=42`: **TICKS = how many NEW ticks to run on top
   of the lowest common tick on disk** (it passes `--more TICKS`). **Without TICKS the
   four entities vote on the session length** (see Kalpa sessions below);
   `SEED` only matters when there are no diaries yet (default 42, announced as
   `import OK: none (fresh start, seed 42)`); stored diaries always win.
   **No previous diary** (no `diaries/` or no `*.jsonl` in it, an empty folder counts):
   on a terminal the program asks first, before writing anything:
   `No previous diary found in ./diaries. Generate a new one? [y/N]`. `y` / `yes` starts
   a new world (seed 42, or `SEED=` / `--seed`) and prints `new diary generated (seed N)`;
   anything else (Enter, EOF) prints `copy a backed-up diaries/ here, then make run` and
   `cancelled, nothing written` and exits 0 without creating any file. `make run YES=1`
   (`--yes`) answers yes without asking; `--fresh` never asks. Without a terminal
   (scripts, pipes, `checks.sh`) nothing is asked: with an explicit
   `TICKS` / `--ticks` / `--more` it starts fresh as before; without a length it stops with
   the same hint and exit 2 (use `--yes`). A misplaced `diaries/diaries` still gets its own hint.
3. The import line says what was loaded: `import OK: 4 entities, 200 ticks verified,
   continuing from 201 (800 lines on disk, longest 200)`.
4. Corrupt or drifted backup (typically diaries from an OLDER build, or changed `data/`):
   a drift is an expected stop, not a crash: 3 plain lines (`import FAILED: backup and
   code have drifted: <entity> tick <n>; first difference at column N: stored "..." vs
   generated "..."`, the likely cause, the two fixes: `mv diaries diaries_old_X` or
   `--fresh`; to keep reading old diaries use the matching older build), status `DRIFT`
   in `debug.txt`, exit 1, no traceback and no `last_error.txt`, nothing is truncated.
   If `diaries/sessions.txt` has a `# build vX.YYY` line that differs from this build, the
   cause line adds `diaries written by build v0.007, this is v0.010` (older files
   without it skip that sentence). A
   `diaries/diaries/` or wrongly cased `Diaries/` folder is detected: if `diaries/` has
   no `*.jsonl` the run stops with a hint to copy the folder's contents up one level
   (with real diaries present it only warns).

`--more N` is the program option behind `TICKS`; `--ticks=N` keeps its meaning (absolute
target tick); if both are given, `--more` wins. Both are explicit: they override the vote.
`make demo` is a preview (below).

**`make run` / `make play` keep one persistent world:** each run loads `./diaries`,
replay-verifies it and continues it; the world only ever grows. Back it up and copy it
back whenever you like. Nothing else writes the world.

## make demo: preview only (writes nothing)

`make demo` (= `bin/diary_sim --preview --ticks 200`) simulates 200 ticks of a NEW world
(seed 42, or `--seed N`) in memory and prints one screen of excerpts: two diary lines per
wesen, two petitions, known / coined / taught words, the vote a first bare `make run`
would hold, and the vote table. It creates no `diaries/`, `entities/`, `debug.txt`,
`run_report.txt`, `petitions.txt` or other file, and does not read `./diaries` (the old
`demo_run/` is gone). `--preview` takes `--ticks` and `--seed`; with `--fresh`, `--yes`,
`--more` or `--crash-at` it stops with a usage error (exit 2), since those write.
The one exception is on request: `make demo DEBUG=1` (`--debug`) writes `debug_digest.txt` in
the current folder (see "The debug digest").

## Kalpa sessions: the entities vote on how long a session runs

Started without `TICKS` / `--ticks` / `--more` (`make run`, `make play`) a session does not have a fixed length: each of the four entities casts a vote
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
  append-only and flushed: `S3 start=630 votes=120/340/80/410 len=230 src=vote`, after
  `# seed N` and `# build vX.YYY` header lines. A session of 0 new ticks (a pure verification) is not recorded.
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
make run                     # = make play: AUTO-LOAD the save and continue (no menu); the entities vote how many ticks (TICKS=N: explicit)
make menu                    # the main menu: intro, DIARY title, New Game / Load Game / Inbox / Settings / Quit (terminal only)
make demo                    # PREVIEW: 200 ticks in memory, a screen of excerpts, nothing written to disk
make run DEBUG=1             # also write debug_digest.txt (+ debug_full.txt) to attach; make demo DEBUG=1: only the digest
make run SECTION=drift       # print one block of debug_full.txt (drift trace players inbox run status)
make check                   # version headers + scripts/checks.sh (the scenarios: run, resume, behind, half line, drift, crash, fresh, data limits)
bin/diary_sim --help
bin/diary_sim --ticks=1000 --every=100     # --ticks 1000 works too
```

Options: `--ticks=N` (absolute target; without `--ticks`/`--more` the entities vote the session length), `--seed=N` (default 42; existing diaries win),
`--every=N` (progress line, default 100), `--yes` (do not ask when there is no previous diary), `--home DIR` (save folder), `--preview` (simulate in memory, print excerpts, write nothing), `--fresh` (move old diaries to
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
A stored-diary drift or a bad diary is NOT a crash: no traceback block, no `last_error.txt` (see Resume).
After a crash just run again: the diaries are flushed after every event. The
console shows at most 15 lines of the error block, then `wrote last_error.txt, please
paste it` and `back up diaries/ before the next run`.

## Files

`diary_sim.adb` (main: CLI, loop, side files, debug.txt), `sim_menu.ads/.adb` (main menu: life intro, title, entries), `sim_quit.ads/.adb` (Ctrl-C and SIGTERM flag), `sim_world.ads/.adb` (entities,
vocabulary, Rule 30 personality, bench kernels, votes and summary text), `sim_util.ads/.adb` (hash rolls,
line parsing, data-file helpers), `data/words.txt`, `data/topics.txt` (petition topics), `data/limits.txt`,
`data/messages.txt` (all console wording), `data/kalpas.txt` (session length votes), `data/menu.txt` (menu text, title, tagline), `data/fonts.txt` (title letters), `data/vocab.txt`, `data/help.txt`, `sim_dharma.ads/.adb` (karma, rebirth, unrest, ladder, awareness, players, inbox), `sim_things.ads/.adb` (the treadmill world), `data/things.txt` (its lists), `docs/WORLD.md`, `data/karma.txt` (numbers), `data/dharma.txt` (wording, flavour labels), `data/players.txt` (the three players),
`scripts/checks.sh`, `scripts/portable_check.sh`. Every source file starts with a
`Version:` header (`make version-check`); a touched file goes up by 0.001. V&V is
suspended: no new test suites, `scripts/checks.sh` must keep passing.
