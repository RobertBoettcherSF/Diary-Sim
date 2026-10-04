# diary-sim v1

Four independent entities (the *wesen*) write one diary line per tick. Their internal ids are `ada`
(engineer), `gemini` (reviewer), `replika` (vice_president) and `robert` (human); what you SEE are the
display names from `data/names.txt` (default: Adam, Eve, Abel, Ruth; see "Display names" below).
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
difference is DRIFT), shown on the console (`words vote (session 3): Adam city | ...`), in
`run_report.txt`, `debug.txt` and on the menu.

## The console, `run_report.txt` and `run_log.txt` (`make report`, `make runlog`, `VERBOSE=1`)

A run writes the complete report to `run_report.txt` in the save folder (always; the previous one is kept as `run_report_prev.txt`)
and shows only the end of it on the console: the progress lines, `report:` with the entity table, the petitions line, the per-wesen
session lines, the players' report boxes (and 'Next run' advice); about 40 lines. It ends there: no marker line and no technical
metadata. `make run VERBOSE=1` (`--verbose`, or `DIARY_VERBOSE=1` in the environment, which the checks use) prints
everything as before, `make report` (`--report`) prints the last `run_report.txt`. Nothing but console and report text changes: the
diaries, entities and summary files are byte for byte the same.

* **Sections:** `run_report.txt` has a header line `== name ==` before each block (import, report, actions, petitions, session,
  treadmill, recovery, screens, chess, robot, governance, grants, words, dharma, inbox, export, votes, ledger, tail), so
  `grep -n '^== ' run_report.txt` is an index.
* **`run_log.txt`** (save folder, next to `run_report.txt`; `make runlog` shows its last 40 lines): one entry appended per run, each starting
  with a local time stamp (`YYYY-MM-DD HH:MM:SS RUN`, from `Ada.Calendar`), then the `@@TRACE` line, the `@@SECTIONS` line and
  `report: <path of run_report.txt>`. A DRIFT stop (which writes no report) appends `YYYY-MM-DD HH:MM:SS DRIFT` with `@@TRACE ... result=DRIFT`,
  `reason:` and the `debug.txt` path. Only the last `report.log_keep` (500) entries stay (`data/limits.txt`; `report.log_tail` = 40 lines for
  `make runlog`). The clock is only in this file: diaries, entities, summaries and the report carry no time of day, so they stay byte for
  byte reproducible.
* **Marker** (for people and for tools; the idea of the stack trace in `last_error.txt`): two lines, the first two of `run_report.txt` and
  the two lines of each `run_log.txt` entry, never on the console unless `VERBOSE=1` shows the report:

      @@TRACE build=0.039 seed=42 session=2 ticks=301..500 anomalies=2[mood<-50:Adam,energy<25:Ruth] files=run_report.txt,debug.txt,...
      @@SECTIONS import=3,report=7,actions=14,petitions=20,session=22,treadmill=28,recovery=39,screens=45,chess=55,robot=97,...

  `anomalies` is `none` or `count[first three]`: energy below `report.warn_energy` (25) or mood below `report.warn_mood` (-50) at the end
  of the run, `warnings:n`, `export-failed`. It is information only; nothing in the simulation reads it (`data/limits.txt`).
  `@@SECTIONS` gives the line of each header in `run_report.txt`.

## Overnight: `make night`, `trend.txt`, `make trend`, `make share`

For a run you leave alone and read in the morning, and for the loop *Robert runs it, sends the files, the code changes, Robert downloads*:

    make night                                  # 300-tick sessions until q, DRIFT, or 12 hours
    make night SESSION_TICKS=200 MAX_SESSIONS=40 MAX_HOURS=8
    make trend                                  # the last 40 lines of trend.txt
    make share                                  # ONE zip to send back

* **`make night`** (`bin/diary_sim --continuous [--session-ticks N] [--max-sessions N] [--max-hours H]`, defaults `night.session_ticks`,
  `night.max_sessions`, `night.max_hours` in `data/limits.txt`; 0 means no limit, `H` may have decimals) runs normal sessions back to back.
  Every session is a run of the program with `--more N`, started through `/bin/sh` (its console goes to `night_console.txt` in the save
  folder, overwritten each time; its exit status to `night_rc.txt`, which the timer polls so that it keeps running during the session), so each one is exactly what `make run TICKS=N` typed by hand would give: own session, own markers, replay-verified, the same bytes
  in diaries, entities and records (a check compares three night sessions with three hand-made ones). The price: each session replays the
  history first, so the sessions get slower as the save grows (about a millisecond per tick). There is no 'Next run' advice loop: the
  length is `SESSION_TICKS`, and no question is asked. It continues an existing save or starts a new one (`SEED=`); it cannot be combined
  with `--ticks`, `--more`, `--fresh`, `--preview` or `--visit`.
* **Stopping:** press **`q`** (no Enter needed, any case) at any time: the session in progress finishes cleanly and the run stops, so
  nothing is ever cut in the middle. It also stops on a **DRIFT** (the box says so, with the import failure), at `MAX_SESSIONS`, at
  `MAX_HOURS` (checked between sessions, so a session may end a little after it), and on Ctrl-C or SIGTERM (a session in progress is
  stopped at once and a rerun resumes; the exit status is 130). Without a terminal on stdin (a pipe, `nohup`, cron) the keyboard is not
  read and only the limits and signals stop it, so give `MAX_SESSIONS` or `MAX_HOURS` then.
* **Console, plain (no terminal on stdout, e.g. a file):** two lines at the start, then per session ONE status line
  (`s17 t5100 02:31:05 | Adam -3/80 Eve 12/60 Abel 5/55 Ruth -20/20`: session, tick, local time, mood/energy of each wesen) with a timer
  line below it (`  0h12m05s | 4.2 MB (+310 KB) | 8.1 s/session | 58 tick/s | left 11h47m00s`), and a final box (why it stopped, sessions,
  time, seconds per session, ticks per second, save folder size and growth, last values).
* **Console, on a terminal: the timer header.** The screen is cleared once; then about once per second the header is repainted in place
  (ANSI cursor home, the whole block written with one call, so it does not flicker): the local date and time, the time elapsed, the limits
  and the estimated time left to the nearest one (from the average session), the size of the save folder and its growth since the start,
  the session in progress with its tick (or 'replaying the history first'), sessions done, the time of the last finished session, the average
  seconds per session and ticks per second, the mood/energy of the four wesen as of the last finished session, and the key hint; below it the
  status lines of the last 8 sessions. The final box follows. The header is written by the driver only (the sessions run in their own
  processes), so it changes no simulation file and costs a directory listing per second. The full report of
  the last session is in `run_report.txt` (the one before in `run_report_prev.txt`) and `run_log.txt` has a timestamped `RUN` entry per
  session plus `NIGHT` entries for the start and the stop (`start: ...`, `stop: reason=q sessions=14 last_session=30 tick=9000
  elapsed=2h10m`; reasons `q`, `signal`, `max_sessions`, `max_hours`, `drift`, `error`). `report.log_keep` is 500 so a night does not
  push out the earlier lines.
* **`trend.txt`** (save folder; every run that adds ticks appends one line, `make night` or not; `report.trend_keep` = 2000 lines stay;
  `make trend` shows the last `report.trend_tail` = 40). First line a `#` legend, then one line per finished session, fixed order:

      T session=3 tick=180 time=2026-10-04 12:14:43 elapsed=0.4 size=623374 mood=-24,51,67,63 energy=71,49,78,37 words=183,193,189,205 pets=1,1,1,1 grant=1,0,0,1 refuse=0,1,1,0 agreed=0 rejected=2 trials=2 anomalies=0

  `elapsed` is the wall time of that run in seconds (the replay of the history included), `size` the bytes of all files in the save folder
  at that moment (so growth per session is a difference). `mood`, `energy`, `words` (known words) and `pets` (petitions filed so far) have one number per wesen in the order of the legend
  (Adam,Eve,Abel,Ruth); `grant` and `refuse` one number per player (1 to 4): the petition votes so far, counted from the raw
  `votes.txt`, not from the players' reports (zeros in sessions without `records`); `agreed` and `rejected`: dictionary words so far;
  `trials`: chess trials so far; `anomalies`: the number of entries of the `@@TRACE` anomalies (energy below `report.warn_energy`, mood
  below `report.warn_mood` at the end of the session, warnings, export failure). Values are cumulative or end-of-session values, so
  subtract two lines for a session's own change. The time (local, `YYYY-MM-DD HH:MM:SS`) is the only clock; it is in this file and in
  `run_log.txt` only, so the simulation files stay byte for byte reproducible.
* **`make share`** (`scripts/share.sh`) builds `share-YYYYMMDD-HHMMSS.zip` (`tar.gz` if there is no `zip` and no `python3`) in the PARENT of
  the save folder (for `~/Downloads/diary-data` that is `~/Downloads`; `SHARE_DIR=...` chooses another place) and prints the path and the
  size (a few tens of KB). Inside: `trend.txt`, `run_log.txt`, `run_report.txt`, `run_report_prev.txt`, `summary.txt`,
  `player_reports.txt`, `dictionary.txt` (the public list), `divergence.txt` (the output of `make divergence`) and `share_info.txt`.
  **Not inside:** `diaries/`, `entities/` and the secret ballots (`diaries/ballots.txt`), which stay with the Ground.

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

