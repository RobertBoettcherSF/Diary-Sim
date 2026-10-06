# Version: 0.050
# make ship       ROBERT'S DAY COMMAND (after unzipping over the source folder; the save in ../diary-data stays): REPORTS ONLY, no
#                 night, no q, seconds: build if needed, then active, wordstat, frustration, evolve on the save as it is, and verify if the
#                 save has at most SHIP_VERIFY_TICKS (150000) ticks (verify replays the whole history, minutes on a big save; the
#                 end check of the last night is quoted instead; SHIP_VERIFY=1 always, 0 never).
#                 EVERYTHING goes into checkin.txt in the save folder (../diary-data/checkin.txt, or --home / $DIARY_HOME) with a VERDICT
#                 header on top (build, the last night's stop reason, symstrict=1 / slowfloor=1 on its sessions, mint-slow at the floor,
#                 chess strings since symstrict=1, verify, early signals: roles, shared words, petition topics, mood spread, and the
#                 changes since the last ship from ship_stamp.txt, which every ship writes); the terminal shows a short summary and the
#                 path of that ONE file to attach.
#                 Exit 0 = PASS.  SHIP_SESSIONS=N (0) adds N new sessions of CHECKIN_TICKS (300) ticks first, without q; NOTE: that run
#                 replays the whole history once before the first new session (minutes on a big save).  An empty save (cold start) gets
#                 SHIP_COLD_SESSIONS (10) sessions first.  (scripts/ship.sh)
# make night-ship THE OVERNIGHT COMMAND: ONE wall-clock budget of NIGHT_SHIP_HOURS (9, decimals allowed) from the start of make for the
#                 WHOLE job: the history replay, sessions of NIGHT_SHIP_TICKS (300) ticks, then the reports and checkin.txt.  New sessions
#                 stop at the budget minus a reserve (0.060: the measured REPORTS phase of the last run of that kind x
#                 NIGHT_SHIP_RESERVE_FACTOR 1.5 + NIGHT_SHIP_RESERVE_MARGIN 60 s + the end check, at least 60 s, at most a quarter of the
#                 budget, kept in ship_stamp.txt; NIGHT_SHIP_RESERVE=<s> by hand); the planned stop and the reserve are printed first and
#                 stand in checkin.txt.  Without a valid checkpoint the run prints a replay estimate and, if it cannot hold, "the budget
#                 cannot hold: replay first (~N min), then sessions; checkin.txt late by ~M min", then goes on.  The end check and verify follow SHIP_VERIFY / SHIP_VERIFY_TICKS like make ship
#                 (no full replay of a big save: make verify by hand).  A closed terminal (SIGHUP) ends the night; the reports still run and
#                 checkin.txt is still written (the console also goes to ship_log.txt).  NIGHT_SHIP_DETACH=1: run detached, no live screen.
#                 Stop reason max_hours (or max_sessions) = PASS; q still works (FAIL: stopped by hand, the reports still run).
#                 Reports (both ships) cover the sessions since the last ship stamp; SHIP_FULL=1: the whole save.
# make slice      THE DAYTIME SLICE (build 0.058): make night-ship with a budget of SLICE_MINUTES (20) MINUTES for the whole job (any
#                 value: make slice SLICE_MINUTES=10); the same reserve, reports, checkin.txt with VERDICT and vocabulary line, exit status.
#                 It says first whether the save has a state checkpoint (state.ckpt); the start loads it (seconds) instead of replaying
#                 the history (minutes on a big save); the verdict line "checkpoint:" says loaded or full replay (and why), the startup
#                 time and what the end wrote.  The end check / verify replay only saves of at most SLICE_VERIFY_TICKS (30000) ticks.
# state.ckpt      (0.058) every run that wrote sessions and every clean stop (q, SIGHUP/SIGTERM, time limit) writes the checkpoint;
#                 (0.059) it belongs to a STATE FORMAT (diary-sim-ckpt 2; a 0.058 format 1 checkpoint loads too), not to the build: a new
#                 zip loads it; a start replays only if the state layout changed (tagged sections), the file is broken or a record file
#                 does not fit, and says why.  data/ changes are information only ("data changed since the checkpoint ...").
#                 --replay and make verify-full always replay from scratch; make verify from state.verified.ckpt (0.060); a passed
#                 verify writes a fresh checkpoint.
#                 ckpt.enabled = 0 in data/limits.txt switches it off.  docs/CHECKPOINT.md.
# make ckpt-layout  the layout guard: the State_IO code against "ckpt_layout: <format> <hash>" in docs/CHECKPOINT.md (part of make check;
#                 FAIL = bump Ckpt_Format)
# make            build bin/diary_sim      make GNATMAKE=gnatmake-12  (GNAT 12)
# make portable   0-warning build with GNAT 14 and 12 in a copy without .git
# make run        build, then AUTO-LOAD and continue (no menu): prints "Save folder: <path>" and
#                 "Found N sessions, T ticks - continuing" (or "No save found - creating it") first,
#                 then imports and replay-verifies the save in ../diary-data (--home / $DIARY_HOME), never --fresh.
#                 make run TICKS=400 EVERY=100 SEED=42   (TICKS = NEW ticks on top of the
#                 lowest common tick on disk; without TICKS the four entities VOTE on the
#                 session length (data/kalpas.txt, median); SEED only matters when there
#                 are no diaries yet, default 42; without diaries a terminal is asked first, YES=1 answers
#                 yes, see README)
#                 The console shows a SHORT form (entity table, petitions, session lines, the players' boxes; it ends there, no
#                 marker and no path); run_report.txt in the save folder always has everything and run_log.txt gets one time
#                 stamped entry per run (the @@TRACE and @@SECTIONS lines and the path of the report).  VERBOSE=1 (or --verbose, or
#                 DIARY_VERBOSE=1 in the environment) prints it all as before.
# make report     print the last run_report.txt of the save folder (the full report, with `== name ==` headers and the @@TRACE marker)
# make runlog     show the last 40 lines of run_log.txt (one entry per run and per DRIFT stop, newest last)
# make chat       one paced session (SESSION_TICKS=600 ticks, chat.tps ticks a second) with an input line: `@name text` talks to a wesen, a player
#                 or the observer, `/help` lists the orders; every line is recorded in diaries/chat.txt (replay-verified); q or /quit stops
# make chatlog    print the last lines of diaries/chat.txt (chat.log_tail), read-only
# make wordstat   the vocabulary report (read-only): what each wesen knows by kind (start, world, taught, screen, coined, chess move
#                 coordinates, chess move numbers), how many words were used again, agreed in the dictionary, their lengths, prefix and
#                 suffix variants, and one conclusion line with the biggest source; wording in data/wordstat.txt; make share includes it
# make evolve    the evolution preview (read-only, docs/EVOLVE.md): word fitness (top words, the words that would go dormant), the weight table each chess
#                 competitor would hold after learning from the recorded games, the Elo curve; numbers in data/limits.txt evolve.*, wording in data/evolve.txt
# make active    the active vocabulary: on an active=1/2 save the real state of diaries/active.txt (active, dormant, woken per wesen; both params lines, floor and cap; who is at the cap); on an older save the read-only preview under a cap of evolve.cap (500)
# make frustration  the MiniMax report (read-only): per wesen refused petitions and the lowest mood, the worst session and the
#                 smallest worst case; per player the petitions decided in one session (load); the grant rate is not changed
# make voices     print the four wesen messages (what the night header shows, one line each, at most voice.max_chars) for the last tick of the
#                 save; deterministic, read-only, replay-verified; data/voices.txt holds the templates
# make night      sessions back to back, for the night: SESSION_TICKS=300 (ticks per session), MAX_SESSIONS=n, MAX_HOURS=n (default 12;
#                 0 = no limit).  ONE process: the history is replayed once, then the sessions follow (a session ~0.2-0.5 s instead of a
#                 full replay each); the files are byte for byte what the same sessions started by hand (--more N) would write.  q (no
#                 Enter needed) works at every stage: during the first replay it stops at once, later the session in progress finishes,
#                 everything is written, the box is shown, exit 0.  Ctrl-C, SIGTERM and SIGHUP (terminal closed) stop at the next tick;
#                 a rerun resumes.  On a terminal a header repainted about once a second (clock, elapsed, save folder size and growth,
#                 session and tick, seconds per session, time left; mood, energy, words, petitions of the wesen and watches, mood,
#                 grant/refuse, stance of the players), else one status line and one timer line per session; a box at the end;
#                 trend.txt and run_log.txt get a line per session.  At the end (limits) a child process replays the WHOLE history from the
#                 files (make verify); night.verify_every in data/limits.txt = also every N sessions.  Do not use say/grant/veto during a
#                 night run: quit first.
# make verify     (0.060) INCREMENTAL: loads the last verified checkpoint (state.verified.ckpt, written by every passed verify), replays
#                 only the newer ticks from the files and compares them with everything stored; one OK line (exit 1: DRIFT); without a
#                 verified checkpoint the whole history.  When it passes: a VERIFY entry in run_log.txt, verify_stamp.txt (checkin.txt:
#                 "last verify: <date> (ticks A-B)"), a fresh state.ckpt and state.verified.ckpt.  Weekly.
# make verify-full  the same from tick 1 (minutes on a big save; checkin.txt: "last full verify: <date> (N ticks)").  DUE (checkin.txt)
#                 after 30 days, and when the simulation fingerprint (scripts/sim_print.sh: the simulation sources and data rules, not
#                 the reports or scripts) or the state format differs from the one of the last full verify: an incremental verify
#                 cannot see a code change that alters how OLD sessions replay.  docs/CHECKPOINT.md.
# make sim-print  prints that fingerprint
# make bench      seconds per session: 20 sessions of 300 ticks after a 6000-tick save, the old way (one program start per session)
#                 against the night run (BENCH_SESSIONS, BENCH_TICKS, BENCH_BASE); diaries of both must be identical
# make trend      the last 40 lines of trend.txt (one line per session: mood, energy, words, petitions, votes, trials, anomalies)
# make share      ONE zip (tar.gz without zip) with trend.txt, run_log.txt, run_report*.txt, summary.txt, player_reports.txt, dictionary.txt and
#                 divergence.txt; no diaries and no ballots; next to the save folder (SHARE_DIR=... to choose); prints path and size
# make play       the same as make run
# make menu       build, then the main menu (needs a terminal): Conway intro, DIARY title, New Game /
#                 Load Game / Inbox / Settings / Quit.  The bare program on a terminal does the same.
# make demo       PREVIEW ONLY: build, then 200 ticks of a new world in memory, a screen of
#                 excerpts, nothing written to disk (make run is what writes ./diaries)
# make say       Robert speaks, between sessions (recorded in ../diary-data/diaries/says.txt, applied
#                 from the next run): make say PLAYER=Jehova TEXT="..." (a player may pass it on),
#                 make say WESEN=ada TEXT="..." (direct), make say TEXT="..." (all four);
#                 optional AS=name.  make answer TEXT="..." answers the latest collective petition.
# make inbox      print the inbox: the reports of the players to Robert (newest 40 lines)
# make grant     Robert grants a petition: make grant PETITION=P12 [AS=name] (one G line in diaries/grants.txt at the lowest
#                 common tick; the next run applies it: more_rest / faster_work_recovery raise the recovery rate of those who
#                 asked, most for the one who asked most; the topic is not filed again; replay-verified, tamper = DRIFT)
# make map        print the treadmill view: for each wesen its position, nearest landmark, biome and a
#                 5x5 window of its surroundings, as of the end of the last saved session (read-only)
# make ledger    print the mood ledger (report only): per wesen the top 3 drains and gains of mood, whole run and last
#                 session, one sentence each (FULL=1: also by action, place, verb, event, rest model); replays and
#                 verifies the save, writes nothing
# make elo       print the Elo ranking of the four wesen and the players (chess=1 sessions; display names; replays and
#                 verifies the save, writes nothing).  make perft: the move generator checks (data/chess.txt), no save needed
# make trials    print the trials (trial=1 sessions: disputes settled with chess games, T lines of diaries/trials.txt; display names;
#                 replays and verifies the save, writes nothing)
# make divergence  the players' reports against the raw records (records=1 sessions): claim, truth, grants and refusals counted from
#                 diaries/votes.txt, yes/no on new words, and the growth of the dictionary per session; read-only, replay-verified
# make ballots     the secret ballots on alternative word forms (diaries/ballots.txt), for Robert only, read-only
# make dictionary  the official word list (diaries/dictionary.txt: words the wesen proposed and the players voted), read-only
# make screens   print the text screens of the wesen as of the end of the replay (screen=1 sessions: words known, things examined,
#                 words seen on others' screens; pinned *, unknown ?) and the notes lying on things; read-only, replay-verified
# make robot     print the robot (robot=1 sessions): position, battery, its 5x5 camera view, who steers it, the last commands;
#                 replays and verifies the save, writes nothing
# make govern    print the governance (govern=1 sessions): per player the counter line (petitions seen, granted, partial, deferred,
#                 refused), trust and standing per wesen, the governed rule levers, the last decisions; replays and verifies, writes nothing
# make veto DECISION=D12 [AS=name]     Robert reverts a granted / partial decision of a player (one V line in diaries/vetoes.txt at the lowest
#                 common tick; the next run writes the D line, lowers the player's standing and trust).  make approve DECISION=D12: raises both.
#                 make grant (a petition granted by Robert himself) stays as it is
# make audit     the player reports checked (preport=1 sessions): per player what it CLAIMED to Robert against what was TRUE, the number of
#                 misreports, the biggest one and the latest claims per wesen; replays and verifies, writes nothing.  The text boxes of the
#                 players come last at the end of every run (also in player_reports.txt of the save folder).
# make next      the advice for the next run (nextticks=1 sessions): what each wesen asked for, what each player settled on, the median
#                 (replays and verifies the save, writes nothing).  With nextticks.use = 1 in data/limits.txt `make run` without TICKS runs the
#                 advised number of ticks (the last N record of diaries/nextticks.txt); TICKS=n always wins; use = 0 (default): the wesen vote
# make challenge PLAYER=<name> [AS=name]   Robert caught a player lying (see make audit): one Q line in diaries/challenges.txt at the lowest
#                 common tick; the next run lowers that player's standing with its wesen a little (data/limits.txt preport.challenge_cost)
# make visit WHO=<name|id|1-4> [TICKS=n] [SEED=n] [YES=1] [SCRIPT=file]   Robert stands next to ONE wesen for a session of n ticks (default
#                 visit.ticks of data/visit.txt, 60; the session carries visit=1): each tick shows what it sees (5x5 view, its screen, mood,
#                 energy, what it does, who and what is near); between ticks type  say <text>  teach <word>  show  wait [n]  leave.  The wesen
#                 understands only the words it knows and answers only with them; every input is a line of diaries/visit.txt (replay-
#                 verified, tamper = DRIFT).  SCRIPT=file (--visit-script) reads the commands from a file; stdin pipes work.  See README.
# DEBUG=1         make run DEBUG=1 / make demo DEBUG=1 (--debug): also write debug_digest.txt (<= debug.digest_bytes,
#                 data/limits.txt; line 1 = status, anomalies, then only what changed since the last digest)
#                 to attach to chat: in the save folder for run, in the current folder for demo (the only
#                 file a demo ever writes); the full record is debug_full.txt (run).
#                 make run SECTION=drift|trace|players|inbox|run|status prints one block of it (nothing runs)
# make small      (always a full rebuild) the SMALL binary bin/diary_sim_small: no -g, -Os (SMALL=-O1: ~20 % faster, ~20 % larger), -ffunction-sections
#                 -fdata-sections, -no-pie, --gc-sections, stripped (-s); own object folder obj_small.  Same program, same output (the dev build bin/diary_sim stays
#                 as it is); the only difference: no symbols, so a crash report shows addresses instead of names.  make footprint: the
#                 sizes (source, data, per unit, stripped / unstripped, debug share) of the files that exist
# make check      version headers + the resume/replay/drift/crash checks
# make checkin    the older paste (humans: use make ship / make night-ship): a night run of CHECKIN_SESSIONS (40) sessions of CHECKIN_TICKS (300) ticks (no q needed; it says
#                 when the history replay is done and the new sessions begin), then active, wordstat, frustration, evolve, verify,
#                 each after "=== make <x> ===" with its own wall-time line; the last line is the wall time of the whole checkin.
GNATMAKE ?= gnatmake
# The default is -O2: the program replays the whole history on every start, and -O2 runs that about 2.2 times faster than -O0 (same
# output, byte for byte).  A clean build takes ~50 s with -j0; for quick edit-and-test builds use make all OPT=-O0 (~12 s).
# make portable builds with both compilers at -O0, at -O1 and at -O2 and fails on any warning; OPT="-O1 -fno-inline" is the
# strict (optimizer-level warnings) one, e.g. make all OPT="-O1 -fno-inline".
OPT ?= -O2
JOBS ?= -j0
FLAGS = -g $(OPT) -gnatwa -gnat2022 -gnata $(JOBS)

