# Life in the station: roles, companies, life support, leisure (design only, nothing built)
Version: 0.004

Status: **proposal for Robert**. No code for any of this exists yet; every number below is a *proposed default* that
lives in `data/` when built, and every decision is open until Robert answers section 9 (and 6.9), except the exhaustion rule (2.6), which is a rule. Style as `docs/WORLD.md`: what it is,
what it is made of, what is recorded. (`docs/MVP.md` does not exist in this tree; this follows `docs/WORLD.md`.)
Amendment of Robert (this version): each player owns a **company** with departments; players create **positions** that wesen fill; the
"hard work" the wesen petition about becomes the terms of a position; energy and exhaustion tracking is a **hard constraint** (2.4 to 2.6).

## Contents
1. Where we start (facts of the present build)
2. Roles and population (`roles=1`), companies, departments and positions (`company=1`, 2.4), the exhaustion rule (`exhaust=1`, 2.6)
3. Life support: water, air, temperature, power, maybe food (`life=1`)
4. Leisure and spare time (`leisure=1`)
5. How the three interlock
6. One being model (`bio=1`): one stored record for players and wesen, ages, death, text hooks
7. Build order, markers, size and risk
8. Rules every step keeps
9. Open questions for Robert, with a recommended answer each (the being model's own are in 6.9)

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

## 2. Roles, population, companies and exhaustion (`roles=1`, `company=1`, `exhaust=1`)

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
With companies (2.4) a role is the **qualification** a position asks for: `data/roles.txt` rows get a `dept` link (water engineer, air
technician, power operator, heating keeper, caretaker -> maintenance; cook, librarian / host, masseur -> hospitality), and the title of the
position a wesen holds is what the texts call its role (6.7 `{role_word}`). A wesen without a position keeps the role it has.

### 2.2 Vacancy, then birth
* Each session boundary (the `E` of the end report, before the next session's tick 1) a **vacancy list** is computed from data:
  for every role, `needed(population) - filled`. Needs come from the services (3) and the leisure sites that exist (4), so the
  list is a pure function of the replayed state. **Open positions (2.4) count as vacancies** of the role their department links to (so a
  player that opens positions it cannot fill lets the station grow, inside the same birth rule).
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
* **Dies:** by age, accident or disease under the being model (6.5, `bio=1`); or, without it, only if `life.lethal = 1` (default 0) and a service has been `out` for `life.lethal_ticks` while the wesen's energy
  is 0: a record `R<n> ... cause=<water|air|heat>`. Not in the first steps (question 3).
* **After leaving:** a held position is released (`O` kind=left, 2.4); diary file stays (history), entry stays in the roster as `gone` (the ledger, Elo list and trial lines keep
  their name), the chess Elo of a gone wesen is frozen, its open petitions are closed as `lapsed`, its watcher is freed, its
  beds/duty are freed. Ids and slot numbers are never given again.

### 2.4 Companies, departments and positions (`company=1`; amendment of Robert)
Robert: *"The Players each have companies. They create Positions which Wesen can fill. That would be the 'hard work' they are discussing. Each
would have a different department as in warehousing and acquisition etc."*
* **A company per player.** Each of the four players owns exactly one company (a name from `data/companies.txt`, planned: one row per
  owner id with 3 or 4 name candidates, e.g. placeholder names such as "Harbour Works" or "Lantern Supply", Robert replaces them freely).
  A company is a stored fact like a birth: a record `Q<n>` in `diaries/companies.txt` (`Sim_Store`, replay-verified): `Q1 t= id=<company>
  owner=iris name=... depts=warehousing,records,hospitality h=`. It is part of the player's being record (`roles`, 6.1).
* **Departments.** `data/departments.txt` (planned) lists the departments of the world, each with id, display word, a linked role (2.1),
  the skill kind a position there asks for, and default energy cost, pay and hours. Proposed list (placeholders): **warehousing,
  acquisition, maintenance, records, hospitality**, plus a few more (workshop, kitchen, transport) so that the mixes can differ. At
  genesis each company gets **3 to 5 departments** (`company.depts_min = 3`, `company.depts_max = 5`) picked from the list by `Pick60`; the four mixes must be
  **distinct** (a re-roll up to `company.reroll` times, then a forced swap of one department), so every player's "hard work" sounds different.
* **A Position** is a job slot in one department of one company: `department, title (data list per department), skill need (kind + minimum
  0 .. 100), energy cost per shift (bounded, 3 .. 40), pay (credits per shift, 0 .. 5, the spare-time credits of 4.3), hours (shift length in
  ticks and shifts per day, 2.5)`. A player **creates** positions at a session boundary (`company.positions_per_session`, default 1; at most
  `company.max_positions`, default 4 per company, so 16 positions can exist for at most 12 wesen and some stay open on purpose). What it opens
  follows its company's departments, its traits and what its wesen petition about (2.5). Own salts **15000 .. 15399**.
* **Wesen fill positions by application.** A wesen without one applies at the boundary (and when a position opens) with a hash roll weighted
  by skill, energy, mood and the role it has; an application is a **petition-like line** in the petitions file already built
  (`diaries/petitions.txt`: topic `apply_<department>`, lever `position`). The **player decides** (accept, defer, refuse) with the same
  machinery as the four levers (trust, standing, personality, an announcement may weigh a little), and the decision is a vote line
  (`votes.txt`, `kind=position`, the weight and standing as for petitions). The four-lever governance (`rate cool work quick`, `D` records)
  **stays exactly as it is**; a position is a **fifth, separate decision type** (it creates or changes a job, not a global rule).
* **Record of positions: `diaries/positions.txt`** (planned, `Sim_Store`, replay-verified, a changed, invented or removed line is DRIFT):
  `O<n> t= s= pos=<id> company=<id> dept= title= kind=opened|applied|filled|declined|terms|left|closed player= wesen= need= cost= pay= hours= why=<reason code> h=`.
  One line per event, so the whole life of a job can be read in order; the application and the decision also appear in the petitions and
  votes files (one line each, same ids). `make divergence` gets a section for the positions (what the player reported against what it did).
* **What a position does for the wesen:** while it holds one, a wesen's `Choose` is leaned to its shift (a *shift duty* as in 2.1: during
  its shift ticks it works the position's task), it pays the position's **energy cost** per shift (through the one energy point of 2.6),
  earns its pay, and the position's department output is counted (a number per day: items stored, items bought, repairs, records kept,
  guests served; no trade between companies in the first release, question 16). A shift that cannot be worked (spent, 2.6) is a **missed
  shift** in the `O` file and in the mood ledger, and the player's next report mentions it.
* **Maintenance stays shared:** the jobs of the life services (3.2) go on the common board and may be taken by the holders of
  *maintenance* positions of any company (a position there is where a "water engineer" is employed).

### 2.5 The "hard work" petitions become terms of a position
Today the wesen petition about rest and recovery: `more_rest` (lever `rate`) and `faster_work_recovery` (lever `cool`), decided as global
offsets. Proposed (marker `company=1`): for a wesen that **holds a position** the same two topics name **the terms of that position**, which
is what the players are "discussing":
| petition topic | today (global lever) | with a position |
|---|---|---|
| `faster_work_recovery` (`cool`) | cool-down offset of everybody it governs | the position's **energy cost per shift** goes down one step, or its rest pause after the shift shortens |
| `more_rest` (`rate`) | recovery rate offset | the position's **shift pattern**: fewer shifts per day, shorter shift, longer rest between |
The decision is still grant / partial / defer / refuse by the same dice and reason codes; a grant changes the term by **one step** inside
bounds in `data/company.txt` (the same step-and-bounds device as `data/govern.txt`) and is written as a `D` record (as now, with the position id) **and** an
`O` line `kind=terms` (old -> new). A wesen without a position still petitions the global levers, which keep working unchanged
(off = byte-identical). The player's report (`preport=1`) names the position and the term ("Adam's night shift in warehousing now costs
less"), and its honesty trait applies as to any claim; `make audit` compares claim and record.

### 2.6 Exhaustion: energy is a hard constraint (`exhaust=1`; a rule, not a question)
Robert: energy and exhaustion tracking is a **hard constraint**. It is therefore stated as a rule that every step keeps, not as an open question.
* **One energy point.** Every change of a wesen's energy (work, chess, talk, a shift's cost, rest, petition effects) goes through **one**
  procedure (planned `Sim_Rest.Spend` / `Recover`), so no activity can skip the tracking; a checks scenario compares the total of all changes with the stored energy.