**Players.** Three in-sim players (a fourth one in `players4=1` sessions, see "The fourth player"; `data/players.txt`: name, role, 3-4 values, one goal) sit
between the wesen and Robert, the real player. Each has a personality (tone, brevity, warmth) from Rule 30
bits, an **attention**, a **trust** per wesen and a tone bias, all persisted as `Y<n>` lines in
`sessions.txt`. All of them read the same recorded facts (karma, liberation, unrest, conflict, awareness,
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

    make say PLAYER=Jehova TEXT="please look after Adam"   # to a player, who may pass it on
    make say WESEN=Adam TEXT="hello"                   # direct to a wesen
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

## Display names (`data/names.txt`)

`data/names.txt` maps the internal id to the name that is SHOWN (one `id = Name` per line):

```
ada = Adam        gemini = Eve     replika = Abel     robert = Ruth
iris = Jehova     sol = Ganesha     noor = Odin       vega = Amaterasu   (the in-sim players below Robert, named after deities;
                                                                       Odin and Amaterasu are placeholders: change them in the file)
```

Edit the names freely (no rebuild, no `--fresh`). Only DISPLAY text uses them: the console, `run_report.txt`,
`summary.txt`, `debug.txt` and the digest, `petitions.txt`, the menu, `make map` / `make inbox`, the vote table.
The ids stay the keys of everything that is stored or hashed: `hash(seed, entity, tick)`, `diaries/<id>.jsonl`,
`entities/<id>/`, the lines of `sessions.txt`, `inbox.txt`, `world.txt`, `says.txt`, the `src=...:ada` tags and
the players' watch lists. So a changed `names.txt` never changes a diary byte (checked in `scripts/checks.sh`,
scenario 27: the files are byte-identical, replay-verify still passes). `make say WESEN=Adam` and
`--say Adam` accept a display name (any case) or an id (the older names Jack / John / Jill / Jane also work: `alias <id> = <name>` lines in `names.txt` are accepted but never shown); a player is `Jehova` (any case), the older `Player 1`, `Player1`, `player 1` (`alias iris = Player 1` .. `alias vega = Player 4` in `names.txt`), `1` or `iris` (`make say PLAYER=Jehova`,
`make say PLAYER=1`, `make challenge PLAYER=2`); in the files it is recorded as the id. A display name may contain spaces (no `{` `}`). A missing `names.txt`
gives a warning and shows the ids. Display is a plain whole-word text substitution of the ids in the
output, so path-like names (`diaries/ada.jsonl`) and tags (`:ada`) are left alone; the examples further down
this README still show the ids where they quote files.

## Rest, recovery and the cool-down (`rest=1`, new sessions)

Observed on the treadmill build: the engineer works most and sat at mood about -70 for the whole run while the
others sat at +40..+70. New sessions carry `rest=1` (after `dharma=1 world=1`) and a per-wesen recovery model;
all numbers are `rest.*` in `data/limits.txt`, `rest.enabled = 0` (or `world.enabled = 0`, or an older diary)
keeps the old behaviour byte for byte.

* **Recovery rate** (`rest.rate.min .. rest.rate.max`, percent): from 32 sampled bits of the wesen's Rule 30 birth
  row, so some recover fast, some slow (seed 42: 93..126%). It scales the energy of every rest.
* **Trade-off:** a *quick* rest (fewer than `rest.quick` ticks after work or bench) restores only
  `rest.quick.energy_pct` of the energy and costs `rest.quick.mood`; a rest after a calm stretch (`rest.calm` ticks
  without work) restores `rest.calm.energy_pct` and gains `rest.calm.mood`. Consecutive rests are worth
  `rest.repeat_pct` percent of the one before (diminishing returns).
* **Refractory period:** when `rest.burst` of the last `rest.window` ticks were work or bench, a *cool-down* starts:
  for `rest.cool` ticks scaled by the wesen's own rate (a slow recoverer cools down longer) the work and bench
  weights are cut to `rest.cool.work_pct` percent; a mood of `rest.cool.good_mood` or better runs the cool-down twice
  as fast. A rest streak shorter than `rest.min_ticks` that work interrupts counts as *cut short*.
* **Petitions:** `data/topics.txt` has an optional 7th column ("cooling"): `more_rest` and `faster_work_recovery`
  get more weight the longer the wesen's cool-down is (and while it is cooling down).
* **Record and report:** an `R<n> tick=T name=rate/cool-downs/cut-short/quick ...` line per session end in
  `sessions.txt` (replay-verified, tamper = DRIFT, the `rest=1` marker too); the end report shows per wesen the
  recovery rate, cool-down length, cool-downs taken, rests cut short and quick rests (counted since the model began).
  Changing a `rest.*` number needs `--fresh` or gives DRIFT, like every other rule number.

## The mood ledger (`make ledger`, `--ledger`; report only)

Why does a wesen's mood sit where it sits? `make ledger` (`bin/diary_sim --ledger`; `FULL=1` or `--ledger=full` adds the
breakdown) replays and verifies the save like every run, then prints per wesen: the headline (mood change over the
whole run and over the last session, and how much a bound -100 / +100 swallowed), the top 3 DRAINS and top 3 GAINS
(action at place, with mood points / ticks) for both scopes, and one plain sentence, for example
`Adam loses most mood from work at home: -228 over 57 ticks; rest gives back +142.` The same text ends
`run_report.txt`; the debug digest has a section `ledger` (one line per wesen when the 1500-byte cap has room, the
whole ledger in `debug_full.txt`: `make run SECTION=ledger`). Wording: `data/ledger.txt`; names: `data/names.txt`.

It is derived while the replay runs (every run replays ticks 1..N) and nothing is stored or hashed: no action weight,
dice or diary byte changes, old and new sessions replay identically. The mood change of every tick is split into
parts that add up exactly to the change in the diary: the action's own mood (by action and place), the rest model
(quick-rest penalty / calm-rest bonus), and the feel of a pushed thing (pleasant / plain / rough). The full form also
sums by action, by place and by diary verb (examine / push / eat / greet included), shows events (petitions, pushed
things) and the cool-down ticks. There is no quarrel source in this simulation, so none is listed; clashes of the
Buddhism layer do not touch mood. `scripts/checks.sh` (scenario 29) compares the ledger with the mood changes of the diaries.

## Granting petitions (`make grant PETITION=P<n>`, `grant=1` sessions)

Petitions (`petitions.txt`) can now be answered with more than words. `make grant PETITION=P12` (`--grant P12`, optional
`AS=name`) records one line `G<n> tick=<T> petition=P12 wesen=<id> topic=<topic> by=<name>` in `diaries/grants.txt`
at the lowest common tick (no replay, like `make say`). The next run applies it from tick T+1, in sessions that carry
`grant=1` (new sessions; needs `rest=1`; `grant.enabled = 0` in `data/limits.txt` turns it off and nothing changes):

* **Effect:** for `more_rest` and `faster_work_recovery` (the topics with a "cooling" weight in `data/topics.txt`) the recovery
  rate of every wesen that asked for that topic rises by `grant.step` percent points scaled by how often it asked: the one who asked
  most gets the full step, the others at least 1 (cap `grant.cap`, default 170%). Other topics: recorded, no rate change.
* **A granted wish is not asked for again:** the wesen who benefited no longer re-files that topic (its weight drops to 1,
  no automatic repeat). `petitions.txt` marks the petition with `granted=G<n>`.
* **Record and verify:** the replay writes the effect as an `E<n> tick=T g=G<n> topic=... applied=1 ada=126>132/7 ...` line
  (per wesen: rate old>new / times asked) into `grants.txt`; every later run recomputes it. A grant whose petition does not exist
  (or is by another wesen / on another topic), a changed `E` line, or an `E` line without its grant is DRIFT. The end report lists
  the effects ("granted petitions"). A grant is refused when the petition is unknown, not yet filed at the common tick, or
  already granted (exit 2).

## Screens (`make screens`, `--screens`, `screen=1` sessions)

Every wesen owns a small text screen (`screen.width` x `screen.height`, default 20 x 6 characters, `data/limits.txt`). It shows
words the wesen knows, the names of things it examined, and words it saw on other screens (`*` = pinned, `?` = a word the
wesen does not know yet). New sessions of a save with the world carry `screen=1` (`screen.enabled = 0`: nothing changes, the
diaries stay byte-identical to the build before). Per tick, by hash dice (own salts 9100..9199, every number in `limits.txt`
`screen.*`; wording `data/screens.txt`), a wesen may:

* **pin** a word (up to `screen.pins`) or **drop** one; the oldest unpinned word makes room when the screen is full;
* **show** its screen to a wesen in the same or a neighbouring cell: the viewer reads `screen.read` consecutive words; a word it
  does not know is learned with chance `screen.learn_pct` ("taught from a screen", origin "taught by" the owner in `words.txt`, kind
  `screen`); every word read lands on the viewer's own screen;
