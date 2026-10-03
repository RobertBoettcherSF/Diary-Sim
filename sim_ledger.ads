--  Version: 0.003
--  The mood ledger of diary_sim: REPORT ONLY.  Every tick the replay hands over how the mood of a wesen
--  moved and from which source; nothing here is stored in a diary, hashed, or read back by the simulation,
--  so action weights, dice and every stored byte are what they were without it.  The ledger exists
--  because the replay (every run replays ticks 1 .. N) runs the same code as a new tick.
--
--  The mood change of one tick is split into parts that add up exactly to the change in the diary:
--    base      the action's own mood (data: Mood_D), clamped to the mood bounds
--    rest model quick-rest penalty / calm-rest bonus (rest=1 sessions)
--    push      the feel of the pushed thing (world=1 sessions: pleasant / plain / rough)
--    chess     the mood of finished chess games, taken at the wesen's step (chess=1 sessions)
--    governance  the mood of the decisions on its petitions, taken at the wesen's step (govern=1 sessions)
--  Per wesen it answers: which action at which place drains or gives mood (top 3 each), per action, place and
--  verb, events (petitions, pushed things), the rest model (quick penalty, calm bonus, cool-down ticks),
--  and how much a bound (-100 / +100) swallowed.  Wording: data/ledger.txt.
--  PROOF-LATER: Importance 2/10, Urgency 2/10, SPARK2 (integer sums and a stable top-3 selection)
pragma Ada_2022;

with Sim_Util;
with Sim_World;

package Sim_Ledger is

   use Sim_Util;
   use Sim_World;

   procedure Reset;

   --  One tick of one wesen.  A: the rolled action, V: the verb of the diary line, Loc: the location after the
   --  tick.  Base + Rest_Fx + Push_Fx = the change of the mood; Nominal: what was asked before the bounds.
   --  Phase: -1 quick rest, +1 calm rest, 0 other.  Cool: the tick began inside a cool-down.
   --  Feel: the class (0 pleasant, 1 plain, 2 rough) of a pushed thing, else -1.
   procedure Add (E : Entity_Id; Tick : Int; A : Action; V : List_Id; Loc : Natural;
                  Base, Rest_Fx, Push_Fx, Nominal, Phase : Integer; Cool : Boolean; Feel : Integer; Chess_Fx : Integer := 0;
                  Gov_Fx : Integer := 0);

   function Ticks_Seen return Natural;   --  records held (all wesen)

   --  Sum of the mood changes of E in ticks From + 1 .. To (To = 0: to the last one).
   function Net (E : Entity_Id; From, To : Int) return Integer;

   --  The text of the ledger for the whole run and for the ticks after Last_From (the last session).
   --  Short: per wesen the headline, top 3 drains and gains for both scopes, and one sentence.
   --  Full: also the breakdown by action, place, verb, event and rest model (whole run).
   function Report (Seed, Last_From : Int; Full : Boolean) return String;

   --  One short line per wesen for the debug digest, and the sentence / breakdown for the full record.
   function Digest_Line (E : Entity_Id; Last_From : Int) return String;
   function Sentence (E : Entity_Id) return String;

end Sim_Ledger;
