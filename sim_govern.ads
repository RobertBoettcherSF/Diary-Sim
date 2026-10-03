--  Version: 0.005
--  Governance of diary_sim (govern=1 sessions; needs rest=1): the players (Player 1, Player 2, Player 3) decide what happens to the
--  petitions of the wesen they watch.  A SHORT WHITELIST of rule levers (data/govern.txt: recovery rate, cool-down length, the mood
--  cost of work, the quick-rest energy) can each be moved a small step by a petition of the matching topic, never past its bounds.
--  For every petition the responsible player rolls hash dice (salts 9700 .. 9799) weighted by its Rule 30 personality (generous /
--  strict: Sim_Dharma.Warm_Of / Brev_Of), its TRUST in that wesen (rises with reasonable petitions, falls on spam), and its
--  workload (Attn_Of): grant, partial, defer (comes back later) or refuse, with a reason code (text in data/govern.txt).
--  Every decision - also a refusal - is a record line D<n> (diaries/govern.txt, replay-checked by diary_sim through Sim_Store); the
--  report of a player to Robert is built from these lines ONLY (plus a counter line).  Robert may veto (revert a change, lowers the
--  player's standing with its wesen and its trust) or approve (raises both) a decision: input lines of diaries/vetoes.txt.
--  Pure functions of (seed, wesen, tick, salts) and of the replayed state.  Nothing here runs without a govern=1 session.
--  PROOF-LATER: Importance 4/10, Urgency 3/10, SPARK2 (bounded lever arithmetic, weighted dice, record parsing)
pragma Ada_2022;

with Sim_Dharma;
with Sim_Util;
with Sim_World;

package Sim_Govern is

   use Sim_Util;
   use Sim_World;

   type Lever is (Rate, Cool, Work, Quick);

   procedure Init (Seed : Int);          --  not started; reads data/limits.txt (govern.*) and data/govern.txt
   procedure Begin_Life (Tick : Int);    --  the first govern=1 session: trust and standing at their start values
   function Started return Boolean;

   --  Petition Pet of E was filed at Tick while E's mood was Mood: the responsible player will decide in a few ticks.
   procedure Filed (Pet : Positive; E : Entity_Id; Tick : Int; Mood : Integer);
   --  Robert's input (diaries/vetoes.txt): V<N> at Tick, decision D<Dec>, veto or approve; applied at the start of tick Tick + 1.
   procedure Add_Input (N : Positive; Tick : Int; Dec : Positive; Approve : Boolean);
   --  Once per tick before the wesen: Robert's inputs, then the decisions that are due.  Lines: complete D lines.
   --  Bad: 0, or the V number of an input that cannot be applied (unknown or wrong decision).
   procedure Tick_Begin (Tick : Int; Lines : in out Str_Vectors.Vector; Bad : out Natural);

   function Off (E : Entity_Id; L : Lever) return Integer;   --  the governed offset of a lever for E (0 = unchanged)
   function Take_Mood (E : Entity_Id) return Integer;        --  mood of decisions since E's last step, handed over once
   function Trust_Of (E : Entity_Id) return Integer;         --  the watching player's trust in E, 0 .. 100
   function Standing_Of (E : Entity_Id) return Integer;      --  the watching player's standing with E, 0 .. 100

   --  The report of player P to Robert, from the D records only: line 1 is the counter line, then every change
   --  (grant, partial, veto) with a tick after Since.  Variant: "plain" | "calm" | "alarm" (the wording only).
   function Report (P : Sim_Dharma.Player_Id; Since : Int; Variant : String) return Str_Vectors.Vector;
   function Counter_Line (P : Sim_Dharma.Player_Id) return String;   --  "12 petitions seen, 5 granted, 3 partial, 2 deferred, 2 refused"
   function Totals_Line return String;                                --  "seen/granted/partial/deferred/refused" for the digest
   function Decision_Count return Natural;
   --  For the player reports (Sim_Preport), from the D records: seen / granted / partial / deferred / refused / vetoed of a player,
   --  and the topic it was asked about most (refused and deferred ones count double; "" before the first decision).
   type Counts_T is array (1 .. 6) of Natural;
   function Counts_Of (P : Sim_Dharma.Player_Id) return Counts_T;
   function Top_Concern (P : Sim_Dharma.Player_Id) return String;
   function Open_Of (E : Entity_Id) return Natural;       --  petitions of E that wait for a decision (a deferred one counts too)
   function Deferred_Of (E : Entity_Id) return Natural;   --  ... of which already put off at least once
   --  Robert caught a player lying (make challenge): the player's standing with E drops by By points (never below 0).
   procedure Lower_Standing (E : Entity_Id; By : Natural);
   function View return Str_Vectors.Vector;                           --  --govern / make govern (ids; the output layer maps names)
   function Describe (Line : String) return String;                   --  one D line as a sentence

end Sim_Govern;
