--  Version: 0.002
--  The player reports of diary_sim (preport=1 sessions; needs govern=1): at the end of every run each player (Player 1, Player 2, Player 3) writes
--  Robert a short first-person report in a framed text box: how many petitions came to it, what it decided (counts from the D records
--  of Sim_Govern - NEVER omitted or changed), how the wesen it watches are doing ('overall happiness' as the PLAYER REPORTS it), its top
--  concern and what it wants from Robert.  The player MAY MISREPORT the impression (happiness, how many petitions came lately): a data-set
--  honesty trait from its Rule 30 personality (Sim_Dharma.Warm_Of / Brev_Of) and its trust / standing with the wesen
--  (Sim_Govern.Trust_Of / Standing_Of) decides, a hash roll (salts 9800 .. 9802) says when and how far (at most preport.lie_max mood
--  points, never outside the mood scale; a petition tone moves by one step).  The box says only what the player claims.
--  Every claim is a record line P<n> (diaries/preports.txt, replay-checked by diary_sim through Sim_Store) with the claim next to the TRUE
--  value and a flag lie / none; make audit (--audit) shows them side by side; make challenge (--challenge <player>) lowers the standing of
--  a player whose lie was caught (an input line Q<n> of diaries/challenges.txt, applied at the start of the next tick).
--  A round (the claims of all four wesen) happens at the last tick of every preport=1 session.  Pure functions of (seed, wesen, tick,
--  salts) and of the replayed state; nothing here runs without a preport=1 session.  Wording and numbers: data/preport.txt, data/limits.txt.
--  PROOF-LATER: Importance 4/10, Urgency 3/10, SPARK2 (bounded claim arithmetic, hash dice, record parsing)
pragma Ada_2022;

with Sim_Dharma;
with Sim_Util;
with Sim_World;

package Sim_Preport is

   use Sim_Util;
   use Sim_World;

   type Ints is array (Entity_Id) of Integer;

   procedure Init (Seed : Int);                    --  reads data/limits.txt (preport.*); nothing is started
   procedure Begin_Session (Tick : Int; Pets : Ints);   --  a preport=1 session starts: the petitions so far (the tone counts from here)
   --  Robert's input (diaries/challenges.txt): Q<N> at Tick, player P; applied at the start of tick Tick + 1.
   procedure Add_Challenge (N : Positive; Tick : Int; P : Sim_Dharma.Player_Id);
   --  Bad: 0, or the Q number of a challenge that cannot be applied (the player had no unchallenged lie).
   procedure Tick_Begin (Tick : Int; Bad : out Natural);
   --  The claims of all four wesen at Tick (mood and total petitions per wesen): complete P lines, remembered for the audit.
   procedure Round (Tick : Int; Mood, Pets : Ints; Lines : in out Str_Vectors.Vector);
   function Round_Count return Natural;
   function Last_Tick return Int;                  --  tick of the latest round, -1 before the first
   --  The text boxes of the three players as of Tick (the latest round if it is at Tick, else computed now without recording anything),
   --  one string with LF line ends, display names, every line exactly preport.width columns; "" without a round.
   function Boxes (Tick : Int; Mood, Pets : Ints) return String;
   function Audit return Str_Vectors.Vector;       --  --audit / make audit (ids; the output layer maps names)
   function Digest_Line return String;             --  "3 rounds, 4/12 misreports, biggest +22"
   function Lie_Total return Natural;

end Sim_Preport;