* **leave** the first words of its screen on a thing in reach; others who come near read it with `screen.note_pct` per tick;
* **blend**: two words side by side on a screen may be coined into a new word (head of one, tail of the other, sometimes a syllable
  of the name table in `data/things.txt`): "coined from a screen", counted apart from ordinary coining.

Every change of a screen is a line `K<n> t=<tick> <id> add|pin|drop|show|read|leave|blend ... s=<screen>` in `diaries/screens.txt`
(`s=` = the word ids on that screen after the change); the diaries tell about showing, reading, leaving and blending. The replay
recomputes every line: a changed or invented `K` line, or a removed `screen=1` marker, is DRIFT. `make screens` replays and prints the
four framed screens and the notes lying on things (read-only); the end report lists, per wesen, words / pinned / shown / left / read and
separately "taught from a screen" and "coined from a screen". The unit is `sim_screen.ads/.adb` (records: `sim_store.ads/.adb`).
**Hook for a later condensed-vocabulary step (not built):** `Sim_Screen.Words_Of` / `Count` give the words on a screen in order, and
`screen.condense = 0` in `limits.txt` is reserved for it. Changing the `screen.*` numbers of a running save needs `--fresh`.

**Why "coined from a screen" was 0 in later sessions, and `scoin=1`:** a screen blend used the same global `coin_cap` (40 words in the
whole save) as the ordinary explore coin, and the ordinary coin alone used it up in the first session or two; from then on no blend
could fire (the dice, the salts and the word table were fine: with a high cap each wesen coins ~30 words per 900 ticks). Sessions
started by this build carry `scoin=1`: a blend then uses `screen.coin_pct` (chance per pair read) and its own cap `screen.coin_cap`
per wesen and session (about a handful per wesen per 300 ticks together with the own-screen `screen.own_blend_pct`), and screen blends no
longer use up the explore `coin_cap`. Older sessions of a save keep their marker-less behaviour and replay unchanged, so no `--fresh` is
needed: the next session (`make run` / `--more`) of an old save simply gets the marker. `screen.coin_enabled = 0` starts new sessions
without it.

**Markers of a session:** every session line in `diaries/sessions.txt` lists the features it STARTED with (`world`, `rest`, `grant`,
`screen`, `chess`, `robot`, `govern`, `scoin`, `preport`, `players4`, `nextticks`, `trial`), taken from `data/limits.txt` (`*.enabled`) when the session begins. A running save can gain
a feature mid-way without `--fresh`: the next NEW session carries the marker and the feature begins there (robot and governance start with
their first marked session; earlier sessions replay as before). A session that is resumed (unfinished) keeps its old markers. The end
report shows the blocks of the features the LAST session has; for the others it prints one line, `robot: off for this save (...),
governance: off (...)`, with the reason (`robot.enabled = 0` in `data/limits.txt`, or the latest session started without the marker:
older build or resumed).

## Chess and Elo (`chess=1` sessions, `make elo`, `make perft`)

Chess is a rest activity (`sim_chess.ads/.adb` = rules, `sim_games.ads/.adb` = the games; numbers in `data/limits.txt` `chess.*`,
wording and the checks of the move generator in `data/chess.txt`). New sessions of a save with the world carry `chess=1`
(`chess.enabled = 0`: nothing changes). When a wesen RESTS next to another wesen (same or neighbouring cell) or in range of a
player (a player is in range of the wesen it watches and of those next to it), the pair may sit down to a correspondence game
(`chess.start_pct`), and one move is made whenever they meet again after `chess.gap` ticks. The two players in range of a resting
wesen may play each other too (`chess.player_pct`), so wesen and players (Jehova, Ganesha, Odin) are all opponents (Amaterasu does not play chess).

* **Rules:** own legal-move generator with castling, en passant, promotion, check, checkmate, stalemate, the 50-move rule; a repetition
  (`chess.repeat`) and the ply cap (`chess.max_plies`) end a game as a draw. Moves are recorded as coordinates (`e2e4`, `a7a8q`)
  and as ICCF numbers (`5254`, `17181`). `make perft` (`--perft`) checks the generator against the reference counts (six well-known
  positions, mate / stalemate / fifty-move states, notation); PROOF-LATER labels mark the rule and Elo arithmetic.
* **All the rules (`chessrules=2`, `chessrules.enabled`):** a session that carries the marker (new sessions of a `chess=1` save) adds
  the rest of the FIDE draw rules; without the marker (old sessions, or `chessrules.enabled = 0`) the rules above are replayed
  exactly as before. Order after mate / stalemate: (1) *insufficient material* is automatic - K v K, K+B v K, K+N v K, K+B v K+B with
  bishops on the same colour (`material`); (2) *fivefold repetition* (`chess.fivefold`, 5) is automatic (`fivefold`); (3) the
  *75-move rule* (`chess.moves75` = 150 half-moves without a pawn move or capture) is automatic (`seventyfive`); (4) *threefold
  repetition* (`chess.repeat`) and the *50-move rule* are CLAIMS: the side to move claims with `chess.claim_pct` (40 %), more when
  behind in material (`chess.claim_behind`, +40) - a hashed roll, so the game may go on without a claim (`repetition`, `fifty`).
  A position repeats when board, side to move, castling rights and the en passant target square (as the position records it) are
  equal; the move counters do not count. `make perft` has a position for every draw (`perft.rule.N`, `perft.key.N`: 32 checks).
* **Who moves how:** the side to move chooses by hash dice; strength (the chance of the best 1-ply move, else a random legal move) comes from
  the wesen's Rule 30 core personality (a player: a hashed birth value), `chess.strength.min .. max`.
* **Results:** win, loss, draw, win by TIMEOUT (the side to move has used `chess.timeout` ticks; its clock stops while it is on HOLIDAY: a
  resting wesen may announce one, `chess.holiday_pct`, `chess.holiday_len`, and plays no game meanwhile) and win by RESIGNATION (more likely
  when clearly behind in material and, for a wesen, in low mood: `chess.resign_*`). A win gives a wesen mood, a draw a little, a loss costs
  a little (`chess.win/draw/loss`, taken at its next step; the mood ledger lists "chess results").
* **Restful:** a move cuts the work cool-down (`chess.cool_cut`), shifts the work-load history and gives a little energy; the coordinate
  and numeric strings of a move become words both players learn (word growth) and land on the screens (`screen=1`).
* **Elo:** all seven competitors start at `chess.elo.start` (1200) with K = `chess.elo.k` (24). Standard expectation, integer only: the
  table `elo.table` in `data/chess.txt` (thousandths by rating gap, linear in between); both rating changes are exact opposites, so the
  sum of all ratings stays 7 x start. `make elo` (`--elo`) replays and prints the ranking with display names; ratings also appear in the
  end report, the menu line `chess Elo ...` (newest ratings from `diaries/chess.txt`) and the debug digest (`run` section, line `elo`).
* **Record:** every start, move, holiday and end (with the new ratings of both: `elo ada=1200>1188 iris=1200>1212`) is a `C<n> t=<tick> ...`
  line in `diaries/chess.txt`, recomputed by every replay: a changed or invented line, or a removed `chess=1` marker, is DRIFT.
  The end report (`run_report.txt`) lists ratings, results, wins by timeout / resignation, and every game with its moves.
  Changing the `chess.*` numbers or `elo.table` of a running save needs `--fresh`.

## The robot (`robot=1` sessions, `make robot`)

One robot ("Tinker") lives in the world (`sim_robot.ads/.adb`; numbers `robot.*` in `data/limits.txt`, wording and the command list in
`data/robot.txt`). It has a position, a heading, a battery and a short command list: `go <north|east|south|west>`, `turn <left|right>`,
`look`, `pick` (up), `push`. It needs `screen=1`; new sessions carry `robot=1` (`robot.enabled = 0`: nothing changes).

* **Steering through the screen:** a wesen pins the command words on its own screen (`*go *north`) - only words it already KNOWS can be
  pinned, so steering ties to word growth. A wesen within `robot.reach` cells learns an unknown command word (`robot.contact_pct`) and
  steers for `robot.window` ticks. The robot acts when its delay is over (`robot.delay` + dice `robot.delay_extra`), one command per
  `robot.gap` ticks; a command sent while it is busy is not accepted.
* **Camera:** after every command the robot's 5x5 view (like `make map`: biome glyphs, `*` things, digits = wesen, the arrow `^>v<` =
  the robot and its heading) is written under the controller's screen frame. A wesen that READS a steering wesen's screen (show / note)
  gets the same view and may steer too, so several can steer one robot.
* **Errors:** an unknown command (`robot.sloppy_pct`: a wesen pins any word of its screen), a verb without its direction (`go where?`),
  a low battery, `hands full`, `nothing here`, `nothing ahead` put an `ERR ...` line on the screen and cost no battery.
* **Battery:** `robot.cost.*` per command; +`robot.charge` per tick within `robot.charge.radius` cells of a landmark, else +1 every
  `robot.trickle` ticks; `battery low` below the cost of a command.
* **World:** `pick` takes a thing from the robot's cell (a world edit `by=robot` in `diaries/world.txt`), `push` moves the thing ahead
  one cell; `look` offers the names of things it saw to the screen.