.PHONY: ckpt-layout ship night-ship slice checkin chat chatlog voices wordstat evolve active frustration all version-check portable run play menu demo check clean say answer inbox map ledger grant screens elo perft robot govern veto approve audit challenge next visit trials divergence dictionary ballots report runlog trend night verify verify-full sim-print bench share small footprint
export WESEN PLAYER TEXT AS

# Every user-facing target prints its wall time as the LAST line (scripts/timed.sh), e.g. "make wordstat wall time: 0m12s (12s)":
# the whole make command from its start, the up-to-date check (or rebuild) of `all` included; the exit status of the program is kept.
# The command line is still echoed first (not with make -s).
T0 := $(shell date +%s)
TIMED = @scripts/timed.sh "$(if $(filter 1,$(words $(MAKECMDGOALS))),$(MAKECMDGOALS),$@)" $(T0) $(if $(findstring s,$(firstword -$(MAKEFLAGS))),1,0)
# One step of make checkin: its own wall time (from the start of that step), labelled like the single target.
STEP = @scripts/timed.sh
QUIET = $(if $(findstring s,$(firstword -$(MAKEFLAGS))),1,0)
# make checkin: one paste with everything.  A night run with a FIXED number of sessions (no q needed), then make active, wordstat,
# frustration, evolve and verify, each after a "=== make <x> ===" line and with its own wall-time line; the total comes last.
#   make checkin CHECKIN_SESSIONS=10 CHECKIN_TICKS=300 SEED=42
CHECKIN_SESSIONS ?= 40
CHECKIN_TICKS ?= 300
# make ship: reports only (0 sessions); verify up to this many ticks (auto), or always (1) or never (0); a cold start's sessions
SHIP_SESSIONS ?= 0
SHIP_VERIFY ?= auto
SHIP_VERIFY_TICKS ?= 150000
SHIP_COLD_SESSIONS ?= 10
# make night-ship: the overnight form of make ship (0 sessions = no session limit; the hours end it)
NIGHT_SHIP_SESSIONS ?= 0
NIGHT_SHIP_TICKS ?= 300
NIGHT_SHIP_HOURS ?= 9
# make slice: the daytime form of make night-ship, the budget in minutes (any value: make slice SLICE_MINUTES=10)
SLICE_MINUTES ?= 20
SLICE_VERIFY_TICKS ?= 30000
export SHIP_FULL NIGHT_SHIP_RESERVE NIGHT_SHIP_RESERVE_FACTOR NIGHT_SHIP_RESERVE_MARGIN NIGHT_SHIP_DETACH SHIP_VOCAB_GOAL

