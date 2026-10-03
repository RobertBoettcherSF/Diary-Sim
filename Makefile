# Version: 0.025
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
# make play       the same as make run
# make menu       build, then the main menu (needs a terminal): Conway intro, DIARY title, New Game /
#                 Load Game / Inbox / Settings / Quit.  The bare program on a terminal does the same.
# make demo       PREVIEW ONLY: build, then 200 ticks of a new world in memory, a screen of
#                 excerpts, nothing written to disk (make run is what writes ./diaries)
# make say       Robert speaks, between sessions (recorded in ../diary-data/diaries/says.txt, applied
#                 from the next run): make say PLAYER="Player 1" TEXT="..." (a player may pass it on),
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
# make check      version headers + the resume/replay/drift/crash checks
GNATMAKE ?= gnatmake
# Build speed: units compile in parallel (-j0 = all cores) and at -O0 (a clean build took ~60 s serial at -O1; ~12 s now; the run
# itself is ~35 % slower, 300 ticks on 1800 replayed ticks take ~2 s).  make portable builds BOTH ways with both compilers and
# fails on any warning: OPT="-O1 -fno-inline" is the strict (optimizer-level warnings) one, e.g. make all OPT="-O1 -fno-inline".
OPT ?= -O0
JOBS ?= -j0
FLAGS = -g $(OPT) -gnatwa -gnat2022 -gnata $(JOBS)

.PHONY: all version-check portable run play menu demo check clean say answer inbox map ledger grant screens elo perft robot govern veto approve audit challenge next visit
export WESEN PLAYER TEXT AS

EVERY ?= 100

all:
	mkdir -p obj bin
	$(GNATMAKE) $(FLAGS) -D obj diary_sim.adb -o bin/diary_sim -bargs -E
	@rm -f b~*

version-check:
	@bad=0; for f in Makefile diary_sim.adb sim_util.ads sim_util.adb sim_world.ads sim_world.adb sim_quit.ads sim_quit.adb sim_menu.ads sim_menu.adb sim_dharma.ads sim_dharma.adb sim_things.ads sim_things.adb sim_ledger.ads sim_ledger.adb sim_store.ads sim_store.adb sim_screen.ads sim_screen.adb sim_chess.ads sim_chess.adb sim_games.ads sim_games.adb sim_robot.ads sim_robot.adb sim_govern.ads sim_govern.adb sim_preport.ads sim_preport.adb sim_next.ads sim_next.adb sim_visit.ads sim_visit.adb; do \
	  head -1 $$f | grep -Eq 'Version: [0-9]+\.[0-9]{3}' || { echo "no version header: $$f"; bad=1; }; done; \
	  v=$$(head -1 diary_sim.adb | grep -Eo '[0-9]+\.[0-9]{3}'); \
	  grep -q "Build : constant String := \"$$v\"" diary_sim.adb || { echo "Build constant differs from diary_sim.adb header $$v"; bad=1; }; \
	  [ $$bad = 0 ] && echo "version-check: PASS"

portable:
	scripts/portable_check.sh

run: all
	bin/diary_sim $(if $(SECTION),--debug-section $(SECTION),$(if $(TICKS),--more $(TICKS),$$(bin/diary_sim --next-ticks 2>/dev/null | tail -n 1 | grep -E '^[0-9]+$$' | sed 's/^/--more /')) --every $(EVERY) $(if $(SEED),--seed $(SEED),) $(if $(YES),--yes,) $(if $(DEBUG),--debug,))

play: run

menu: all
	bin/diary_sim --menu

demo: all
	bin/diary_sim --preview --ticks 200 $(if $(SECTION),--debug-section $(SECTION),$(if $(DEBUG),--debug,))

say: all
	bin/diary_sim --say "$${PLAYER:-$${WESEN:-all}}" --text "$$TEXT" $(if $(AS),--as "$$AS",)

answer: all
	bin/diary_sim --answer --text "$$TEXT" $(if $(AS),--as "$$AS",)

inbox: all
	bin/diary_sim --inbox

map: all
	bin/diary_sim --map

grant: all
	bin/diary_sim --grant $(PETITION) $(if $(AS),--as $(AS))

elo: all
	bin/diary_sim --elo

perft: all
	bin/diary_sim --perft

screens: all
	bin/diary_sim --screens

robot: all
	bin/diary_sim --robot

govern: all
	bin/diary_sim --govern

veto: all
	bin/diary_sim --veto $(DECISION) $(if $(AS),--as $(AS))

approve: all
	bin/diary_sim --approve $(DECISION) $(if $(AS),--as $(AS))

audit: all
	bin/diary_sim --audit

next: all
	bin/diary_sim --next

visit: all
	bin/diary_sim --visit "$(WHO)" $(if $(TICKS),--more $(TICKS),) $(if $(SEED),--seed $(SEED),) $(if $(YES),--yes,) $(if $(SCRIPT),--visit-script "$(SCRIPT)",) $(if $(EVERY),--every $(EVERY),)

challenge: all
	bin/diary_sim --challenge "$(PLAYER)" $(if $(AS),--as $(AS))

ledger: all
	bin/diary_sim --ledger$(if $(FULL),=full)

check: version-check all
	scripts/checks.sh

clean:
	rm -rf obj bin diaries diaries_old_* entities summary.txt summary.jsonl run_report.txt debug.txt debug.tmp debug_digest.txt debug_digest.prev debug_full.txt last_error.txt
