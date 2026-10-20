# Changelog

Generated from the git history. Each build is numbered 0.0NN; the full rationale of each change is in the commit messages and in `docs/`.

## 0.067 (2026-10-08 .. 2026-10-08)

- 0.067 timing.txt: wall clock per session phase (next, ticks, verify, ckpt, summary, report, chess, write, petitions, console) in the save folder
- 0.067 chess report: run_report.txt lists only the games open at the session start and the ones begun since; every finished game once in chess_games.txt (append-only); timing.txt also gives the simu...
- 0.067 timing.txt: carry= the most words one wesen can carry to each learner now (diagnosis of the frozen missing-by-one)
- 0.067 speed: Coined_Total is a count (was a walk over the whole word table at every coin roll and screen blend); the export check reads only the header line of the side files (bench.txt, words.txt,...
- 0.067 speed: Sim_Store keeps a low-water mark of matched lines, so the per-session orphan checks (Verify_*) start after it instead of walking every stored line of chess.txt, screens.txt, ...
- 0.067 checkin.txt (early signals): the timing line from timing.txt (average ms per phase over the window, last session, the simulation's missing-by-one and carryable counts)
- 0.067 checks: scenario 71 (timing.txt per session, chess_games.txt once each in order, run_report lists only open games); scenario 32 finds G1 in run_report.txt or chess_games.txt; scenario 70 remo...
- 0.067 fix: a check-only replay (make verify, verify-full, the night's end check) writes nothing to the save: no start lines appended to words.txt by a drifting replay, no diary or side file opened...
- 0.067: the coined-word count is reset by Reindex after a checkpoint read (State_IO unchanged: layout guard PASS, checkpoint format stays 4)
- 0.067 lesson=1 (new sessions with carry): lesson pool = words the teacher knows (dormant too: teaching wakes them, 'by=teach:') that at least lesson.min_knowers (2) of the wesen other than the lear...
- 0.067 checkin.txt: shared (3 of 4) counts a lesson=1 lesson word only once it is used (Replika's guard), a 'taught but not used yet' line per wesen, the teachable pool per learner in the timing line
- 0.067 docs: README build 0.067, docs/EVOLVE.md 21 (speed, timing.txt, chess_games.txt, check-only replays write nothing, lesson=1), --help; checks: scenario 73 (lesson=1)
- 0.067 docs/CHECKPOINT.md: layout hash re-recorded (Session_Rec, not streamed, got the lesson field; format stays 4)
- 0.067 lesson=1: anyone may teach (Robert 2026-10-08): no teacher mood bound; one lesson plan a tick: the pull die, then the learner rolled by its pool from the possible teachers, then the teacher b...
- 0.067 checks: scenarios of older rules run with lesson.enabled = 0 (as relief.enabled = 0); the checkin key comparison skips the lesson=1 lines and wrapped tails
- 0.067 checks: the active=2 record accepts teach: wakes in active=1 sessions too (the teacher uses the word; lesson: wakes stay active=2 only)

## 0.066 (2026-10-07 .. 2026-10-07)

- 0.066 crash fix: run_report sections stay on the heap (Sect took a copy of the chess block on the stack: STORAGE_ERROR at s4072), diary block buffer 32 KiB, Data_Prints and --frustration tables on...
- 0.066 scenario 70: end of a session under ulimit -s 160 with a run_report bigger than the stack, debug.txt step line, start after a session whose end checkpoint is missing
- 0.066 docs: README build 0.066 (the end-of-session crash fix, debug.txt step:, the restart after such a crash), docs/EVOLVE.md section 20; scenario 70 greps them
- 0.066 scenario 70: the small-stack run uses the default data (chess on), not the check's copy with chess off

## 0.065 (2026-10-07 .. 2026-10-07)

- 0.065: mood causes v=2 (soft bounds, pull, grants apart; actions only their own effect; moodcause.txt v=2 lines, checkin table with pull and grant, the pull split line); relief=1 (below carry.relie...
- 0.065 relief=1: below the relief energy every tiring action (work, explore, wander, bench) becomes rest; demo min energy 10 instead of 0
- 0.065 NIGHT_SHIP_FULL=1 (make night-ship): the full verify first inside the one budget (SIGHUP ignored during it, detached by default), sessions get the rest; a failed verify: no sessions, VERDICT...
- 0.065 cosmetics: checkin.txt head lines wrap at a space instead of being cut (w79); the terminal night box wraps its lines to fit 79 columns (night_console.txt keeps them whole)
- 0.065 docs: README build 0.065 (relief=1, mood causes v=2, NIGHT_SHIP_FULL=1, wrapping), --help, EVOLVE 19, CHECKPOINT (format stays 4); budget line 'sessions got <time>'
- 0.065 fixes after the first full check: checkin.txt wraps only the cut lines Robert saw (known per wesen, roles) plus the new blocks, the other lines as before; scenario 68 skips the v= token; layo...
- alb_report 0.003: held-back baselines (majority gender, last letter -ë/-a = feminine) and the held-back score of the first 10 alb sessions ever against the last 10 of the window (one line; albanian...
- ship 0.013: early signal 'missing-by-one flow' per wesen (entered / new words, left / by lessons in the window, from entities/*/words.txt; report only)
- 0.065 docs: Albanian baselines line, missing-by-one flow, the root cause of the flat missing-by-one count
- 0.065 docs: which checkin.txt lines wrap
- ship 0.014: the verify line of checkin.txt fits 79 columns: 'no new tick after the verified tick N' (scenario 61 reads the new wording), a long skipped / FAILED line wraps at a space

## 0.064 (2026-10-07 .. 2026-10-07)

- 0.064 data: Albanian book (968 Tatoeba sentences, CC BY 2.0 FR), nouns with gender and their forms (Wiktionary via kaikki.org, CC BY-SA 4.0, trimmed to 1355 nouns), credits, maintainer-only scripts...
- 0.064 wip: Sim_Albanian (alb=1: book found, hearing in book order with held-back nouns skipped, ending x gender cue table and bounded noun memory, own sentences, first person); data/wesen_gender.tx...
- 0.064: alb=1 sessions (marker alb=1 albg=<genders>, albanian.enabled), Sim_Albanian at the session start, diaries/albanian.txt written once per session; state.ckpt format 4 (section albanian, forma...
- 0.064: Sim_Albanian reads its data from the data folder of the run (fixed before the start moves into the save folder, as Load_Data); gender stamp u (unset) / n (none) instead of '-'; held-back nou...
- ship 0.011 / alb_report 0.002: the albanian line in checkin.txt (one line when it fits 77 columns, else two labelled lines: agreement vs shuffle and held-back vs always-m; held-back feminine and fi...
- checks: scenario 68 (alb=1 deterministic, held-back never heard, checkpoint format 4 + verify-full, gender stamp, format 3 fixture, format 3 + alb=1 before the tick -> full replay, the report lines...
- 0.064 docs: README build 0.064, help, EVOLVE 18 (Albanian book and mood causes)
- smoke_test 0.004: the 0.059 fixture step runs with albanian.enabled = 0 and allows for the albanian section of format 4

## 0.063 (2026-10-06 .. 2026-10-06)

- 0.063: moodrest=2 (moodrest.enabled = 2): the drift to the resting mood is a one-point step with the probability pull_bp x gap / 10000 (high above the band), the soft bounds round by a die; no roun...
- 0.063 checks and docs: scenario 67 (moodrest=2 deterministic and wider, moodrest=1 = 0.062 byte for byte via tests/ckpt061_mr1.expect, fixture +0, verify-full, reload); README, help, EVOLVE 17, CHE...
- checks: the short-console scenario runs without resting moods (its anomaly listing needs a wesen that ends low; moodrest=2 keeps energy above 25 in those 500 ticks)

## 0.062 (2026-10-06 .. 2026-10-06)

- 0.062: carry=2 (a lesson is an exchange: words by energy both ways, favour settled in the meeting) and moodrest=1 (resting moods 60-80 from the birth row, soft bounds, faster drift above the band);...
- 0.062: rename the exchange word list (a layout false alarm by name); record the layout hash (no streamed change, format 3 payload proven identical by the ckpt061 fixture)
- ship 0.010: carry line counts carry=2 exchanges (words per lesson out/back, settled at once, Pareto per wesen); mood stats per wesen over the window (median, p10/p90, >=+95, <=-95, in band, below 0...
- 0.062 checks: scenario 66 (the 0.061 fixture loads +0 and continues byte for byte; carry=2, moodrest=1, both; markers; old sessions; verify-full; reload; ship lines; docs); old scenarios run with m...
- 0.062: in a moodrest=1 session a teacher is at or below its own resting mood (+ carry.teacher_rest_margin) instead of mood <= carry.teacher_mood (resting moods of 60..80 stopped all teaching)
- docs: the teacher bound in moodrest=1 sessions
- ship 0.010: the mood stats and the mood goal go to the early signals of checkin.txt (the verdict block keeps lines <= 79 columns; check 61)
- tests: ckpt061_mr1.expect: what 0.062 gives from the 0.061 fixture with carry=2 moodrest=1 (2 sessions, teacher_mood 100): moodrest=1 must stay byte for byte

## 0.061 (2026-10-06 .. 2026-10-06)

- 0.061: word carrying (carry=1 sessions): target by missing-by-one words, teacher pull, relief below 20, favours and standing; checkpoint format 3 with section carry, formats 1/2 still load
- 0.061 ship.sh: the carry line (acts, top pairs, missing-by-one, favours, top teacher's mood, Pareto) on the terminal and in checkin.txt; symstrict, chess strings and shared words lines only in chec...
- 0.061 checks: scenario 65 (target, relief, favours without grants, old sessions unchanged, format 3, the carry line); 64 and make test continue the fixture without carrying; docs (README, EVOLVE 15...
- 0.061: a debtor's help also halves the teacher's work energy (favours get spent when work costs no mood)
- 0.061: carry=1 written before screen=1 in the session line (older checks anchor the end at active=N)
- 0.061 checks: scenarios 62/63 expect the format this build writes (3); the symstrict scenario's 0.053-rules runs without carrying
- 0.061 checks: the symstrict scenario's test and control sessions run without carrying, so they differ only in symbols.strict
- tests: ckpt061 fixture (format 3 checkpoint of tick 1200 written by 0.061, carry=1 sessions with favours) and what 0.061 gave from it (2 more sessions, carry.teacher_mood = 100)

## 0.060 (2026-10-06 .. 2026-10-06)

- 0.060 wip: per-tick O(history)/O(lexicon) work replaced by indices (session records by tick, first running chess game, word-table text index and bit mirrors; DIARY_CHECK_INDEX=1 cross-checks the ol...
- 0.060 wip: end-of-session report faster (Show without per-letter conversions, govern counter with a hash set, games report without copies)
- 0.060 wip: make verify incremental (state.verified.ckpt, --verify / --verify-full, verify_stamp.txt with the simulation fingerprint), replay estimate and 'budget cannot hold' line (--deadline, --re...
- 0.060 wip: make verify (incremental) / make verify-full / make sim-print; ship.sh: reserve from the reports phase only (capped at a quarter of the budget, at least 60 s), --deadline/--reserve/--sim...
- 0.060: version headers, Build 0.060; sim_print.sh leaves the Build constant out; docs: CHECKPOINT.md (incremental verify, due rules, indices, estimate, old-window proposal), README build 0.060, Mak...
- 0.060: checks scenario 64 (a 0.059 checkpoint fixture loads and continues byte for byte as 0.059 did, indices cross-checked; incremental verify / verify-full; fingerprint; due lines; growth; estima...
- 0.060: sim_things: the edits of a chunk read and appended in place (Things_At and Store copied the whole edit vector per call)
- 0.060: make test (scripts/smoke_test.sh: layout guard, fresh save with verify-full / verify, the 0.059 checkpoint fixture)
- 0.060: checks updated to the incremental verify (verified checkpoint and verify_stamp.txt are no records; verify-full where a full replay is the point; make verify on a changed old line still DRIFT...
- 0.060: checks: q during the new ticks no longer assumes the trigger comes in session 1 (sessions are much faster now); verify-full there

## 0.059 (2026-10-06 .. 2026-10-06)

- 0.059 wip: checkpoint keyed to a state format (Ckpt_Format 2, tagged sections with length and hash; format 1 of 0.058 accepted, same layout), build no longer a reason, data/ rule files information...
- 0.059: layout guard scripts/ckpt_layout.sh (State_IO bodies + reached declarations, 'bump Ckpt_Format'), docs/CHECKPOINT.md (format 2, what invalidates, data/ reasoning, ckpt_layout: 2 line, weekly...
- 0.059: checks scenario 63 (0.058 checkpoint built from git 87a2a7c loads in 0.059, M sessions = full replay byte for byte; layout change refused per section; data/ information; verify refresh; layo...
- 0.059: start values of data/ (read before the restore point) are recorded in the checkpoint and refuse it when changed; docs, check 63
- 0.059: ship.sh: 'last full verify' on the terminal only when due (the summary stays at 20 lines); checkin.txt always

## 0.058 (2026-10-06 .. 2026-10-06)

- 0.058 wip: state checkpoint (state.ckpt): Sim_Ckpt, State_IO in the modules, load/restore/write in diary_sim, --replay, verify compares
- 0.058: checkpoint fallbacks (diaries reopened), ckpt_log.txt, start line, test-only DIARY_TEST_REPLAY_MS / DIARY_TEST_TICK_MS; checks: scenario 62 (checkpoint proof), check 57 deterministic, checks...
- 0.058: make slice (SLICE_MINUTES ?= 20, ship.sh 0.005: slice mode, checkpoint pre-announce and verdict line, slice_post_secs, run_log part found by time after a trimmed log); docs README/help/limit...
- 0.058 checks: make slice scenario (checkpoint loaded, verdict line, slice_post_secs); ckpt_log.txt may carry the clock; hand-made night comparison runs without the checkpoint (verified count)
- 0.058: sim_ckpt 0.003: To_Bytes loop instead of an iterated String aggregate (GNAT 12 rejected it: static Constraint_Check)
- 0.058: slice verdict line short (start loaded/full replay + seconds; end tick, MB, seconds), picked from the night box and time-stamped ckpt_log lines; near the time limit at most 2 checkpoint writ...
- 0.058: sim_ckpt 0.004: the fingerprint covers only record files (*.txt, *.jsonl; not inbox.txt): a stray copy or backup file no longer makes the checkpoint stale

## 0.057 (2026-10-06 .. 2026-10-06)

- build 0.057: night-ship one time budget (reserve from the last run, HUP-safe, detach), no stray debug.txt from read-only modes, --end-check-ticks, reports only over the new window (--since-session)...
- build 0.057: the since-last-ship line keeps counts and overlap apart (all 4 +N, overlap -P pts; shared 3-of-4 delta on the vocabulary line); reads a 0.056 stamp (shared_all/shared_pct)
- build 0.057: vocabulary line names the wesen (Adam Eve Abel Ruth), not internal ids; ship.sh 0.004

## 0.056 (2026-10-05 .. 2026-10-05)

- build 0.056: make ship is report-only (day early panel, no q); night-ship overnight

## 0.055 (2026-10-05 .. 2026-10-05)

- build 0.055: make ship (day) / make night-ship (overnight, 10 h): one command, one file (save folder checkin.txt with the same VERDICT header), short terminal summary, long sections clipped; night...

## 0.054 (2026-10-05 .. 2026-10-05)

- build 0.054: capped night ends with max_sessions (no false q), mint-slow also at the floor (slowfloor=1), symstrict=1 closes the chess-string leak

## 0.053 (2026-10-05 .. 2026-10-05)

- build 0.053: every make target prints its wall time last (scripts/timed.sh, exit status kept); make checkin (night of CHECKIN_SESSIONS + active, wordstat, frustration, evolve, verify, each timed);...

## 0.001 .. 0.052 (early builds) (2026-10-03 .. 2026-10-05)

- Scaffold: data files (words, messages, help), Makefile, portable check
- diary_sim: entities, hash rolls, JSONL diaries, autoload/replay/drift, error trace
- diary_sim: tighter traceback, drift message, fresh stamp, checks script, README
- Mood range -100..100 (data/limits.txt), mood tone lists, signed JSON mood, helpers into sim_util, checks updated
- Vocabulary word game, entities/<id>/ working folders, bench action, final votes, make demo
- Real vocabulary: German sign-language index 'Von A - Z' transcribed, one English word per entry (275 words)
- Import confirmation, end-of-run report, export check, run_report.txt and debug.txt (<=1500 bytes) on every exit path
- Rule 30 personalities: weighted action choice from a per-entity CA ring plus energy/mood/word leans
- Petitions: propose action, data/topics.txt, petitions.txt view, per-entity counts and top topics
- make run / make play: continue ./diaries with --more N (TICKS new ticks), clearer import line, misplaced-backup hints
- Kalpa sessions: the four entities vote the session length (median), recorded and verified in diaries/sessions.txt
- Drift at import is an expected stop: 3 plain lines, no traceback, no last_error.txt; build version in sessions.txt header
- make run/play ask before creating a new diary: 'No previous diary found ... [y/N]'
- make demo is a preview: --preview simulates in memory, prints excerpts, writes nothing
- Save folder ../diary-data (sibling of the source folder), 'Saved to <path>', since-the-last-session block
- Main menu (New/Load/Settings/Quit, life intro, title) and per-session wesen word vote
- Buddhism layer (karma, rebirth, attachment, commitment, awareness) + 3 in-sim players + inbox, record-first and replay-verified
- make run/play auto-load with a Save folder header; make menu; menu fits 80x24 in one write per frame; debug digest (--debug, --debug-section)
- Treadmill world (world=1, new sessions): endless generated grid, things teach words, edit log, landmarks, map
- Display names (data/names.txt) and per-wesen rest model (rest=1): recovery rate, quick/calm rest trade-off, cool-down, R lines
- Mood ledger (report only): --ledger / make ledger, run_report section, digest section; digest and debug.txt capped after display names
- Petition wording: the adverb opens the sentence (data/words.txt only, no replay change)
- Grantable petitions: make grant / --grant, replay-checked effect records (grant=1 sessions)
- Screens (screen=1): text screens, show/leave/read, taught and coined from a screen, K records in screens.txt (Sim_Screen, Sim_Store), --screens
- Chess (chess=1): Sim_Chess rules + perft, Sim_Games, timeout/resign/holiday, Elo for wesen and players, C records, --elo/--perft
- Robot (robot=1): Sim_Robot commands pinned on screens, 5x5 camera, battery, errors, Q records, --robot / make robot
- Petition wording: 'Once again' only for repeat=N petitions, no we/I mix, no kindly duplicate, clearer 'other' topic (wording only, replay identical)
- Governance (govern=1): players decide petitions via rule levers, D records, veto/approve, --govern
- Screen blends (scoin=1): own per-session cap and rate instead of the spent global coin_cap; report line why robot/governance are off for a save
- Closed pipe (| head): all view/print commands end quietly, no PROGRAM_ERROR traceback
- Display names: Greek letters (Alpha Beta Gamma Delta / Epsilon Zeta Eta); chess game list, govern view and inbox src tags show names (display only)
- Speed: parallel -O0 build by default (-j0), strict -O1 via OPT, Known_Count counter (output byte-identical)
- Player report boxes (preport=1): first-person text boxes, claimed vs true P records, make audit/challenge
- Display names: Jack/John/Jill/Jane and Player 1..3 (display only; ids unchanged); Player N / N / names accepted case-insensitively
- Fourth player (players4=1): Player 4 (vega) with own personality, watcher, governance, honesty and report box; boxes in frames; old saves get it from the next new session
- One report box for all players (varied wording); wesen names Adam/Eve/Abel/Ruth with old names as aliases
- Next-run advice (nextticks=1): wesen propose ticks, players decide, median in the box, N records, make next, optional make run use
- Visit: stand next to one wesen, watch and talk (visit=1, make visit, sim_visit, diaries/visit.txt)
- Chess: all the rules (chessrules=2): insufficient material, fivefold, 75 moves, threefold/50-move claims; perft draw-rule checks; scenario 43
- Trial by chess (trial=1): disputes settled over the board, best of 3 with odd extensions and a Rule 30 coin, wesen adherence, T lines in diaries/trials.txt, make trials
- Footprint: make small (-Os, gc-sections, stripped, same output), make footprint, README size table, scenario 45
- Names: the players are Jehova, Ganesha, Odin, Amaterasu (display only, data/names.txt; Player 1..4 stay as aliases); README/help/checks updated
- docs/LIFE.md: design proposal for roles and population, life support and leisure (no code)
- docs/MYTH.md: design proposal for creation myths of the players (no code)
- docs: one being model (bio=1) in LIFE.md section 6, linked from MYTH.md: one stored record for players and wesen, calendar, mortality, text hooks (no code)
- Records (records=1): votes, petitions, dictionary and announcements as replay-verified record files, word proposals voted by the players, make divergence and make dictionary, clean word vote (no di...
- Records quality (records=2): the meaning of a word proposal is a base word never a coined one, no meaning is put to a vote again while agreed or pending, a rejected meaning waits rec.mean_cooldown...
- Secret ballot (records=2): up to rec.alt_max forms compete for one meaning, the players pick (plurality, seeded die on a tie), only Robert sees picks and tallies in diaries/ballots.txt and make bal...
- docs/LIFE.md: companies, departments and positions per player (2.4), hard-work petitions as position terms (2.5), exhaustion rule with logged crossings (2.6), being record and build order updated,...
- Short console by default: entity table, petitions, session lines, the players' boxes, @@TRACE marker and pointer; run_report.txt always complete with == name == sections, make run VERBOSE=1 prints...
- docs/LEARN.md: design for slow core, mixed study, dictionary pruning, pondering and notebooks with study (byte level postponed), LIFE.md cross-reference and README docs list (no code)
- Console ends after the narrative summary: @@TRACE/@@SECTIONS and the report pointer move to a time stamped run_log.txt (also DRIFT stops), make runlog, report.log_keep cap; build 0.039
- make night (--continuous): sessions back to back, q / DRIFT / limits stop it; trend.txt per session, make trend, make share; build 0.040
- make night: live timer header (clock, elapsed, save size and growth, speed, time left), trend.txt with elapsed and size, sessions polled through night_rc.txt; build 0.041
- Phase A (build 0.042): q works at every stage, SIGHUP, header with wesen and players, night run in one process, make verify, make bench, -O2
- B1 (build 0.043): wesen voices under the night header, make voices
- B2 (build 0.044): chat - @name text and /orders under the voices, diaries/chat.txt record-first (chat=1, salts 18000..18499), make chat, make chatlog
- docs/PORTALS.md (design only): settings per player, 12 wesen, portals and journeys, farm flower market, island, Accounting ledger, stories, glossary; open questions
- make wordstat (build 0.045): read-only vocabulary report by kind, use, length, variants; in make share; checks
- docs: LEARN.md section 12 condensing the vocabulary (measured numbers, options c/a/b, recommendation); PORTALS.md salt note
- wordstat: dictionary section (agreed/rejected/announced from dictionary.txt), the 'agreed' row is now only a same-text coincidence count; build 0.046
- docs/EVOLVE.md: evolutionary pressure on words and chess (design only); salts 20000..20999 noted in LEARN.md and PORTALS.md
- symbols=1 (EVOLVE step 1): chess moves stay symbols of the board, no longer minted, learned, taught or put on screens; wordstat symbols section; checks scenario 51; build 0.047
- make evolve + make active (EVOLVE steps 2 and 3, read-only previews): word fitness, would-be dormant words, 500 cap preview, chess weights and Elo curve; Sim_Evolve; checks scenario 52; build 0.048
- checks.sh: scenario 52 counts words per file (no cross-file dedup); scenario 14 accepts the symbols=1 session marker
- active=1 (EVOLVE 13, LEARN 12 (a)): per-wesen active vocabulary, dormant words not taught/coined/shown, wake on use, diaries/active.txt replay-verified; make active shows the real state; checks sce...
- checks.sh: scenarios 31 and 33 accept the active=1 session marker
- make wordstat: active-only section on active=1/2 saves (kinds, most used, themes); checks 54 (build 0.050)
- make frustration: read-only MiniMax report (worst wesen by refusals + mood, worst player load); checks 55 (build 0.051)
- active=2 for new sessions: floor 300 under cap 500, mint-slow at the cap (salts 20870..20873), wake by lesson/screen show/petition; old active=1 sessions replay with their locked params; checks 56...
