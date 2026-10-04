# Creation myths of the players (design only, nothing built)

Status: **proposal for Robert**, written after `docs/LIFE.md` and in the same style (`docs/MVP.md` does not exist in this tree; the
model is `docs/WORLD.md`): what it is, what it is made of, what is recorded, then the decisions. No code exists. Every number is a
*proposed default* that would live in `data/`; section 10 lists the questions with a recommended answer each.

## Contents
1. The frame: Ground, players, wesen
2. What the three source pages show (structure only)
3. The dimensions of a creation myth (the schema)
4. Mapping table: African, South American / Latin American, Hindu
5. The generator (data files, Rule 30 seeding, the 60-entry picks, name syllables)
6. How it shows in play (story, biography, report voice, values, petitions, `make myth`, the M record)
7. Respect: fictional mixes, flagged, never real practice
8. Coverage plan: all the global families
9. Build order, marker `myth=1`, size and risk
10. Open questions for Robert, with a recommended answer each

## 1. The frame: Ground, players, wesen
Robert's framing: *"Basically we are Brahman in this."* In the fiction there are three layers and the document keeps them apart:

| layer | who | in the program | what it is in a myth |
|---|---|---|---|
| **the Ground** | the human, Robert | the human player; no id, no entity, no Elo, no `Y` line | the unnamed ground of everything: it does not act inside the story, it *stirs* and *attends* (`make say`, a visit, a veto are its words) |
| **the manifestations** | the four players (Jehova, Ganesha, Odin, Amaterasu; names are data) | `iris sol noor vega` | each is a god-like manifestation of the Ground with its own story, domain and way of ruling |
| **the creatures** | the wesen (Adam, Eve, Abel, Ruth ...) | `ada gemini replika robert` | the made ones, watched by a player |

* **The human is not a fifth player.** It gets no myth of its own, no domain, no watch list. The Ground appears in every myth only
  as a *slot*: a phrase of the family ("the one beyond names", "the dreamer", "the breath") that is told at the start and at the end of a
  story. Whether it carries Robert's name is data (`myth.ground.name`, default empty: unnamed).
* This is a **literary device for the simulation**, borrowed from the structure of non-dual and emanation thinking (one ground, many
  faces), not a statement about any religion. Each myth can take a *stance* toward the Ground: devout, covenant, bargaining, playful,
  doubting, identical ("I am its face"). The stance changes wording and one small trait (6.4); it never makes the player disobey Robert's
  commands: vetoes, `say`, challenges work as they do today.
* A player's myth has **two parts**: where *it* came from (its rise out of the Ground, through older figures if the family has them) and
  how it made, or came to watch, its wesen.

## 2. What the three source pages show (structure only, paraphrased)
**African deities and mythological figures** (a list of names grouped by ~60 peoples, no stories). The unit is the **people**, not
the continent: Akan, Yoruba, Dahomey (Fon), Bakongo, Dinka, Nuer, Igbo, Zulu, Xhosa, Maasai, Songhai, Serer, Khoikhoi, Nubian and
many more. Recurring shapes: a distant **high creator** often *withdrawn* from daily life (the sky-god type) beside a **working
company of domain powers** (thunder, iron, rivers and sea, divination, earth); an **earth mother**; **paired or dual creators** (moon
and sun, twin pairs); the **trickster** as a sacred, necessary figure (messenger, opener of roads, bringer of culture and of trouble);
**water spirits**; **death** as a named power; **culture heroes and ancestors** who are close to people. So: *one distant ground, many
near agents, one cheeky go-between.*

**South American deities** (a small category: Andean peoples, Guaraní, Mapuche, Muisca, Rapa Nui, Brazil, Chiloé; entries such as
a mountain lord, a luck figure, a mine spirit, a fire serpent, a protector of animals, a possession spirit, a Patagonian power). The shapes
that stand out: **spirits of place** (mountains, mines, forests, fire in the marsh) rather than a ranked sky court; **protectors of
animals and land**; **layering and fusion** (colonial saints and mine devils, Afro-Brazilian and Venezuelan spirits: two sources
braided into one figure); and, from general knowledge outside the page, Andean **three-layered worlds** and **world ages** that end and
are made again, an earth-mother, and Amazonian **animal ancestors** and transformation. So: *the world is crowded with local powers
and is made, unmade and remade; fusion is normal.*

