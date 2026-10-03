# Version: 0.014
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
#                 from the next run): make say PLAYER=iris TEXT="..." (a player may pass it on),
#                 make say WESEN=ada TEXT="..." (direct), make say TEXT="..." (all four);
#                 optional AS=name.  make answer TEXT="..." answers the latest collective petition.
# make inbox      print the inbox: the reports of the players to Robert (newest 40 lines)
# make map        print the treadmill view: for each wesen its position, nearest landmark, biome and a
#                 5x5 window of its surroundings, as of the end of the last saved session (read-only)
# make ledger    print the mood ledger (report only): per wesen the top 3 drains and gains of mood, whole run and last
#                 session, one sentence each (FULL=1: also by action, place, verb, event, rest model); replays and
#                 verifies the save, writes nothing
# DEBUG=1         make run DEBUG=1 / make demo DEBUG=1 (--debug): also write debug_digest.txt (<= debug.digest_bytes,
#                 data/limits.txt; line 1 = status, anomalies, then only what changed since the last digest)
#                 to attach to chat: in the save folder for run, in the current folder for demo (the only
#                 file a demo ever writes); the full record is debug_full.txt (run).
#                 make run SECTION=drift|trace|players|inbox|run|status prints one block of it (nothing runs)
# make check      version headers + the resume/replay/drift/crash checks
GNATMAKE ?= gnatmake
FLAGS = -g -O1 -fno-inline -gnatwa -gnat2022 -gnata

.PHONY: all version-check portable run play menu demo check clean say answer inbox map ledger
export WESEN PLAYER TEXT AS

EVERY ?= 100

all:
	mkdir -p obj bin
	$(GNATMAKE) $(FLAGS) -D obj diary_sim.adb -o bin/diary_sim -bargs -E
	@rm -f b~*

version-check:
	@bad=0; for f in Makefile diary_sim.adb sim_util.ads sim_util.adb sim_world.ads sim_world.adb sim_quit.ads sim_quit.adb sim_menu.ads sim_menu.adb sim_dharma.ads sim_dharma.adb sim_things.ads sim_things.adb sim_ledger.ads sim_ledger.adb; do \
	  head -1 $$f | grep -Eq 'Version: [0-9]+\.[0-9]{3}' || { echo "no version header: $$f"; bad=1; }; done; \
	  v=$$(head -1 diary_sim.adb | grep -Eo '[0-9]+\.[0-9]{3}'); \
	  grep -q "Build : constant String := \"$$v\"" diary_sim.adb || { echo "Build constant differs from diary_sim.adb header $$v"; bad=1; }; \
	  [ $$bad = 0 ] && echo "version-check: PASS"

portable:
	scripts/portable_check.sh

run: all
	bin/diary_sim $(if $(SECTION),--debug-section $(SECTION),$(if $(TICKS),--more $(TICKS),) --every $(EVERY) $(if $(SEED),--seed $(SEED),) $(if $(YES),--yes,) $(if $(DEBUG),--debug,))

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

ledger: all
	bin/diary_sim --ledger$(if $(FULL),=full)

check: version-check all
	scripts/checks.sh

clean:
	rm -rf obj bin diaries diaries_old_* entities summary.txt summary.jsonl run_report.txt debug.txt debug.tmp debug_digest.txt debug_digest.prev debug_full.txt last_error.txt