EVERY ?= 100

SMALL ?= -Os
SMALL_LINK ?= -no-pie -Wl,--gc-sections -s
SMALL_FLAGS = $(SMALL) -ffunction-sections -fdata-sections -gnatwa -gnat2022 -gnata $(JOBS)

all:
	mkdir -p obj bin
	@[ "$$(cat obj/.opt 2>/dev/null)" = "$(OPT)" ] || { rm -rf obj; mkdir -p obj; echo "$(OPT)" > obj/.opt; }   # another OPT: build everything again (the build tool does not notice)
	$(GNATMAKE) $(FLAGS) -D obj diary_sim.adb -o bin/diary_sim -bargs -E
	@rm -f b~*

version-check:
	@bad=0; for f in Makefile diary_sim.adb sim_util.ads sim_util.adb sim_world.ads sim_world.adb sim_quit.ads sim_quit.adb sim_menu.ads sim_menu.adb sim_dharma.ads sim_dharma.adb sim_things.ads sim_things.adb sim_ledger.ads sim_ledger.adb sim_store.ads sim_store.adb sim_screen.ads sim_screen.adb sim_chess.ads sim_chess.adb sim_games.ads sim_games.adb sim_robot.ads sim_robot.adb sim_govern.ads sim_govern.adb sim_preport.ads sim_preport.adb sim_next.ads sim_next.adb sim_visit.ads sim_visit.adb sim_chat.ads sim_chat.adb sim_voice.ads sim_voice.adb sim_wordstat.ads sim_wordstat.adb sim_evolve.ads sim_evolve.adb sim_active.ads sim_active.adb sim_trial.ads sim_trial.adb sim_records.ads sim_records.adb sim_ckpt.ads sim_ckpt.adb; do \
	  head -1 $$f | grep -Eq 'Version: [0-9]+\.[0-9]{3}' || { echo "no version header: $$f"; bad=1; }; done; \
	  v=$$(head -1 diary_sim.adb | grep -Eo '[0-9]+\.[0-9]{3}'); \
	  grep -q "Build : constant String := \"$$v\"" diary_sim.adb || { echo "Build constant differs from diary_sim.adb header $$v"; bad=1; }; \
	  [ $$bad = 0 ] && echo "version-check: PASS"

