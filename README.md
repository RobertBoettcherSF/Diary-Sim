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

    make say PLAYER="Player 1" TEXT="please look after Adam"   # to a player, who may pass it on
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
iris = Player 1   sol = Player 2    noor = Player 3   vega = Player 4   (the in-sim players below Robert)
```

Edit the names freely (no rebuild, no `--fresh`). Only DISPLAY text uses them: the console, `run_report.txt`,
`summary.txt`, `debug.txt` and the digest, `petitions.txt`, the menu, `make map` / `make inbox`, the vote table.
The ids stay the keys of everything that is stored or hashed: `hash(seed, entity, tick)`, `diaries/<id>.jsonl`,
`entities/<id>/`, the lines of `sessions.txt`, `inbox.txt`, `world.txt`, `says.txt`, the `src=...:ada` tags and
the players' watch lists. So a changed `names.txt` never changes a diary byte (checked in `scripts/checks.sh`,
scenario 27: the files are byte-identical, replay-verify still passes). `make say WESEN=Adam` and
`--say Adam` accept a display name (any case) or an id (the older names Jack / John / Jill / Jane also work: `alias <id> = <name>` lines in `names.txt` are accepted but never shown); a player is `Player 1`, `Player1`, `player 1`, `1` or `iris` (`make say PLAYER="Player 1"`,
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
`screen`, `chess`, `robot`, `govern`, `scoin`, `preport`, `players4`, `nextticks`), taken from `data/limits.txt` (`*.enabled`) when the session begins. A running save can gain
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
wesen may play each other too (`chess.player_pct`), so wesen and players (Player 1, Player 2, Player 3) are all opponents (Player 4 does not play chess).

* **Rules:** own legal-move generator with castling, en passant, promotion, check, checkmate, stalemate, the 50-move rule; a repetition
  (`chess.repeat`) and the ply cap (`chess.max_plies`) end a game as a draw. Moves are recorded as coordinates (`e2e4`, `a7a8q`)
  and as ICCF numbers (`5254`, `17181`). `make perft` (`--perft`) checks the generator against the reference counts (six well-known
  positions, mate / stalemate / fifty-move states, notation); PROOF-LATER labels mark the rule and Elo arithmetic.
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
then one short paragraph per player (Player 1, Player 2, Player 3 and, from `players4=1` sessions on, Player 4; names from `data/names.txt`):
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
| Player 1 (Adam): My desk had 14 petitions. Granted 3, partly 4, put off      |
|    0, refused 7. Adam stands at about -32 for me, low. What comes up most is |
|    quicker recovery after hard work.                                         |
| Player 2 (Abel): 15 petitions came in; I granted 5, 1 in part, put 6 off     |
|    and refused 9. Happiness of Abel about +47, so good. Above all they ask   |
|    for more time to rest.                                                    |
| Player 3 (Ruth): 13 petitions so far: 2 granted, 2 in part, 3 put off, 9     |
|    refused. By my reading the mood of Ruth is +71, which I call very good.   |
|    The wish I hear most: quicker recovery after hard work.                   |
| Player 4 (Eve): I saw 11 petitions: granted 4, partly 3, deferred 5,         |
|    refused 4. Mood of Eve: +78, I would say very good. Mostly it is about    |
|    quicker recovery after hard work.                                         |
| Next run: 400 ticks (wesen asked 400/500/600/300, players settled on         |
| 400/500/300/400).                                                            |
| Player 1: the unrest is growing, Robert. 400 ticks, and watch closely.       |
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

Robert has four players below him: **Player 1 .. Player 4** (ids `iris`, `sol`, `noor`, `vega`). Player 4 is a full player, like the other three:
its own Rule 30 personality (tone, brevity, warmth from `hash(seed, vega)`), attention, a trust and a standing per wesen (`Y` lines), a
governance share (it decides the petitions of the wesen it watches, `D` records with `player=vega`), an inbox voice, an honesty trait (the
P records of the report boxes) and a report box of its own.

* **Data, not code:** `data/players.txt` has the `player.4.*` keys (name, role, values, goal). `player.N.takes = <wesen>` says which wesen the
  player takes over from the one that watched it before: `player.4.takes = gemini` - Player 1 keeps ada (Adam), Player 4 gets gemini (Eve),
  Player 2 replika (Abel), Player 3 robert (Ruth): four wesen, four players, one watcher each. Without a `takes` key the old watch rule
  (`player.N.watches`) is used. Its display name is `vega = Player 4` in `data/names.txt`. The number of players is a data question up to
  four; a fifth player would need a bigger id range in `sim_dharma.ads` (and a tour through the loops that are gated by `Last_Player`).
* **Marker:** a new session carries `players4=1` in its `diaries/sessions.txt` line when `players4.enabled = 1` (default) in
  `data/limits.txt` (and `dharma=1`). Sessions without the marker replay with three players, exactly as before; **an existing save gets
  Player 4 from its next NEW session on, no `--fresh` needed**: earlier sessions are replayed with three players (byte-identical), and a
  removed marker is DRIFT. `players4.enabled = 0`: no marker, three players, everything as before (byte-identical). A session that is resumed keeps its old markers.
* **Chess:** Player 4 does not play chess (the Elo list stays seven names; changing that would change every chess session).
* **Box:** the one box lists all four players (`player_reports.txt`); `make audit` and `make govern` list all four players.
* **Addressing:** `make say PLAYER="Player 4" TEXT="..."` (also `player4`, `4`, `vega`; `make challenge PLAYER=4`). On a save whose latest
  session has no `players4=1` an address to Player 4 is recorded but nobody passes it on (no effect).

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
Player 1 decided 400: mean of its wesen 400, own preference 330, honesty 45
Player 2 decided 500: mean of its wesen 600, own preference 260, honesty 70
Player 3 decided 300: mean of its wesen 300, own preference 290, honesty 58
Player 4 decided 400, rounded its way: mean of its wesen 500, own preference 340, honesty 42
the players' choices 400/500/300/400: the median is 400 ticks
Player 1: the unrest is growing, Robert. 400 ticks, and watch closely.
nextticks.use = 0: advice only (make run without TICKS keeps the vote of the wesen); set nextticks.use = 1 in data/limits.txt to follow it
```

* **`make run` and the advice.** By default (`nextticks.use = 0`) nothing changes: `make run` without `TICKS` lets the four wesen VOTE on the
  session length (`data/kalpas.txt`, the median, see "Kalpa sessions"), `make run TICKS=n` runs n ticks. With **`nextticks.use = 1`** in
  `data/limits.txt` a `make run` WITHOUT `TICKS` runs the advised number of ticks of the latest session (the Makefile asks
  `bin/diary_sim --next-ticks`, which prints the number of the last N line and nothing else; no N line yet: the vote as before).
  `TICKS=n` always wins. The bare program and the menu are not changed (they keep the vote).

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
`sim_next.ads/.adb` + `data/ticks.txt` (the advice for the next run), `scripts/checks.sh`, `scripts/portable_check.sh`. Every source file starts with a
`Version:` header (`make version-check`); a touched file goes up by 0.001. V&V is
suspended: no new test suites, `scripts/checks.sh` must keep passing.
