# Life in the station: roles, life support, leisure (design only, nothing built)

Status: **proposal for Robert**. No code for any of this exists yet; every number below is a *proposed default* that
lives in `data/` when built, and every decision is open until Robert answers section 8. Style as `docs/WORLD.md`: what it is,
what it is made of, what is recorded. (`docs/MVP.md` does not exist in this tree; this follows `docs/WORLD.md`.)

## Contents
1. Where we start (facts of the present build)
2. Roles and population (`roles=1`)
3. Life support: water, air, temperature, power, maybe food (`life=1`)
4. Leisure and spare time (`leisure=1`)
5. How the three interlock
6. Build order, markers, size and risk
7. Rules every step keeps
8. Open questions for Robert, with a recommended answer each

## 1. Where we start
* Four wesen (`ada gemini replika robert` = Adam, Eve, Abel, Ruth), `Entity_Id` is `range 1 .. 4`; every array is indexed by it. Their
  *role* is a fixed word (`Kind`: engineer, reviewer, vice_president, human) with no effect on what they do.
* Players (Jehova, Ganesha, Odin, Amaterasu) watch them, decide petitions (`govern=1`), report with a trait *honesty* (`preport=1`).
* The day-to-day: `Choose` rolls one of rest / work / explore / talk / wander / bench / propose; `rest=1` adds energy, cool-down and a
  recovery rate; `world=1` a grid with four landmarks (office, lab, cafe, home); `chess=1` is a rest activity; petitions have topics
  (`data/topics.txt`) and a short whitelist of rule levers; the mood ledger lists the drains and gains.
* Everything is replay-verified: record lines (`diaries/*.txt`) are recomputed by every replay; a difference is DRIFT; a new feature is
  a session marker (`chess=1`) and "marker off = byte-identical".
* Robert's save: tick 3400, session 10, v0.034. All three features would start with the **next new session**, no `--fresh`.

## 2. Roles and population (`roles=1`)

### 2.1 Roles are data (`data/roles.txt`)
A role = id, display word, what it does (a *shift duty* or none), how many are *needed* for N wesen, and a lean on the action table.
Proposed set (13; the first four exist today as words):

| role | duty (when on shift) | needed | lean |
|---|---|---|---|
| engineer, reviewer, vice_president, human | as now: no duty | - | none |
| water engineer | keeps Water at capacity (3.2) | 1 | work + |
| air technician | keeps Air | 1 | work + |
| power operator | keeps Power | 1 | work + |
| heating keeper | keeps Temperature | 1 | work + |
| cook | meals (Food, shared meals 4.2) | 1 per 6 | talk + |
| gardener | garden, park, a little Food and Air | 1 per 8 | wander + |
| masseur (spa and sauna host) | spa, massage, sauna | 1 per spa | talk + |
| caretaker | repairs anything small, cleans, books | 1 per 8 | work + |
| librarian / host | library, games room, bar | 1 per 10 | talk + |