portable:
	$(TIMED) scripts/portable_check.sh

run: all
	$(TIMED) bin/diary_sim $(if $(SECTION),--debug-section $(SECTION),$(if $(TICKS),--more $(TICKS),$$(bin/diary_sim --next-ticks 2>/dev/null | tail -n 1 | grep -E '^[0-9]+$$' | sed 's/^/--more /')) --every $(EVERY) $(if $(SEED),--seed $(SEED),) $(if $(YES),--yes,) $(if $(DEBUG),--debug,) $(if $(VERBOSE),--verbose,))

play: run

menu: all
	$(TIMED) bin/diary_sim --menu

demo: all
	$(TIMED) bin/diary_sim --preview --ticks 200 $(if $(SECTION),--debug-section $(SECTION),$(if $(DEBUG),--debug,))

say: all
	$(TIMED) bin/diary_sim --say "$${PLAYER:-$${WESEN:-all}}" --text "$$TEXT" $(if $(AS),--as "$$AS",)

answer: all
	$(TIMED) bin/diary_sim --answer --text "$$TEXT" $(if $(AS),--as "$$AS",)

inbox: all
	$(TIMED) bin/diary_sim --inbox

map: all
	$(TIMED) bin/diary_sim --map

grant: all
	$(TIMED) bin/diary_sim --grant $(PETITION) $(if $(AS),--as $(AS))