**Hindu deities** (an overview article). Shapes: **unity and multiplicity** (many deities seen as aspects of one ultimate ground,
Brahman, which is also the self in every being: the frame of section 1); **orientations rather than species** (devas and asuras:
the same origin, different direction; each person holds both); **triads of function** (creator, sustainer, ender; also three worlds
with eleven each); **descent** (an *avatar* comes to restore balance); the **goddess as power** (the consort or the mother as the active
energy); **families** (mother, father, son relations among deities); deities as **parts of the cosmos and of the body**; fierce and
gentle faces of one figure; a **chosen deity** per devotee; worship as **hospitality** (inviting, hosting, offering food and praise, taking
leave). So: *one ground that wears many faces, with balance and descent as the story engine.*

What all three agree on, and the generator must therefore model: **(a)** a ground or distant creator plus many near agents; **(b)** domain
powers with names and families; **(c)** a go-between or disturber; **(d)** creation by a *kind of act* (speak, think, form, divide,
give birth, sacrifice); **(e)** death, ancestors and the return of cycles; **(f)** exchange between gods and people (offering,
hospitality, naming).

## 3. The dimensions of a creation myth (the schema)
Twelve core dimensions plus the blend. Each is one **list of 60 entries** (three blocks of 20, section 5) in `data/myth.txt`; an entry
carries *family tags* and, where it matters in play, an *effect key*.

| # | dimension | question it answers | example values (generic wording) | used in play |
|---|---|---|---|---|
| 1 | **primordial state** | what was before? | still waters; a hush; a sleeping giant; an egg; a tangle of threads; a dark sky lying on the earth; breath without a body | story beat 1; mood of the voice |
| 2 | **the stirring** | what first moved? | a wish; a dream; a sound; loneliness; a crack; a counting; a quarrel | beat 2; the Ground slot |
| 3 | **creator type** | who/how many made it? | one; a pair (moon and sun, mother and father); twins; a council; a distant one with agents; a self that divides; one born of the ground | voice; governance lean (6.4) |
| 4 | **creation act** | by what act? | speaks; sings; thinks; breathes; shapes clay; weaves; forges; splits the whole in two; dives for the first earth; gives birth; gives itself up | beat 3; value lean |
| 5 | **material** | out of what? | red clay; reed; maize; a bone; a seed; sound; ash; copper; tears | beat 3/5; names of the wesen's make |
| 6 | **domains** (1 to 3) | what does the god keep? | sky, earth, waters, fire, storm, sun, moon, iron and craft, fertility, healing, roads, mountains, forests, animals, luck, home, order, the dead | epithets; **petition leans; the life-support services of LIFE.md** |
| 7 | **family relations** | who is kin to whom? | parent / child / sibling / twin / consort / teacher / rival / fosterling; succession by gift, contest or flight | biography graph among the four players |
| 8 | **tricksters and disturbers** | who spoils it and why is that needed? | a cunning small one; a thief of fire or words; a serpent; a giant who must be bound; a clown who breaks the rules and so makes rules | beat 6; honesty trait |
| 9 | **animal and ancestor forms** | who is near the people? | a bird messenger; a snake ancestor; a hare; a first mother; a hero; a totem family | companion, epithet, view of the wesen |
| 10 | **death and below** | why do things end, where do they go? | a road down and back; sleep; the ground takes them; rebirth in another shape; the ancestors stay close; scattering | beat 7; attitude to leaving/retiring wesen (LIFE.md 2.3) |
| 11 | **ages and cycles** | how long, and does it come again? | a breath in and out (the kalpa); successive suns; a flood or fire that ends an age; a retreat of the creator; a promised return | ties to `kalpas` / session length (6.4) |
| 12 | **reciprocity and asking** | what do gods and people owe? | offering; hospitality; naming; work; silence; keeping an order; gift for gift; a debt remembered; **what the gods ask of people** | `asks` (6.4), trust earning |
| 13 | **view of the made** | what are the wesen to it? | children; clay figures; servants; guests; partners; an experiment; mirrors; ancestors-to-be | voice, strictness, report words |
| 14 | **stance to the Ground** | how does it speak of the human? | devout; covenant; bargaining; playful; doubting; identical | voice, honesty (6.4) |
| + | **blend** | which second family colours it? | none; one other family strand (fictional mix) | tags, names, flagged in output |