A role changes only **weights** (`role.<id>.lean.<action> = +n`, same device as the rest model's `Work_Pct`), never the dice
themselves: the wesen still chooses by hash dice, so a water engineer works more but is not a robot. A role also gives the
duty a *quota*: `duty.ticks` of the day (3.2) it will do the maintenance job if it is not too tired.

### 2.2 Vacancy, then birth
* Each session boundary (the `E` of the end report, before the next session's tick 1) a **vacancy list** is computed from data:
  for every role, `needed(population) - filled`. Needs come from the services (3) and the leisure sites that exist (4), so the
  list is a pure function of the replayed state.
* **Birth rule** (`pop.birth_*`): at most `pop.births_per_session` (1) wesen are born per session boundary, only if
  (a) a vacancy exists, (b) beds `<` housing (`pop.beds`, data: 6 at the start, more when a *home* cell is added), (c) every
  service has headroom: `load <= capacity * pop.headroom_pct` (3.1), (d) `pop.cooldown` sessions since the last birth. Which
  vacancy first: the one marked most urgent by data order (water, air, power, heat, then comfort roles).
* **Who is born:** `Rule 30` row seeded by `hash(seed, slot, session)` picks a name from the pool (`data/namepool.txt`, ~40 short
  names, a name is used once), a role from the vacancy, the usual personality bits (the Rule 30 birth row, as for the first four),
  a start slice of words (as now), a home cell, and a **watcher** (the player with the fewest wesen). Born at tick 1 of the new
  session; the birth is a record line `B<n>` (`diaries/population.txt`, `Sim_Store`, own salts 10000 .. 10199): slot, id, name,
  role, session. Tamper, removed or invented line = DRIFT.
* **Ids stay replay-safe:** slots are numbered 1, 2, 3 ... and **never reused**; the id of slot >= 5 is the pool name in lower case
  (`odo`, `mira` ...: file names `diaries/<id>.jsonl`, `entities/<id>/` as today). `Entity_Id` becomes `range 1 .. Max_Slots`
  (a compile-time constant, 32, arrays of small integers); unborn and gone slots are *inert* (no step, no diary line, no hash
  roll). The first four keep their ids, files and every byte. The display name comes from `data/names.txt` (the pool maps id ->
  shown name, or the id capitalised if the file has no line).
* **Cost:** a replay is linear in wesen x ticks. 12 alive wesen is ~3x today's replay time (measure at step 2).

### 2.3 Leaving, retiring, dying
* **Leaves:** the existing karma layer already has *liberation* (a wesen that has let go). Proposed: a liberated wesen **retires
  at the next boundary** (`R<n>` record) instead of being reborn into the same slot; its role is vacant again. Otherwise rebirth as now.
* **Retires** after `pop.service_sessions` (e.g. 25) sessions of service: a slot-age rule, same record, gentle.
* **Dies:** only if `life.lethal = 1` (default 0) and a service has been `out` for `life.lethal_ticks` while the wesen's energy
  is 0: a record `R<n> ... cause=<water|air|heat>`. Not in the first steps (question 3).
* **After leaving:** diary file stays (history), entry stays in the roster as `gone` (the ledger, Elo list and trial lines keep
  their name), the chess Elo of a gone wesen is frozen, its open petitions are closed as `lapsed`, its watcher is freed, its
  beds/duty are freed. Ids and slot numbers are never given again.

## 3. Life support: water, air, temperature, power, (food) (`life=1`)

### 3.1 A service is a number with a capacity
Each service `S` (`data/life.txt`) has: `cap` (units per tick it can supply), `stock` 0 .. 100 (level), `wear` 0 .. 100, a list of
**maintenance jobs**, and a *draw* per wesen and per site. Every tick (replayed, a pure function of hash and state):

    load  = sum of draws of the wesen present + sites open (spa, kitchen ...)
    make  = cap * staffing_pct(S) / 100        (staffing: shifts actually worked this day by the role, 3.2)
    stock = clamp(stock + make - load - leak(wear), 0, 100)
    wear  = clamp(wear + wear_rate - repairs_done, 0, 100)

* **Water** (draw per wesen 1, spa 6, sauna 4, kitchen 3, garden 2), **Air** (1 per wesen, +1 crowded cell, garden helps), **Temperature**
  (a band: too cold / fine / too hot; heating keeper balances; sauna adds heat locally), **Power** (draws of everything; a cut halves
  other services' `make`). **Food** (optional, question 2): meals eaten from stock the cook fills; `eat` in the present world stays a
  taste-the-world verb and is not Food.
* Bands (data): ok `>= 60`, low `30 .. 59`, short `10 .. 29`, out `< 10`.

### 3.2 Maintenance jobs, done by wesen in roles
A job = `(service, kind, ticks, effect)`: *inspect* (reveals wear), *service* (wear -n), *repair* (clears a failure). Jobs appear on a
board (`diaries/life.txt` `J<n>` lines: opened, taken, done). A wesen on shift **takes a job with the hash roll
`hash(seed, wesen, tick, 10230)` against `skill`** (skill 0 .. 100, grows by +1 per finished job, 3.4); a vacant role means nobody takes
it and wear grows: *that is how a vacancy hurts*, and it feeds the vacancy list of 2.2. The day: `day.length = 24` ticks (pure data,
only used by roles/life/leisure so old output is untouched); a shift is `shift.ticks` of it.

### 3.3 Failure events
Per service per tick: failure chance `fail_pct = base + wear * k` (hash 10260). A failure is a record `F<n>` (`diaries/life.txt`):
service, kind (pump, fan, boiler, grid), severity 1 .. 3, duration if unrepaired. It opens a *repair* job; while open `make` is cut.
Clustered failures (power out -> heat and water pumps down) follow from 3.1, not from special code.

### 3.4 Effects on the wesen (no new stat)
| state | effect | how it is applied |
|---|---|---|
| Water low / short | energy recovery of rest x0.7 / x0.4; mood -1 / -3 per 10 ticks | rest model `Recovery_Rate` multiplier, mood drift |
| Air low / short | energy cap 90 / 60; work yields less; `Work_Pct` down | clamp in the energy step |
| Temperature off band | mood -1 .. -3, rest worse; sauna/blanket leisure fix it | band table |
| Power cut | screens and robot stop (the existing screen/robot features read the service), lights: world view range 1 | flags |
| Out for long | `life.lethal` (off by default) | 2.3 |

Everything shows up in the **mood ledger** as new sources ("water short", "too cold") so Robert sees why a mood fell. There is no
separate health value in the first versions (question 8).

### 3.5 Petitions, players, honesty
* New petition topics (`data/topics.txt`, state-weighted by the service band, `life=1` only): `too_cold`, `too_hot`, `no_water`,
  `stale_air`, `power_cuts`. A petition names a service; the **governance lever whitelist** (`data/govern.txt`) gets
  `maintenance` (priority of the service in the job board: a small step per decision, never past bounds), the same Grant / partial /
  defer / refuse dice and trust/standing as now.
* **Reports (`preport=1`):** each player's paragraph adds one clause about the services its wesen suffer from. **A player may play
  it down**: the existing honesty trait gives a misreport chance; a shortage `short` may be called `low` (one band), never
  invented out of nothing. `make audit` compares the claim with the service state record (`V<n>` per session end), as it does for mood.
* **Robert's view:** `make life` (read-only, replay-verified): per service stock/cap/load/wear, open failures, open jobs, who works
  what; one line in the end box when a service is `short` or `out`.

## 4. Leisure and spare time (`leisure=1`)

### 4.1 Spare time competes with work and rest
`leisure` is one new action in the table (weight from state: mood below ~60, energy above ~40, credits > 0, preference, free slot
at a site); it cuts `Work` weight like the cool-down does, and *restful* leisure counts as a rest for the cool-down. A wesen's
**spare-time budget** is `day.length - shift.ticks - rest need`; each leisure episode costs its `ticks` from it
(`leisure.budget_cap` per day stops a wesen living in the spa). Preference per activity comes from the Rule 30 birth row (a segment
of bits per activity group: calm / physical / social / making / mind), plus a small hashed taste per wesen and activity, so no two
agree. Effects scale with *skill* (0 .. 100, +1 per episode, diminishing) where it makes sense.

### 4.2 The list (proposed defaults; `data/leisure.txt`)
Price in **credits** (4.3), time in ticks, effects as mood / energy / recovery, needs = services and role.

| activity | place | price | ticks | effects | needs | social / skill | leans to |
|---|---|---:|---:|---|---|---|---|
| walk in the park | park (outdoor cell) | 0 | 4 | mood +2, energy +1 | Air ok | meets others | calm |
| gardening | garden | 0 | 6 | mood +3, a little Food/Air | Water, gardener nearby | skill | calm, making |
| library | library | 0 | 5 | mood +2, a word learned (chance) | Power | quiet; skill (words) | mind |
| board games | games room | 0 | 5 | mood +3 (win +1) | Power | 2-4 players, bond | social, mind |
| music (play/listen) | music room | 0-1 | 5 | mood +3, bond with listeners | Power | skill | making, social |
| hobby workshop | workshop | 1 | 8 | mood +4, an item ("a carved bead") | Power | skill | making |
| gym | gym | 1 | 4 | energy -3 now, recovery +20 % for the day, mood +2 | Power, Water | skill (fitness) | physical |
| bath | baths | 1 | 4 | recovery +, mood +3 | Water 4, Heat | calm | calm |
| sauna | sauna | 2 | 4 | mood +3, recovery +30 %, cold fixed | Water 4, Power, Heat; host | social | calm, physical |
| spa and massage | spa | 3 | 6 | mood +5, energy +6, recovery x2 for the day | Water 6, Power, Heat; **masseur** | bonds masseur | calm |
| cooking / shared meal | kitchen, dining | 1 | 6 | mood +3, bond with the table, Food | Water 3, Power; cook | social; skill (cook) | social, making |
| cinema | cinema | 1 | 6 | mood +3, a shared memory (talk topic) | Power | social | social, mind |
| bar | bar | 2 | 5 | mood +3, honesty of talk down a little (more words coined) | Power, Water; host | social | social |
| chess (as now) | anywhere | 0 | game | as now (and trials) | - | Elo | mind |

Each site has a **capacity** (`seats`) and a **booking queue**: a wesen books a slot at a site (a record `L<n>` `book/start/end`);
if full it waits (`queue.max`) or picks the next choice; a masseur has `slots_per_day`. Hosts (masseur, cook, librarian) make the site
open; with the role vacant the site is closed and its price listed as a *vacancy*.

### 4.3 Credits (or not) and costs
Proposed: **spare-time credits**, a small integer per wesen (0 .. 20), earned `+1` per finished shift and per finished maintenance
job, spent at the price column. No trading, no savings beyond the cap (question 6). A site's host earns a credit per guest.

### 4.4 Social effects and the ledger
Shared activities add *bond* between participants (a number per pair, small, `L` lines) that makes talk and chess partners likelier
and softens trials (adherence +); skill grows per activity. The ledger adds a "leisure" source per activity (gains) and
"queue" (small drain when a booked slot is lost); the reports mention it only when large ("Eve spent a lot of time in the spa").

## 5. How the three interlock
* **A spa** needs Water + Power + Temperature *and* a masseur: if no masseur exists the vacancy list gets "masseur" - and if beds,
  headroom and the cooldown allow, a new wesen is born with that role at the next boundary. If Water is short the spa closes and
  its guests get a mood drain, which makes `no_water` petitions likelier; the players may grant `maintenance` priority.
* **Population needs life support:** each new wesen draws Water/Air/Power; a birth is refused when headroom is gone, so the
  station *cannot* grow past its services; extra services need more operators, which need more wesen: a loop with a ceiling.
* **Leisure feeds the services:** a busy sauna raises Heat and Water load; the garden gives Food and Air back; a power operator
  on leisure leaves the board unstaffed -> wear -> failure. Rest/work stay the base: leisure is only a third choice.
* **Governance and honesty** connect everything: the same D / trust / standing / misreport machinery, with new topics and one lever.
* **Trials** can start from a leisure dispute (queue for the last massage slot): the existing `trial.clash` pairs get topic pairs.

## 6. Build order, markers, size and risk
Each step is one commit: marker, `*.enabled` in `data/limits.txt`, **off = byte-identical** (proved by `offcmp2` against the previous
tip), a checks scenario, README/help, version headers, 0 warnings on both compilers, `make portable` green. "Size" = Ada lines + data
lines; "time" = my working time incl. gates (full checks ~20 min, portable ~12 min). Risk: L low, M medium, H high.

| step | marker | what | size | time | risk |
|---|---|---|---|---|---|
| R1 | `roles=1` | `data/roles.txt`, roster of the first four with roles, role leans on `Choose`, `make roles`; no births | ~500 + 120 | 1 day | L |
| R2 | `roles=1` | `Entity_Id` -> `Max_Slots` with inert slots (a refactor with **no** change for 4 wesen: proved byte-identical), name pool, `B`/`R` records, births at the boundary, retire on liberation | ~900 + 150 | 2-3 days | **H** (touches every array) |
| L1 | `life=1` | Water + Power: stock/cap/load/wear, jobs on a board, `make life`, ledger lines; no failures, no petitions | ~800 + 150 | 1.5 days | M |
| L2 | `life=1` | Air + Temperature, failure events, effects on energy/mood, topics + `maintenance` lever, player clause and honesty, audit | ~900 + 120 | 2 days | M |
| P1 | `leisure=1` | action `leisure`, budget, credits, free sites: park, library, games, music, garden; ledger | ~800 + 200 | 2 days | M |
| P2 | `leisure=1` | priced sites needing services and hosts: baths, sauna, spa/massage, kitchen, gym, cinema, bar; booking queue; vacancies from sites feed R2 | ~900 + 200 | 2-3 days | M-H |
| P3 | all | interlock checks, trials from leisure disputes, report wording, tuning of the numbers, README tour | ~300 + 100 | 1 day | L |

Rough total: ~5000 lines of Ada, ~1000 of data, 2 weeks of steps. The small binary grows by ~0.5 MB (`make small`, today 2.8 MB).
Dependencies: `life=1` needs `rest=1` + `world=1`; `leisure=1` needs `rest=1` + `world=1`; `roles=1` needs `world=1`; sites ignore a
service need if `life=0`; the vacancy list ignores a site if `leisure=0`. R1 and L1 can be done in either order; R2 should come before P2.

## 7. Rules every step keeps
Plain Ada, standard library only; every number, word and table in `data/`; every roll is `hash(seed, entity, tick, salt)` with its own
salt range (roles 10000 .. 10199, life 10200 .. 10399, leisure 10400 .. 10699); state is rebuilt by replay and the *records*
(`B R J F V L` lines) are compared: changed / invented / removed = DRIFT; markers on the `S` line, new sessions only, removed
marker = DRIFT; `--help` and README stay current; no new test suites (extend `scripts/checks.sh`); compact output
(`debug.txt` <= 1500 bytes); version header on every file; 0 warnings (GNAT 14 and 12, -O0 and -O1); PROOF-LATER labels on the
arithmetic. Display names only from `data/names.txt`.

## 8. Open questions for Robert (recommended answer first)
1. **How many wesen at most?** *Recommend:* 12 alive at once, 32 slot numbers in total (never reused), start with 4; a data limit
   `pop.max_alive` below the compile-time slot count. More means a slower replay (about 3x at 12).
2. **Is Food a fifth service?** *Recommend:* not in L1/L2; it comes with the cook in P2 (`food.enabled`), so the first life-support
   steps stay four services.
3. **Do wesen die?** *Recommend:* no. They *retire* (after N sessions) or *leave* by liberation; `life.lethal = 0` is written but off,
   so a long water failure hurts mood and energy, never ends a wesen. Revisit when the services are stable.
4. **What does a new wesen inherit?** *Recommend:* nothing but the rolled personality and start words (like the first four); no copy of
   a leaver's words or karma. The rebirth hook of the karma layer stays for non-retiring cases.
5. **Who watches the new ones?** *Recommend:* the player with the fewest wesen, ties by id; up to 4 per player; a player's decisions
   keep the same dice. (A fifth player stays out of scope.)
6. **Credits, or time and energy only?** *Recommend:* start with time/energy only in P1 (free sites), add the 0 .. 20 credits in P2
   when priced sites arrive; earned by shifts and jobs, no trade, no savings beyond the cap.
7. **A "day" of 24 ticks?** *Recommend:* yes, `day.length` and `shift.ticks` in data, used only by roles/life/leisure, so a save
   without the markers is unchanged; session lengths (100 .. 1000) are then 4 .. 40 days.
8. **A health value?** *Recommend:* no. Energy cap + mood + ledger lines carry all the effects; a health number would double
   what the rest model already says. Add it only if the ledger turns out too coarse.
9. **May players play down a shortage, and by how much?** *Recommend:* yes, by one band at most, with the existing honesty
   trait; `make audit` shows the true band beside the claim; a `challenge` costs the player standing as now.
10. **Who pays for repairs / who decides priorities?** *Recommend:* no money for the station; repairs are jobs done by role-holders;
    the players decide only the `maintenance` priority lever (small steps, bounds), through petitions as today.
11. **Roles of the first four?** *Recommend:* assign by data at the first `roles=1` session without `--fresh`: Adam engineer ->
    power operator, Eve reviewer -> air technician, Abel vice_president -> caretaker, Ruth human -> water engineer (placeholders, change
    in `data/roles.txt`); the old words stay as titles. Their ids, diaries and every old byte stay.
12. **Names of the newborn?** *Recommend:* a pool of ~40 short names in `data/namepool.txt` (ids = lower case), picked by Rule 30,
    each used once; deities stay for the *players*, the wesen get ordinary short names. Robert may replace the pool freely.

*End of the proposal; nothing here changes the program until the steps of section 6 are started.*