* **Named states with fixed thresholds** (`data/exhaustion.txt`; energy 0 .. 100 as in the rest model; these numbers are the rule's constants):

  | state | energy | work, chess, talk | action choice |
  |---|---|---|---|
  | fresh | 50 .. 100 | normal | free |
  | tired | 30 .. 49 | **worse**: work yield -15 %, chess: a weaker move is chosen with +15 points chance, talk: fewer words per exchange | free |
  | spent | 10 .. 29 | **much worse**: work -35 %, chess weakening +35 points, talk halved | **a rest is forced** until energy >= `exhaust.resume` (45); no shift, no match, no talk start |
  | collapsed | 0 .. 9 | none possible | forced rest as above, mood -2 per 10 ticks until resume |
  The forced rest keeps a hysteresis: a wesen that fell below 30 returns to free choice only at `exhaust.resume`, not at 30, so it cannot flicker between states.
* **Every crossing is logged.** A change of state is a record `X<n>` in `diaries/exhaustion.txt` (planned, `Sim_Store`, replay-verified):
  `X1 t=412 s=2 id=gemini from=tired to=spent energy=27 cause=work pos=P3`; at most one line per wesen per tick; a changed, invented or removed
  line is DRIFT. The mood ledger gets "exhausted" and "forced rest" sources; the end box may show one short line ("two wesen spent").
* **Deterministic.** The thresholds and the effects have no dice (the chess weakening uses the existing seeded hash scheme, salt 15390
  inside the company range), so the rule is a pure function of the replayed state. Marker `exhaust=1` on the `S` line, new sessions only (an existing
  save gets it at the next new session, no `--fresh`), **off = byte-identical** (proved by `offcmp2`). It needs `rest=1` only, so it can ship
  before the companies (section 7: X1).
* **Positions obey it.** A position's `energy cost per shift` is paid through the same point; a shift is worked only if the wesen is
  `fresh` or `tired` at its start; a position whose cost would push its holder below `spent` every day shows up as a petition topic (2.5)
  and as a number in `make divergence` (shifts missed against what the player reported).

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
only used by roles/life/leisure so old output is untouched); a shift is `shift.ticks` of it. With companies (2.4) the shift is the one of the
position a wesen holds; the maintenance jobs are taken by holders of maintenance positions.

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
job (with companies: the **pay** of the position it holds, 2.4), spent at the price column. No trading, no savings beyond the cap (question 6). A site's host earns a credit per guest.

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
* **Companies and exhaustion:** a position costs energy per shift (2.6), so the hard work of a company shows in the exhaustion log, in
  the petitions for lower cost or fewer shifts (2.5) and in the players' reports; a company without maintenance staff leaves its services
  to the others (3.2); open positions feed the vacancy list and so the birth rule (2.2).
