# Learning in the station: slow core, mixed study, pruning, pondering, notebooks (design only, nothing built)
Version: 0.004

Status: **proposal for Robert**. No code for any of this exists yet; every number below is a *proposed default* that lives in `data/` when
built, and every decision is open until Robert answers section 11. Style as `docs/LIFE.md`: what it is, what it is made of, what is recorded.
Source of the ideas: the mini-AGI README (volotat/mini-AGI), read by Robert, who said "everything except the Byte Level". The **byte-level
predictor is postponed**: "we cross that bridge once we get to it". This file reserves one hook name for it (section 9) and designs nothing
else about it. Robert's second wish is in section 6: "The Wesen should be able to study their own notes and look at those of others."

## Contents
1. Where we start, and what mini-AGI gives us
2. Slow core, fast skills (`slow=1`)
3. Mixed learning (`mix=1`)
4. Dictionary pruning (`prune=1`)
5. Adaptive depth: pondering (`ponder=1`)
6. Notebooks and study (`notes=1`)
7. Control loop (optional, later; `ctrl=1`)
8. How it interlocks: exhaustion, positions, records
9. The byte-level predictor: postponed, one hook name reserved
10. Build order, check plan, risks
11. Open questions for Robert (recommended answer first)
12. Condensing the vocabulary by an order of magnitude (measured with `make wordstat`)

## 1. Where we start, and what mini-AGI gives us
* **What the wesen have today:** energy 0 .. 100 and mood -100 .. 100 (fast, move every tick), a vocabulary that only grows (taught, coined,
  learned, screens, chess words), a personality fixed at birth (Rule 30 bits: tone, brevity, warmth), karma and the player-facing numbers
  (trust, standing, commit) that already move slowly, the action table (rest, work, explore, talk, wander, bench, propose; `learn` is a
  delivery, never rolled), petitions, the records (votes, petitions, dictionary, announcements, ballots).
* **What Robert saw in the runs:** mood swings that are too big (Eve from +78 to +20 in one session; Adam stuck negative for sessions), and one
  action eating the day (Ruth talks about 1700 of about 5800 actions). The dictionary only grows; nothing ever leaves it. A wesen cannot
  read back what it did, and cannot look at what another wesen wrote down.
* **What we take from mini-AGI** (one line each; the right column is the section here):

| mini-AGI idea | meaning for us | where |
|---|---|---|
| slow trunk (about 0.1x rate) plus fast experts keeps old knowledge | a slow core (mood baseline, temperament leans) and fast skills (words, mood now) | 2 |
| interleaved subjects cost no forgetting, massed reading forgets | rotate study subjects; measure a "massed share"; lean against it | 3 |
| prune experts nothing asks for; "dead means unaddressed" | retire dictionary words nobody uses; never by score | 4 |
| adaptive depth / halting | small decisions in one step, big ones deliberate a few steps, more when the options are close | 5 |
| weights are files on disk, paged in when needed | notebooks are files, read lazily; "the folder is the model" | 6 |
| learning-rate controller from held-out loss | a controller nudges one rate from a held-out style measure (optional) | 7 |
| byte-level model | **postponed** | 9 |

* **Rules kept by every part** (as `docs/LIFE.md` section 8): plain Ada, standard library only, integer arithmetic only; every number, word
  and table in `data/`; every roll is `hash(seed, entity, tick, salt)` with its own salt range; state by replay, records compared (changed,
  invented or removed line = DRIFT); each part has its own marker on the `S` line, **new sessions only** (an existing save picks it up at
  its next new session, **no `--fresh`**), **marker off = byte-identical** (`offcmp2` against the previous tip); `--help` and README current;
  no new test suites (extend `scripts/checks.sh`); 0 warnings on GNAT 14 and 12; PROOF-LATER labels on the arithmetic; no em-dashes in texts.