elo: all
	$(TIMED) bin/diary_sim --elo

trials: all
	$(TIMED) bin/diary_sim --trials

divergence: all
	$(TIMED) bin/diary_sim --divergence

dictionary: all
	$(TIMED) bin/diary_sim --dictionary

ballots: all
	$(TIMED) bin/diary_sim --ballots

report: all
	$(TIMED) bin/diary_sim --report

runlog: all
	$(TIMED) bin/diary_sim --runlog

trend: all
	$(TIMED) bin/diary_sim --trend

night: all
	$(TIMED) bin/diary_sim --continuous $(if $(SESSION_TICKS),--session-ticks $(SESSION_TICKS),) $(if $(MAX_SESSIONS),--max-sessions $(MAX_SESSIONS),) $(if $(MAX_HOURS),--max-hours $(MAX_HOURS),) $(if $(SEED),--seed $(SEED),)

verify: all
	$(TIMED) bin/diary_sim --verify --sim-print $$(scripts/sim_print.sh)

verify-full: all
	$(TIMED) bin/diary_sim --verify-full --sim-print $$(scripts/sim_print.sh)

sim-print:
	@scripts/sim_print.sh $(if $(LIST),--list,)

bench: all
	$(TIMED) scripts/bench.sh bin/diary_sim

share: all
	$(TIMED) scripts/share.sh bin/diary_sim

