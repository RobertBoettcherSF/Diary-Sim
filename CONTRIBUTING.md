# Contributing

- Build with GNAT 12 or newer (`make`, or `alr build`). The code must compile with **zero warnings** under `-gnatwa`
  on GNAT 12 and 14 (`make portable` checks both); fix warnings in the code, do not suppress them.
- Run `make test` before every commit (seconds); run `make check` (the full scenario suite, ~16 min) before a release.
- Every source file starts with a `Version: 0.NNN` header line (`make version-check`); bump `Build` in `diary_sim.adb`
  for a new build and add an entry to `CHANGELOG.md`.
- Determinism is the core contract: the same seed and the same data give byte-identical diaries, and every start
  replay-verifies the save. A change to the simulation rules goes behind a switch in `data/limits.txt` so older
  saves still replay. A change to the checkpoint state layout needs `make ckpt-layout` (see `docs/CHECKPOINT.md`).
- Wording lives in `data/*.txt`, not in the code.
- Keep commits focused, and say in the message which build they belong to (`0.068: ...`).
