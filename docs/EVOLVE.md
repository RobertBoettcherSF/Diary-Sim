# Evolutionary pressure on words and on chess (previews built, the rest design)
Version: 0.005

Build state: **step 1 (`symbols=1`) is built** (build 0.047), **step 1 (`symbols=1`)**, **step 2 (`make evolve` preview)** and **step 3 (`make active` preview)** are built (build 0.048); **the real `active=1` (section 13) is built** (build 0.049); everything else is design only.

Status: **proposal for Robert**. No code for any of this exists; every number below is a *proposed default* that lives in `data/` when
built, and every decision is open until Robert answers section 11. Style as `docs/LIFE.md` and `docs/LEARN.md`: what it is, what it is made
of, what is recorded, then the decisions. Robert's wish: "evolutionary pressure on (a) new word generation and (b) finding chess
strategies". Part (a) builds on `docs/LEARN.md` 4 (pruning) and 12 (condensing the vocabulary); part (b) on `Sim_Chess`, `Sim_Games` and the Elo
list. Source of the numbers: `make wordstat` and `diaries/chess.txt` of a real 287-session run (seed 42, 86,100 ticks).

## Contents
1. Where we start (measured)
2. Why the dictionary and the vocabulary differ (84 agreed, 10 in the word lists)
3. Words: fitness, upkeep, retirement, mutation, selection
4. Chess: weights, results, mutation, selection
5. Records, markers, determinism
6. What Robert can see (`make evolve`)
7. Numbers in `data/`
8. Salts
9. Build order and checks
10. Risks and bounds
11. Open questions for Robert (recommended answer first)
12. What the previews showed (`make evolve`, `make active`)

## 1. Where we start (measured)
* **Words** (287 sessions): each wesen knows about 5,400 words (21,414 in all, 6,047 different texts). 58 % are chess strings (coordinates and numbers, 12,605 words
  from 1,661 different moves); without them about 2,200; 19 % were never used again after they were learned. Words only come in: nothing leaves, nothing competes.
  How words are made today: names of things (`Sim_Things`), taught words, screen words, coined blends of two words, and two chess strings for every chess move played.
* **Dictionary** (diaries/dictionary.txt): 85 agreed, 214 rejected, 62 announced with the entry. All 85 agreed entries are `slot=name`: a made-up string proposed as a
  *new name for a base word* (`katora = age`, `lebe = alone`, `guzo = work`). Each base word is agreed once, so the agreed list is a list of synonyms of the base vocabulary.
* **Chess:** 3,519 games, 98,575 moves (about 12 games and 340 moves per session). 99 % end with a win (1,748 black, 1,736 white), 35 draws. `Sim_Chess.Choose` is a 1-ply
  chooser: with chance *strength* (a fixed personality number, not learned) it takes the move with the best material after the move, ties by a die; otherwise a random legal move.
  Nothing a competitor does in game 1 changes game 3,000. Elo after 287 sessions: gemini 1276, noor 1289, ada 1254, replika 1186, iris 1137, sol 1129, robert 1129
  (start 1200), so the spread is only what the fixed strengths produce.

## 2. Why the dictionary and the vocabulary differ (84 agreed, 10 in the word lists)
They are **two separate lists that nothing connects**:
* `diaries/dictionary.txt` is the list of *votes*. An agreed line (`L269 A madadi = big Adam 3/1 s271`) is written by `Sim_Records.Vote_Words` and stays there.
  `Vote_Words` never adds the word to `entities/<id>/words.txt` and nothing teaches it ("Not done: an agreed word is not taught to anybody", README, dictionary section).
* `entities/<id>/words.txt` is what a wesen *knows*. A proposed string is checked against the words known at proposal time, and then forgotten by the vocabulary.
* So the 10 words that `make wordstat` used to count under "agreed meaning" were **coincidences**: a string agreed at tick 4,800 (`doba` = kiss) was minted again at tick 8,726
  by the world as the name of an unrelated thing (`doba` = "leafy rough chalk"). In the 287-session save 85 agreed, 8 word texts coincide, and all 8 were learned *after* the vote.
  `make wordstat` now prints the dictionary figures in a section of their own (agreed, rejected, announced) and labels the 8 as "same text as an agreed word".