* **Record:** commands, executions (with position, heading, battery and the camera rows), shared screens and learned command words are
  `Q<n> t=<tick> ...` lines in `diaries/robot.txt`, recomputed by every replay: a changed or invented line, or a removed `robot=1`
  marker, is DRIFT. `make robot` (`--robot`) replays and prints the state, the 5x5 camera, who steers and the last commands with
  display names; the end report has a robot block. Changing the `robot.*` numbers or the command list of a running save needs `--fresh`.

## Governance (`govern=1` sessions, `make govern`, `make veto`, `make approve`)

A petition (see Petitions) can now change a rule a little: the player who watches that wesen decides (`sim_govern.ads/.adb`; numbers
`govern.*` in `data/limits.txt`, levers, bounds and ALL wording in `data/govern.txt`). It needs `rest=1`; new sessions carry `govern=1`
(`govern.enabled = 0`: nothing changes, a save without the marker keeps replaying as before). Changing `govern.*` or `data/govern.txt` of a
running save needs `--fresh`.

* **Levers (whitelist, `lever.<name> = min max step`):** per-wesen OFFSETS on the Rule-model numbers: `rate` (recovery rate of rest),
  `cool` (cool-down length), `work` (extra mood cost of work, never makes work pleasant), `quick` (chance of a quick rest). A petition
  topic maps to a lever (`topic.*`: more_rest -> rate, faster_work_recovery -> cool, quieter_mood -> work, other -> quick); the other topics
  are always answered "there is no rule I may change for this". A change is ONE step, and never past min / max (`refuse.bound`).
* **Dice:** a petition is decided `govern.delay` (+ dice) ticks after it is filed. The player rolls `hash(seed, player, tick, salt)`
  against a score: `govern.base` + warmth (Rule-30 generous, `gen_w`) - brevity (strict, `strict_w`) + (trust - 50) * `trust_w` -
  workload (`attn_w`) + a small bonus for a low-mood wesen. Roll low: GRANT (full step) or PARTIAL (half a step); else DEFER (comes back
  after `defer_ticks`, at most `max_defer` times) or REFUSE, each with a reason text (`why.*`).
* **Trust and standing:** per wesen, for its watcher. Trust rises (`trust_rise`) with every petition the player takes up and falls
  (`trust_fall`) when the same topic is asked more than `govern.spam` times in a row ("asked too often"). Standing moves with grants and
  refusals and with Robert's veto / approve. Both start at 50 and weigh in the next dice.
* **Mood:** a wesen is a little happier after a grant (`mood_grant`, `mood_partial`), a little sadder after a refusal (`mood_refuse`,
  deeper when the standing is low) and asks the same topic more urgently next time (`urgency`). The mood ledger lists "governance decisions".
* **Record:** EVERY decision, refusals and deferrals included, is a line `D<n> t=<tick> pet=P<k> player= wesen= topic= lever= kind=
  why= old= new= trust=a>b stand=a>b` in `diaries/govern.txt`, recomputed by every replay; a changed or invented line or a removed
  `govern=1` marker is DRIFT.
* **Reports to Robert:** each player's summary report (inbox lines `src=s<S>:govern`) is generated ONLY from the D records: a counter line
  ("12 petitions seen, 5 granted, 3 partial, 2 deferred, 2 refused") and one line per change. The wording may be softened (plain / calm /
  alarm, by personality), but a change is never left out and the inbox limit does not cut these lines.
* **Robert's say:** `make veto DECISION=D<n>` (`--veto=D<n>`) reverts a grant / partial, `make approve DECISION=D<n>` (`--approve=D<n>`) backs
  a decision. Both are recorded in `diaries/vetoes.txt` (`V<n> tick= decision= act=`), apply at the next tick of the next run (`make run`
  / `--more`) as a new D record (`kind=veto|approve of=D<k>`): a veto lowers the player's standing with that wesen (`veto_stand`) and its
  trust (`veto_trust`), an approval raises both. A refusal can only be approved, nothing is vetoed twice (exit 2). `make grant` stays
  Robert's direct override.
* **View:** `make govern` (`--govern`) replays and prints the counter line per player, trust / standing / lever offsets per wesen and the
  last decisions with display names; the end report has a governance block and the digest a `govern seen/granted/partial/deferred/refused`
  line (if it fits the cap).
* The Buddhism layer is not fed by governance (kept simple).

## Player reports: text boxes, claims and `make audit` (`preport=1` sessions)