* **Trials** can start from a leisure dispute (queue for the last massage slot): the existing `trial.clash` pairs get topic pairs.

## 6. One being model (`bio=1`)
Robert's rule: **players and wesen have the same kind of details record**. It is *initially generated*, then *stored* in the save files, and then
*changed over time by recorded events*. The only difference is a lifespan: a wesen has at most about **125 years**, a player (a wesen of the
upper kind) **50,000 years, or an order of magnitude more (500,000)**, and is effectively immortal except by a violent accident or a sudden disease.
It is enough that the record **lives in data**; **showing it on screen can wait**, but the stored fields must be **used in the text
generation** (reports, petitions, visit answers, chess and trial lines, myth stories). The human is the Ground (`docs/MYTH.md` section 1): it has **no
being record** and is never a fifth player.

### 6.1 The record (one shape for everybody)
| field | player | wesen | stored as |
|---|---|---|---|
| `id`, `kind` | iris .. vega, `player` | ada .. robert and the pool names, `wesen` | id never reused; kind fixed |
| `born` | rolled long before the run (a *negative* day) | backdated for the first four (adult), the birth tick for newborns | an absolute day number (6.3); **age is derived**, never stored |
| `lifespan` | one of 50,000 .. 500,000 years (a roll, 6.2) | cap 125 years (hard, 6.5) | years, fixed at genesis |
| `origin` | the myth home family, place, "made of" (MYTH.md 6.3: stored as a reference `myth=M<n>`, not copied) | a place word, a family word, parents or "made by" (an id or none) | words from data lists |
| `roles` | its office (`players.txt`) + its domains (myth) + **its company** (`Q` id, LIFE.md 2.4) | the current role, **the position it holds** (`O` id: company, department, title) and the role history (LIFE.md 2.1, 2.4) | ids + ticks |
| `traits` | Rule 30 bits: tone, brevity, warmth, **plus** curiosity, courage, patience, frailty (0 .. 100) | the same | numbers at genesis, a small overlay of events (+/- 15 at most) |
| `beliefs` | a view of the Ground, of death, of the made (myth dimensions 10, 13, 14) | views of the players, of death, of work, of Robert | key = a word from a list (a few per being) |
| `relations` | kin and rivals of the other players (MYTH.md 6.3), its watch list | kin, friends, rivals, teacher, watcher | id -> kind + strength; trust and standing stay in the `Y` lines |
| `history` | events (6.4) | events (6.4) | `H` records |
| `health` | 0 .. 100 + conditions with an end tick (well, ill, hurt, frail) | the same | a number + a few keyed conditions |
| `body` | build, height class, hair, eyes, marks, bearing (a few words from lists) | the same, changing with age and scars | words; a mark is added by an event |
Everything that exists today (energy, mood, karma, trust, standing, the Rule 30 ring, Elo, vocabulary) **stays where it is**: the record
holds the *slow, biographical* state and refers to the fast state; nothing is moved, so a `bio=0` run is untouched.