Dimensions 1 to 5 and 11 make the **cosmos**; 6 to 9 the **pantheon**; 10, 12, 13, 14 the **bond with the made**.

## 4. Mapping table: how each source family fills the dimensions
"Family" below means a **tradition cluster** (a tag), not a continent: the African page shows that a continent is dozens of
different systems. Cells say what the *tagged entries* of that family lean to; they are structure, never a retelling.

| dimension | African clusters | South American / Latin American clusters | Indic |
|---|---|---|---|
| clusters shipped in wave 1 | **af-gulf** (Yoruba, Fon, Edo), **af-akan** (Akan and neighbours), **af-igbo** (Igbo, Ijo, Efik), **af-bantu-c** (Kongo, Luba, Fang, Nyanga), **af-bantu-s** (Zulu, Xhosa, Shona, Sotho), **af-nilo** (Dinka, Nuer, Maasai, Oromo, Gikuyu), **af-sahel** (Bambara, Fulani, Songhai, Serer), **af-khoi** (Khoikhoi) | **an-andes** (Inca, Aymara), **an-guarani** (Guaraní and Tupí), **an-mapuche** (Mapuche, Patagonia), **an-muisca** (Muisca), **an-amazon** (forest peoples: animal ancestors), **an-syncretic** (a *mode*, see blend), **po-rapanui** shared with Polynesia | **in-vedic** (nature powers, fire and sacrifice), **in-puranic** (triads, avatars, families), **in-shakta** (the goddess as the power), **in-nondual** (the Ground itself) |
| 1 primordial | water, a sleeping sky, an egg, "the unspoken" | dark water or a lake, a world before the sun, a hollow mountain | undifferentiated ground; waters; a golden egg; sound before things |
| 2 stirring | a wish of the distant one; a quarrel of twins; a drum-beat | a call from a lake or cave; the need for light | desire, breath, a dream, a churning |
| 3 creator type | distant high one + near agents; paired (moon/sun); twins | a lone maker who walks away; a mother of origin; a lord of ages | one ground in many forms; triad; the mother-power as source |
| 4 creation act | speaks, thinks, hammers (iron), shapes from clay, sets down from the sky on a chain | calls light up, shapes from clay or stone, brings out of water, sows | breathes out, sacrifices the first being, churns the waters, dreams |
| 5 material | clay, iron, calabash halves, river silt | stone, clay, maize, lake water | primal waters, a body of the first being, sound, light |
| 6 domains | thunder, iron, rivers, sea, divination, earth, the crossroads, smallpox/healing | mountains, mines, fire, rain, animals, the earth-mother, luck, hunting | sun, fire, wind, speech, wealth, learning, destruction, protection, the dead |
| 7 relations | high one withdrawn, children as the working powers; sibling pairs; the trickster as a younger go-between | siblings who share the world; heroes who reorder; a mother and her rainbow children | mother-father-son families; consort as power; rivals of the same origin (the two orientations) |
| 8 trickster | the sacred go-between (opener of roads), the clever small hero | the animal trickster; fire-serpents and spirits that test | the disturber who must be churned into use; the other orientation (asura-type) |
| 9 animal/ancestor | spider, hare, tortoise; ancestors as near powers | condor, serpent, jaguar, ancestors in animal form | animal vehicles, the bird, the serpent |
| 10 death | a named power; the ancestors stay as guardians; a road to the river | the underworld road; the ground takes and gives back | rebirth, the wheel, release; death as function |
| 11 cycles | the creator withdraws after finishing; ages of drought/flood | world ages ending and renewed; a turning-over of the world | cosmic breaths (kalpas), four ages, dissolution and re-making |
| 12 reciprocity | gift for gift; naming; offerings at shrines; keeping peace | offering to the land (reciprocity with the earth), feeding the mountain | hospitality: invite, host, feed, take leave; duty in balance |
| 13 view of the made | children and kin; the ones who must keep the world | guests of the land; the planted; the shaped ones | aspects of the same ground; reflections |
| 14 stance to Ground | devout (the far high one) or bargaining (with the near powers) | reciprocal | identical / devotion to the chosen face |
| blend modes | two clusters in one story | **syncretic**: a figure fused of two sources (the Latin American shape) | avatar-like *descent* of one strand into another |