* "745 announced" is the number of lines in `diaries/announcements.txt`: announcements of **all** kinds (wishes, words, petitions), not 745 words. Entries announced with
  their vote are the `ann=1` ones (62 of 299 decided in the 287-session save).
* Consequence for this design: **an agreed synonym is the one signal that a made-up word got a meaning**, and today it is thrown away. Section 3 uses it.

## 3. Words: fitness, upkeep, retirement, mutation, selection (`evolve=2`)
**Idea:** a word lives only while it pays for itself. New words are made from words that already work, and the words that work are taught more.

**3.1 Fitness (per word and wesen, integer, once per session, computed from the replay; no dice)**
Points earned in the session:
| source | points (`data/evolve.txt`) | counted from |
|---|---|---|
| used (a screen action, a proposal, a favourite vote, a petition text, a notebook line: the `make wordstat` list) | 1 each, at most 5 per session | diaries, notebook |
| named in a petition that was **granted** | 3 | petitions.txt |
| used in an action that **succeeded** (work finished, a lesson that raised mood, a trial won) | 2 | world, trials |
| is the meaning or the alias of an **agreed** dictionary entry | 5 once, then 1 per session while used | dictionary.txt |
| **synonym of a base word, agreed** (the bonus applies only then) | +4 per session while used | dictionary.txt |
| synonym of a base word, **not agreed** (proposal open, rejected, or never proposed) | 0 (no bonus; a rejected synonym counts only as an ordinary word) | |
| upkeep | -1 per session for every active word, -2 above the cap | |
Running fitness: `fit = (3 * fit + 4 * points) / 4`, floor 0, cap `evolve.fit_cap` (200). A word in its first `evolve.probation` (3) sessions pays no upkeep and is not retired.

**3.2 Retirement.** A word with `fit <= evolve.retire_fit` (1) for `evolve.idle_sessions` (6) sessions, past probation, becomes **dormant**: this is the dormant state of `docs/LEARN.md` 12 (a), same
rules (stays in `words.txt` as history, not in `Nth_Known`, not taught, `diaries/vocab.txt` status `D`; wakes when met or taught again, status `W`), and the dictionary prune rule of LEARN.md 4 applies to the
dictionary the same way. At most `evolve.retire_max` (40) per wesen per session, lowest fitness first, ties by a seeded die. Never retired: `data/vocab.txt` words (the 282 base words), words with an open
proposal, the last active word of a meaning class, and anything below `evolve.min_active` (300 words per wesen). **The cap is not a hard wall:** above `evolve.cap` (500) the upkeep doubles, so the cap bends the fitness instead of cutting words by a count.

**3.3 Mutation (new words).** Each session each wesen makes at most `evolve.mut_max` (6) new words, only from **blends and variants** of active words with fitness above `evolve.parent_fit` (8): a parent
is drawn with chance proportional to `1 + fit` (die 20100 .. 20199), then the existing blend rule (`a+b`, Sim_Things blending) or a prefix/suffix variant makes the child. The child starts on probation and is
recorded (`B` line). Chess strings are **not** words any more (needs `symbols=1`, LEARN.md 12 (c)), so they do not mutate or die here. A fresh made-up string (like the dictionary proposals) is still allowed at a low rate
(`evolve.fresh_pct`, 10) so the pool does not only recombine itself.

**3.4 Selection (what gets taught and used).** Lessons, coining parents and favourite words draw a word with weight `1 + fit / evolve.fit_div` (10), capped at `evolve.weight_cap` (8) and floored at 1: well-used words are
taught more, but every active word keeps a chance. Dormant words have weight 0 except a wake chance of `evolve.wake_pct` (2) when a wesen meets the word again.

**3.5 The agreed-synonym link (the fix for section 2).** When an entry is agreed, the proposer and the voters **learn the word as an alias** of the base word (status `S` of LEARN.md 12 (b): `st=S word= head=`), only
then does it exist in a word list and only then can it earn fitness and the synonym bonus. An alias that nobody uses falls to dormant like any word, and the dictionary keeps the entry. This is a change of the dice pools,
so it is new sessions only like everything else here. Without it the bonus would have nothing to pay.