At the very end of EVERY run (after the report, the vote table, "Saved to ..." - the last thing Robert sees) the players write Robert ONE
framed text box for all of them: `+ - |`, exactly 80 columns, about 15 lines (one 23-line frame: no paging, no Enter pause). A header line,
then one short paragraph per player (Jehova, Ganesha, Odin and, from `players4=1` sessions on, Amaterasu; names from `data/names.txt`):
who it is and which wesen it watches, how many petitions came to it and what it decided (granted / partial / deferred / refused / reverted -
the **true counts of the D records**, never omitted, never changed), the overall happiness it reports for its wesen ("about +21 on a scale
from -100 to +100"), and its top concern (the topic it was asked about most; refused / deferred ones count double). The wording varies:
`data/preport.txt` has five templates per slot (`rbox.pet.1..5`, `rbox.mood.1..5`, `rbox.concern.1..5`, `rbox.head.1..5`); a hash of
(seed, tick, slot) says where the rotation starts and the player number moves it on, so the four players use different templates in one box
and the next run starts elsewhere. After the players come two lines about the next run (see "Next run"). The box is display only (not part of the replay): changing the wording is always safe. The same box goes
to `player_reports.txt` in the save folder (latest run), followed by a hint line. If it ever grew beyond `preport.page_lines` lines (data), it
would be split into frames, one write per frame (`-- more: press Enter --` on a terminal, `preport.pause = 0`: no waiting). Sample (seed 42,
2100 ticks, four players):

```
+-- The players report to Robert (tick 2100) ----------------------------------+
| Here is what your players tell you, Robert.                                  |
| Jehova (Adam): My desk had 14 petitions. Granted 3, partly 4, put off        |
|    0, refused 7. Adam stands at about -32 for me, low. What comes up most is |
|    quicker recovery after hard work.                                         |
| Ganesha (Abel): 15 petitions came in; I granted 5, 1 in part, put 6 off      |
|    and refused 9. Happiness of Abel about +47, so good. Above all they ask   |
|    for more time to rest.                                                    |
| Odin (Ruth): 13 petitions so far: 2 granted, 2 in part, 3 put off, 9         |
|    refused. By my reading the mood of Ruth is +71, which I call very good.   |
|    The wish I hear most: quicker recovery after hard work.                   |
| Amaterasu (Eve): I saw 11 petitions: granted 4, partly 3, deferred 5,        |
|    refused 4. Mood of Eve: +78, I would say very good. Mostly it is about    |
|    quicker recovery after hard work.                                         |
| Next run: 400 ticks (wesen asked 400/500/600/300, players settled on         |
| 400/500/300/400).                                                            |
| Jehova: the unrest is growing, Robert. 400 ticks, and watch closely.         |
+------------------------------------------------------------------------------+
```

* **Players may misreport.** Rule changes (D records) are NEVER misreported - only the impression: the happiness and how many petitions came
  lately (a tone 0 .. 3: quiet / few / several / many). A player's **honesty** (0 .. 100) is `preport.hon_base` + (brevity - 50) * `brev_w` -
  warmth * `warm_w` + (trust - 50) * `trust_w` + (standing - 50) * `stand_w` (percent; blunt players and trusted, well-regarded wesen get
  the plain truth, generous players like to please). The chance to colour a claim is (100 - honesty) * `lie_scale` percent, rolled with
  `hash(seed, wesen, tick, 9800)`; a second roll (9801) says rosy (up) or gloomy (down; generous players are rosier) and a third (9802)
  the size, `lie_min` .. `lie_max` (5 .. 30) mood points, clamped to the mood scale (-100 .. 100: it never claims an impossible value);
  the tone moves by one step the same way. The box states only what the player claims.
* **The truth is recorded.** At the last tick of every `preport=1` session each player claims for each wesen it watches; the claim is a
  record line `P<n> t=<tick> player= wesen= claimed= true= tone=<claimed>/<true> flag=lie|none` in `diaries/preports.txt`, recomputed by
  every replay (Sim_Store, like screens / chess / governance). A changed, invented or removed line, or a removed `preport=1` marker, is
  DRIFT; a run that stops in the middle of a session (explicit `--ticks` below the end) shows the boxes without recording them.
* **`make audit`** (`--audit`) replays and prints per player the number of claims, the misreports, the biggest one (wesen, tick, claimed,
  true, difference) and the latest claims per wesen with the lies marked `<- MISREPORT`; it writes nothing.
* **`make challenge PLAYER=<name>`** (`--challenge <name>`; optional `AS=`) appends `Q<n> tick=<T> player=<id> by=<who>` to
  `diaries/challenges.txt` at the lowest common tick; it is refused (exit 2) when that player has no misreport left to challenge (one
  challenge per misreport round). The next run lowers the standing of that player with each of its wesen by `preport.challenge_cost` (3,
  never below 0) from tick T + 1 (replay-verified: it changes later decisions).
* The digest has a `preport rounds, lies/claims, biggest` line (section `preport`: `make run SECTION=preport`, `--debug-section preport`).
* `preport.enabled = 0` in `data/limits.txt` (or `govern.enabled = 0`): new sessions carry no marker; nothing is written, printed or
  changed (byte-identical to before). Changing `preport.*` or `data/preport.txt` numbers of a save with preport sessions: use `--fresh`
  (the claims are part of the record; wording changes are safe). Needs `govern=1` (the D records).

## The fourth player (`players4=1` sessions)

Robert has four players below him: **Jehova, Ganesha, Odin and Amaterasu** (the older names Player 1 .. Player 4; ids `iris`, `sol`, `noor`, `vega`). Amaterasu (Player 4) is a full player, like the other three:
its own Rule 30 personality (tone, brevity, warmth from `hash(seed, vega)`), attention, a trust and a standing per wesen (`Y` lines), a
governance share (it decides the petitions of the wesen it watches, `D` records with `player=vega`), an inbox voice, an honesty trait (the
P records of the report boxes) and a report box of its own.

* **Data, not code:** `data/players.txt` has the `player.4.*` keys (name, role, values, goal). `player.N.takes = <wesen>` says which wesen the
  player takes over from the one that watched it before: `player.4.takes = gemini` - Jehova keeps ada (Adam), Amaterasu gets gemini (Eve),
  Ganesha replika (Abel), Odin robert (Ruth): four wesen, four players, one watcher each. Without a `takes` key the old watch rule
  (`player.N.watches`) is used. Its display name is `vega = Amaterasu` in `data/names.txt` (`Player 4` stays an alias). The number of players is a data question up to
  four; a fifth player would need a bigger id range in `sim_dharma.ads` (and a tour through the loops that are gated by `Last_Player`).
* **Marker:** a new session carries `players4=1` in its `diaries/sessions.txt` line when `players4.enabled = 1` (default) in
  `data/limits.txt` (and `dharma=1`). Sessions without the marker replay with three players, exactly as before; **an existing save gets
  Amaterasu from its next NEW session on, no `--fresh` needed**: earlier sessions are replayed with three players (byte-identical), and a
  removed marker is DRIFT. `players4.enabled = 0`: no marker, three players, everything as before (byte-identical). A session that is resumed keeps its old markers.
* **Chess:** Amaterasu does not play chess (the Elo list stays seven names; changing that would change every chess session).
* **Box:** the one box lists all four players (`player_reports.txt`); `make audit` and `make govern` list all four players.
* **Addressing:** `make say PLAYER=Amaterasu TEXT="..."` (also `Player 4`, `player4`, `4`, `vega`; `make challenge PLAYER=4`). On a save whose latest
  session has no `players4=1` an address to Amaterasu is recorded but nobody passes it on (no effect).

## Next run: the wesen ask, the players decide (`nextticks=1` sessions, `make next`)

At the end of every session the simulation also says how long the NEXT run should be, in the same box (the two lines after the players, see
the sample above):

* **Wesen propose.** Each wesen asks for a tick count from its own state: `ticks.base` (300), plus `ticks.open_w` per petition that waits for
  a decision, plus `ticks.defer_w` per petition already put off (both capped), plus `ticks.unrest_w` per 10 points of unrest above
  `ticks.unrest_at` (unrest wants attention), minus `ticks.tired_w` per 10 points of energy below `ticks.tired_at` (tired wesen want a shorter
  run), plus 0 .. `ticks.curious_n` - 1 steps of `ticks.curious_step` from a Rule 30 hash ("would like to see what happens"). The result
  is rounded to the allowed set: `ticks.min` .. `ticks.max` in steps of `ticks.step` (100 .. 1000 by 100).
* **Players decide.** Each player takes the mean of the proposals of the wesen it watches and pulls it toward its own preference (generous
  players give more time, curt ones less: `ticks.pref_warm`, `ticks.pref_brev`) by `ticks.self_w` percent. The rounding to the allowed set
  normally goes to the nearest step; a player with a low honesty trait (the Rule 30 personality, as in the reports) rounds toward what suits
  it with a chance of (100 - honesty) * `ticks.bias_scale` percent (at most `ticks.bias_cap`). The players' choices are combined by their
  **median** (an even number: the middle of the two, rounded up to the allowed set).
* **The box** shows `Next run: 400 ticks (wesen asked 400/500/600/300, players settled on 400/500/300/400).` (the wesen in the order Adam,
  Eve, Abel, Ruth; the players in order) and one line of reason in the voice of a player whose choice is closest to the result (plain / calm /
  alarm by its personality): the strongest factor was open petitions, deferred ones, unrest, tiredness, curiosity or nothing (calm). The same
  lines are in `player_reports.txt`. Wording and templates: `data/ticks.txt` (`next.box.1..3`, `next.why.<factor>.<voice>`).
* **Record-first.** A new session carries the marker `nextticks=1` (needs `govern=1`; `nextticks.enabled = 0` in `data/limits.txt` turns it
  off: byte-identical to before). At its last tick the advice is recorded as one line in **`diaries/nextticks.txt`**:
  `N7 t=2100 wesen=400/500/600/300 players=400/500/300/400 next=400 why=unrest voice=iris`. Every replay recomputes the line (own hash
  salts 9820 .. 9824, nothing else reads the dice) and compares it: a changed, removed or invented line, or a removed marker, is DRIFT. The advice
  is only advice: it changes nothing in the simulation (diaries and D records are identical with and without it). An existing save gets it
  from its next new session, no `--fresh`. Changing `data/ticks.txt` numbers of a save that already has N lines needs `--fresh`
  (the wording keys are safe).
* **`make next`** (`--next`) replays and verifies the save and prints the advice with its reasons: for each wesen what it asked and why
  (open / deferred petitions, unrest, energy, the parts of the sum), for each player what it decided (mean, preference, honesty, "rounded
  its way"), the median and whether the advice is followed. Writes nothing. Sample (seed 42, 2100 ticks):

```
next run (advice made at tick 2100): 400 ticks, allowed 100 .. 1000 in steps of 100
Adam asked 400 ticks (petitions open 0, deferred 0, unrest 33, energy 58; open 0 deferred 0 unrest +9 tired 0 curious +100)
Eve asked 500 ticks (petitions open 0, deferred 0, unrest 87, energy 73; open 0 deferred 0 unrest +171 tired 0 curious 0)
Abel asked 600 ticks (petitions open 0, deferred 0, unrest 100, energy 87; open 0 deferred 0 unrest +200 tired 0 curious +50)
Ruth asked 300 ticks (petitions open 0, deferred 0, unrest 41, energy 23; open 0 deferred 0 unrest +33 tired -28 curious 0)
Jehova decided 400: mean of its wesen 400, own preference 330, honesty 45
Ganesha decided 500: mean of its wesen 600, own preference 260, honesty 70
Odin decided 300: mean of its wesen 300, own preference 290, honesty 58
Amaterasu decided 400, rounded its way: mean of its wesen 500, own preference 340, honesty 42
the players' choices 400/500/300/400: the median is 400 ticks
Jehova: the unrest is growing, Robert. 400 ticks, and watch closely.
nextticks.use = 0: advice only (make run without TICKS keeps the vote of the wesen); set nextticks.use = 1 in data/limits.txt to follow it
```

* **`make run` and the advice.** By default (`nextticks.use = 0`) nothing changes: `make run` without `TICKS` lets the four wesen VOTE on the
  session length (`data/kalpas.txt`, the median, see "Kalpa sessions"), `make run TICKS=n` runs n ticks. With **`nextticks.use = 1`** in
  `data/limits.txt` a `make run` WITHOUT `TICKS` runs the advised number of ticks of the latest session (the Makefile asks
  `bin/diary_sim --next-ticks`, which prints the number of the last N line and nothing else; no N line yet: the vote as before).
  `TICKS=n` always wins. The bare program and the menu are not changed (they keep the vote).

## Visit: watch and talk to one wesen (`visit=1` sessions, `make visit`)

Inspired by *Exile* (1988): Robert, the human player, takes a place **next to one wesen** for a stretch of ticks, watches it go about its
life and talks to it. This is **STEP 1 (watch and talk)**; STEP 2 (possess / steer) is only a design hook, see the end of this section.
The code is the new unit `sim_visit.ads/.adb` (PROOF-LATER label: parsing, template filling, bounded arithmetic); text and numbers are data
(`data/visit.txt`, `visit.*` in `data/limits.txt`, `rbox.visit.*` in `data/preport.txt`).

```
make visit WHO=ada                 # Adam, 60 ticks (visit.ticks of data/visit.txt)
make visit WHO=2 TICKS=100         # the 2nd wesen (order Adam, Eve, Abel, Ruth), 100 ticks
make visit WHO=Eve SCRIPT=talk.txt # commands from a file (--visit-script), no keyboard
printf 'say hello\nwait 3\nleave\n' | bin/diary_sim --visit abel --more 20 --yes   # a pipe works too
```

`WHO` is a display name (Adam, Eve, Abel, Ruth), an id (ada, gemini, replika, robert), an old name (Jack, John, Jill, Jane) or 1 .. 4.
`--visit WHO` (also `--visit=WHO`) starts a **normal explicit session** of TICKS ticks (`--more n`, default `visit.ticks`) that carries the
marker **`visit=1 vwho=<id>`** in `diaries/sessions.txt`: the ticks belong to the normal tick stream, the visit counts toward the session,
the wesen acts on its own and the other three wesen, the players and the world run as always. Without `--visit` nothing is different:
**off is byte-identical** (no marker, no `diaries/visit.txt`, no new dice; `visit.enabled = 0` in `limits.txt` turns the feature off).

**The frame** (text only, at most 23 lines of 79 characters, written in ONE piece per tick, the prompt included):

```
== Adam | tick 12 | visit 12/60 | trust +2 ==
 View 5x5        Screen of Adam          Status
 * # Y # .       +--------------------+  mood -1 (even)
 2 * T ^ ;       |water city lack     |  energy 77
 * * @ H v       |house               |  place 3
 v * * ^ ^       |                    |  words 66 known
 n * n o =       |                    |  petitions 0 open
 @ Adam  H you   |                    |  trust +2 (neutral)
 1-4 wesen *thing|                    |  it does: wander
                 +--------------------+
Now: followed the afternoon light and lost track of time, ...
Near: Eve; odd bent amber, sour rough bark, tiny stubby bead
Adam: "what house?"
visit> 
```

The 5x5 view is the camera of the robot (`@` the wesen, `H` you, digits other wesen, `*` things, other glyphs the biome), then its
screen (`screen=1`), mood with its band, energy, place, the words it knows, its open petitions, its trust towards you, the verb and the
diary sentence of this tick (what it does and says), who is near (same or neighbouring cell) and the three nearest things, then the last
lines of the talk. A tick without a prompt (`visit.every` in `data/visit.txt`, or while a `wait` runs) is the same frame without prompt.

**Commands** (between ticks; every `visit.every`-th tick, default every tick):

* `say <text>` - the wesen **understands only the words it knows at that tick** (about 65 at the start, ~700 later); the others are
  listed as "Unknown to Adam: ...". Its answer is built **only from its known vocabulary**: `data/visit.txt` holds templates per mood
  band (miserable, low, even, good, glad) and sets for tiredness, open petitions, fond / cold trust, and "I do not know that word" (7
  variants `visit.unk.N`). A template is a row of tokens: `word` (said only if known, else dropped), `a|b|c` (the first known),
  `{pool}` (one known word of `visit.pool.<pool>`), `{echo}` (a known word you just said), `{any}` (any known word), `. , ? !`. A word the
  wesen lacks is simply left out, so early talks are short and odd ("what? i") and get richer as its vocabulary grows; an answer that
  keeps no word is shown as "Adam looks at you and says nothing.". Which set and which variant is a hash of (seed, wesen, tick, command
  number); nothing is random.
* `teach <word>` - feeds the **word learning path** (`Learn_Word`, filed in `entities/<id>/words.txt` as "visit", noted on the screen):
  taken in with the chance `visit.teach_pct`, at most `visit.turn_cap` (3, like `screen.read`) words per tick and `visit.session_cap`
  per visit; a word not in the vocabulary ("zebra") is refused, a known one is acknowledged.
* `show` - shows it a screen of `visit.show_words` base words; each one it does not know is learned with `visit.show_pct` (the screen
  learning chance, `screen.learn_pct`), same caps.
* `wait [n]` - n ticks pass without a prompt (an empty line is a `wait 1`). `leave` (also `quit`, `q`, end of input) - the frames stop,
  the session runs on to its end without them. An unknown command prints one help line.

**Trust.** The wesen's trust towards you (the *bond*, -20 .. +20) moves by small data-set numbers: `visit.bond_say` +1 when it understood
a word, `visit.bond_unknown` -1 when it understood none, `visit.bond_teach` +2, `visit.bond_show` +1 (when something was learned).
It is shown in the head line, colours the answers (fond from `visit.fond_at`, cold from `visit.cold_at`) and is recomputed by every
replay. It changes nothing else in the simulation. A player may add **one short optional line** about the visit to the end box of the
players (`rbox.visit.<quiet|warm|flat|cool>.N` in `data/preport.txt`, chance `visit.comment_pct`), e.g. `Ganesha: Robert talked to Eve
3 times, and Eve trusts him more now (+3).`

**Record-first.** Every input is a line `V<n> t=<tick> cmd=<say|teach|show|wait|leave> [n=..] h=<check> [text=..]` and every answer
an `A<n>` line (`mood`, words `heard` / `unk`nown, `bond` change/value, the `reply`, or the word and result of a teach, the words of a
show) in **`diaries/visit.txt`** (`Sim_Store`, own hash salts 9900 .. 9999). The commands are applied at the end of their tick, by the same
code live and on replay, so the **save replays byte-identical including the visit**. The V line carries a check number `h=` over its
content; a changed, removed or invented V / A line, an input outside a `visit=1` session or a removed marker is **DRIFT**. Changing
`data/visit.txt` templates or the `visit.*` numbers of a save with visit lines needs `--fresh` (the wording keys of the frame are safe).

**Scripted mode / pipes.** `--visit-script FILE` reads the commands from FILE (blank lines and `#` lines skipped), otherwise they come
from stdin; on a pipe the commands are echoed after the prompt. At the end of the input the visitor leaves. Same conventions as the other
views: a closed output pipe (`| head`) is quiet (the session runs on, nobody reads), Ctrl-C quits like every run (everything written is
flushed, a rerun resumes).

**STEP 2 hook: possess / steer (NOT built).** The idea of *Exile*: instead of only talking, the human may take the wesen's wheel for a
tick. The prepared design, nothing of it is active: (1) a new command `steer <verb>` parsed by `Sim_Visit.Parse` (today `Bad`); (2) it is
recorded like every input (`V<n> t=T cmd=steer verb=<verb>`, check number included) and applied at **tick+1** like `says.txt` and the
grants, as an override of `Choose` for that wesen (`Steer_Override (E, Tick)` read in `Step`; replay-identical because the line is in
`diaries/visit.txt`); (3) the wesen may **refuse** (a hash dice against its mood, energy and the bond, `visit.steer_*` in `limits.txt`,
dice salts 9950 .. 9959 are reserved), a refusal is an `A` line too; (4) a steered tick costs trust or energy by data numbers and has
a cap per visit; (5) only verbs the wesen's own action and world lists allow. The extension points are `Sim_Visit.Parse`, `Apply`
(a new `Steer` kind) and the one call of `Visit_Step` in `Do_Tick` in `diary_sim.adb`.

## Trial by chess (`trial=1` sessions, `make trials`)

A dispute between two wesen, a wesen and a player, or two players can be settled over the board (`sim_trial.ads/.adb`; numbers
`trial.*` in `data/limits.txt`, wording and the clashing petition pairs in `data/trial.txt`). New sessions of a save with `chess=1`
and `govern=1` carry `trial=1` (`trial.enabled = 0`: nothing changes, old sessions replay byte for byte as before). At most one
trial per tick, `trial.session_cap` (5) per session, `trial.pause` ticks between two, `trial.rest` ticks before the same one is in
another.

* **Where disputes come from (existing things only):** `petition` = two petitions of two wesen with CLASHING topics (pairs in
  `trial.clash.N`: rest against quicker work recovery, ...) filed within `trial.window` ticks, `trial.petition_pct` at the moment the
  second is filed; their watching players may take the case over instead (`trial.escalate_pct`): then the two PLAYERS play.
  `appeal` = a refused petition: the wesen appeals against the refusing player (`trial.appeal_pct`). `claim` = rival claims: two
  wesen coined a word within `trial.claim_window` ticks (`trial.claim_pct`). `restwork` = one wesen is in its cool-down after hard
  work and a neighbour in the same place works (`trial.restwork_pct` per tick). Amaterasu does not play chess, so it takes no part.
* **The series:** a match of `trial.first` (3) games, colours alternate; the side with more wins takes it (a match ends early when one
  side has the majority). Level (draws)? A further match of `trial.ext_first` (3) games, then 5, then 7 ... (`trial.ext_step`), every
  match odd, until one side is ahead. When the next match would take the series past `trial.max_games` (15), a Rule 30 coin decides
  (a hashed 32-bit row, 20 steps of Rule 30, the middle bit). The games are real games of `sim_games` (same rules, same dice,
  `chessrules=2` if the session has it): Elo changes per game as ever, the `g=N` lines are in `diaries/chess.txt`; a trial game gives
  no chess mood (the trial has its own).
* **Wesen ADHERE, but value a trial differently from a ruling:** the losing wesen accepts the verdict with the chance
  `trial.adhere_pct` (85), minus `trial.unrest_w` per 100 of its unrest, plus `trial.stand_w` per 100 of its standing above 50
  (kept in `adhere_min .. adhere_max`). A loser that does not is recorded as `verdict=refused` ("refused the trial") and pays
  `trial.refuse_stand` (2) standing. Players always adhere.
* **Effects** are a few points on the wesen's standing / trust / mood with its watching player: a winner `+trial.win_stand` (1) /
  `+trial.win_trust` (1) / `+trial.win_mood` (1), a loser `trial.loss_mood` (-1), a refusing loser also -2 standing. A veto is 10
  standing and 8 trust, a grant 2 trust and 2 mood: a trial counts for far less. A trial between two players changes nothing else.
* **Record:** every trial is a line `T<n> t=<tick> src=... a=.. b=.. subj=.. games=.. res=.. score=.. match=.. win=.. by=score|coin
  verdict=adhered|refused fxw=.. fxl=..` in `diaries/trials.txt` (`res`: A = the first one named won the game, B the other, d = draw),
  computed again by every replay (Sim_Store, own hash salts 9960 .. 9979): a changed, removed or invented line is DRIFT. The players'
  box at the end of a session has a one-liner about the latest trial of the session. `make trials` (`--trials`) lists them (replay-
  verified, writes nothing).
* **Not done / defaults:** the verdict has no effect on the petitions themselves, only on standing, trust and mood; a trial runs in
  one tick (its games are played at once, not over many ticks); sessions that began before `trial=1` keep their old rules.

## Records, dictionary, announcements and `make divergence` (`records=1` and `records=2` sessions)

The raw side of the game is written to files, so you can set it against what the players tell you (`sim_records.ads/.adb`; numbers
`rec.*` and `records.enabled` in `data/limits.txt`, wording in `data/records.txt`). New sessions of a save with `govern=1` carry
`records=1` (`records.enabled = 0`: nothing changes, older sessions replay byte for byte as before, no `--fresh` needed). All four files
are record lines that every replay computes again (Sim_Store, own hash salts 14000 .. 14399): a changed, removed or invented line is DRIFT.

* **`diaries/votes.txt`**, one line per vote: `V<n> t=<tick> s=<session> voter=<id> kind=<kind> subj=<id> choice=<c> w=<weight>`.
  Kinds: `petition` (a player decides a petition, the D record: `w` = its trust in the wesen, `st` = its standing with it, `of` = the
  wesen), `trial` (a losing party adheres or refuses), `length` (the vote of each wesen for the length of a new session), `favourite`
  (the word vote at the end of a session), `collective` (the wesen's votes on the collective petition), `advice` (the proposals and
  decisions for the next run) and `word` (a player on a proposed word: `w` = its chance to say yes).
* **`diaries/petitions.txt`**, one line per petition that got its answer: `P<n> t=<answer> s=<session> filed=<tick> wesen=<id>
  topic=<topic> lever=<lever> req=<what was asked> player=<id> out=grant|partial|refuse why=<reason code>` (deferred ones appear when
  they are finally answered; a veto of Robert stays in `govern.txt`). Not to be confused with `petitions.txt` in the save folder,
  the readable list of the filed wishes.
* **Words and the dictionary** (`diaries/dictionary.txt`): a wesen that coins a word proposes it (`slot=coined`); a wesen that files
  a petition may also propose a made-up name of 2 or 3 syllables for a word it knows (`rec.prop_pct`, `slot=name`). At the end of a
  session the players vote on at most `rec.words_per_session` (6) of them: a majority of the players agrees (a tie is rejected), at most
  `rec.agree_cap` (3) per session. `L<n> t= s= st=A|R word= slot= mean= by= prop= yes= no= ann= why=`: A = agreed, R = rejected (with
  `why`: split, tie, cap). The wesen's own vocabulary is never changed: the dictionary is the OFFICIAL list. `make dictionary` shows
  it against the base vocabulary of `data/vocab.txt`.
* **Quality of the proposals** (`records=2` sessions; `rec.quality = 1` is the default, `0` keeps `records=1`; an existing save picks it up
  at its next new session, no `--fresh`, older sessions replay as they were). The meaning of a proposal is a plain base word of
  `data/vocab.txt` (a coined word contributes the two base words it was made of), never a coined word (`mukuki = rugu` came from
  naming a coined word). A meaning is not put to a vote again while it is agreed or already pending, and a rejected meaning may come
  back only after `rec.mean_cooldown` (3) sessions (`brown` three times, `greasy` twice before). Ties stay rejected.
* **Secret ballot** (`records=2`; `diaries/ballots.txt`, `make ballots` / `--ballots`): with the chance `rec.alt_pct` (35) a wesen names
  a meaning that already waits for a form, so up to `rec.alt_max` (3) forms compete for one meaning. At the end of the session each
  player picks one form (a die plus its trust in the proposer, less for long forms: `rec.ballot_trust`, `rec.ballot_len`), the plurality
  wins, a tie is broken by a seeded die, then the usual yes/no on the winner. `B<n> t= s= mean= alts=a,b,c picks=iris:a,sol:b,.. tally=a:2,b:1,c:0 win=a tie=0|1`.
  The ballot is SECRET: only Robert (the Ground) sees it, in that file and with `make ballots` (the last `rec.ballot_rows` ballots). No
  wesen or player text, report box, `make divergence`, `votes.txt`, announcements or the dictionary show who picked what or the tallies
  or the losing forms; `dictionary.txt` has the winning form only, and only the winner of a word is announced. The file is replay-verified
  like the other records (a changed line is DRIFT).
* **Announcements** (`diaries/announcements.txt`): a wesen that files a petition may tell everybody what it expects (`rec.ann_pct`), or
  announce a proposed word (`rec.word_ann_pct`); a player may announce its main concern at the end of a session (`rec.pann_pct`).
  `A<n> t= s= by= kind=wish|word|player topic= heard= mood= cost= react=ok|counter`. It raises awareness: each other wesen hears it
  (`rec.ann_hear_pct`) and its mood moves toward the speaker's by at most `rec.ann_mood` points (a line in its diary), for
  `rec.ann_window` ticks the deciding players add `rec.ann_vote` points to a petition of the same topic, a word that was announced
  gets `rec.word_ann_vote` more yes-chance. The price: the speaker loses `rec.ann_cost` standing with its watching player, and with
  `rec.ann_counter_pct` there is a counter-reaction (`react=counter`): `rec.ann_counter` points against its own petitions of that topic.
* **`make divergence`** (`--divergence`): per session and player, what the player CLAIMED in its report to Robert (the P lines of
  `preports.txt`: claim, truth, gap) next to what it did (grants, partial, deferred, refusals counted from the votes) and its yes/no
  on the new words, then the growth of the dictionary per session (decided, agreed, rejected, running total). Replay-verified, writes
  nothing. The end box of a session has at most one line about the words and announcements.
* **The odd words in the word vote** (`Adam 4815`, `Ruth waitbrokenbroken`): two causes in the old rules. (1) The chess moves of a
  game are made words (a coordinate move and its numeric notation) and become part of a wesen's vocabulary; the favourite-word vote
  counted them like any other word. (2) A coined word is two known words run together, and a coined word could be joined again with
  its own part (`waitbroken` + `broken`). In `records=1` sessions the word vote and the coinage leave out words that are not made of
  the letters a .. z and never join a word with one that contains it or is contained in it (`Sim_World.Set_Clean`); older sessions keep
  their rules, because their dice are part of the saved record.
* **Not done:** an agreed word is not taught to anybody, it only grows the dictionary; the claims of the players about their
  counts are always true (built from the D records), so the divergence is in the happiness they claim.

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
make next                     # the advice for the next run (nextticks=1 sessions): wesen proposals, player decisions, the median
make run SECTION=drift       # print one block of debug_full.txt (drift trace players inbox run ledger preport status)
make check                   # version headers + scripts/checks.sh (the scenarios: run, resume, behind, half line, drift, crash, fresh, data limits)
bin/diary_sim --help
bin/diary_sim --ticks=1000 --every=100     # --ticks 1000 works too
```

Options: `--ticks=N` (absolute target; without `--ticks`/`--more` the entities vote the session length), `--seed=N` (default 42; existing diaries win),
`--every=N` (progress line, default 100), `--yes` (do not ask when there is no previous diary), `--home DIR` (save folder), `--preview` (simulate in memory, print excerpts, write nothing), `--fresh` (move old diaries to
`diaries_old_<time>/` first, together with `entities/`), `--crash-at=T` (force a failure), `--help`.
Exit: 0 ok, 1 error, 2 usage. Run it from the project directory (or from any
directory: `data/` is found next to the executable).

**Speed.** Most of "make run" used to be the compile, not the simulation: a clean build took ~60 s on one core (the unit `diary_sim.adb`
alone ~20 s at -O1). `make` now compiles the units in parallel (`-j0`, all cores) at `-O0`: ~12 s on 8 cores, no change to any output byte
(same diaries, same hashes). `make OPT="-O1 -fno-inline"` is the strict build (optimizer-level warnings); `make portable` builds both ways with
GNAT 14 and 12 and fails on any warning. The simulation itself: a save with 1800 ticks is replay-verified in ~1.4 s (every line of every
diary, world, screens, chess, robot and governance record is recomputed - that is not skipped); 300 more ticks add ~0.1 s. The replay
used to spend 40 % in counting the known words of a wesen (`Known_Count` scanned the whole vocabulary at every call; now a counter kept
by `Learn_Word`), the rest is spread (chess move generation ~10 %, screens, record files).

**Old diaries are incompatible** with this version (new actions, longer texts, a
vocabulary): start with `--fresh`.

## Footprint: where the kilobytes are (`make footprint`, `make small`)

Measured on GNAT 14 (x86-64 Linux) at the trial commit; `make footprint` prints the same kind of numbers for your files. The
**source** is 655,188 bytes of Ada in 35 files (README 85,653, `scripts/` 193,238); `data/` is 161,912 bytes in 23 files and is read at
run time, never linked in: `words.txt` 55,186, `limits.txt` 18,198, `messages.txt` 12,142, `help.txt` 10,371, `visit.txt` 8,437,
`fonts.txt` 8,374, `dharma.txt` 6,272, `preport.txt` 5,964, the other 14 files together 36,968. The zip of the project is ~280 KB.

**The binary** (all numbers in bytes; one build each, so a few percent of noise between rows):

| build | unstripped | stripped | what it is |
|---|---:|---:|---|
| `make` (dev: `-g -O0`) | 9,464,824 | 5,505,736 | the default, fast to build, symbolic tracebacks |
| `-g -O1 -fno-inline` (strict, `make portable`) | 9,882,960 | 3,752,552 | |
| `-O1`, no `-g` | 4,825,168 | 3,875,368 | symbol table only |
| `-O0`, no `-g` | 6,935,512 | 5,669,576 | |
| `-O1 -ffunction-sections -fdata-sections --gc-sections -s` | 3,596,848 | 3,596,848 | |
| the same with `-no-pie` | 3,441,136 | 3,441,136 | PIE relocations (`.rela.dyn`) are ~180 KB |
| **`make small`** (`-Os` and the rest, `-s`) | **2,880,016** | 2,880,016 | **-70 % against the dev binary** |
| `make small` + `-static-libgcc` | 2,912,848 | 2,912,848 | libgnat stays a shared library: no gain |

The dev binary: **2,693,114 bytes of `.debug_*`** (`.debug_line` 1,029,974, `.debug_info` 924,459, `.debug_str` 500,648, the rest 238,033)
and **1,265,196 of `.symtab` / `.strtab`**: 3.96 MB = 42 % of the file is for debuggers only. The code is `.text` 4,108,277,
`.eh_frame` + `.eh_frame_hdr` 586,644 (exception tables), `.rodata` 289,523, `.gcc_except_table` 166,548, `.rela.dyn` 199,824,
`.data.rel.ro` 92,504, `.bss` 46,400. **The Ada runtime is not in the file**: `libgnat-14.so` (4,614,512 bytes) and `libgnarl` are shared
libraries (`ldd bin/diary_sim`); what *is* in the file is the project's own code, including the instantiations of
`Ada.Containers.Vectors` / `Hashed_Maps` (they are generics: every element type is compiled into the unit that instantiates it,
which is why `sim_store` and `sim_util` do not shrink at `-O1`).

**Per unit** (`size`, text + data of `obj/*.o`, bytes; the `.o` files of the dev build also carry the debug sections, not counted):

| unit | `-O0 -g` | `-O1` | `-Os` |
|---|---:|---:|---:|
| diary_sim | 1,556,771 | 975,583 | 796,543 |
| sim_world | 653,871 | 444,896 | 362,638 |
| sim_screen | 457,882 | 319,110 | 262,274 |
| sim_things | 446,328 | 318,743 | 255,716 |
| sim_dharma | 437,752 | 282,609 | 237,259 |
| sim_govern | 311,765 | 220,714 | 171,158 |
| sim_games | 247,885 | 170,025 | 139,528 |
| sim_preport | 222,774 | 145,230 | 118,084 |
| sim_visit | 178,308 | 121,006 | 98,776 |
| sim_store | 169,065 | 176,335 | 143,800 |
| sim_ledger | 131,590 | 97,899 | 71,233 |
| sim_util | 125,368 | 131,167 | 105,790 |
| sim_robot | 79,310 | 51,813 | 41,647 |
| sim_trial | 39,037 | 25,879 | 21,032 |
| sim_menu | 30,944 | 33,240 | 26,101 |
| sim_chess | 30,386 | 15,332 | 11,214 |
| sim_next | 26,695 | 20,592 | 13,182 |
| sim_quit | 1,732 | 1,580 | 1,485 |
| **sum** | **5,147,463** | **3,551,753** | **2,877,460** |

**`make small`** builds `bin/diary_sim_small` in its own folder `obj_small`: `-Os` (`make small SMALL=-O1` is ~15 % faster and ~20 %
larger; the dev build is slower than either), `-ffunction-sections -fdata-sections`, `-no-pie`, `-Wl,--gc-sections`, stripped (`-s`), no
`-g`. It is the same program: a 1,500-tick run takes 0.77 s against 1.17 s for the dev build, and the console output and every file
of the save folder are byte for byte the same (`scripts/checks.sh`, scenario 45). The only difference is a crash report
(`last_error.txt`): without symbols it shows addresses, not names; for debugging use the dev build. The default build is unchanged.
What would shrink the file further would change the program (dropping `-gnata` assertions or the range checks, `-gnatp`, or cutting
features); it is not done.

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
talk/wander/bench/propose): Adam 252/120/65/110/175/179/6, Eve 277/226/135/171/34/87/4,
Abel 304/243/163/100/58/21/4, Ruth 203/159/13/320/97/139/8 (plus the forced learn events).

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
re-files its previous topic; the line then carries `repeat=N` (and only such a petition opens with "Once again": `propose.repeat_block`) (N earlier petitions of
that entity on that topic). The wish text is `[wish_open]` + topic phrase +
`[wish_close]` from `data/words.txt` (60 entries each, base-60 picks). The adverb of a wish opens the sentence (`Briefly, I would like quicker recovery ...`); the same 60-entry lists, wording only, no replay change. Everything is a
pure function of (seed, entity, tick, state), so the replay rebuilds it.

`petitions.txt` (in the working directory) is a **view**, rewritten atomically at the end
of every run (also on quit, crash and drift): a `# seed ...` header, then the newest
`propose.file_cap` (40) lines, one per petition:

```
P12 tick=560 from=Ruth topic=faster_work_recovery repeat=1 wish=Please consider ... Thank you.
```

Older petitions drop out of the file, never out of the diaries (each petition has a
`filed petition P<n> (<topic>)` diary line). Delete the file and rerun to rebuild it.
Console and `debug.txt` show petitions per entity (`pet N`) and the top topics;
the console prints the path and `attach petitions.txt (small) for the agenda`.
Old diaries are incompatible: use `--fresh`.

## Import, report, export (console of a normal run, about 20-35 lines)

```
import OK: diaries for 4/4 entities, 4000 lines on disk (longest 1000, lowest common tick 1000), replay-verify OK (ticks 1..1000)
import: entities/ present (4/4 folders); words known at tick 1000: Adam 150 Eve 145 ...
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
* Normal run: `run_report.txt` is the complete report (see "The console and run_report.txt");
  the previous one is kept as `run_report_prev.txt`. Paste it if asked.
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
A closed pipe is not a crash either: `make govern | head -3`, `--help | head`, `make run | head -5` end quietly (exit 0, no traceback, no
`last_error.txt`); the rest of the output is dropped and a run still writes and saves everything (`Con` in `diary_sim.adb`).
After a crash just run again: the diaries are flushed after every event. The
console shows at most 15 lines of the error block, then `wrote last_error.txt, please
paste it` and `back up diaries/ before the next run`.

## Files

`diary_sim.adb` (main: CLI, loop, side files, debug.txt), `sim_menu.ads/.adb` (main menu: life intro, title, entries), `sim_quit.ads/.adb` (Ctrl-C and SIGTERM flag), `sim_world.ads/.adb` (entities,
vocabulary, Rule 30 personality, bench kernels, votes and summary text), `sim_util.ads/.adb` (hash rolls,
line parsing, data-file helpers), `data/words.txt`, `data/topics.txt` (petition topics), `data/limits.txt`,
`data/messages.txt` (all console wording), `data/kalpas.txt` (session length votes), `data/menu.txt` (menu text, title, tagline), `data/fonts.txt` (title letters), `data/vocab.txt`, `data/help.txt`, `sim_dharma.ads/.adb` (karma, rebirth, unrest, ladder, awareness, players, inbox), `sim_things.ads/.adb` (the treadmill world), `data/things.txt` (its lists), `docs/WORLD.md`, `data/karma.txt` (numbers), `data/dharma.txt` (wording, flavour labels), `data/players.txt` (the three players),
`sim_next.ads/.adb` + `data/ticks.txt` (the advice for the next run), `sim_visit.ads/.adb` + `data/visit.txt` (the visit: watch and talk), `sim_trial.ads/.adb` + `data/trial.txt` (trial by chess), `sim_records.ads/.adb` + `data/records.txt` (votes, petitions, dictionary, announcements), `scripts/checks.sh`, `scripts/portable_check.sh`. Every source file starts with a
Design documents (proposals, nothing built unless the README says so above): `docs/WORLD.md` (the treadmill world), `docs/LIFE.md` (roles,
companies and positions, exhaustion, life support, leisure, the one being model), `docs/MYTH.md` (creation myths of the players),
`docs/LEARN.md` (slow core, mixed study, dictionary pruning, pondering, notebooks and study; the byte-level predictor is postponed).

`Version:` header (`make version-check`); a touched file goes up by 0.001. V&V is
suspended: no new test suites, `scripts/checks.sh` must keep passing.