Test of the design (acceptance, `scripts/checks.sh`): the generator must produce, for each shipped cluster, myths that use at least four
of its tagged entries per dimension in 20 samples, and the three oriented families (African, South American, Indic) must reach
**full** depth (>= 8 tagged entries per dimension) in wave 1. If it models these three well, the rest is more data, not more code.

## 5. The generator
### 5.1 Data files (all text in `data/`, none in Ada)
* `data/myth.txt` the dimension lists: `myth.<dim>.N = text | tags | effect-key`, N = 1 .. 60, plus the story grammar and the dimension
  weights. Example (generic wording, invented): `myth.prim.17 = a hush that was awake | af,in,*  | tone=still`.
* `data/mythfam.txt` the **families**: tag, display word, wave, depth (full/light), the **home table** (`home.jehova = ab`,
  `home.ganesha = in-puranic`, `home.odin = no`, `home.amaterasu = ja`; keyed by the display name in lower case), a **second-family
  strand** chance (`blend_pct`), the *avoid list* of real deity names (7.3).
* `data/mythsyl.txt` **syllable tables per family** (section 5.4) and name patterns.
* `data/mythtext.txt` story templates, the biography templates, the report voice clauses per creator type and stance, the headers.
* Numbers (`myth.reroll`, `myth.blend_pct`, `myth.effects`, effect sizes) in `data/limits.txt`.

### 5.2 Seeding: Rule 30 per player name and master seed
For each player a **myth row** = the existing Rule 30 machinery on `hash(master seed, player id, 11000)` (the player's *core* bits are
the ones that already give it warmth and brevity, so the myth and the temperament agree). The row gives three things: the player's
*lean* per tone (gentle / mixed / severe), its *openness* to a second family, and a tie-break stream. Every pick afterwards is
`Pick60 (Seed, Player, Beat * 10 + Attempt, Salt_Base = 11000 + 41 * Dim)` of `Sim_Util`: **D4 with a reroll on 1, 2/3/4 choose block 1/2/3
of 20, then a D20 inside the block** (the same rule as the world lists), a pure function of the seed, the player and the dimension, so
the myth is the same whenever it is rebuilt. Salt range reserved: **11000 .. 12999** (LIFE.md uses 10000 .. 10699; trial 9960 .. 9979).

### 5.3 Blocks, tags, rerolls
* **Block meaning:** within every list block 1 is the *gentle* register (ordering, giving, nourishing), block 2 *mixed*, block 3 *severe*
  (breaking, taking, binding). The D4 therefore gives a tone; the player's lean may push a block-3 result to a reroll with the
  chance `myth.tone_pull` (a warm player tells gentler stories, never a rule).
* **Family filter:** an entry whose tags do not include the player's home family, its blend strand or `*` (universal) is rerolled
  (next attempt) up to `myth.reroll` (3) times; the 4th result is taken as it is. So a list of 60 can serve 16 families at once with each
  family owning a few entries per list; coverage is *measured* (8.2), not hoped.
* **No copying:** entries are original generic phrases of the kind the sources show (a hush, a churning, a sky on a chain), never
  sentences or names from a text. Fixed phrases such as titles are written fresh.

### 5.4 Names: syllable tables per family
A god's name is 2 to 3 syllables from the family table (60 syllables in 3 blocks of 20, same pick rule), plus an optional title from a list
("the one who keeps the roads open" style, original wording). The tables give the *sound shape* of a family without borrowing real
names: e.g. an African-cluster table leans to open CV syllables with some prenasalised onsets (`ko ba nde ya ... `), an Andean one to
`qu ch ll` onsets and `-ay -uq` endings, an Indic one to long vowels and `-ya -ra -sha`, a Norse one to clusters and `-ir -ar`, a Japanese one
to light open syllables, a Polynesian one to open syllables with doubled vowels. A name that equals an entry of the **avoid list** (real
deity names, a few hundred, in `mythfam.txt`) is rerolled; the four player labels are the only real names that appear, because Robert chose them.

### 5.5 The story grammar
Seven beats, each a template with slots filled from the picks: (1) before: primordial + the Ground slot; (2) the stirring; (3) the
making: creator (type, name), act, material; (4) the divisions: sky/earth/waters and the first powers (domains, relations); (5) the
**making of the made**: how the wesen were made, from what, and what they are (view of the made; the names of the wesen come in through the display names);
(6) the **disturbance**: the trickster/disturber and what it cost or gave (also why death exists, dimension 10); (7) the compact: what is
asked and owed, the age we are in (the `yuga.N` words of the kalpa layer), and the Ground slot again. Slots missing in a family are
skipped, so short myths are normal. A story is 12 to 16 lines of at most 78 columns.