* **Salt ranges.** Used so far: 9820 .. 9824, 9900 .. 9999 (incl. trial 9960 .. 9979), LIFE 10000 .. 10699, MYTH 11000 .. 12999, being model
  13000 .. 13999, records 14000 .. 14399, companies, positions, exhaustion 15000 .. 15399. **This file: 16000 .. 16999** (checked free in the
  code): slow 16000 .. 16099, mix 16100 .. 16299, prune 16300 .. 16399 (no dice, reserved), ponder 16400 .. 16599, notes 16600 .. 16899,
  control 16900 .. 16999, **vocabulary condensing 19900 .. 19999 (section 12)**, **evolution of words and chess 20000 .. 20999 (`docs/EVOLVE.md`)**. Reserved for the postponed byte predictor: 17000 .. 17999. **Phase B (voices and chat): 18000 .. 18499** (voices 18000 .. 18099, chat answers 18100 .. 18299, check numbers of the chat lines 18400 .. 18499); not used by anything here.

## 2. Slow core, fast skills (`slow=1`)
**Idea:** the things that make a wesen *who it is* change at a fraction (default 1/10) of the rate of the things it *knows and feels today*.
That damps the big swings and stops a wesen from being locked in a bad state by one bad session.

**Which existing quantities are core and which are fast**

