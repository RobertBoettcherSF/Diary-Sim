--  Version: 0.002
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
   function Kind (E : Entity_Id) return String;   --  engineer reviewer vice_president human

   --  Diary word lists (data/words.txt): action texts, mood tones, vote reasons.
   type List_Id is (Rest, Work, Explore, Talk, Wander, Bench, Learn,
                    Mood_Low, Mood_Neutral, Mood_High, Reason_Low, Reason_Mid, Reason_High);
   subtype Action is List_Id range Rest .. Learn;   --  Learn is never rolled: it delivers a lesson
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
   procedure Learn_Word (E : Entity_Id; W : Positive);
   function Find (Text : String) return Natural;   --  0: no such word
   function Add_Coined (Text : String; P1, P2 : Natural) return Positive;
   function Parents (W : Positive) return String;   --  "hand+phone" or "" for a base word
   --  Words E knows / words From knows and To lacks, and the N-th of each.
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
   function Choose (Seed : Int; E : Entity_Id; Tick : Int; Energy, Mood : Integer) return Action;

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
