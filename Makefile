# Version: 0.001
# make            build bin/diary_sim      make GNATMAKE=gnatmake-12  (GNAT 12)
# make portable   0-warning build with GNAT 14 and 12 in a copy without .git
# make check      version headers + the resume/replay/drift/crash checks
GNATMAKE ?= gnatmake
FLAGS = -g -O1 -gnatwa -gnat2022 -gnata

.PHONY: all version-check portable check clean
all:
	mkdir -p obj bin
	$(GNATMAKE) $(FLAGS) -D obj diary_sim.adb -o bin/diary_sim -bargs -E
	@rm -f b~*

version-check:
	@bad=0; for f in Makefile diary_sim.adb sim_util.ads sim_util.adb; do \
	  head -1 $$f | grep -Eq 'Version: [0-9]+\.[0-9]{3}' || { echo "no version header: $$f"; bad=1; }; done; \
	  [ $$bad = 0 ] && echo "version-check: PASS"

portable:
	scripts/portable_check.sh

check: version-check all
	scripts/checks.sh

clean:
	rm -rf obj bin diaries diaries_old_* last_error.txt