| quantity | class | why |
|---|---|---|
| mood now (-100 .. 100) | **fast** | moves with every event; it stays the number the texts and the ledger use |
| **mood baseline** (new, `-60 .. 60`, starts 0) | **core, slow** | the level mood returns to; rate 1/10 |
| energy, location, cool-down, bench steps | fast | tick-level bookkeeping |
| vocabulary (taught, coined, learned) and word freshness (6.4) | fast (skills) | grows every session |
| personality bits (tone, brevity, warmth) | core, fixed | stay fixed; only the *leans* below move |
| **action leans** (the `lean.*` offsets of `data/limits.txt` as seen by one wesen; new per-wesen overlay, `-10 .. 10`) | **core, slow** | temperament: a wesen that rests a lot becomes slightly more restful, slowly |
| karma, commit, trust, standing (players' side) | already slow | unchanged |
| Elo | unchanged | has its own rate |

**Mechanism (integer, bounded; `data/limits.txt`, keys `slow.*`)**
* Every tick, mood is pulled toward the baseline: `mood = mood + clamp((baseline - mood) * slow.pull_pct / 100, -slow.pull_max, slow.pull_max)`
  with `pull_pct = 4`, `pull_max = 3`. A big swing is therefore eased, never cancelled; a wesen at +78 with baseline +10 loses a little each tick.
* At each session end the baseline moves **one tenth of the way** toward the mean mood of the session: `baseline += clamp((mean - baseline) / slow.div, -slow.step_max, slow.step_max)`
  with `div = 10`, `step_max = 5`, then a slow regression toward 0, `baseline -= baseline / slow.home_div` (`home_div = 40`), then the clamp to `base_min .. base_max`.
  So a bad session moves the core by at most 5 points, and no wesen is stuck for ever: the home term and the limits make recovery possible.
* The action leans move the same way: after a session the lean of the most-chosen action goes up by `slow.lean_step` (1) and of the least-chosen down by 1, bounded `-10 .. 10`, never more than one step per session.
* The dice are untouched: the pull is arithmetic on the replayed state, the leans add to the weights the way the rest model's `Work_Pct` does.
* **Record:** `diaries/core.txt` (planned, `Sim_Store`), one line per wesen per session: `C<n> t= s= id= base=<old>><new> mean=<m> leans=rest:+1,talk:-1 h=`. Salts 16000 .. 16099 are reserved for a later chance event; the first version has none.
* **Effect on the reports:** `make audit` and the end report can print "mood now" next to "baseline"; players' claims (preport) stay about mood now.

## 3. Mixed learning (`mix=1`)
**Idea:** interleaved subjects keep everything fresh; massed single-subject practice forgets the rest. Measure it, and lean gently against it.
* **Subjects** (`data/subjects.txt`, planned, a short list): what a wesen can spend free time on, taken from what exists: `talk`, `explore`,
  `wander`, `bench`, `chess`, `screens`, `petition`, `work`, `rest` (later: `study`, `look`, `craft`). Learning events (a word learned, a game, a bench result)
  are tagged with their subject.
* **Massed share** (per wesen, per session, whole percent): the largest share any one subject has of the **free-choice** actions of the session
  (a position's mandated shift ticks, 2.4 of LIFE.md, and forced rests, 2.6, are not counted: they are not choices). Ruth's about 1700 talk actions of about 5800 would read
  `share=29`; a session where one subject has 62 % reads `share=62`.
* **Bias** (the only effect): if `share > mix.cap_pct` (40), the least-studied subject gets `+bias` points on its weight in the next session's action table, where
  `bias = min(mix.bias_max, (share - cap) * mix.bias_per_pct / 10)` with `bias_max = 10`, `bias_per_pct = 5`, and the most-studied subject gets `-bias / 2`.
  It is a lean, not a rule: the wesen still chooses by dice, and the bias fades as the share falls. Exhaustion and positions keep priority over it.
* **Record:** `diaries/study.txt` (planned, `Sim_Store`, shared with the notebook events of section 6), line letter `U`, one line per wesen per session:
  `U12 t=900 s=3 id=robert kind=mix share=62 top=talk least=bench bias=+8 free=412`. Salts 16100 .. 16299 are reserved for the tie-breaks only.
* **View:** `make divergence` gets a short "learning" block: massed share per wesen per session next to the words learned (planned, 80 columns).
* **Success measure** (checked in the scenario): in `mix=1` sessions the mean massed share is lower than in the same seed without the marker, and no session's share rises above `cap + 25`.

## 4. Dictionary pruning (`prune=1`)
**Idea:** "dead means unaddressed." A dictionary word that nobody uses is not wrong, it is *unneeded*; retire it. A word in use is kept. Never by a score.
* **Needs** `records=2` (the dictionary, `L` lines) and, for something to *use*, `notes=1` (section 6); with `notes=0` the first version counts the uses that already exist
  (the word is named in an announcement, a petition text, a vote line, a coined-from list).
* **A use** is any recorded mention (data list `prune.uses`): a notebook entry that contains the word, a study or look that read it, an announcement or a petition that names it,
  a wesen using it in a report line, a player's vote that names it. Mentions are counted per session from the replay; no dice.
* **Rule:** a word with `uses = 0` in each of the last `prune.idle_sessions` (6) sessions, and at least `prune.min_age` (3) sessions old, is **retired**: a new line
  `L<n> ... st=P word= mean= idle=6 s=` appended to `diaries/dictionary.txt` (status `P`, next to `A` and `R`). Nothing else decides: not votes, not trust, not length. At most `prune.per_session` (2) words are retired per session, oldest-idle first.
* **A retired word** leaves `make dictionary` (counted as "retired"), stays in the file (history), and its **meaning is free again after the existing cooldown**: `P` counts like `R` in the rule
  `rec.mean_cooldown` (3 sessions); it may then be proposed again by anybody, including the same wesen. A re-agreed word starts a new idle count.
* **Not pruned:** words of `data/vocab.txt` (the base vocabulary), a word with an open proposal, a word used this session. The wesen's own vocabulary is never touched (the dictionary stays the official list).
* **Check idea:** a word with a use in the window is never retired; a word with none is retired within `idle_sessions + 1`; the order of the lines is by idle time; replay verifies.

## 5. Adaptive depth: pondering (`ponder=1`)
**Idea:** small decisions are made in one step, big ones deliberate for a few steps, longer when the options are close (adaptive depth / halting).
* **Classes** (`data/ponder.txt`, planned): *small* (which action, which word, a chess move: 1 step, as now, so the cost does not change) and *big* (a player deciding a petition, a wesen accepting a trial,
  a player deciding a position application, a wesen leaving or accepting a position, the collective petition): up to `ponder.max_steps` (4, hard cap 8).
* **Steps:** step 1 is the decision as it is today (so `ponder=1` with `max_steps = 1` equals the old run on those decisions except for the record). Each further step re-evaluates the options with a new
  seeded die (`hash(seed, who, tick, 16400 + step)`) added as a small *consideration*; the final score of an option is the integer mean over the steps taken. The next step is taken only while
  the margin between the best two options is below `ponder.margin` (12 points) and steps < max. So close calls get more thought, clear ones stop early (halting).
* **Cost:** a wesen's extra steps cost energy `ponder.energy` (1 point per 2 extra steps) through the one energy point of LIFE.md 2.6 (so a tired wesen may only ponder `tired` steps: `ponder.tired_cap = 2`). A player has no energy: its extra steps delay
  the answer by `ponder.delay` (1 tick per step, recorded; the D record keeps its tick, the `PN` line carries the delay).
* **Record:** `diaries/ponder.txt` (planned, `Sim_Store`): `PN<n> t= s= who=<id> kind=petition|trial|position|leave|collective subj=<id> steps=3 margins=9,4,2 pick=grant h=`. One line per big decision, so the file is small. Salts 16400 .. 16599.
* **Honesty and trust** (the existing machinery) are inputs of the options, not of the stopping rule.

## 6. Notebooks and study (`notes=1`)
Robert: "The Wesen should be able to study their own notes and look at those of others." This is also mini-AGI's "weights are files on disk, paged in when needed".
* **The notebook:** `entities/<id>/notebook.txt` (planned, append-only working file like `words.txt`; the display name comes from `data/names.txt`). Lines are the wesen's *own history*, written as they happen from the replay:
  `N<n> t= kind=learned|coined|petition|outcome|chess|trial|position|read|note word=<w> text=<short sentence from data/notes.txt>`. Only what the wesen itself could know: its words, its petitions and the
  **public** answer it got (granted, refused, why code), games and trials it played, positions it held. **Secrecy rule (as built):** nothing from `diaries/ballots.txt` or the picks of the players is ever written into a notebook, only the winning form of a word and the public result. A check greps notebooks for `picks=` and for losing forms.
* **Lazy loading (the "folder is the model" idea):** the replay keeps, per wesen, only a compact ring of the last `notes.keep` (200) entries (tick, kind, ids) in memory; the file is a mirror that is
  appended where a line is new and rebuilt from nothing if missing (as `words.txt`). A notebook is **read from disk only when a study or look needs it**; a run with no study never opens one.
* **Action 1: study own notebook** (`study`, weight in the action table from `data/limits.txt` `notes.study_w`, leaned up by rusty words and a low mood): takes `notes.study_ticks` (3) ticks, costs
  `notes.study_cost` (2) energy (the one energy point; not allowed when `spent`), **refreshes** up to `notes.refresh` (3) rusty words (6.4), and gives a **small mood lift** (+1 .. +`notes.lift_max` (3)) when there is *visible progress*
  (at least `notes.progress_min` (2) new entries since the last study); no progress, no lift.
* **Action 2: look at another's notebook** (`look`, weight `notes.look_w`, target by dice weighted by the pair trust): allowed if the **pair trust** of the reader toward the owner is >= `notes.share_trust` (45). Pair trust is derived from the replay (no new random state): `50 + 2 * talks_together + chess_games_together - 3 * trial_losses_to - 5 * refused_looks`, clamped 0 .. 100.
  Below the threshold the look is **refused and recorded** (`ok=0`; the refusal lowers pair trust a little, a refused wesen may petition about it).
* **What reading gives:** up to `notes.read_words` (2) words the reader does not know, with `notes.read_pct` (60) each (origin `read-from-<id>` in the word list, like `taught-by`). If the notebook shows a petition of the owner that was refused or
  ignored on a topic the reader also cares about, the reader's urgency for that topic rises by `notes.seed_pts` (10, bounded) with chance `notes.seed_pct` (25): **a grievance found may seed a petition**. The owner may notice: its pair trust toward the reader changes by +1 (shared) or -1 (felt watched, by the owner's warmth bit).
* **Record:** every study and look is a `U` line in `diaries/study.txt`: `U40 t=1210 s=4 id=gemini kind=own words=3 lift=+2 cost=2 h=` and `U41 t=1260 s=4 id=ada kind=look owner=robert ok=1 words=2 seed=more_rest h=`. Replay-verified. Cap `notes.lines_per_session` (24).
* **6.4 Rust (word freshness):** each known word has a *last used* tick (from the replay). A word unused for `notes.rusty_ticks` (300) is **rusty**: it has half weight in the favourite-word vote and in the
  notebook texts, and counts as an idle use for pruning (4). Rust never removes a word (open question 6); study and use refresh it.
* **Salts** 16600 .. 16899 (study choice, look target, read, seed, notice).

## 7. Control loop (optional, later; `ctrl=1`)
**Idea:** mini-AGI adjusts the learning rate from held-out loss. Here: a small controller nudges **one rate** from a measure the wesen do not optimise directly. Marked **optional and PROOF-LATER**; build only if Robert wants it after 2 to 6.
* **Held-out style measures** (data choice, `ctrl.measure`): (a) the **divergence** between the players' claims and the true values (`make divergence`: mean absolute claim-gap per session), (b) **mood variance** across the last 3 sessions of a wesen, (c) the massed share of 3.
* **Controller:** integer, one step per session, never more than `ctrl.step` (1) per key: if the measure is above its target for 2 sessions in a row, `slow.div` goes down by 1 (faster core) or `mix.bias_per_pct` up by 1; below target, the other way; each key has bounds in `data/limits.txt` and the controller only touches keys on a whitelist (the `govern.txt` device).
* **Record:** `diaries/control.txt` (planned): `CT<n> t= s= key=slow.div old=10 new=9 measure=gap value=14 target=8`. Replay-verified; **informational for Robert** first (the controller may run in `observe` mode that writes the line but changes nothing). Salts 16900 .. 16999 (none needed in the first version).

## 8. How it interlocks: exhaustion, positions, records
* **Exhaustion (LIFE.md 2.6, a rule):** study, look and every extra pondering step spend energy through the one energy point; a `spent` or `collapsed` wesen cannot start a study, a look or a deliberation beyond its cap, and the forced rest wins over any bias. The
  slow core is *not* touched by a single exhaustion crossing, only by the session mean. Study is a **lift for the tired** only by the small mood lift, never by energy (it costs energy).
* **Positions (2.4, 2.5):** a position's shift ticks are mandated, so they do not count in the massed share (3) and the mix bias never touches a shift. Skills a position asks for read word **freshness**: a rusty skill word lowers the performance
  term a little, study fixes it. "Accepting a position", "leaving a position" and the player's decision on an application are **big decisions** for pondering (5). The notebook gets `position` entries (taken, left, terms changed). A wesen that looks at a colleague's notebook may learn the words of the department.
* **Records (votes, petitions, dictionary, ballots):** the dictionary gets status `P` (4); the word `uses` read the records; the **ballot stays secret exactly as built** (the Ground only; notebooks and study lines never contain picks, tallies or losing forms); a refused look is a record of its own, not a petition; a seeded petition is an ordinary petition
  (petitions.txt, then votes.txt) with `lever=-` or the existing topic, so the governance machinery is unchanged. `make divergence` shows learning and pondering as extra blocks; `make dictionary` shows retired words.
* **Slow core and records:** players' reports (preport) claim a wesen's mood; the audit compares with mood *now* as today, and may show the baseline beside it.

## 9. The byte-level predictor: postponed, one hook name reserved
Robert: everything except the Byte Level; "we cross that bridge once we get to it". **Nothing about it is designed here.** Only a name is reserved so that nothing else takes it: the Ada package name **`Sim_Bytes`**, the marker name **`bytes=1`**, the file name `diaries/bytes.txt`, and the salt range 17000 .. 17999. No procedure, no data format, no promise.

## 10. Build order, check plan, risks
Steps are called **LN1 .. LN7** (the names L1, L2 are taken by the life-support steps of LIFE.md section 7). Each is one commit: marker, `*.enabled` in `data/limits.txt`, off = byte-identical (`offcmp2`), a scenario in `scripts/checks.sh`, README and `--help`, version headers, 0 warnings on both compilers, `make portable` green.

| step | marker | what | size (Ada + data) | time | risk |
|---|---|---|---|---|---|
| LN1 | `slow=1` | mood baseline, pull, session update, action leans, `core.txt`, audit column; needs `rest=1` | ~300 + 60 | 1 day | M (changes mood dynamics of new sessions) |
| LN2 | `mix=1` | `subjects.txt`, free-choice share, bias, `U` lines `kind=mix`, divergence block | ~350 + 80 | 1.5 days | L-M |
| LN3 | `notes=1` | notebook ring + file mirror, `study` action, rust, mood lift, `study.txt`, lazy load | ~550 + 150 | 2 days | **M-H** (new actions, new files) |
| LN4 | `notes=1` | `look`: pair trust, refusal, reading words, seeded petitions, notice | ~350 + 80 | 1.5 days | M |
| LN5 | `ponder=1` | classes, steps, margin, energy and delay, `ponder.txt`; petition/trial first, positions after C3 | ~400 + 60 | 1.5 days | M |
| LN6 | `prune=1` | uses, idle window, status `P`, cooldown link; needs `records=2`, best after LN3 | ~250 + 40 | 1 day | L |
| LN7 | `ctrl=1` | optional controller, observe mode first | ~300 + 40 | 1 day | M (PROOF-LATER) |

Total about 2,500 Ada + 500 data lines, about 9.5 days (LN7 optional: 8.5 without). Interleaving with LIFE.md section 7: LN1 and LN2 need only `rest=1` and may follow X1; LN3 needs the being record (B1) for the history texts and X1 for the energy point; LN5 follows C3 for the position decisions
(petition and trial pondering can ship earlier); LN6 follows LN3. `slow`, `mix`, `notes`, `ponder`, `prune` are independent markers: any can be off with the others on, each off = byte-identical.

**Check plan (extend `scripts/checks.sh` only; one scenario per step, run on the usual idle data copy):** (1) *off = byte-identical* against the previous tip for each marker; (2) *an existing save picks the marker up at its next new session, no `--fresh`*, older sessions replay as they were, and the whole save replay-verifies;
(3) *tamper*: a changed, removed or invented line in `core.txt`, `study.txt`, `ponder.txt`, `control.txt` or the `P` dictionary lines is DRIFT; (4) *bounds*: baseline within `base_min .. base_max`, no step over `step_max`, leans within `-10 .. 10`, ponder steps <= cap, study lines <= cap, retired words <= `per_session`;
(5) *effect*: over the same seed and 6 sessions, mood variance with `slow=1` is lower than without, the mean massed share with `mix=1` is lower, a word with a use is never pruned and an unused one is, a refused look is recorded when trust < threshold and not when above, reading adds words with origin `read-from-`;
(6) *secrecy*: no notebook, study line or view contains `picks=`, a tally or a losing form of a ballot; (7) *lazy*: a run with `notes=1` and no study opens no notebook (a counter in `debug.txt`); (8) *speed*: ticks per second within 10 % of the previous tip (the existing speed profile); (9) *text*: README, Makefile and `--help` mention the markers; no em-dashes.

**Risks.** (a) *Replay compatibility:* every part changes dynamics (mood, weights, decisions), so it is **new sessions only**, behind its marker, with the old rules kept for old sessions; a marker removed from the `S` line is DRIFT. Never a `--fresh`. (b) *Interaction of markers:* each has its own salts; combinations are tested pairwise in one scenario. (c) *Balance:* the pull and the leans could flatten the wesen; the limits and the `home_div` keep them alive, and the numbers are data. (d) *Disk:* notebooks and `study.txt` grow; caps per session and the ring keep them small. (e) *Time:* the replay does a few integer operations per tick for `slow`; `ponder` multiplies a handful of decisions by at most 8; notebooks are read lazily. (f) *Secrecy:* the only new way to leak the ballot would be a notebook line; the check in (6) covers it.

## 11. Open questions for Robert (recommended answer first)
1. **Core rate 1/10?** *Recommend:* yes, `slow.div = 10` with the 4 % pull; tune after one test of six sessions (Eve's swing should halve). Robert may ask for 1/5 (livelier) or 1/20 (steadier).
2. **Which things are core?** *Recommend:* only the mood baseline and the action leans; personality bits stay fixed at birth, karma and trust are already slow.
3. **What is a "subject"?** *Recommend:* the action kinds plus `study` and `look` (list in `data/subjects.txt`); a cap of 40 % for one subject on free choices, bias at most +10 points, never a hard rule.
4. **Is the mix bias allowed to override a petition granted by a player** (for example more rest)? *Recommend:* no; granted levers and positions win, the bias only uses the free part of the table.
5. **Pruning: what counts as a use?** *Recommend:* any recorded mention (notebook, study, announcement, petition, report line, player vote); idle window 6 sessions, at most 2 retired per session, base vocabulary never pruned.
6. **May a rusty word be forgotten for good?** *Recommend:* no. Rust only halves weight and counts as idle; a wesen never loses a word it has (the floor keeps the observation clean).
7. **Does pondering need to be visible to the players?** *Recommend:* no; the `PN` lines are for Robert (`make divergence`), the players' boxes may say "after some thought" only.
8. **Who may look at whose notebook?** *Recommend:* any wesen at the pair-trust threshold 45; players do not read notebooks (they read reports); Robert (the Ground) reads them with a view `make notes NAME=<n>` later.
9. **Is a refused look a petition topic?** *Recommend:* yes, a new topic `private_notes`, filed rarely, so the players can order sharing or respect privacy (a lever later); in the first version only recorded.
10. **Are notebooks private from the players' decisions?** *Recommend:* yes: the players never see notebook text; the seeded petitions are the only visible effect.
11. **May study give more than a small mood lift?** *Recommend:* no. +1 .. +3 mood on visible progress, no energy, no word bonus beyond refreshing; it should not become the best action.
12. **Control loop: build it?** *Recommend:* not now. Observe-only first (`ctrl.observe = 1`), after LN1 to LN6 have run for ten sessions; it changes nothing until Robert switches `ctrl.observe` off.
13. **Where does the pondering budget come from for players?** *Recommend:* delay in ticks (recorded), no energy; Robert may later give players an "attention" cost.
14. **Order: notes before slow, or slow first?** *Recommend:* LN1 and LN2 first (small, measurable, answer the two observed problems), then LN3 and LN4 (Robert's wish), then LN5 to LN7.
15. **Byte level later?** *Recommend:* leave `Sim_Bytes`, `bytes=1` and 17000 .. 17999 reserved; revisit after LN4, when notebooks give the predictor something to learn from.

## 12. Condensing the vocabulary by an order of magnitude (measured with `make wordstat`)
Robert asked why each wesen knows 5,000+ words after 287 sessions (start vocabulary 275), what the words mean, and whether the vocabulary can be condensed by about
a factor of ten with synonyms. The read-only report `make wordstat` (`--wordstat`, `data/wordstat.txt`) answers the first two from the files. **Numbers of one real run of this build
(build 0.045, seed 42, 287 sessions of 300 ticks, 86,100 ticks, `make night`-style, replay-verified):**

| per wesen (Adam, Eve, Abel, Ruth) | words |
|---|---|
| known words | 5,526 / 5,396 / 5,425 / 5,067 (21,414 in all; only **6,047 different texts**, the wesen share one pool) |
| start words | 64 / 61 / 65 / 74 (the start slice of the 282 words of `data/vocab.txt`) |
| names of things met in the world | 669 / 411 / 633 / 353 |
| taught in lessons (not chess or numbers) | 1,286 / 1,449 / 1,231 / 1,042 |
| read on a screen | 184 / 180 / 181 / 299 |
| coined or blended | 120 / 126 / 155 / 226 |
| **chess move as coordinates** (`e2e4`) | 1,603 / 1,588 / 1,571 / 1,540 |
| **chess move as numbers** (`5755`) | 1,600 / 1,581 / 1,589 / 1,533 |
| same text as an agreed dictionary word (coincidence, not a meaning) | 4 / 2 / 1 / 1 (8 in all) |
| never used again after learning | 21 % / 16 % / 26 % / 14 % (19 % of all words; chess tokens 13 %, start words 40 %) |

* **What the words mean.** 58 % of all words (12,605 of 21,414; 1,661 different moves, each as a coordinate string and as a number string) mean one thing: "a chess move (coordinate or numeric notation)". The rest are
  the 282 base words, made-up names of things (meaning stored by the world: taste, quality, social, feel), words that were taught or read, and 627 blends of two words. The dictionary is a separate list: it holds 85 agreed new names for base words, but they are not in any word list; only eight word texts coincide (see the wordstat dictionary section, and EVOLVE.md).
* **Where they come from.** Every chess move a wesen plays while resting (`diary_sim.adb`, rest -> `Sim_Games.Turn`) makes two words, the move string and its numeric string (`Sim_Things.Prop_Word`, text `chess.word`); the player and the
  partner both learn them as `world` words, and lessons and screens then spread them (of the 12,605 tokens: 6,309 met in the world, 5,140 taught, 1,156 read on a screen). They are never *used* much: they sit on screens
  (a screen is a small list of words) and are shown again, which is why 87 % count as "used again". The **biggest source is the chess moves**; without them a wesen knows about 2,200 words, and about 1,600 if the 2,275 words that
  start or end with another known word (at least 3 letters) were folded into it.
* So a factor of ten needs more than synonyms: synonyms alone give about 1.3x on the non-chess words (1.1x on all words), the tokens about 2.4x, and the rest has to come from keeping fewer words *active*.

**Options (each is new sessions only, behind its own marker, off = byte-identical, the old rule kept for old sessions; nothing of the history is deleted):**
* **(c) Stop minting meaningless tokens as words (`symbols=1`).** Chess strings and numeric strings stay *symbols*: they are written on the screens and in the chess record exactly as now, but they are not word ids, are not learned, taught or counted in
  `Known_Count`, and they do not enter the dice pools of lessons, coining and favourite words. Effect: 5,353 -> about 2,200 known words per wesen (-58 %), the screen file shrinks (31 % of its 141,000 lines are chess adds, more with the chess tokens seen on other screens), and the pool of distinct texts drops from
  6,047 to about 2,700. Cost: the word ids and `Teachable` counts change, so the dice of the new sessions differ from a run without the marker: **marker `symbols=1` on the S line, own salt range 19900 .. 19919 (a symbol needs none; the range
  is for the tie-break of which symbol a screen keeps), new sessions only, an existing save keeps every old byte (no `--fresh`)**, and `make verify` replays old sessions with the old minting rule and new ones with the new rule. Cheap (about 150 Ada lines), safe.
* **(a) A per-wesen active vocabulary with a cap (`active=1`).** Each wesen keeps at most `vocab.cap` (proposed **500**) *active* words; the others become *dormant* with the pruning rule of section 4 (a word unused for `vocab.idle_sessions` = 6
  sessions and older than `vocab.min_age` = 3 sessions goes first, oldest idle first, at most `vocab.per_session` = 40 per boundary, ties by a seeded die in 19920 .. 19949). A dormant word stays in `entities/<id>/words.txt` (history), is a record line
  (`diaries/vocab.txt`, planned, `Sim_Store`, status `D` for dormant and `W` for woken, with `h=`; replay-verified: a changed, removed or invented line is DRIFT), is not in `Nth_Known`, is not taught, and wakes when the wesen meets or is taught it again. Words of
  `data/vocab.txt` and words with an open proposal are never dormant (as in section 4). Effect: the *active* vocabulary is about 500 per wesen (x10 against 5,353) while "ever known" keeps counting upward in the report. This one changes the dice pools, so it is
  new sessions only (marker `active=1`).
* **(b) Synonym classes (display and later use).** A word gets a **canonical head** from (1) the agreed dictionary meaning (`st=A`: words with the same meaning are one class), then (2) shared parents of coined blends (`a+b` and `a+c` share `a`), then
  (3) exact prefix/suffix variants. Aliases map to the head in reports and screens (a dictionary status `st=S word=<alias> head=<word>`, records=2). **The data say this saves little on its own:** the 85 agreed names are dictionary entries that no wesen ever learned (they are synonyms of base words, so they can only be classes if they are taught first), and the
  prefix/suffix variants are 26 % of the non-token words, so classes give about 1.3x on those. Keep it as a *view* of `make wordstat` (the variants line) until the dictionary has meaning to build classes on.

**Recommended answer.** Do **(c) first** (one small step, removes 58 % of the words and a third of the screen traffic without touching anything the wesen say), then **(a) in two stages**: first as a report only (`make wordstat` shows the active count the
rule *would* give, no dice change, no marker), then the real `active=1` with cap 500 if Robert likes the numbers. **(b) stays a view** for now. Together: about 5,400 -> 500 active words per wesen (x10), the full history untouched.
Questions for Robert: (1) is the goal "fewer words known" or "fewer words *in use*"? *Recommend:* in use (active), and let the report keep the history. (2) May chess strings stop being words? *Recommend:* yes. (3) Cap 500, idle window 6 sessions?
*Recommend:* yes, both tunable in `data/limits.txt` (`vocab.cap`, `vocab.idle_sessions`). (4) Retroactive? *Recommend:* never: no `--fresh`, no edit of an old line, new sessions only; the old sessions keep replaying with the old rules.
**Replay determinism, in one line:** every step above changes which words exist or which are drawn, so each is a session marker with its own salt range, new sessions only, off = byte-identical, and the record of dormancy (`diaries/vocab.txt`) is
recomputed by every replay; `make wordstat` itself changes nothing.

*End of the proposal; nothing here changes the program until the steps of section 10 are started.*