**3.6 What this connects to.** LEARN.md 4 retires dictionary entries that nobody uses; here the same idle test applies to vocabulary words. LEARN.md 12 (c) `symbols=1` is a prerequisite (otherwise 58 % of the words are
chess strings that are used "again" only because the screens show them, and fitness would reward screen noise). LEARN.md 12 (a) `active=1` is the dormant mechanism itself; `evolve=2` replaces its idle-only rule by the fitness rule.

## 4. Chess: weights, results, mutation, selection (`evolve=1`)
**Idea:** each competitor (4 wesen, 3 players; ids 1 .. 7) owns a **small table of integer weights** that nudge the move choice, learns them from its results, mutates them a little, and copies from a winner now and then.

**4.1 The table (35 numbers per competitor; the preview in `Sim_Evolve` uses exactly these).** Features of a move, all computed from the position by pure functions (`Sim_Chess`): piece moved (6), piece taken (5: a pawn, knight, bishop, rook or queen), gives check, castles,
promotes, moves to the centre (4 squares) or the ring around it, pawn two-step, a minor piece leaves its back rank (development), king move in the first 10 moves of a side, and an **opening bucket** (16 values: a hash of the move text, used for the first 3 moves of a side). A weight is an integer -8 .. +8; the start value is 0 for all (a later `data/evolve_chess.txt` may carry a hand-made start per competitor; default all zero).
**Effect:** `Choose` scores a move `16 * material_after + sum(weights of its features)`, with the total bonus clamped to -12 .. +12, so a weight can order moves of equal or nearly equal value but **never beat a pawn**
(16) and never beats a mate (160,000). Only the strong branch of `Choose` (chance *strength*) uses the table; the random branch is untouched. **With all weights 0 the order of the scores equals the old order, so the choice,
the dice and the record are identical to off** (a property the checks assert).

**4.2 Learning from results.** At the end of a game (`C... end`), for each side and for each feature used in its moves of that game (counted again from the recorded move list, pure):
`credit = sign(result) * clamp(uses in this game - the competitor's usual uses of the feature, -evolve.use_cap .. +evolve.use_cap) * step` (**as built in the preview**: what was *different* from its usual play is credited; the plain count only rewards long games), with `result` = +1 win, 0 draw, -1 loss (resignation and timeout count as win/loss) and `step` = 1, or 2 when the Elo change of the game was 16 or more
(an upset teaches more). Changes are collected per session: at most +-`evolve.sess_max` (3) per weight, at most `evolve.sess_total` (12) moves of the table in all, weights within +-`evolve.w_max` (8). The preview has no decay, mutation or copying (they need dice). Every session each weight also decays by 1 toward 0 with chance
`evolve.decay_pct` (10), so unused habits fade (the slow core of LEARN.md 2 in miniature).

**4.3 Mutation (seeded small tweaks).** At the session boundary each competitor, with chance `evolve.mut_pct` (30, die 20500 .. 20599), picks one weight by die and adds +-1 (die 20600 .. 20699). The tweak is **tentative**: its
`evolve.trial_games` (6) next games are scored against the six before; if the Elo change of the competitor over the trial is below `-evolve.revert_elo` (8) the tweak is undone (`M` line, status `reverted`), otherwise it stays (`kept`).
With about 12 games per session in the real run a trial takes a few sessions; at most one open tweak per competitor.

**4.4 Selection (teaching / copying).** At the session boundary, a competitor with at least `evolve.min_games` (20) games since its last copy and an Elo at least `evolve.gap` (40) below the best-rated competitor copies **with chance
`evolve.copy_pct` (20, die 20700 .. 20799)** the table of a higher-rated one picked by die (weight `1 + gap / 10`), but only **half way**: each weight moves halfway to the teacher's (rounded toward the teacher), so the pool keeps variety.
A copy is a diary line for the learner ("learned the way Noor opens") and a `Y` record. Players are competitors like the wesen (open question 6).

