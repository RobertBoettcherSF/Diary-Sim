--  Version: 0.004
--  active=1 sessions (docs/EVOLVE.md 12 and 13, docs/LEARN.md 12 (a)): every wesen keeps an ACTIVE vocabulary.  The fitness of each
--  word is counted from the record lines the replay emits (screens K, votes V, petitions P, dictionary L: the same inputs and points as
--  make evolve), a running average per session.  At the end of an active=1 session a word whose fitness stayed at or under the line
--  for `idle` sessions after its probation goes DORMANT, and above the cap the lowest fitness goes first; at most `retire_max` a
--  session, never a base word (a start word), never a chess or number string (symbols are out of the pool).  A dormant word is not
--  taught, not coined or blended from, not put on a screen and not a favourite (Sim_World.Asleep); it WAKES when a record line uses
--  it again.  Every decision is a line of diaries/active.txt (record-first, replay-verified); no die is rolled.  Pure counting.
--  PROOF-LATER: Importance 4/10, Urgency 3/10, SPARK2 (bounded counters, sorted candidate lists, token parsing)
pragma Ada_2022;

with Ada.Streams;

with Sim_Util;
with Sim_Evolve;

package Sim_Active is

   use Sim_Util;

   --  active=2 (docs/EVOLVE.md 14): its own numbers (a floor under the cap: floor 300, cap 500) and the MINT-SLOW percents: a wesen
   --  that held at least the cap at the last session end gets a new word only when a die lets it through (Sim_World.Slow_Pass).
   --  Wider wake: a lesson of a word the pupil has dormant wakes it (Wake), a screen show or read wakes it for the other wesen of
   --  the line too, a petition naming the word wakes it for every wesen that has it dormant.
   type Slow_Pcts is record
      Lesson, Coin, Screen : Natural := 100;
   end record;

   --  Forget everything (before a replay from tick 1).  Pr: the numbers of active=1 (evolve.*; Min_Active and Cap = evolve.cap),
   --  Pr2 and Slow: the numbers of active=2.  A save keeps the params line of its first session of each level.
   procedure Reset (Pr : Sim_Evolve.Word_Params; Pr2 : Sim_Evolve.Word_Params; Slow : Slow_Pcts);
   function Params return Sim_Evolve.Word_Params;
   function Params_Text (Pr : Sim_Evolve.Word_Params) return String;   --  "use_pts=1 use_cap=5 ..." (the params line)
   procedure Parse_Params (Line : String; Pr : in out Sim_Evolve.Word_Params; OK : out Boolean);
   function Params_Level (Line : String) return Positive;   --  2 for a "params level=2 ..." line, else 1
   procedure Parse_Slow (Line : String; Slow : in out Slow_Pcts);

   --  The start of session N at Tick: the window of the previous active session is closed (dormancies, state lines) with the
   --  numbers of its level, then the new window opens if Level is 1 or 2 (0: no window).  The lines go to Drain.
   --  Floor (slowfloor=1 sessions, build 0.054): mint-slow already from the floor up (a wesen that held at least the floor of active
   --  words at the last session end), with the same percents; without it only from the cap up.
   procedure Open (N : Positive; Tick : Int; Level : Natural; Floor : Boolean := False);
   function Is_Open return Boolean;
   function Level return Natural;   --  the level of the open window (0: none)
   --  active=2: a lesson of word W by By (a wesen id) to E, who has W dormant: it wakes ("by=lesson:<teacher>").  False if nothing woke.
   procedure Wake (E : Positive; W : Positive; Tick : Int; By : String; Woke : out Boolean);
   --  A record line that was just emitted (K, V, P, L): its uses count for the open window; a dormant word that is used wakes.
   procedure Note_Line (Line : String);
   --  The new lines of diaries/active.txt (without the key "A<n>", starting with "t=<tick>").
   procedure Drain (Into : in out Str_Vectors.Vector);

   function Dormancies (E : Positive) return Natural;   --  dormant lines so far
   function Wakes (E : Positive) return Natural;        --  wake lines so far

   --  0.058: the state the replay builds, for the checkpoint (state.ckpt): Save writes it, else it is read back.
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean);

end Sim_Active;