perft: all
	$(TIMED) bin/diary_sim --perft

screens: all
	$(TIMED) bin/diary_sim --screens

robot: all
	$(TIMED) bin/diary_sim --robot

govern: all
	$(TIMED) bin/diary_sim --govern

voices: all
	$(TIMED) bin/diary_sim --voices

chat: all
	$(TIMED) bin/diary_sim --chat $(if $(SESSION_TICKS),--session-ticks $(SESSION_TICKS),) $(if $(SEED),--seed $(SEED),)

chatlog: all
	$(TIMED) bin/diary_sim --chatlog

wordstat: all
	$(TIMED) bin/diary_sim --wordstat

evolve: all
	$(TIMED) bin/diary_sim --evolve

active: all
	$(TIMED) bin/diary_sim --active

frustration: all
	$(TIMED) bin/diary_sim --frustration

veto: all
	$(TIMED) bin/diary_sim --veto $(DECISION) $(if $(AS),--as $(AS))

approve: all
	$(TIMED) bin/diary_sim --approve $(DECISION) $(if $(AS),--as $(AS))

audit: all
	$(TIMED) bin/diary_sim --audit

next: all
	$(TIMED) bin/diary_sim --next

visit: all
	$(TIMED) bin/diary_sim --visit "$(WHO)" $(if $(TICKS),--more $(TICKS),) $(if $(SEED),--seed $(SEED),) $(if $(YES),--yes,) $(if $(SCRIPT),--visit-script "$(SCRIPT)",) $(if $(EVERY),--every $(EVERY),)

