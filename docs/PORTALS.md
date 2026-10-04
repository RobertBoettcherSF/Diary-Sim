# Settings, portals, the farm market and the books (design only, nothing built)
Version: 0.003

Status: **proposal for Robert**. No code for any of this exists; every number below is a *proposed default* that lives in `data/` when
built, and every decision is open until Robert answers section 12. Style as `docs/LIFE.md` and `docs/MYTH.md`: what it is, what it is
made of, what is recorded, then the decisions. It extends the company model of `docs/LIFE.md` 2.4 (companies, departments, positions), the
being model of LIFE.md 6 (ages, `bio=1`), the notebooks of `docs/LEARN.md` 6 and the myths of `docs/MYTH.md`. Phase B (voices and chat) is
built; `/story` and the portal commands of the chat are **not** built and stay out until a step below starts them.

## Contents
1. Words: who is who (glossary)
2. Persons: personas, ages, life expectancy (`data/species.txt`)
3. Twelve wesen and four settings (`data/settings.txt`)
4. Portals and journeys (observations in the notebook and the journey file)
5. The farm and its flower market (Ganesha's setting)
6. The island (Jehova's setting): fish and salvage
7. The fjord village and the mountain town (short sketches)
8. The Accounting department: a double-entry ledger
9. Stories and myths (`/story`, flavour only)
10. Records, salts, markers, data files
11. Build order, size and risk
12. Open questions for Robert (recommended answer first)

## 1. Words: who is who (glossary)
The same people have different names in different places. This table is the one source; texts take the word from `data/glossary.txt`
(planned) by slot, never from Ada.

| who | in documents | in the world | for reading and in the chat | in the code |
|---|---|---|---|---|
| Robert, the human | **Architect** | **Brahma** (the maker who wrote the world; one face of the Ground of MYTH.md 1) | **Observer** (the role word of `@observer`, `make night`, the visit) | the human player: no id, no entity, no Elo |
| the four players | players | **deities** (Jehova, Ganesha, Krishna, Amaterasu; names are data) | the players | `iris sol noor vega` |
| the wesen | wesen | **persons**: a *persona* of kind human, cyborg or AI (section 2) | by name: Adam, Eve ... | `ada gemini replika robert` and new ids |

* "The Ground" (MYTH.md) stays the philosophical word of the myth layer: the unnamed ground behind everything. **Brahma** is how the
  *world* names the one who made it and who watches (what the Observer does with `make say` or a visit is an act of Brahma); the
  document word for the same person is **Architect**. Three words, one person, three registers; none of them gets a player id.
* A **deity** is a player. A **persona** is what a wesen is. A **setting** is a place with its own economy (section 3); a **portal** is a
  passage between places (section 4).
* No real religious practice and no real figures are shown (MYTH.md 7 stays in force); the deity names are only labels of Robert's choice.

## 2. Persons: personas, ages, life expectancy (`data/species.txt`)
Every wesen has one **persona kind**, a stored fact of its being record (LIFE.md 6.1, field `kind2`):

| kind | what it is | life expectancy | notes |
|---|---|---|---|
| `human` | born, grows, ages | **85 years** (`species.human.expect = 85`) | the base case |
| `cyborg` | a human who was augmented; **only from age 15, permanent** | **500 years** (`species.cyborg.expect = 500`) | a one-way event (`H kind=augmented`), never undone; a wesen below 15 cannot take it |
| `ai` | an artificial person | **none** (`species.ai.expect = 0` means "no end by age") | can still be lost by accident or a fault (LIFE.md 6.5 tables, `ai` rows) |

* **Numbers, not code.** `species.<kind>.expect`, `species.cyborg.min_age = 15`, `species.cyborg.permanent = 1`, hazard tables per kind in
  `data/mortality.txt` (LIFE.md 6.5). Age is derived from the born day and the world clock (LIFE.md 6.3: **600 ticks = 1 year**), so a human of 85 lives
  51,000 ticks, a cyborg of 500 lives 300,000 ticks, and the cyborg step at age 15 comes at 9,000 ticks of life. Robert's present save (3,400 ticks) is about 5.7 years: nothing here ends in a played run, as in LIFE.md.
* **How the expectation acts.** Not a hard cap but the centre of the hazard curve: the annual death chance rises around the expectation (for a human
  from about 60; certain only at `species.human.cap`, proposed 110; for a cyborg `cap` 650). This **replaces the flat "125 years" cap** of LIFE.md 6.5 by one number per kind
  (question 3). Players keep the 50,000-year scale of LIFE.md 6; deities are not personas.
* **Cyborg event.** At a session boundary a human wesen of at least 15 years may take the step if (a) its player allows it as a decision of the
  fifth kind (LIFE.md 2.4: `votes.txt` `kind=augment`, an `O`-like line), (b) its company (section 3) pays the cost (a cost in the ledger, section 8: `augmentation`, proposed
  400 coins; question 6). It changes: expectation, a few trait leans (+ patience, - warmth, data), the body words (LIFE.md 6.1 `body`) and its **energy cap** (+10, data), never its words, bonds or notebook.
* **Persona in texts.** `{persona}` is a text slot (LIFE.md 6.7): the voices and chat answers (Phase B) may say "I am a cyborg, thirty years in" when the field exists; before that they
  ignore it.

## 3. Twelve wesen and four settings (`data/settings.txt`)
Robert's picture: **three wesen per player, twelve in all**, each player group living in its **own setting** with its own economy. This is the same number as the recommended
`pop.max_alive = 12` of LIFE.md question 1 (32 slots, never reused); the first four wesen keep their ids and every old byte (LIFE.md 2.2). Each setting is a **company** of its player (LIFE.md 2.4),
and the setting decides which departments it has.

| player (deity) | id | setting | one-line economy | company departments (LIFE.md 2.4 ids; new ones marked +) |
|---|---|---|---|---|
| **Jehova** | iris | a **deserted island** | fish, salvage, little else; supplies by a boat that comes now and then | fishing+, salvage+, maintenance, **accounting+** |
| **Ganesha** | sol | a **farm in Albania** | grows and sells edible flowers at the farm market (section 5) | growing+, packing+, delivery+ (= transport), **accounting+**, records |
| **Krishna** (today's placeholder Odin: `noor = Krishna` in `names.txt`) | noor | a **village at a fjord** | boats, dried fish, a ferry, wool (sketch, section 7) | boatyard+ (workshop), ferry (transport), kitchen, **accounting+** |
| **Amaterasu** | vega | a **mountain town with a shrine** | a guest house, shrine care, pilgrims and a small market (sketch, section 7) | hospitality, shrine+, records, **accounting+** |

* **Settings are data.** `data/settings.txt` (planned) has one block per setting: `setting.<id>.player`, `.name_pool` (place words), `.climate` (seasons, weather odds for fish and
  growing), `.start_stock`, `.start_cash`, `.departments`, `.rent`, `.wage_base`, `.home_cell` (where its map lives, `docs/WORLD.md`), and the **observation list** (section 4). A setting is
  chosen per player by id in `data/players.txt`, so Robert can swap Jehova's island for another block without code.
* **Three wesen each:** a setting starts with its group: the three wesen of a player share the company's positions (LIFE.md 2.4 limits: positions < wesen, so work stays scarce). The existing four
  are placed by data (question 4), one in each group (Adam with Jehova, Eve with Ganesha, Abel with Krishna, Ruth with Amaterasu are placeholders). The 8 newborns are born into their player's setting by the birth rule
  (LIFE.md 2.2), 2 per session boundary at most at the start (`pop.births_per_session`, here proposed 2 until 12 are alive).
* **Separate worlds.** A setting has its own map and market; wesen of different settings do not meet unless a portal opens (section 4). This is also what makes the four economies comparable: same
  rules, different dice and goods. One `world=1` map per setting replaces the single treadmill map only for `settings=1` sessions (WORLD.md stays for the old sessions).

## 4. Portals and journeys (observations in the notebook and the journey file)
A **portal** is a named passage between two places: inside a setting (the farm to the town market) or between settings (the island to the fjord). A **journey** is one wesen (alone or with a companion) going through a
portal, doing something there for a few ticks, and coming back. The point is *observation*: what a wesen sees elsewhere is added to what it knows, in its own voice.
* **Portals are data** (`data/portals.txt`): `portal.<id>.from`, `.to` (setting + place), `.open` (always, or a window of ticks per day), `.cost` (energy per passage, 5 .. 25),
  `.who` (persona kinds allowed; a human child needs a companion), `.risk` (a die with a bound, `portal.<id>.risk_pct`), `.dwell` (ticks spent there). The island portal might open only at the supply boat times; the farm
  market portal every day.
* **Who goes, and when.** A wesen with free time (LIFE.md 4: spare time) may take a journey instead of a leisure action: a new action `travel` in the table, weight from curiosity and the persona (an AI travels more, a child less),
  gated by `exhaust=1` (no journey when spent, LIFE.md 2.6). Which portal is a hash roll over the open portals of its setting. A player may also **send** a wesen (an order of the fifth kind, LIFE.md 2.4); the Observer cannot force it.
* **What happens:** begin (tick, portal, energy paid) -> `dwell` ticks -> up to `journey.obs_max` (3) **observations** -> return. An observation is picked by `Pick60`-style dice (salt range below) from the destination's
  list in `data/observe.txt` (keys `observe.<setting>.<place>.<k>`: "the market stalls were already packed", "a net hung to dry with silver scales in it"), with a slot for the wesen's mood word. Each observation may name a **new word**
  (the study/look hook of LEARN.md 6: seen on the other side) and nudges mood by a small bounded amount (a good market +1, a hard sight -1; never more than `journey.mood_cap = 3`).
* **Records.** Two places, as LEARN.md 6 does: (1) the facts in **`diaries/journeys.txt`**, record-first like `visit.txt` (`Sim_Store`, replay-verified, a changed, invented or removed line is DRIFT):
  `P<n> t= s= wesen=<id> portal=<id> from=<place> to=<place> kind=begin|obs|back obs=<key> cost=<energy> word=<id or -> h=` (letter re-checked at build); (2) the **notebook line** in the wesen's
  `entities/<id>/notebook.txt` (LEARN.md 6.1, append-only working file, rebuilt by replay): "t=4210 through the market portal: the stalls were already packed. Learned 'nasturtium'." The notebook text is flavour; the `P`
  line fixes which key was picked, so a replay writes the same notebook byte for byte. Nothing secret from `ballots.txt` goes in (LEARN.md 6 secrecy rule).
* **Display only?** The first release is **observation without effect on the dice** beyond the mood step and the word: no goods, no money cross a portal except through the Accounting rules of section 8 (the farm
  delivering flowers to the town market is a *delivery*, not a journey).
* **Chat later (not built):** `/portals` (list), `/where <name>` (where a wesen is, where it has been), `@name where have you been?` answered from the `P` lines and notebook with templates in `data/chat.txt`. `/story` follows in section 9. All
  read-only: no chat order opens a portal or sends anyone (question 11).

## 5. The farm and its flower market (Ganesha's setting)
Incentive: **the farm only keeps running if the wesen earn money by delivering edible flowers**; wages, rent, seeds and repairs are paid from what they sell (section 8).
* **Flowers (`data/flowers.txt`):** a short list of garden flowers eaten as food, each with a growing time, yield, price and shelf life. Proposed (placeholders): nasturtium, pansy, calendula, borage, violet, chive
  blossom, squash blossom, rose petal. Per kind: `flower.<id>.grow = 40` ticks to harvest in season, `.yield = 12` pieces per bed per harvest, `.price = 6` coins per piece, `.shelf = 30` ticks, `.seed_cost = 1` per piece, `.pack_cost = 1`,
  `.season` (months of the setting's year, LIFE.md 6.3: a month = 50 ticks). Nothing is advice about real food safety; it is a game table.
* **Beds:** `farm.beds = 6` at the start (max 20 by investment), each bed one flower kind at a time: states `empty -> sown -> growing -> ready -> harvested`, a bed has a quality 0 .. 100 (soil, care) that scales yield (x0.5 .. x1.2).
  Weather dice from the setting's climate add or remove ticks (frost, dry spell); a replayed hash roll per bed per day, never a hidden state.
* **Price:** the farm has a **list price per kind** (set by the player's `price` decision, a bounded lever of the fifth kind: +/- 1 coin per session, within `price.min .. price.max` of the flower table). The price the customer pays is the list
  price, if within its tolerance.
* **Customers (`data/customers.txt` + dice):** each day the market rolls `market.customers_per_day` (2 .. 6) customers from a pool of types (café, family, restaurant, florist, a stranger). Each customer has: `demand` (pieces wanted, 3 .. 40), `kind` wanted (or any),
  `tolerance` (the highest price per piece it accepts, a number around the list price, 70 % .. 130 %), `deadline` (ticks within which the delivery must arrive, 20 .. 120), `distance` (cells or portal hops from the farm), and a
  `late_penalty` (the customer takes less or refuses). An order is **accepted** by the farm (a wesen in the market role, a decision with the usual dice, or the player by its price lever) only if price <= tolerance and stock can cover it.
* **Delivery:** the **delivery cost** of an order is `delivery.base + delivery.per_distance x distance` coins (fuel, a van, a boat) **and** energy for the deliverer (LIFE.md 2.6: paid through the one energy point); a delivery
  that arrives after the deadline is a *late sale* (price x `late_pct`, default 50 %) or is lost with the flowers back in stock (they spoil by shelf life). Long distances go through a portal (section 4); the passage cost adds to the delivery cost.
* **Who does what (positions, LIFE.md 2.4):** `grower` (sow, tend, harvest: energy cost 15 per shift), `packer` (pack harvest into orders: 8), `deliverer` (drive or walk to the customer: 12 + distance), and the three wesen of the group can hold at
  most one each (LIFE.md question 13). Missing a role leaves the work undone and the ledger shows it (stock rotting, orders lost). The *incentive* is plain: **no deliveries, no cash, no wages, no rent, no new beds.**
* **Output:** per day the department counts beds harvested, pieces packed, orders delivered on time (the department output of LIFE.md 2.4), and sales feed the ledger (section 8).
* **Honesty of the player (preport):** the deity reports the farm's money; its honesty trait can talk up a bad week by one band, `make audit` shows the ledger beside the claim (as LIFE.md 3.5).

## 6. The island (Jehova's setting): fish and salvage
A closed economy: little money moves; **stock and survival** matter. Money exists only when the supply boat comes (the island sells to it and buys from it at fixed boat prices).
* **Fish (`data/island.txt`):** `fish.catch_base = 4` pieces per fishing shift, scaled by weather and tide dice (`weather` table of the setting: calm x1.2, wind x0.8, storm x0), by gear (net, rod, boat: `gear` level
  0 .. 3), and by the fisher's skill. Fish keep `fish.fresh = 20` ticks, then must be dried or smoked (a **processing** shift that turns 3 fresh into 2 dried, `fish.dry_ratio`, dried keeps 400 ticks).
  The group eats first (a daily need from the life-support layer if `life=1`, LIFE.md 3, else a fixed `island.food_need`), the rest is stock.
* **Salvage:** after storms (a weather die) wreckage and goods wash ashore: `salvage.finds_per_storm = 0 .. 3`, each a find from `data/salvage.txt` (rope, planks, cans, a crate of tools, a radio, a bag of seeds), with a **value in coins**, a use (repair
  material for the maintenance department, gear upgrade, trade good) and a risk (a bruise: small energy loss). Salvage sorted and *stored* is stock; finds that are never used or sold have a holding cost of zero (they only take shelf place, `island.shelf = 30`).
* **The boat:** every `boat.every` ticks (proposed 150) a supply boat stops a few ticks (a portal window, section 4): it **buys** dried fish and salvage at `boat.buy.<item>` prices and **sells** fuel, nets, seeds, tools and
  tinned food at `boat.sell.<item>` prices (prices in `data/island.txt`; spread 20 %). Cash earned pays rent (a levy to the boat company), wages if the group chooses to pay itself (question 9) and gear.
* **Incentive:** nobody pays them to stay; without fish and salvage sold to the boat there is no fuel, no nets, no repair material, and the shelter decays (maintenance, LIFE.md 3.2).
* **Positions:** fisher, processor, beachcomber (salvage), keeper (maintenance), and the Accounting clerk (section 8) - three wesen, so most hold two small hats by shifts rather than two positions (LIFE.md question 13 stays: one position at a time; part-time positions exist).

## 7. The fjord village and the mountain town (short sketches)
Sketches only, to size the data; Robert has not specified their economies yet (question 8).
* **Fjord village (Krishna):** goods `boat_hull`, `dried_cod`, `wool`; services `ferry` crossings (price per passenger, timetable window = a portal), a boatyard that repairs boats (labour + materials); customers: fishers, tourists, the next
  village; weather dice for the fjord (fog, swell). Costs: timber, tar, fuel, wages, rent of the yard.
* **Mountain town with a shrine (Amaterasu):** goods `guest_night`, `meal`, `candle`, `offering_cake`; the shrine is a **place** with upkeep (cleaning, repairs, festival days from the calendar, `shrine.festivals` in the setting
  block) that costs money and brings pilgrims who book rooms and buy candles; seasonal visitors (snow, spring festival). The shrine is a fictional shrine in flavour text only (MYTH.md 7: no real practice, no real figures).
* Both use exactly the same ledger and customer machinery as the farm: a **customer** with demand, tolerance, deadline; a **product** with cost and price; a department that produces and one that delivers or serves.

## 8. The Accounting department: a double-entry ledger
Every company (setting) has a department **accounting** (a department of `data/departments.txt`, LIFE.md 2.4; role `bookkeeper` in `roles.txt`). A position there (clerk) keeps the books;
without a clerk the entries are still made by the simulation but **late** (posted at the session boundary, `late` flag) and the player's report says the books are behind.
The model is the **company model of LIFE.md**: each player owns a company, its departments produce, positions pay wages, a wesen's energy is the cost of labour. This section adds the money side.
* **Money is integer coins** (`ledger.unit = coin`, whole numbers, no decimals); amounts are `0 .. money.max` (10,000,000). PROOF-LATER: the sum bounds of the ledger fit in `Int` for `money.max x entries_per_session`.
* **Chart of accounts (`data/accounts.txt`):**

| group | accounts (id: word) | normal side |
|---|---|---|
| assets | `cash`, `stock_goods` (flowers, fish, boat goods: one account per good in the setting), `equipment` (beds, gear, van), `receivable` (customers who pay later, optional) | debit |
| liabilities | `wages_payable`, `rent_payable`, `loan` (optional) | credit |
| equity | `capital` (the start cash and stock from `settings.txt`), `retained` (profit carried), `current_result` (this session's profit, closed at the boundary) | credit |
| income | `sales` (per good), `other_income` (salvage sold, boat sales) | credit |
| costs | `cogs` (cost of goods sold), `seeds`, `packing`, `delivery`, `wages`, `rent`, `repairs`, `augmentation`, `spoilage`, `other_costs` | debit |

* **Entries (the journal).** Every money or stock event is **one balanced entry**: `sum(debits) = sum(credits)`, a date (tick), a reference (order, bed, shift), lines `account, side, amount`. Examples (flowers, price 6, cost 3 per piece, 10 pieces):
  * *sale (per-sale entry, two postings):* `Dr cash 60 / Cr sales 60`, and `Dr cogs 30 / Cr stock_flowers 30` (cost at the weighted-average cost of the stock: `cost_per_piece = stock_value / pieces`, integer division, the rounding rest goes to `cogs` so stock never goes negative);
  * *delivery cost:* `Dr delivery 12 / Cr cash 12`; *seeds bought:* `Dr stock_flowers (or seeds) 20 / Cr cash 20`; *harvest into stock:* `Dr stock_flowers 30 / Cr labour absorbed` is **not** used in the first release - production cost is the seeds and packing only, the wesen's time is
    paid through wages (question 7);
  * *spoilage:* `Dr spoilage x / Cr stock_flowers x` when shelf life ends; *wages:* `Dr wages w / Cr cash w` if affordable, else `Dr wages w / Cr wages_payable w` (a debt, paid first next time); *rent:* the same with `rent`; *late sale* has the reduced price; *a refused or lost order* has no entry (only a note).
* **Stock** is both a ledger account (value) and a physical count (pieces per good, batch ages for shelf life); the **stock check** at the session boundary compares them: value = pieces x average cost within rounding, else a
  `stock_diff` line is written (a check that fails the build's test, not a runtime surprise).
* **Wages and rent affordability.** At each pay point (`wage.every`, proposed every 100 ticks; rent `rent.every` 300) the clerk (or the simulation) tests: `cash - reserve >= wages_due + rent_due`, `reserve = ledger.reserve` (50 coins). Rule: **pay in this order:** rent, then wages by position (oldest unpaid first), as far as the cash goes; the remainder goes
  to `*_payable`. Two indicators go to the player's report and to the chat later (`/books`): **affordability** = `projected_income / fixed_costs` with `projected_income` the mean of the last `ledger.window` (3) sessions' income, fixed costs = wages + rent per session
  (< 1.0: "we cannot afford it": the position stays open, no hires, the player may lower a price, raise one, or close a position, LIFE.md 2.4); and **runway** = cash / costs per tick. Unpaid wages for `wage.strike_sessions` (2) sessions give the wesen of that position a mood drain
  and the petition `want_pay` (LIFE.md 2.5 style); they never lead to death or exit by themselves.
* **Session balance sheet and profit/loss.** At the session boundary (after the end report, before tick 1) the clerk **closes the period**: (1) profit/loss = income - costs, printed in a short block of the report; (2) the result is moved to `retained`; (3) the balance sheet:
  `assets = liabilities + equity` (cash, stock at cost, equipment at cost less `equipment.depreciation_pct` per session; payables; capital, retained); (4) the **trial balance** is checked: total debits = total credits over all entries of the session; failure is DRIFT-class (a bug, not a game event) and
  tested. The report shows, per setting: cash, stock value, income, costs, profit/loss, unpaid wages/rent, affordability and runway, in one 79-column block (the box style of the night header).
* **Who posts:** the simulation computes the amounts (pure functions of replayed state: orders, stock, wages due), and the **clerk's skill and energy** decide only *when* (late flag) and a small **error** chance (`ledger.error_pct`, default 0 in the first release; a mistaken entry would be a visible `fix` entry - a reversal and a correct entry, never an edit, which keeps the book append-only like every record file).
* **Records: `diaries/accounts.txt`** (planned, `Sim_Store`, record-first, replay-verified; letter `A` for an entry line, re-checked at build): `A<n> t= s= setting=<id> ref=<order|bed|shift|pay> dr=<acct>:<amount>[,<acct>:<amount>] cr=<acct>:<amount>[,...] note=<code> h=`;
  one line per entry, plus `A<n> ... close=session result=<profit> assets=<a> liab=<l> equity=<e> h=` per session. A replay recomputes every entry from the replayed orders and the data; a changed, invented or removed line, or an unbalanced one, is DRIFT. Marker `accounts=1`, new sessions only, off = byte-identical.
* **Not built here:** taxes, interest, loans between companies, currency exchange, depreciation schedules beyond the one rate (question 7 and LIFE.md question 16: companies do not trade in the first release; the island boat and the farm customers are **outside buyers**, not other players).

## 9. Stories and myths (`/story`, flavour only)
* **`/story [name|setting]`** (chat order, later, not built): prints a short story of 3 to 6 lines **condensed from real records** - the `P` journeys, the `A` entries (a good week, a bad week, an unpaid wage), petitions and outcomes, the
  notebook lines - joined by templates from `data/story.txt` (`story.<kind>.<k>`; kinds: journey, sale, loss, wage, birth, augmentation, storm, festival). A story is **text only**: it changes nothing in the simulation and, like the chat answers,
  is a pure function of the replayed state plus a seeded die (salts below), so a replay reproduces it.
* **From story to myth.** `docs/MYTH.md` stays the generator for the *players'* creation myths. The condensed stories of a setting are **raw material** for a second, slow layer: a *local myth* of the setting ("how the first catch came ashore", "the year the beds froze"),
  written to `MYTH.md`'s `M` records as `M kind=local` only after `myth=1` exists (MYTH.md 6.5). Until then `/story` is a read-only view and writes nothing to the diaries (it may appear in `diaries/chat.txt` as a chat line, like any answer).
* **Tone:** plain words, general audience, the persona and setting words from data; a cyborg's or an AI's story uses its own phrase list. No real religious practice and no real figures (MYTH.md 7).

## 10. Records, salts, markers, data files
| item | what | marker | salts |
|---|---|---|---|
| settings, 12 wesen | `data/settings.txt`, `species.txt`, `personas.txt`, `glossary.txt` | `settings=1` | 19000 .. 19099 |
| portals, journeys | `data/portals.txt`, `observe.txt`; `diaries/journeys.txt` (`P`), notebook lines | `portals=1` | 19100 .. 19299 |
| farm market | `data/flowers.txt`, `customers.txt`; orders and beds derived from the replay, deliveries in the ledger | `farm=1` | 19300 .. 19499 |
| island | `data/island.txt`, `salvage.txt` | `island=1` | 19500 .. 19599 |
| fjord, mountain | `data/fjord.txt`, `mountain.txt` | `fjord=1`, `mountain=1` | 19600 .. 19699 |
| accounting | `data/accounts.txt`; `diaries/accounts.txt` (`A`) | `accounts=1` | 19700 .. 19799 (errors, lateness) |
| stories | `data/story.txt` (no record in the first release) | none | 19800 .. 19899 |
* Salt ranges **19000 .. 19899** are new; the reserved/used ranges stay as in `docs/LEARN.md` and `docs/LIFE.md` (10000 .. 10699 life, 11000 .. 12999 myth, 13000 .. 13999 being, 14000 .. 14399 records, 15000 .. 15399 company, 16000 .. 16999 learning, 17000 .. 17999 reserved, 18000 .. 18499 voices and chat, 19900 .. 19999 vocabulary condensing, `docs/LEARN.md` 12, 20000 .. 20999 evolution of words and chess, `docs/EVOLVE.md` 8). Record letters are re-checked at build.
* Every file here follows the rules of LIFE.md 8: plain Ada, std lib only, all numbers and words in `data/`, record-first with replay verification, markers on the `S` line, new sessions only, **off = byte-identical**, `--help` and README current, checks extended
  in `scripts/checks.sh`, 0 warnings on GNAT 14 and 12, version headers, PROOF-LATER labels on the money arithmetic (no overflow, balance invariant, weighted-average rounding).

## 11. Build order, size and risk
Proposed steps, each one commit, each green on its own (sizes: Ada lines + data lines, rough):

| step | marker | what | size | risk |
|---|---|---|---|---|
| S1 | `settings=1` | `species.txt`, `glossary.txt`, persona kinds in the being record, ages and the cyborg step (needs `bio=1`, LIFE.md 6) | ~500 + 150 | M |
| S2 | `settings=1` | `settings.txt`, 12 wesen (3 per player, birth rule R2 of LIFE.md), one map per setting, `make settings` (read-only) | ~700 + 200 | **H** (touches `Entity_Id`, R2) |
| A1 | `accounts=1` | `accounts.txt`, the ledger package (integer amounts, balanced entries, trial balance), `diaries/accounts.txt`, session close block; fed first by wages and rent only | ~700 + 80 | M |
| F1 | `farm=1` | beds, flowers, customers, orders, grow/pack/deliver positions, sales into the ledger | ~900 + 200 | M-H |
| I1 | `island=1` | fish, drying, salvage, boat window, island ledger | ~600 + 150 | M |
| P1 | `portals=1` | `portals.txt`, journeys, observations, `diaries/journeys.txt`, notebook lines (needs LEARN.md `notes=1`) | ~600 + 200 | M |
| V1, M1 | `fjord=1`, `mountain=1` | the two remaining settings (sketches become data) | ~500 + 150 each | M |
| T1 | none | `/story`, `/portals`, `/books` chat orders, `data/story.txt`, chat templates for settings | ~400 + 150 | L |
Order: S1, A1 (can start right after C2 of LIFE.md), S2, F1, I1, P1, V1, M1, T1. Replay time grows with 12 wesen (about 3x today's at 12, LIFE.md 2.2): measure at S2 with `make bench`.

## 12. Open questions for Robert (recommended answer first)
1. **Names: Krishna in place of Odin?** *Recommend:* yes, as data only: `noor = Krishna` in `data/names.txt` (the id and every saved byte stay; Odin was a placeholder in the file). The fjord setting then belongs to the third player, id `noor`; if you prefer Odin for a fjord (Norse) setting, change the right-hand side
   back, nothing else.
2. **Glossary: Architect, Brahma, Observer, and the Ground of MYTH.md?** *Recommend:* keep all four words with fixed jobs: Architect in documents, Brahma in the world's own texts and myths, Observer for the reading/chat role word, "the Ground" only inside MYTH.md as the unnamed source. One `data/glossary.txt`, no word in Ada.
3. **Life expectancy: replace the 125-year cap?** *Recommend:* yes: per-kind numbers in `species.txt` (human 85, cyborg 500, AI none) with a soft rise of the hazard around the expectation and a hard `cap` per kind (human 110, cyborg 650) so that nothing lives for ever by accident; LIFE.md 6.5 tables become the per-kind tables. Wesen death stays shipped **off** as in LIFE.md question 3.
4. **Which persona kind do the first four have, and the start mix?** *Recommend:* by data in `personas.txt`: the existing four are `human` adults (ages 25 .. 40 rolled at genesis, ids and bytes unchanged); the eight new ones are born 1 human, 1 cyborg (already augmented, age >= 15), 1 AI per group in a mixed order.
   Their id stays; the persona only changes wording and a few small leans, never the dice streams.
5. **Does a cyborg get any penalty or privilege?** *Recommend:* only small leans (energy cap +10, patience +, warmth -) and a cost of 400 coins to the company; no new action, no new stat. Permanent, never reversible, only from age 15; a minor can not.
6. **Who pays for augmentation?** *Recommend:* the company (a ledger cost `augmentation`), decided by the player; if unaffordable it waits (no debt). A rare, remarked event in reports and `/story`.
7. **Is the wesen's time a cost of goods?** *Recommend:* no, in the first release: production cost is seeds, packing and delivery; labour is wages. Keeps the per-sale entry simple (two postings) and the balance sheet readable. Labour absorption is a later refinement.
8. **Fjord and mountain economies: what should they sell?** *Recommend:* build the farm (F1) and the island (I1) first; keep the fjord ferry/boatyard and the mountain guest house/shrine as the sketches of section 7 until you say more; they reuse the same customer and ledger machinery.
9. **Island money: is there any?** *Recommend:* only through the supply boat (fixed buy/sell prices, 20 % spread); inside the island nothing is sold, wages are paid in coins only if the group elects (`island.pay_self = 0` default: no wages, shares of the boat income go to `capital` and `retained`).
10. **How strict is the double-entry ledger?** *Recommend:* fully balanced, append-only, errors fixed by reversal entries, trial balance tested in `checks.sh` and a failure treated as DRIFT; no taxes, interest or loans in the first release.
11. **Portals: which chat orders, and may the Observer send someone?** *Recommend:* read-only orders only (`/portals`, `/where`, `/books`, `/story`); no chat order changes the simulation (as Phase B). Sending a wesen through a portal is a player's decision (a decision of the fifth kind), not the Observer's.
12. **How many settings at once?** *Recommend:* all four from `settings=1`, each at start with 3 wesen; a player's group never moves to another setting, only a visiting journey through a portal (no migration in the first release).
13. **Do journeys give anything beyond observations?** *Recommend:* only a word, a mood step (cap 3), a notebook line and a `P` record; goods and money cross a portal only as ledger deliveries (section 5) or the island boat (section 6).
14. **Where do the stories go?** *Recommend:* `/story` is a read-only view first (not recorded except as a chat line); a later `myth=1` step may promote some stories to local myths in `M` records. Flavour only, `myth.effects = 0` as in MYTH.md question 3.
15. **Currency name and size?** *Recommend:* "coin", whole numbers, prices of a few coins per piece, start cash 200 per setting (`settings.txt`); the spare-time credits of LIFE.md 4.3 stay a separate small counter and are never converted.
16. **Flower list: which ones?** *Recommend:* the eight in section 5 as placeholders in `flowers.txt`; Robert may replace them freely (rules there are numbers only; the game makes no food-safety claims).

*End of the proposal; nothing here changes the program until the steps of section 11 are started.*
