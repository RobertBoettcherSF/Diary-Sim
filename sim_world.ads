--  Version: 0.017
--  The shared world of diary_sim: the four entities, the vocabulary (base
--  words, who knows what, coined words), the bench kernels and the final votes.
--  One world per run; Init rebuilds it from scratch, so a replay from tick 1
--  always reaches the same state.  Standard library only.
pragma Ada_2022;

with Ada.Strings.Unbounded;
with Sim_Util;

package Sim_World is

   use Sim_Util;

   type Entity_Id is range 1 .. 4;
   function Name (E : Entity_Id) return String;   --  ada gemini replika robert
   --  Display names (data/names.txt, "<internal id> = <display name>"): only for text shown to people.  The
   --  internal ids (Name, Player names of players.txt) stay the hash keys, file names and recorded tags.
   procedure Load_Names (Lines : Sim_Util.Str_Vectors.Vector);
   function Display (E : Entity_Id) return String;
   --  Text with every whole-word internal id replaced by its display name (file names, tags after ':' and
   --  words glued to '/', '-', '.ext' are left alone; a table column keeps its width where it can).
   function Show (Text : String) return String;
   function Internal_Id (Text : String) return String;   --  display name (any case, also an "alias" of data/names.txt) or id -> internal id, else Text
   function Kind (E : Entity_Id) return String;   --  engineer reviewer vice_president human

   --  Diary word lists (data/words.txt): action texts, mood tones, vote reasons.
   type List_Id is (Rest, Work, Explore, Talk, Wander, Bench, Propose, Learn,
                    Mood_Low, Mood_Neutral, Mood_High, Reason_Low, Reason_Mid, Reason_High,
                    Wish_Open, Wish_Close,
                    Examine, Push, Eat, Greet);   --  the world verbs (world=1 sessions only, Sim_Things)
   subtype Action is List_Id range Rest .. Learn;   --  Learn is never rolled: it delivers a lesson
   subtype World_Verb is List_Id range Examine .. Greet;
   Words : array (List_Id) of Sim_Util.Str_Vectors.Vector;

   --  ---- vocabulary ------------------------------------------------------
   --  Word ids: 1 .. Base_Count are the lines of data/vocab.txt, coined words follow.
   --  Init: base words, then each entity's start slice = a deterministic random
   --  share of Start_Percent (hash (seed, entity, 0, 1000 + id)).
   procedure Init (Base_Words : Sim_Util.Str_Vectors.Vector; Seed, Start_Percent : Int);
   function Base_Count return Natural;
   function Count return Natural;
   function Word (W : Positive) return String;
   function Knows (E : Entity_Id; W : Positive) return Boolean;
   --  From: the entity that taught the word (0: nobody, e.g. a start word).
   procedure Learn_Word (E : Entity_Id; W : Positive; From : Natural := 0);
   function Find (Text : String) return Natural;   --  0: no such word
   function Add_Coined (Text : String; P1, P2 : Natural; By : Entity_Id) return Positive;
   function Parents (W : Positive) return String;   --  "hand+phone" or "" for a base word
   --  Where E's word W came from: "start" (start slice), "taught by <id>" or "coined by <id>".
   function Origin (E : Entity_Id; W : Positive) return String;
   function Coined_By (W : Positive) return String;   --  entity name, "" for a base word
   --  ---- words from the world (Sim_Things, world=1 sessions) ----------------------------------
   --  Kind: 1 = the made-up name of a thing, 2 = a property / social word, 3 = a dialect variant
   --  of a name (Variant_Of is the word it drifted from).  Meaning is the description.
   function Add_World_Word (Text, Meaning : String; Kind : Positive; Variant_Of : Natural := 0) return Positive;
   function Kind_Of (W : Positive) return Natural;       --  0: base or coined word
   function Meaning_Of (W : Positive) return String;
   procedure Learn_From_World (E : Entity_Id; W : Positive);   --  learn W by meeting it (origin "world")
   --  symbols=1 sessions (docs/EVOLVE.md 9): a SYMBOL word (a chess coordinate string e2e4 or a numeric string 5254, made by an older session)
   --  is Blocked: it is not learned, not taught (Teachable_*) and not blended; whoever already knows it keeps it.  Off: nothing is blocked.
   procedure Hide_Symbols (On : Boolean);
   function Blocked (W : Positive) return Boolean;
   --  active=1 sessions (Sim_Active, docs/EVOLVE.md 13): a DORMANT word of E stays known (words.txt, Known_Count) but while dormancy
   --  is on it is Asleep: not taught (Teachable_*), not coined or blended from (Nth_Usable), not learned from E's screen, not put on a
   --  screen by init, not a favourite.  Off: nothing is asleep and every count and pick is the old one.
   procedure Use_Dormant (On : Boolean);
   procedure Set_Dormant (E : Entity_Id; W : Positive; On : Boolean);
   function Is_Dormant (E : Entity_Id; W : Positive) return Boolean;   --  the flag, whether dormancy is on or not
   function Asleep (E : Entity_Id; W : Positive) return Boolean;       --  dormant and dormancy on
   function Dormant_Count (E : Entity_Id) return Natural;
   function Usable_Count (E : Entity_Id) return Natural;               --  Known_Count without the asleep words
   function Nth_Usable (E : Entity_Id; N : Positive) return Positive;  --  Nth_Known over the words that are not asleep
   function Is_Start (E : Entity_Id; W : Positive) return Boolean;     --  a base word of E's start slice (never dormant)
   function Is_Symbol (W : Positive) return Boolean;                   --  a chess coordinate or number text (out of the pool)
   --  active=2 sessions (Sim_Active, docs/EVOLVE.md 14): MINT-SLOW and WAKE BY LESSON.  A wesen that held at least the cap of active
   --  words at the last session end is Slow: a new word reaches it only when a die lets it through (Slow_Pass: salt 20870 a lesson,
   --  20871 a coined word, 20872 a word learned from a screen, 20873 a screen blend; the percent of each kind, the params line of
   --  active.txt).  Wake_Teach: a word the pupil has asleep may be taught again (it wakes, nothing new is minted).  Off: the old rule.
   type Slow_Kind is (Slow_Lesson, Slow_Coin, Slow_Screen, Slow_Blend);
   procedure Set_Slow (E : Entity_Id; On : Boolean);
   function Is_Slow (E : Entity_Id) return Boolean;
   procedure Set_Slow_Pct (K : Slow_Kind; Pct : Natural);
   function Slow_Pass (Seed : Int; E : Entity_Id; Tick : Int; K : Slow_Kind) return Boolean;   --  not slow, or the die lets it through
   procedure Use_Wake_Teach (On : Boolean);
   function World_Learned (E : Entity_Id) return Natural;     --  words E learned from the world
   function Taught_Count (E : Entity_Id) return Natural;      --  words E learned in lessons
   function Coined_Count_By (E : Entity_Id) return Natural;
   function Coined_Total return Natural;                      --  coined words of everybody
   --  Words E knows / words From knows and To lacks (active=2: or To has asleep, Use_Wake_Teach), and the N-th of each.
   function Known_Count (E : Entity_Id) return Natural;
   function Nth_Known (E : Entity_Id; N : Positive) return Positive;
   function Teachable_Count (From, To : Entity_Id) return Natural;
   function Nth_Teachable (From, To : Entity_Id; N : Positive) return Positive;

   --  ---- personality: Rule 30 + state-driven action weights -------------------------
   --  Each entity has a ring of rule30.width bits (Rule 30: new = left xor (centre or
   --  right)).  Its start row is hashed from (seed, entity); it is stepped once per
   --  rule30.period ticks, so the row at tick T is a pure function of (seed, entity, T)
   --  (the cache only saves time; a resume rebuilds it by replay).  Six segments of the
   --  row lean the six rolled actions up or down: the segments of the start row are the
   --  entity's constant core personality (rule30.core points), the segments of the current
   --  row are its slow drift (rule30.strength points).  The
   --  state leans them too (low energy: rest; high energy: work, bench; low mood: talk,
   --  explore; few known words: talk).  Choose rolls once with Roll (salt 0) over the
   --  total weight.  rule30.enabled = 0 gives the old fixed D20 table.
   --  PROOF-LATER: Importance 4/10, Urgency 3/10, SPARK2 (bit arithmetic, weight sums > 0)
   --  Work_Pct: percent kept of the work and bench weights (a cool-down after a work burst, rest=1 sessions).
   function Choose (Seed : Int; E : Entity_Id; Tick : Int; Energy, Mood : Integer; Work_Pct : Natural := 100) return Action;
   --  Recovery rate in percent (rest=1 sessions): rest.rate.min .. rest.rate.max in limits.txt by 32 sampled bits of the
   --  wesen's Rule 30 birth row (100 = the base gain of a rest).
   function Recovery_Rate (Seed : Int; E : Entity_Id) return Natural;

   --  ---- petitions ------------------------------------------------------------------
   --  The propose action files a wish for a change in its own world.  Topics come from
   --  data/topics.txt (name, five weights, phrase); the topic is rolled by state-weighted
   --  dice, the wording from the [wish_open] / [wish_close] lists (base-60 picks).  All of
   --  it is a pure function of (seed, entity, tick, state); a replay rebuilds the list.
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (parsing the topic table, weight sums)
   procedure Load_Topics (Lines : Sim_Util.Str_Vectors.Vector);   --  call before Init
   function Topic_Count return Natural;
   --  Files a petition by E at Tick (state: energy, mood, benches so far); returns its number P<n>.
   --  Strain 0 .. 100 (rest=1 sessions): how long this wesen's cool-down is; topics with a 'cooling' column gain weight.
   function File_Petition (Seed : Int; E : Entity_Id; Tick : Int; Energy, Mood, Benches : Integer; Strain : Natural := 0) return Positive;
   function Petition_Total return Natural;
   function Petitions_Of (E : Entity_Id) return Natural;
   function Petition_Topic (N : Positive) return String;
   function Petition_From (N : Positive) return Entity_Id;
   function Petition_Tick (N : Positive) return Int;
   function Topic_Id (Name : String) return Natural;   --  0: no such topic
   function Asked (E : Entity_Id; Topic : Positive) return Natural;   --  petitions of E on the topic so far
   function Is_Recovery_Topic (Topic : Positive) return Boolean;      --  has a 'cooling' weight (more_rest, faster_work_recovery)
   --  A grant: E does not file this topic again (a granted wish stays granted); Mark_Petition tags P<N> with G<G>.
   procedure Grant (E : Entity_Id; Topic : Positive);
   procedure Mark_Petition (N : Positive; G : Positive);
   --  govern=1: a refused petition makes the next one on the same topic likelier (Amount added to that topic's weight until E files it).
   procedure Add_Urgency (E : Entity_Id; Topic : Positive; Amount : Natural);
   function Petition_Line (N : Positive) return String;   --  P<n> tick=<t> from=<id> topic=<topic> [repeat=<k>] wish=<text>
   function Top_Topics (N : Positive) return String;      --  "more_rest 5, quieter_mood 4"

   --  ---- ballot for the collective petition (record only; own salt 5010) ---------------------
   --  Each wesen votes for one petition topic: the weight of a topic is the number of petitions on
   --  it since tick Since (any wesen) + 2 per petition of its own; with none since Since, the whole
   --  list counts.  0: no petition at all.  A pure function of (seed, entity, tick, petition list).
   --  PROOF-LATER: Importance 2/10, Urgency 2/10, SPARK2 (weight sums, cumulative pick)
   function Ballot_For (Seed : Int; E : Entity_Id; Tick, Since : Int) return Natural;
   function Topic_Name (T : Positive) return String;
   function Topic_Phrase (T : Positive) return String;
   --  Percent (0 .. 100) of the 1-bits in the entity's birth row (its core Rule 30 personality).
   function Core_Percent (Seed : Int; E : Entity_Id) return Natural;

   --  ---- kalpas: the session length vote --------------------------------------------
   --  Every entity votes for the number of NEW ticks of a session: a base-60 pick
   --  (block of 20 = short / medium / long, then the entry) from hash (seed, entity, session
   --  start tick) in the table of data/kalpas.txt, the block leaned by the entity's state at
   --  the session start.  The decided length is the median of the four votes.
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (index arithmetic, clamps)
   type Kalpa_Votes is array (1 .. 4) of Int;
   procedure Load_Kalpas (Lines : Sim_Util.Str_Vectors.Vector);   --  call before the first vote
   function Kalpa_Count return Natural;
   function Kalpa_Vote (Seed : Int; E : Entity_Id; Start : Int; Energy, Mood : Integer) return Int;
   --  Sorted v1 <= v2 <= v3 <= v4: (v2 + v3) / 2, rounded down (duplicates are fine).
   function Kalpa_Median (V : Kalpa_Votes) return Int;

   --  ---- favourite word (the end-of-session word vote of the wesen) ----------------------
   --  Each entity names one favourite among the words it knows: weight 1 + how often the word
   --  came up for it (learned +2, taught, coined, used as a parent), x3 for words that are not
   --  start words when mood >= mood.tone_high, x3 for start words when mood <= mood.tone_low.
   --  Rolled with its own salt (960) from hash (seed, entity, tick): no existing dice are used,
   --  so old diaries stay valid.  0: the entity knows no word.
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (weight sums, cumulative pick)
   procedure Use_Word (E : Entity_Id; W : Positive; Amount : Positive := 1);
   function Favourite (Seed : Int; E : Entity_Id; Tick : Int; Mood : Integer) return Natural;
   --  records=1 sessions: the word vote and the coinage leave out words that are no words (the numeric chess moves, "4815", "e2e4")
   --  and never run a coined word together with its own part ("waitbroken" + "broken"); off in older sessions (their dice stay valid).
   procedure Set_Clean (On : Boolean);
   function Is_Clean return Boolean;
   function Plain (W : Positive) return Boolean;               --  only the letters a .. z
   function Overlaps (A, B : Positive) return Boolean;         --  one text contains the other

   --  ---- bench ------------------------------------------------------------
   --  A built-in integer kernel with a fixed step budget.  Steps, result and
   --  checksum are pure functions of the arguments (no clock).
   --  HOOK (later, not built): the entity writes Ada into its own folder and
   --  gnatmake builds it there with a timeout and a step budget.
   type Kernel is (Sum, Sort, Sieve);
   type Bench_Result is record
      Which : Kernel := Sum;
      Steps, Result, Checksum : Int := 0;
   end record;
   --  PROOF-LATER: Importance 5/10, Urgency 3/10, SPARK2 (loop bounds, no overflow)
   function Run_Bench (Seed : Int; E : Entity_Id; Tick, Budget : Int) return Bench_Result;

   --  ---- votes ----------------------------------------------------------------
   type Loc_Stats is record
      N, Mood, Energy, Learned, Coined, Benches : Int := 0;
   end record;
   type Stats is array (0 .. 3) of Loc_Stats;   --  by location
   procedure Record_Tick (S : in out Stats; Loc, Mood, Energy : Integer; Learned, Coined, Bench : Boolean);
   --  -100 .. 100 from the average mood and energy at the location and what was done
   --  there (words learned, words coined, benches).
   --  PROOF-LATER: Importance 4/10, Urgency 2/10, SPARK2 (integer arithmetic)
   function Vote (S : Loc_Stats) return Int;
   function Run_Vote (S : Stats) return Int;   --  whole run

   --  The final summary: Console (compact), Text (with reasons) and Json (one object per line).
   type All_Stats is array (Entity_Id) of Stats;
   procedure Summarize
     (Seed, Ticks : Int; Data : All_Stats;
      Console, Text, Json : out Ada.Strings.Unbounded.Unbounded_String);

end Sim_World;
