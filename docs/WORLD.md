# The treadmill world (world=1)

An endless grid that is generated around the wesen as they walk and is the same whenever they come
back. Only NEW sessions get it (they carry `world=1` on their `S` line); older diaries replay with the
old action table exactly and start the world at their next session. `world.enabled = 0` in
`data/limits.txt` gives byte-identical old output.

## What is generated, and from what
Every cell `(x, y)` has a key `1 + (x+16384) mod 32768 + 32768*((y+16384) mod 32768)`. Everything about
a cell is a pure function of `hash(seed, key, slot)` through the usual `Roll` / `Pick60` (base-60 lists
of `data/things.txt`: a D4 picks the block of 20, a D20 the entry). Nothing of an untouched cell is stored.

* biome: `Pick60(seed, key, 0, 8000)` from `[biome]` ("name glyph", about 15 biomes).
* things: slot 1 exists with `world.thing_percent`, slot 2 with `world.thing2_percent`.
* a thing = quality + shape + material ("red round stone"), each a `Pick60` from its list, plus a
  made-up name of 2-3 syllables from `[syllable]` (60 CV pieces). Its feel (`[feel]`, push) and taste
  (`[taste]`, eat) are further picks; the lists run pleasant, neutral, unpleasant in blocks of 20.
* chunks (`world.chunk`, default 8x8 cells) only group the stored edits; no chunk is ever cached, so memory
  is bounded by the edit log and cell content is computed on demand.

## Edits (the only stored state)
`diaries/world.txt`: `X<n> t=<tick> gone|add <ent>.<sub> <x>,<y> by=<wesen|world>`. A thing eaten is a
`gone`; pushed is `gone` + `add` one cell away; churn (every `world.churn` ticks, near each wesen) makes
a new thing appear, wear out or change (`by=world`). The replay regenerates the log; a stored line that
differs, or a stored line the replay never makes, is DRIFT (`err.world`); a deleted file is rebuilt. Each
session end also writes an `L` line to `diaries/sessions.txt` (`words=`, `edits=` and per wesen
`known/from-world/taught/coined@x,y`), checked like the `D/C/Y` lines.

## Walking, landmarks, meeting
Wander/explore step one cell: the direction is salted dice (`7920`) with a lean from the Rule 30 core
(`Core_Percent/25 mod 4`) and a soft pull home beyond `world.leash`. Office, lab, cafe and home are four
landmark cells near the origin (`world.lm0..3`); the nearest one (Manhattan) is the wesen's `location`,
so location votes, summaries and petitions work unchanged. Rest/work/bench/propose stay where they are. Talk
steps toward the nearest wesen within `world.sense`; a lesson needs a pupil on the same or a neighbouring
cell, so meetings are emergent.

## Verbs and words
The base action stays what karma and the reports count; in a world session it may be refined (chance
`world.verb.<action>`): explore/wander -> **examine** (learn the name and the quality word) or **push**
(feel word, mood by the feel block) or, wandering, **eat**; rest -> **eat** (taste word, energy by the taste
block); talk -> **greet** (a social word). A name passed on in a lesson may drift by one letter
(`[drift]`, `world.mutate_percent`): the variant is a new word with the same meaning.
Word ids are created lazily, so older sessions never create any.

## Seeing it
End-of-session report: `world +N/M` per wesen and the treadmill block (position, nearest landmark, biome,
5x5 window; glyphs in `data/things.txt`, digits = wesen, `*` = thing). `make map` / `--map` prints the four
windows as of the last session end (read-only). Menu: world words and places. Digest: `world.<wesen>` lines.

    treadmill  ada        gemini     replika    robert
    at         (1,13)     (1,12)     (4,12)     (0,13)
    near       home       home       home       cafe
    biome      tundra     canyon     orchard    meadow
               ^*o~*      ,:*=.      =..~n      *^*o~
               **2n#      ^*o~*      ~*nov      ***2n
               *41v.      **2n#      n#3Tv      ^*41v
               -Y~=*      *41v.      v.;^#      v-Y~=
               *.*.v      -Y~=*      =*-Y`      T*.*.

Changing a `world.*` number or a list of `things.txt` changes the world: an existing diary then needs `--fresh`.