challenge: all
	$(TIMED) bin/diary_sim --challenge "$(PLAYER)" $(if $(AS),--as $(AS))

ledger: all
	$(TIMED) bin/diary_sim --ledger$(if $(FULL),=full)

ship: all
	$(TIMED) scripts/ship.sh ship $(SHIP_SESSIONS) $(CHECKIN_TICKS) "" $(T0) "$(SEED)" $(SHIP_VERIFY) $(SHIP_VERIFY_TICKS) $(SHIP_COLD_SESSIONS)

night-ship: all
	$(TIMED) scripts/ship.sh night-ship $(NIGHT_SHIP_SESSIONS) $(NIGHT_SHIP_TICKS) $(NIGHT_SHIP_HOURS) $(T0) "$(SEED)" $(SHIP_VERIFY) $(SHIP_VERIFY_TICKS) 0

slice: all
	$(TIMED) scripts/ship.sh slice $(NIGHT_SHIP_SESSIONS) $(NIGHT_SHIP_TICKS) $(SLICE_MINUTES) $(T0) "$(SEED)" $(SHIP_VERIFY) $(SLICE_VERIFY_TICKS) 0

checkin: all
	@echo "=== make night (checkin: $(CHECKIN_SESSIONS) sessions of $(CHECKIN_TICKS) ticks) ==="
	$(STEP) "night" $$(date +%s) $(QUIET) bin/diary_sim --continuous --session-ticks $(CHECKIN_TICKS) --max-sessions $(CHECKIN_SESSIONS) $(if $(SEED),--seed $(SEED),)
	@echo "=== make active ==="
	$(STEP) "active" $$(date +%s) $(QUIET) bin/diary_sim --active
	@echo "=== make wordstat ==="
	$(STEP) "wordstat" $$(date +%s) $(QUIET) bin/diary_sim --wordstat
	@echo "=== make frustration ==="
	$(STEP) "frustration" $$(date +%s) $(QUIET) bin/diary_sim --frustration
	@echo "=== make evolve ==="
	$(STEP) "evolve" $$(date +%s) $(QUIET) bin/diary_sim --evolve
	@echo "=== make verify ==="
	$(STEP) "verify" $$(date +%s) $(QUIET) bin/diary_sim --verify --sim-print $$(scripts/sim_print.sh)
	@echo "=== checkin done ==="
	@scripts/timed.sh "checkin" $(T0) 1 true

ckpt-layout:
	@scripts/ckpt_layout.sh --check

check: version-check all
	$(TIMED) scripts/checks.sh

small:
	mkdir -p obj_small bin
	$(GNATMAKE) -f $(SMALL_FLAGS) -D obj_small diary_sim.adb -o bin/diary_sim_small -bargs -E -largs $(SMALL_LINK)
	@rm -f b~*
	@ls -l bin/diary_sim_small | awk '{ printf "bin/diary_sim_small: %d bytes (%d KB)\n", $$5, $$5 / 1024 }'

footprint:
	$(TIMED) scripts/footprint.sh

clean:
	rm -rf obj obj_small bin diaries diaries_old_* entities summary.txt summary.jsonl run_report.txt run_report_prev.txt run_log.txt trend.txt night_console.txt ship_log.txt ship_console.txt night_verify.txt voice_log.txt debug.txt debug.tmp debug_digest.txt debug_digest.prev debug_full.txt last_error.txt