## 6. How it shows in play
### 6.1 At the start
In the first `myth=1` session the console says two lines ("Four tellings of the beginning are now recorded. make myth"), and each
player's first inbox message to Robert opens with the first line of its story. No wall of text.

### 6.2 `make myth` / `--myth`
`make myth PLAYER=Ganesha` (any spelling: `Jehova`, `Player 1`, `1`, id) prints, read-only and replay-verified: the header (7.2), the
story (12-16 lines), the **biography** and the relations; `make myth` alone lists the four with one line each and the Ground line.
Sample (invented; the shape, not a text):

    == Ganesha: how the world began (a made-up story in the Indic manner with an Andean strand; not scripture) ==
    Before the first counting there was a hush, and the hush was awake. Behind it, the Ground, unnamed, watched without watching.
    Something in the hush wished to be heard. That wish was the first ripple; the Ground did not move.
    Out of the ripple came Oruvhana, who churned the still water until it gave up butter-light and a hard dry shore.
    ... [domains, the older kin, the making of the four small ones from river clay]
    A small cunning one, Tiqay, stole the first word and so taught them to ask. That is why they petition.
    What is asked: that the little ones rest, speak and keep the order; what is owed: a hearing in return. We live in the fourth age.
    -- biography: origin the high shore; rise: given the keeping of speech by an older sister; rivals: Odin; domains: speech, rivers.

### 6.3 Biography
Origin (a place from a 60-list), **rise** (inherited, won in a contest, given, asked for, left behind, found), **rivals** (up to 2:
another player or a mythic rival), **domain** (1 to 3 from dimension 6), three epithets, a companion form (dimension 9) and the **relation
to each of the other three players** (dimension 7, directed: sister of, foster-child of, rival of ...). The relations are rolled once
per unordered pair, so the four stories agree with each other (a sister in one is a sister in the other). The existing role words of
`data/players.txt` ("keeper of the quiet hours") stay as the *office*; the myth adds the *origin*.

### 6.4 Effects (small, bounded, data; the first release is flavor only: `myth.effects = 0`)
| dimension | effect when `myth.effects = 1` | bound |
|---|---|---|
| creator type, view of the made | report voice (a clause per type: "my little ones", "the made", "my guests") | wording only |
| creation act, creator type | governance lean: shaper/forger +work-petitions generosity, speaker +brevity change, separator +strictness, giver +warmth | +/- 5 on `Warm_Of`/`Brev_Of` |
| domains | petitions of the matching topic (and, with LIFE.md, the matching **service**: water god, water shortage) are granted a little more readily | +5 points on the score, never past the lever bounds |
| trickster, stance | honesty trait: a trickster-touched player may exaggerate (comic, not hostile); a "covenant" stance lowers misreport chance | +/- 5 honesty; audit unchanged |
| ages and cycles | preference in `nextticks` (cyclic types like round numbers 100 / 400) | the existing rounding rule only |
| death and below | wording of leaving/retiring wesen (LIFE.md 2.3), liberation messages | wording only |
| reciprocity, **what the gods ask** | `asks` = one action family (rest, work, talk, learn, keep order); trust in a wesen rises +1 per session if it did that act at least `myth.ask_min` times | +1 trust per session |
| stance to the Ground | how a player calls Robert in its box ("Robert", "Ground", ...) | wording only |
All effects apply only in `myth=1` sessions, so replays of older sessions are unchanged. Nothing here changes the veto / approve / say rules.

### 6.5 The M record (replay-checked)
Record-first, like the other layers: `diaries/myth.txt` (`Sim_Store`), own salts 11000 .. 12999:

    M1 t=3401 player=iris home=in-puranic blend=an-andes tone=1,2,1 prim=17 stir=4 ctype=9 act=33 mat=51 dom=6/12 ... ground=2 stance=3 h=48211
    M2 t=3401 pair=iris/sol rel=sister-of h=1177

