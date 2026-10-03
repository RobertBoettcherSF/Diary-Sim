# Version: 0.004
# make            build bin/diary_sim      make GNATMAKE=gnatmake-12  (GNAT 12)
# make portable   0-warning build with GNAT 14 and 12 in a copy without .git
# make demo       build + 200-tick run in demo_run/ (seed and final summary printed)
# make check      version headers + the resume/replay/drift/crash checks
GNATMAKE ?= gnatmake
FLAGS = -g -O1 -fno-inline -gnatwa -gnat2022 -gnata

.PHONY: all version-check portable demo check clean
all:
	mkdir -p obj bin
	$(GNATMAKE) $(FLAGS) -D obj diary_sim.adb -o bin/diary_sim -bargs -E
	@rm -f b~*

version-check:
	@bad=0; for f in Makefile diary_sim.adb sim_util.ads sim_util.adb sim_world.ads sim_world.adb sim_quit.ads sim_quit.adb; do \
	  head -1 $$f | grep -Eq 'Version: [0-9]+\.[0-9]{3}' || { echo "no version header: $$f"; bad=1; }; done; \
	  v=$$(head -1 diary_sim.adb | grep -Eo '[0-9]+\.[0-9]{3}'); \
	  grep -q "Build : constant String := \"$$v\"" diary_sim.adb || { echo "Build constant differs from diary_sim.adb header $$v"; bad=1; }; \
	  [ $$bad = 0 ] && echo "version-check: PASS"

portable:
	scripts/portable_check.sh

demo: all
	rm -rf demo_run && mkdir demo_run
	cd demo_run && ../bin/diary_sim --fresh --ticks 200 --every 50

check: version-check all
	scripts/checks.sh

clean:
	rm -rf obj bin diaries diaries_old_* entities demo_run summary.txt summary.jsonl run_report.txt debug.txt debug.tmp last_error.txt