### 6.2 Generated once, from seed + name
At the first `bio=1` session start each being gets a **genesis** record `Z<n>` in `diaries/beings.txt` (`Sim_Store`, replay-verified, letters
re-checked at build: `G` is taken by grants): `Z1 t=3401 id=iris kind=player born=-61820000 life=240000 ... h=`. The picks are the world's
rule: **Rule 30 row** seeded by `hash(master seed, id)` for the trait bits, then every list pick is `Pick60` (D4 reroll on 1, 2/3/4 = block
1/2/3 of 20, D20 inside) with its own salt range **13000 .. 13999** (LIFE 10000 .. 10699, myth 11000 .. 12999). Lists in `data/bio.txt`:
places, families, body words, belief words, condition words, name pool, and the **age and lifespan tables** (players: block 1 = 50,000 .. 100,000
years, block 2 = 100,000 .. 250,000, block 3 = 250,000 .. 500,000 in 20 steps each; wesen start ages: 18 .. 45). A *name* in `data/names.txt` is a label;
the genesis is keyed to the **id**, so renaming Odin changes no stored detail (the same rule as for the myth). A newborn (LIFE.md 2.2) gets its
`Z` line at the birth tick; the `B` record stays the fact "who exists", `Z` the details.

### 6.3 Ticks, calendar, age
One **world clock** for all beings (data: `data/time.txt`), so the lifespans differ and nothing else:
`time.ticks_per_day = 24` (the leisure day of LIFE.md 4.1), `time.days_per_year = 25` -> **600 ticks = 1 year**, a month = 50 ticks. At the usual
session length (300 ticks) that is two sessions a year; Robert's present 3,400 ticks are about 5.7 years; **a wesen can grow up (a stage change
every few dozen sessions), work, retire and die inside a long run** (125 years = 75,000 ticks, roughly 250 sessions), while a player aged 200,000
years does not change in any run that can be played: its age phrase stays "older than the hills" (data bands) and only an event changes it. Stage
bands (`data/stages.txt`): wesen *child* 0-14, *young* 15-29, *prime* 30-54, *elder* 55-79, *old* 80+; players by fractions of their
lifespan (*young god* < 5 %, *in its prime* 5-70 %, *ancient*), small lean tweaks to the action table (a child rests more, an elder talks more), never a new dice stream.
Alternatives (real time = 8,760 ticks a year, or 100 ticks a year) are table values, not code (question 1).

### 6.4 Events change the record (`H` records)
`H<n> t= id= kind= a= b= h=` in the same file, replay-verified. **Kinds** (data list): born, grew (stage), role taken / left, position taken / left (2.4), learned (a trait
step), bond / fell out, belief shifted, ill / recovered, hurt / healed, scar, milestone (first chess win, a trial won or lost, a landmark),
rise (a player gains a domain; a rival named), retired, died. Most events are **consequences of state already replayed** (a stage change from the age, a
role from a vacancy, a milestone from a `C`/`T` record) and only *recorded*; **chance events** (illness, accident, drifting bonds, belief steps)
use `hash(seed, id, month, salt)` with salts in the 13000 range and **one chance roll per being per month** (a month = 50 ticks), so the cost is
small and independent of session length. Each event writes **at most one line**, `bio.events_per_session` (20) is the cap, and every line
carries `h=` of its rendered text. A removed, edited or invented `H` line is DRIFT.

