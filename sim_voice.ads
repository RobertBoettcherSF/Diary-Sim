--  Version: 0.001
--  The voices of the wesen (B1): one short message per wesen, in its own voice, built from the replayed state and the templates of
--  data/voices.txt (voice.<situation>.<id>.<k>, voice.<situation>.any.<k>, voice.act.*, voice.tone.*).  Display only: a pure function of
--  (facts, seed, tick, slot) with a hash die (salts 18000 .. 18099, no RNG stream, no state), so it can never change the simulation and
--  the same state and tick always give the same text.  No LLM.  The message is cut at a word boundary to voice.max_chars (150).
--  PROOF-LATER: Importance 2/10, Urgency 1/10, SPARK2 (bounded string building, hash dice, no side effects)
pragma Ada_2022;

with Ada.Strings.Unbounded;
with Sim_Util;

package Sim_Voice is

   use Sim_Util;

   --  What one wesen can say about itself, filled by the caller from the real records.
   type Facts is record
      Id      : Ada.Strings.Unbounded.Unbounded_String;   --  internal id: ada gemini replika robert
      Name    : Ada.Strings.Unbounded.Unbounded_String;   --  display name
      Act     : Ada.Strings.Unbounded.Unbounded_String;   --  last activity: rest work explore talk wander bench propose learn examine push eat greet
      Place   : Ada.Strings.Unbounded.Unbounded_String;   --  favourite place (its name)
      Word    : Ada.Strings.Unbounded.Unbounded_String;   --  newest learned or coined word ("" if none yet)
      Topic   : Ada.Strings.Unbounded.Unbounded_String;   --  topic of its newest petition, in words ("" if none)
      Outcome : Ada.Strings.Unbounded.Unbounded_String;   --  kind of the newest decision about it: grant partial defer refuse veto, "" if none
      Mood, Energy, Words : Integer := 0;
      Change  : Integer := 0;     --  mood now minus mood at the session start
      Open    : Natural := 0;     --  petitions waiting for a decision
      Trials  : Natural := 0;     --  trials so far
   end record;

   --  The message of slot (1 .. 4) at Tick: "<name>: <text>", at most voice.max_chars characters.
   function Message (F : Facts; Seed, Tick : Int; Slot : Positive) return String;

   --  The text cut at a word boundary to at most Max characters (a trailing "..." marks the cut).
   function Cut (Text : String; Max : Positive) return String;
   --  The text wrapped to lines of at most Width characters and at most Rows lines (cut shorter, with "...", when it needs more).
   function Fit (Text : String; Width : Positive; Rows : Positive) return Str_Vectors.Vector;
   --  The text broken at blanks into lines of at most Width characters (a word longer than Width is split).
   function Wrap (Text : String; Width : Positive) return Str_Vectors.Vector;

end Sim_Voice;