**4.5 What it can and cannot find.** `Choose` is 1-ply with material, so the table can find what a 1-ply player can use: develop pieces, take the centre, castle, avoid early king walks, prefer checks in the right moments, a
useful first six plies. It cannot find deep tactics. That is stated in the report ("a 1-ply player with a weight table") so the Elo curve is read honestly; a later step may add a 2-ply look (open question 8).

## 5. Records, markers, determinism
* **Marker:** `evolve=1` (chess weights) and `evolve=2` (adds word fitness; needs `symbols=1` and `active=1`) on the `S` line, **new sessions only** (an existing save picks it up at its next new session, **no `--fresh`**).
  **Off = byte-identical** to the previous tip (`offcmp2`); with `evolve=1` and all-zero tables and mutation off the chess record is also identical (a check).
* **Dice:** every roll is `hash(seed, entity, tick, salt)` from the salt range in section 8; nothing uses a clock or an unordered container; integer arithmetic only.
* **Record file `diaries/evolve.txt`** (`Sim_Store`, replay-verified: a changed, invented or removed line is DRIFT). Letters (checked free at build): `D` word retired, `K` word woken, `B` word born (mutant),
  `S` alias learned from an agreed entry, `G` chess weight update of a session (`by= s= feat:+d,...`), `M` mutation (`kept` or `reverted`), `Y` copy (`by= from= gap=`), `P` per-session snapshot per competitor
  (`by= elo= games= sum=` where `sum` is a checksum of the table, so the replay compares the whole table cheaply). Word fitness itself is **not** stored: it is derived from the replay at the session boundary,
  and only the events above are recorded, so the file grows by tens of lines per session, not by a line per word.
* **Replay:** `Sim_Evolve` is a pure package; state (weights, fitness, dormant flags) is rebuilt by replay and the record lines are compared to what the replay produces.

## 6. What Robert can see (`make evolve`, `--evolve`, read-only)
`make evolve` prints (every line at most 79 columns, a conclusion at the end, as `make wordstat`):
```
Words (evolve=2; before that: fitness computed from the records, nothing retired)
  wesen        active  dormant  born  retired  woken  top-10 share
  ...
  top words by fitness (word, wesen, fit, uses, granted, agreed alias)
  retired this save (word, wesen, session, fitness at retirement)
  mutants: born N, still active M (survival %), best parent words
Chess (evolve=1)
  weights, one row per feature, one column per competitor (change from start in brackets)
  Elo curve: one line per competitor, 30 sessions, start / now / min / max, and a bar per session
  mutations kept / reverted, copies (who from whom), best table vs worst table
Conclusion (example numbers): Elo spread now 160 -> 240, 3 copies, 41 % of mutations kept; the top-10 words hold 19 % of the fitness.
```
Before the markers exist (**step 1**) the word part runs on any save from the existing records (fitness without retirement); the chess part says "not on". The diary of a competitor gets a line when it copies or
when a mutation is reverted. `make dictionary` and `make wordstat` stay as they are (the dictionary section of `make wordstat` is the 84-versus-10 answer).

## 7. Numbers in `data/`
`data/evolve.txt` (new, all keys `evolve.*` with the defaults of sections 3 and 4, plus the report texts), `data/evolve_chess.txt` (new: feature names, start weights per competitor, opening-bucket rule),
`data/limits.txt` (caps: `evolve.sess_max`, `evolve.cap`, `evolve.min_active`, `evolve.fit_cap`, `evolve.weight_cap`). Nothing numeric in the Ada code.

## 8. Salts
**This file: 20000 .. 20999** (checked free: used so far 9100 .. 9199 screens, 9400 .. 9599 chess, 10000 .. 10699 life, 11000 .. 12999 myth, 13000 .. 13999 being, 14000 .. 14399 records, 15000 .. 15399 company,
16000 .. 16999 learning, 17000 .. 17999 reserved byte predictor, 18000 .. 18499 voices and chat, 19000 .. 19899 portals, settings, farm, ledger, stories, 19900 .. 19999 vocabulary condensing).
Word fitness and retirement 20000 .. 20099 (ties only), mutation parents and variants 20100 .. 20199, fresh strings 20200 .. 20299, teaching weights 20300 .. 20399, wake 20400 .. 20449,
chess mutation pick 20500 .. 20599, chess mutation sign 20600 .. 20699, chess copy 20700 .. 20799, aliases from agreed entries 20800 .. 20849, `symbols=1` 20850 .. 20869 (reserved, it needs no dice), `active=2` mint-slow 20870 .. 20873 (section 14), reserved 20874 .. 20999.