### 6.5 Death, accident, disease (tables in `data/mortality.txt`)
* **Wesen:** a monthly roll against the hazard of the age band, per 1,000 a year (proposed): 0-14: 1; 15-39: 2; 40-59: 6; 60-79: 30; 80-99:
  120; 100-109: 350; 110-124: 700; **age 125: certain** (`age.cap = 125`, a hard cap). The trait `frailty` and the health band scale it
  (x0.7 .. x1.4; ill x3). *Accident* and *disease* are two more rolls: accident by role (power operator and caretaker higher; a `life=1` failure
  event raises it for the staff on site), disease by season, crowding and a service in `low`/`short`. Severity: minor (a condition), serious (health -30,
  a scar), **fatal** (rare, an age-dependent share of serious cases). A death writes `H kind=died cause=<age|accident|disease>` and the LIFE.md `R` record;
  the diary stays, the slot is never reused, the chess Elo freezes, open petitions lapse (LIFE.md 2.3, which `life.lethal` in 2.3 now generalises).
* **Players:** no age rule at all (the lifespan figure is a *scale* for bands and phrases, question 4). A flat **annual hazard**, only two causes:
  `player.accident_ppm = 200` and `player.disease_ppm = 100` per year (1 in 3,300 together: over 50 game-years about a 6 % chance that *one of four* dies,
  memorable and rare), with the cause text from `data/accident.txt` / `disease.txt` (the world's own misfortunes in plain words). **Shipped off**
  (`player.hazard_x = 0`) until Robert decides (question 2). A health condition of a player heals slowly; nothing makes it "old".
* **What a player's death means (proposed default, question 3):** (1) its record closes with `died`; the name stays in history and in `make myth` as
  *a lost telling* (past tense, its myth kept); (2) its wesen go to the player with the fewest watched, its open petitions lapse; (3) after
  `player.succession_sessions` (2) **a new manifestation stirs from the Ground**: a fresh genesis `kind=player`, a new name from a pool in `names.txt`,
  a new myth (kin of the others, with 50 % chance the heir of one dead domain, rivals reshuffled); (4) the other players' stories mention the loss
  in their biography lines. The Ground (Robert) is told in the inbox. **Technical risk:** every array is `range 1 .. 4` today and the Elo, the quartet
  decisions, the median and the challenge logic assume four; a successor therefore **takes over the seat** (the slot and its id; the being, name and genesis are new, the old record is closed and kept in history) - to be tested before any hazard is turned on.

### 6.6 How it ties to LIFE.md and to the myth framework
* **Roles, companies and population (2):** the `roles` field *is* the role table of 2.1 for one being, plus the company of a player and the position of a wesen (2.4); `O` lines are the facts, `H` the history; the vacancy and the birth rule read age (arrival
  at 16, retirement at about 65 instead of `pop.service_sessions`), health and role history; `B`/`R` stay the facts of who exists, `Z`/`H` the details.
* **Life support (3):** a shortage raises the monthly disease and accident rolls and, through `health`, lowers the energy base a little (a
  condition word, not a new stat; 3.4 stays the rule).
* **Leisure (4):** spare time of a being uses stage and traits (a young one likes games, an elder the library or the bath), health decides the gym;
  an event "milestone" records a first.
* **Myth (`docs/MYTH.md`):** the player's `origin`, domains, rise and kin are *references* to the `M` picks (one source of truth); the myth dimension
  "ages and cycles" supplies the **age phrase** vocabulary; a player's `died` event rewrites its relations text; the myth of a wesen is the
  few lines inside its player's story (MYTH.md question 8), and its *own* history is this record.

### 6.7 Text hooks: which stored field feeds which slot
A template slot is filled from the record; a slot with no value is dropped (the rule of the visit templates), so short and long forms coexist.
Phrase lists are `data/biotext.txt` (original wording; bands, not numbers; a player's age is never printed as a figure unless asked).

| slot | from | example filling |
|---|---|---|
| `{origin}` | origin (place, family word) | "from the high shore", "of the river people" |
| `{age_phrase}` | born, kind, stage | wesen: "in their first years", "grey and steady"; players: "older than the hills", "since before the rivers were named" |
| `{stage}` | stage band | child / young / prime / elder / old |
| `{trait_adverb}` | traits (highest or lowest) | warmth -> "kindly", brevity -> "curtly", courage -> "boldly", patience -> "in no hurry" |
| `{belief}` | beliefs | "who holds that nothing is lost", "who thinks the players listen" |
| `{kin}`, `{rival}`, `{friend}` | relations | "its sister Eve", "the one it quarrels with, Abel" |
| `{role_word}`, `{role_past}` | roles, history | "the water engineer", "once a caretaker" |
| `{health_phrase}` | health, conditions | "a little unwell", "still limping from the fall" |
| `{body_phrase}` | body, marks | "tall, with a scar on the hand" |
| `{event_recent}` | newest `H` line, within `bio.recent` ticks | "who has just come of age", "since the fall at the pump" |
| `{domain}`, `{myth_line}` | M picks | "keeper of the rivers", the first line of the story |

Where each is used, and how (examples are invented wording):
* **Player reports and inbox** (`data/preport.txt`): the box header "Ganesha, {age_phrase}, {trait_adverb}: ..." -> *"Ganesha, older than the hills,
  kindly: Adam has been on shift too long; I granted two petitions and put one off."* A rival or a kin of the petitioner colours the verdict wording:
  *"I granted Abel's request, though {rival} spoke against it."*
* **Petitions** (`data/topics.txt` petition text of a wesen): `{role_word}` and `{health_phrase}` : *"Petition: as the water engineer, still a little unwell, I ask for
  a longer rest."* The **topic** choice may lean to the role (LIFE.md 3.5); the *text* uses the record.
* **Visit answers** (`data/visit.txt`): the visit layer only speaks with **words the wesen knows**, so the record does not add words: it selects
  *which* known pool answers (an ill or old wesen answers from the tired pool and shorter; a child asks more `{q}`; a wesen with a friend named in the
  room uses that name if it knows it).
* **Chess and trial lines** (`data/chess.txt`, `data/trial.txt`): a rival or friend, an elder or a child, a scar or a milestone: *"Abel, the
  old rival, took the bishop"*, *"the court heard Eve, who had lost to Ruth twice."*
* **Myth stories** (`docs/MYTH.md` 5.5): the player's `{origin}`, `{kin}`, `{rival}`, `{domain}`, and the age phrase fill the biography
  line and the two-part story ("how it came from the Ground"); the wesen named in the story use their stage, role and a belief.
* **Later, not now:** `make being NAME=<n>` as a read-only view (B5); the first releases only *speak* with the record.

### 6.8 Build order of the being model
| step | what | size (Ada + data) | time | risk |
|---|---|---|---|---|
| B1 | `data/bio.txt`, `time.txt`, `stages.txt`; pure genesis function; marker `bio=1`; `Z` records + replay check; no text yet | ~450 + 400 | 2 days | M |
| B2 | calendar, age, stage change events, role history; `H` records; the caps | ~350 + 150 | 1-2 days | M |
| B3 | health, mortality, accident, disease; wesen death + the `R` link (needs `roles=1`) | ~400 + 250 | 2 days | **M-H** (population dynamics, tuning) |
| B4 | **text hooks** into reports, petitions, visit, chess/trial, myth lines (`data/biotext.txt`) | ~250 + 500 | 2 days | L-M (content volume) |
| B5 | `make being` view (read-only); player hazard switch + succession (only after Robert's answer) | ~300 + 100 | 2 days | **H** (4-slot assumptions) |
B1 now follows R1 directly and carries the company reference of each player (2.4). Total about 1,750 Ada + 1,400 data lines, ~9 days. `bio=1` on new sessions only; **marker off = byte-identical** (`offcmp2`), the old four keep their
ids and files, 0 warnings on GNAT 14 and 12, README and `--help` updated at each step. Replay cost: one roll per being per month; 12 beings add well under 10 % to the time.

### 6.9 Open questions about the being model (recommended answer first)
1. **How do ticks map to years?** *Recommend:* one world clock, 600 ticks = 1 year (a month 50 ticks, a day 24 ticks), identical for wesen and players; only
   the lifespans differ. A real-time scale (8,760 ticks a year) would make nobody age in the run; 100 ticks a year makes lives of 12,500 ticks.
2. **May a player die at all in the first release?** *Recommend:* the rules ship, the hazard is **off** (`player.hazard_x = 0`); Robert turns it on after seeing a
   test, because a death changes the four-player structure.
3. **What does a player's death mean?** *Recommend:* the seat is refilled after two sessions by a *new manifestation of the Ground* (new genesis, new myth, maybe heir of a
   domain); the dead one stays in history as "a lost telling"; its wesen pass to the player with the fewest. Alternative: the seat stays empty (3 players).
4. **Does a player have a natural end at 50,000-500,000 years?** *Recommend:* no; the number is a scale for phrases and stages. Only accident or disease.
5. **Are the first four wesen backdated?** *Recommend:* yes: adults of 24-41 years (a roll) born on negative days, so no age-0 child needs a school; the first `Z` lines are
   written at tick 3401 and earlier sessions stay byte-identical.
6. **Is a wesen's death final?** *Recommend:* final for the being (the slot is never reused); the karma layer's rebirth stays as *wording* (a newborn is "born into the
   place left") with **no** inherited stat for now.
7. **Do the details show on screen?** *Recommend:* no, they only feed the texts first; a `make being` view comes in B5; health and body are fiction, never medical advice.
8. **How grim may the texts be?** *Recommend:* gentle: illness, accident and death in plain, short, non-graphic words; consistent with MYTH.md 7 (general audience).

## 7. Build order, markers, size and risk
Each step is one commit: marker, `*.enabled` in `data/limits.txt`, **off = byte-identical** (proved by `offcmp2` against the previous
tip), a checks scenario, README/help, version headers, 0 warnings on both compilers, `make portable` green. "Size" = Ada lines + data
lines; "time" = my working time incl. gates (full checks ~20 min, portable ~12 min). Risk: L low, M medium, H high.

| step | marker | what | size | time | risk |
|---|---|---|---|---|---|
| R1 | `roles=1` | `data/roles.txt`, roster of the first four with roles, role leans on `Choose`, `make roles`; no births | ~500 + 120 | 1 day | L |
| R2 | `roles=1` | `Entity_Id` -> `Max_Slots` with inert slots (a refactor with **no** change for 4 wesen: proved byte-identical), name pool, `B`/`R` records, births at the boundary, retire on liberation | ~900 + 150 | 2-3 days | **H** (touches every array) |
| L1 | `life=1` | Water + Power: stock/cap/load/wear, jobs on a board, `make life`, ledger lines; no failures, no petitions | ~800 + 150 | 1.5 days | M |
| L2 | `life=1` | Air + Temperature, failure events, effects on energy/mood, topics + `maintenance` lever, player clause and honesty, audit | ~900 + 120 | 2 days | M |
| X1 | `exhaust=1` | the one energy point (`Spend` / `Recover`), the named states, forced rest, `X` records in `diaries/exhaustion.txt`, effects on work, chess, talk; needs only `rest=1`; ledger sources (2.6) | ~500 + 80 | 1.5 days | M (touches every energy change) |
| C1 | `company=1` | `data/companies.txt`, `departments.txt`, `company.txt`; one company per player, distinct mixes of 3 to 5 departments, `Q` records, `make company` (read-only); no positions yet | ~400 + 150 | 1 day | L |
| C2 | `company=1` | positions: `O` records, a player creates them at the boundary, wesen apply (petitions file), the player decides (votes file), shift duty and energy cost through X1, pay as credits, missed shifts | ~800 + 200 | 2-3 days | **M-H** (a fifth decision type) |
| C3 | `company=1` | the `more_rest` / `faster_work_recovery` petitions become position terms (2.5), `D` + `O terms` lines, reports and `make audit` / `make divergence` sections, open positions in the vacancy list | ~400 + 100 | 1.5 days | M |
| P1 | `leisure=1` | action `leisure`, budget, credits, free sites: park, library, games, music, garden; ledger | ~800 + 200 | 2 days | M |
| P2 | `leisure=1` | priced sites needing services and hosts: baths, sauna, spa/massage, kitchen, gym, cinema, bar; booking queue; vacancies from sites feed R2 | ~900 + 200 | 2-3 days | M-H |
| P3 | all | interlock checks, trials from leisure disputes, report wording, tuning of the numbers, README tour | ~300 + 100 | 1 day | L |

**Order (Robert's amendment): roles + being record + companies and positions first:** R1, B1, X1, C1, C2, C3; then R2 (births), B2 to B5, L1, L2, P1, P2, P3.
X1 comes before the companies because the exhaustion rule is a hard constraint and needs only `rest=1`; C1 needs R1 and B1 (the company is part of the
player's record); C2 needs X1; C3 needs `govern=1` and C2; R2 reads open positions. Each step keeps off = byte-identical.
The being model (section 6) has its own steps B1 to B5 (`bio=1`, ~1750 Ada + 1400 data lines, ~9 days); B1, B2 and B4 can start right after R1, B3 needs R2.
Rough total without it: ~6700 lines of Ada, ~1500 of data, 3 weeks of steps (X1 and C1 to C3 add ~2100 Ada and ~530 data lines, ~6 days). The small binary grows by ~0.5 MB (`make small`, today 2.8 MB).
The **learning layer** (`docs/LEARN.md`: slow core, mixed study, pruning, pondering, notebooks; steps **LN1 to LN7**, salts 16000 .. 16999) is a separate
list so that the names L1 and L2 stay with life support: LN1 and LN2 need only `rest=1` and may follow X1, LN3 needs B1 and X1, LN5 follows C3 for the position decisions.
Dependencies: `life=1` needs `rest=1` + `world=1`; `leisure=1` needs `rest=1` + `world=1`; `roles=1` needs `world=1`; sites ignore a
service need if `life=0`; the vacancy list ignores a site if `leisure=0`. R1 and L1 can be done in either order; R2 should come before P2. `company=1` needs `roles=1`, `govern=1` and `rest=1`; `exhaust=1` needs `rest=1`.

## 8. Rules every step keeps
Plain Ada, standard library only; every number, word and table in `data/`; every roll is `hash(seed, entity, tick, salt)` with its own
salt range (roles 10000 .. 10199, life 10200 .. 10399, leisure 10400 .. 10699, companies, positions and exhaustion 15000 .. 15399, learning (`docs/LEARN.md`) 16000 .. 16999; the records of the present
build use 14000 .. 14399); state is rebuilt by replay and the *records*
(`B R J F V L Q O X` lines; the letters are re-checked at build, each in its own file) are compared: changed / invented / removed = DRIFT; markers on the `S` line, new sessions only, removed
marker = DRIFT; `--help` and README stay current; no new test suites (extend `scripts/checks.sh`); compact output
(`debug.txt` <= 1500 bytes); version header on every file; 0 warnings (GNAT 14 and 12, -O0 and -O1); PROOF-LATER labels on the
arithmetic. Display names only from `data/names.txt`; company and department words only from `data/companies.txt` and `data/departments.txt`.
Energy is tracked through one point and every crossing of an exhaustion state is a record (2.6).

## 9. Open questions for Robert (recommended answer first)
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
   when priced sites arrive; earned by shifts and jobs (the pay of the position held, 2.4), no trade, no savings beyond the cap.
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
    in `data/roles.txt`); the old words stay as titles. Their ids, diaries and every old byte stay. With companies the same four are the first holders of positions in their watcher's company (placeholders in data).
12. **Names of the newborn?** *Recommend:* a pool of ~40 short names in `data/namepool.txt` (ids = lower case), picked by Rule 30,
    each used once; deities stay for the *players*, the wesen get ordinary short names. Robert may replace the pool freely.

13. **Can a wesen hold two positions?** *Recommend:* no. One position at a time, full shift pattern (a part-time job is a position with fewer
    hours); this keeps the energy cost and the exhaustion rule (2.6) simple and the reports readable.
14. **Can a position be closed?** *Recommend:* yes: by its player at a boundary, or automatically after `company.idle_sessions` (3) sessions empty; the
    holder is released (`O` kind=closed, then `left`) and becomes available; the title stays in the history of the company.
15. **What happens to a wesen without a position?** *Recommend:* it keeps today's behaviour (base action table, role leans, global levers), earns no pay
    and applies to open positions with the dice of 2.4; after `company.want_sessions` (4) sessions without work it may petition `want_work`.
16. **Do companies trade?** *Recommend:* not in the first release. No goods and no credits move between companies; a department only counts its own
    output (items stored, bought, kept). A `trade=1` marker (prices, stock between companies, acquisition buying from another) is a later step if Robert wants it.
17. **May a wesen change company or quit?** *Recommend:* yes, at a boundary by an application to another company's position or a `resign` line, with a cooldown
    (`company.move_cooldown`, 3 sessions), decided by both players' trust as for any application; no wesen is forced to move.
18. **How many positions and companies?** *Recommend:* four companies (one per player, fixed), at most 4 positions each, 3 to 5 departments each; the
    totals stay below the number of wesen so that work is scarce and the hard work is shared; the player's own wesen get a small preference.
19. **Who decides the department mix and the titles?** *Recommend:* the genesis roll (distinct mixes, 2.4) from the data lists, so a mix is stable for a
    company's life; Robert may edit the lists. Players only open or close positions inside their own mix.

*End of the proposal; nothing here changes the program until the steps of section 7 (and 6.8) are started.*