The line stores the **picks** and `h=`, a hash of the *rendered text* with the data in force: if a data file is edited later, `h=` no longer
fits and the replay says DRIFT with "myth text changed: data/myth*.txt" (like the other record files: changing the data of a running save needs `--fresh`
or a version bump of the myth data, `myth.data_version` in the line). A changed, invented or removed M line, or a removed `myth=1` marker, is DRIFT.
The myth is generated **once**, at the start of the first `myth=1` session (Robert's save: tick 3401), and then fixed.

## 7. Respect: fictional mixes, flagged, never real religious practice
1. **Fiction, flagged.** Every output of the story carries the header "a made-up story in the manner of ... (mixed with ...); not scripture", in `make myth`, the README and `--help`.
2. **No texts, no rites.** No sentence from a scripture, hymn, prayer or ritual; no instructions to worship; nothing a believer would use. Offerings and hospitality are *story elements* in game words.
3. **No real deity names are generated.** Syllable names are checked against an avoid list; the only real names are the four player labels Robert chose. A player's label is a name tag, **not** a claim that the player is that deity; Robert may rename them in `data/names.txt` at any time.
4. **Living traditions get structure, not figures.** For families that are lived religions (Abrahamic, Hindu, Shinto, the Yoruba-derived and many Indigenous traditions) the entries describe *shapes* (a creator by word, a ground in many faces, a go-between) and never narrate sacred events or secret/restricted content. For Aboriginal Australian, North American and Siberian/Inuit families the default is **off** (`family.*.enabled = 0`) until Robert decides; they are listed in 8 as planned, not shipped.
5. **No stereotypes by family.** Roles come from the dice, not from the family: a family never makes a player the villain, the trickster or the weak one; every family has the full range of tone (blocks 1 to 3).
6. **Equal depth.** A family is shipped only when it reaches its stated depth; no "exotic filler".
7. **Gentle wording.** Violence and birth are told in plain, non-graphic words; no sexual content (content rating: general audience).
8. **Provenance.** `docs/MYTH.md` lists what each cluster's entries were modelled on (type of source), so Robert or a reader can correct them.

## 8. Coverage plan: all global families
Depth: **full** = >= 8 tagged entries per dimension and a full syllable table; **light** = >= 3 per dimension; **structure** = shapes only.

| wave | families (tags) | depth | note |
|---|---|---|---|
| universal | `*` entries (~15 per list), neutral syllable table | full | the fallback; keeps any unknown name working |
| **1 (build)** | **African clusters** (8 above), **South American / Latin American** (andes, guaraní, mapuche, muisca, amazon, syncretic mode), **Indic** (4) | **full** | Robert's oriented set |
| 1b (the four labels) | `ab` Abrahamic (structure: creation by word, ordered days, covenant), `no` Norse (a cosmos of nine layers, a world-tree, giants and kin), `ja` Japanese (islands from a stirred sea, sun and storm kin, spirits of place), `in` already | light | so Jehova, Odin, Amaterasu have a native strand from day 1 |
| 2 | Greek, Egyptian, Mesopotamian | full | shared motifs: primordial waters/chaos, succession by overthrow, the sun's journey |
| 3 | Celtic, Slavic, Chinese | full / light | cosmic egg and giants, dual powers, ancestors and order |
| 4 | Polynesian (with Rapa Nui), Melanesian | full | land fished up from the sea, ancestors, voyaging, tapu-like restriction (structure only) |
| 5 | Aboriginal Australian, North American, Siberian / Inuit | structure, **off by default** | living and often restricted; only after Robert decides and a review (question 5) |
`make myth-coverage` (read-only) prints entries per family per dimension, so gaps are visible; checks fail if a *shipped* family is under its depth.

## 9. Build order, marker `myth=1`, size and risk
Every step is one commit with its own checks scenario, README / `--help` lines, version headers, 0 warnings on both compilers, `make portable` green, and
**marker off = byte-identical** (proved by `offcmp2` against the previous tip). Markers: `myth=1` (new sessions only); `myth.enabled = 0` in limits.txt turns it off.

| step | what | size (Ada + data) | time | risk |
|---|---|---|---|---|
| M1 | schema, lists for universal + the three oriented families, syllable tables, `Sim_Myth` as a **pure function**, `make myth` / `--myth` computed on the fly (no record, no marker) | ~600 + 900 data lines | 2-3 days | L (no save impact) |
| M2 | marker `myth=1`, `M` records in `diaries/myth.txt`, replay check, session-start two lines, first inbox line; flavor only | ~300 + 100 | 1-2 days | M |
| M3 | biography, relations (pair rolls), rivals in the report box; `make myth-coverage` | ~300 + 200 | 1-2 days | L |
| M4 | effects (6.4), each behind `myth.effects`, one scenario per effect, small bounds | ~250 + 60 | 1-2 days | **M-H** (touches governance / honesty dice: only in `myth=1` sessions) |
| M5 | wave 1b light families for the four labels | ~0 + 500 data | 1 day | L |
| M6+ | waves 2 to 4 (data only, one family per commit); wave 5 only after the decision | data | ~1 day per family | L |
Size: Ada +~1500 lines, data +~3000 lines (the data is read at run time; the binary grows ~0.15 MB). Dependencies: needs the player layer
(the four players); independent of LIFE.md (the domain / service link is optional wording), and it reuses `Pick60`, the Rule 30 rows, `Sim_Store` and the display names.
Rules kept: plain Ada, text in `data/`, every roll `hash(seed, entity, tick, salt)`, state by replay, PROOF-LATER labels on the arithmetic, compact output (`debug.txt` <= 1500 bytes).

## 10. Open questions for Robert (recommended answer first)
1. **Fixed or re-rolled when a player is renamed?** *Recommend:* fixed. The M record is authoritative; renaming Odin to another
   name later changes nothing. A deliberate `make myth PLAYER=x NEW=1` writes a superseding M line (an input record like a veto).
2. **How is the home family chosen from the name?** *Recommend:* a table in `data/mythfam.txt` keyed by the lower-case display name
   (`jehova` -> Abrahamic structure, `ganesha` -> Indic, `odin` -> Norse, `amaterasu` -> Japanese); unknown names get a family by Rule 30 among
   the shipped ones; a second strand with `blend_pct` 25. So Robert can test the African and Andean sets by renaming a player (e.g. to a made-up name).
3. **Flavor only first, or effects from the start?** *Recommend:* flavor only (`myth.effects = 0`) through M3; effects in M4 with small
   bounds, one switch, so Robert can see the stories before they touch the dice.
4. **Are real deity names allowed in generated text?** *Recommend:* never; only the four labels Robert chose. Fictional syllable
   names, avoid list enforced by a check.
5. **Which living-tradition families are allowed, and how deep?** *Recommend:* Abrahamic, Hindu, Shinto-like: structure only and no
   figures (7.4). Aboriginal Australian, North American, Siberian/Inuit: **off** until you decide, and then only structure, ideally after a
   review by someone from or close to those traditions.
6. **Is the Ground named?** *Recommend:* unnamed by default ("the one beyond names", family wording); `myth.ground.name` can hold "Robert".
   The Ground never gets a player id, entity, myth or Elo; stances change wording and one small honesty step, never obedience.
7. **Content rating?** *Recommend:* general audience: killing and birth in plain, non-graphic words; creation "by sacrifice" is allowed as
   a story element, no gore, no sexual content.
8. **Do the wesen get myths of their own?** *Recommend:* no. A wesen's origin is one or two lines inside its player's story (view of the
   made, dimension 13); a separate myth per wesen is a later idea once LIFE.md brings newborns.
9. **Do the myths connect to LIFE.md?** *Recommend:* yes, lightly: domains use the same keys as the services (water, air, heat,
   power) so a water-keeper is slightly more generous to a water petition; new wesen are "made in a later age". No build dependency.
10. **When is the myth generated for the existing save (tick 3400, session 10)?** *Recommend:* at the start of the next new session with
    `myth=1` (tick 3401), no `--fresh`, earlier sessions byte-identical; the four stories appear in `make myth` and as the first inbox line.

## Sources consulted (structure only; nothing quoted)
* https://en.wikipedia.org/wiki/List_of_African_deities_and_mythological_figures (names by people; no narratives)
* https://en.wikipedia.org/wiki/Category:South_American_deities (a short list by people and region)
* https://en.wikipedia.org/wiki/Hindu_deities (overview: devas and asuras, Brahman, triads, avatars, worship as hospitality)
Statements marked "general knowledge" in section 2 (Andean worlds and ages, Amazonian animal ancestors) are not from these pages.

*End of the proposal; nothing here changes the program until the steps of section 9 are started.*