## 9. Build order and checks
1. **`make evolve` report only (BUILT, build 0.048, no marker, no `--fresh`).** Reads the records of any save and writes nothing (a checksum of the save folder is identical before and after; two runs give the same text). Checks (scenario 52): known, symbol and base word counts equal an independent awk count of `words.txt`, active + dormant = the other words, the chess moves and games equal the record, the Elo equals the last rating in `chess.txt`, no weight outside -8 .. +8, every line at most 79 columns, a folder without word lists gives one line and exit 2. **`make active`** (the preview of the 500 cap of LEARN.md 12 (a)) is built on the same code, see section 12.
2. **`Sim_Evolve` weights, `evolve=1` with all-zero tables**: `Choose` takes a table; check: off byte-identical, on-with-zero byte-identical in the chess record.
3. **Learning from results** (4.2) + record file + replay verification (`G`, `P`); check: weights stay in bounds, the replay equals the record, a changed line is DRIFT.
4. **Mutation and revert** (4.3), then **copying** (4.4); check: bounds, determinism (two runs, same bytes), a tampered `M` line is DRIFT.
5. **A/B on a long run**: same seed with `evolve=0` and `evolve=1` for 287 sessions; accept only if the Elo spread and the tables are readable in `make evolve` and no bound was hit more than the limits say.
6. **`symbols=1` (BUILT, build 0.047, new sessions only, no `--fresh`).** A session of a `chess=1` save that carries `symbols=1` keeps the move string and the numeric string as
   symbols of the board (`diaries/chess.txt`, the diary line of the game): they are **not minted as words**, **not put on the screens** (a screen is a list of words, so a symbol has no place there; this
   is the one change against the idea in LEARN.md 12 (c)), and the chess strings that older sessions made are **not learned, not taught and not blended** from then on (`Sim_World.Blocked`; whoever
   knows one keeps it). `symbols.enabled = 0` in `data/limits.txt`: the old rule, byte for byte (checked against the previous tip: only the timestamps of the diaries differ). Measured on seed 42, 60 sessions of 300
   ticks, fresh: known words per wesen 1685 / 1799 / 1643 / 1482 with the marker (no chess word at all) against 2239 / 2567 / 2298 / 2246 without; the words that are not chess strings grow *more* with it
   (about 1,650 per wesen against 713), because lessons and blends no longer draw from a pool that was 70 % chess strings. A run of 60 sessions took 39.9 s against 44.3 s, `make verify` 14.0 s against
   15.6 s, the save folder is 11 % smaller. The old words stay in an existing save until the dormant state (`active=1`) retires them.
   Then `active=1` (LEARN.md 12) as the second prerequisite, then **word fitness live** (`evolve=2`: retirement, no mutants yet), then **mutants and weighted teaching** (3.3, 3.4), then **the agreed-synonym link** (3.5).
Every step: version headers, README and `--help` current, PROOF-LATER labels on the integer arithmetic (importance 3/10, urgency 2/10, SPARK2), 0 warnings on GNAT 14 and 12, extend `scripts/checks.sh` only.

## 10. Risks and bounds
| risk | what could happen | bound |
|---|---|---|
| **vocabulary collapse** | a few words win, the rest die, wesen can say little | `evolve.min_active` 300 per wesen; the 282 base words and the last word of a class never retire; teach weight capped at 8 and floored at 1; `evolve.retire_max` 40 per session; top-10 share reported, fitness capped at 200 |
| **vocabulary explosion by mutants** | blends multiply faster than they die | `evolve.mut_max` 6 per wesen per session; the cap bends upkeep; fresh strings 10 % |
| **fitness gaming** (screen noise counts as use) | chess strings and repeated screen words always win | `symbols=1` first; at most 5 use points per word per session; the synonym bonus only when agreed |
| **chess overfitting** | a table that only beats the one opponent it plays, or a habit that wins by chance | weights never beat a pawn (bonus clamp +-12 against 16); decay 10 % per session; the copy is half way; trial and revert for every tweak; `min_games` 20 before a copy |
| **runaway weights** | every weight at the limit, all the same move | integer range -8 .. +8; +-3 per weight and 12 in all per session; decay; the table checksum is recorded, so a jump is visible in `make evolve` |
| **monoculture** | everyone copies the best table | half-way copy only, a copy chance of 20 %, at least 40 Elo gap, the learner keeps its mutations; the report shows the distance between tables |
| **noise read as learning** | 12 games per session are few; Elo moves by luck | the report prints the Elo curve against a control (the same seed with `evolve=0` is a documented run, not a stored file) |
| **determinism** | a replay differs | pure package, own salts, no clock, sorted iteration, `P` checksums; a DRIFT check in the suite |

## 11. Open questions for Robert (recommended answer first)
1. **One marker or two?** *Recommended:* one marker `evolve=` with levels: 1 = chess weights, 2 = adds word fitness. Chess is independent of the vocabulary work and can start first.
2. **Start with the report?** *Recommended:* yes. Step 1 (`make evolve` on today's saves) costs nothing and shows whether the fitness numbers look sensible before anything is retired.
3. **Should agreed synonyms be learned (3.5)?** *Recommended:* yes, as aliases of the base word, and only then the synonym bonus. Today 85 agreed names reach no word list at all.
4. **Prerequisites for the word part.** *Recommended:* `symbols=1` first (it removes 58 % of the words as noise), then `active=1` (the dormant state), then `evolve=2`.
5. **Fitness inputs and weights** (uses 1, granted petition 3, successful action 2, agreed 5, agreed synonym +4, upkeep 1). *Recommended:* keep them, they are numbers in `data/evolve.txt` and the report shows each source, so Robert can change them after the first run.
6. **Do players learn too (iris, sol, noor), and can a wesen copy a player?** *Recommended:* yes to both: the tables are plain numbers and the three players are the strongest and weakest competitors, so they teach and are taught. The copy is a diary line either way.
7. **Table scope:** 40 features and a 16-bucket opening table, or only openings? *Recommended:* both, small. Features find general habits, the opening buckets find first moves; together about 56 numbers per competitor.
8. **A 2-ply look for the chooser?** *Recommended:* not in this design. First see what a weight table does to a 1-ply player; the report states the limit. A deeper look is a separate marker later.
9. **Mutation accepted by trial (4.3) or plain drift?** *Recommended:* trial and revert with 6 games. It is a hill climb that is easy to explain in a diary line and easy to bound.
10. **Retire by fitness only, or by fitness and age?** *Recommended:* fitness for 6 sessions in a row below the floor, after 3 sessions of probation; nothing else decides (as LEARN.md 4: "never by a score" for votes, but here the score is the use record itself, not a vote).
11. **Control run.** *Recommended:* the A/B in step 5 with the same seed and `evolve=0`, kept as a documented command, not a stored file.

## 12. What the previews showed (build 0.048, `make evolve` and `make active`, read-only)
The rule of 3 as built: the fitness is a **running average per session** (`fit = (3 * fit + 4 * points) / 4`, kept in tenths, at most `evolve.fit_cap`); a word whose fitness is **at or under** `evolve.line10` (3 tenths: a word must earn more than 0.3 points a session) for `evolve.idle_sessions` (6) sessions in a row, after `evolve.probation` (3) sessions, would go dormant. This replaces the "upkeep of 1 per session" of section 3. Base words never go; `evolve.min_active` (300) is a floor, `evolve.retire_max` (40) a limit per session. `make active` is the same with the cap `evolve.cap` (500) as floor and ceiling: the lowest fitness above the cap goes first. Chess and number strings are symbols and left out of both. The previews use no dice, so no salt is taken.

Measured on the 287-session seed-42 run (old rule, 12,605 chess strings = 58 percent of the words):
* **The floor binds.** `make evolve` (floor 300): 8,809 other words; the rule would retire 7,609 (86 percent), but every wesen is held at the 300 floor (638 more are "idle, but kept"). Even `evolve.line10 = 1` gives the same count, so the floor decides, not the line. The most used words are wash, gentlyfollow, kano, pick, right, turn, go, none, scaly, look, kine.
* **A wake rule is needed.** 1,450 words that would be dormant were used again later (13 in a 15-session symbols save), so a dormant word has to wake when it is read again.
* **Cap of 500.** 500 active words per wesen (2,000 in all), 6,809 dormant, the cap is reached in session 28 (at 40 retirements a session), 952 dormant words were used again later. Active / dormant by kind: start 264 / 0, world 245 / 1,821, taught 1,238 / 3,770, screen 145 / 699, coined 108 / 519. The taught and world words carry most of the pressure.
* **Chess.** 98,575 moves of 3,519 games were counted again. Weights still saturate at +-8 for several features (credit follows the length of the game) and 185 changes ran into the limit of the table: the 4.2 rule needs a smaller step or a result-only credit before it is switched on. Elo now runs from 1,129 to 1,289.
* **Speed.** `make evolve` takes about 2.2 s and `make active` 1.4 s on the 287-session save at -O0; a normal run is not changed (the previews are only called by `--evolve` / `--active`).

## 13. The real active vocabulary (`active=1`, BUILT, build 0.049, new sessions only, no `--fresh`)
A new `screen=1` session with `active.enabled = 1` carries the marker `active=1` (session line). Off or an older session: the replay is byte-identical to the previous build (`active.enabled = 0`). The rule is the one of `make active` (section 12): floor = cap = `evolve.cap` (500); fitness, probation, idle, retire_max as `evolve.*`; chess and number strings are symbols and left out; base (start) words never go. A dormant word is not taught, not coined or blended from, not put on a screen and not a favourite (`Sim_World.Asleep`); it wakes when a K, V, P or L record line uses it again. Every decision is an A line of `diaries/active.txt` (params of the first active=1 session, dormant, wake, state); the replay regenerates them (DRIFT on a change). No die is rolled, so no salt is taken (the 20000 .. 20999 band stays free for mutation and decay of the chess table). `make active` prints the real last state on an `active=1` save and the would-be preview on an older one. Checks: scenario 53.

## 14. `active=2` (BUILT, build 0.052, new sessions only, no `--fresh`)
With `active.enabled = 2` (the default now) a new `screen=1` session carries `active=2`. An existing save goes on: its `active=1` sessions replay with their own params line (floor = cap = 500), the first `active=2` session writes a second params line `params level=2 ... floor=300 cap=500 slow_lesson=25 slow_coin=50 slow_screen=50` (kept for the life of the save). Three changes against section 13, only inside `active=2` windows:
* **Floor 300, cap 500** (`active.floor`, `active.cap`): idle words (fitness at or under the line for 6 sessions after the probation) may go dormant down to 300 active words; above 500 the lowest fitness goes first; at most 40 a session as before.
* **Mint-slow at the cap.** A wesen that held at least the cap at the last session end (the state line ends `slow=1`) gets a NEW word only when a die lets it through: a lesson `active.slow_lesson_pct` (25 %, salt **20870**, rolled by the teacher's tick with the pupil's id), a coined word `active.slow_coin_pct` (50 %, salt **20871**), a word learned from a screen `active.slow_screen_pct` (50 %, salt **20872**, tick + index of the word on the screen), a screen blend (the coin percent, salt **20873**). Not at the cap: no die, the old rule.
* **Wider wake.** (a) A lesson may pick a word the pupil has dormant (the teacher has it active): the lesson wakes it (`wake ... by=lesson:<teacher>`), nothing is minted and words.txt gets no line; the diary says "remembered the word ... again". (b) A screen `show` or `read` line wakes and counts the words for the other wesen of the line too (field 5). (c) A petition naming a word wakes it for every wesen that has it dormant.
Every decision stays an A line of `diaries/active.txt` and is replay-verified (DRIFT on a change). `make active` shows both params lines, the level of the last closed window and who is at the cap. Checks: scenario 56. Measured (an active=1 save of 39 sessions + 10 sessions of 300 ticks): new words 474 against 796 with active=1, about 250 lesson wakes, active words about 330 .. 400 per wesen (floor 300), the same run time (21.0 s against 20.1 s).
