--  Version: 0.001
--  Trial by chess (trial=1 sessions; needs chess=1 and govern=1): a DISPUTE between two wesen, a wesen and a player, or two players is
--  settled over the board.  Disputes come from sources that already exist: two CLASHING petitions (one asks for rest, the other for
--  quicker work: the pairs are data, trial.clash.N) filed within trial.window ticks (src=petition; their watching players may take the
--  case over, trial.escalate_pct: then the two PLAYERS play); a REFUSED petition that its wesen appeals against the refusing player
--  (src=appeal, trial.appeal_pct); two RIVAL CLAIMS to a coined word (both coined within the window, src=claim); a REST / WORK dispute
--  (one wesen is in its cool-down after hard work, a neighbour in the same place works, src=restwork).  Every chance, number and word is
--  data (trial.* in data/limits.txt, data/trial.txt).
--  The series: a match of trial.first games (3), colours alternating; the one with more wins takes it (a match ends early when one side
--  has the majority).  Level (draws): a further match of trial.ext_first games (3), then trial.ext_step more each time (5, 7, ...), so
--  every match is odd, until decided; when the next match would take the series past trial.max_games, a RULE 30 COIN (a hashed row, 20
--  steps, the middle bit) breaks it.  The games are real games (Sim_Games.Play_Out: same rules, same dice, Elo per game as ever, g=N
--  lines in diaries/chess.txt; no chess mood).
--  Wesen generally ADHERE to the verdict but value it differently from a ruling of a player: the loser (if a wesen) adheres with the
--  chance trial.adhere_pct, lowered by its unrest (trial.unrest_w per 100) and raised by its standing (trial.stand_w per 100 above
--  50); a loser that refuses is recorded as "refused the trial" and pays trial.refuse_stand standing.  The effects (standing, trust,
--  mood of a wesen) are a few points, far below a veto or a grant (trial.win_*, trial.loss_mood).  Players always adhere.
--  Each trial is a record line T<n> (diaries/trials.txt, replay-checked by diary_sim through Sim_Store, own hash salts 9960 .. 9979):
--  a changed, invented or removed line is DRIFT.  Pure functions of (seed, wesen/player, tick, salts) and of the replayed state.
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (bounded integer arithmetic, hash dice, a bit-row coin, record parsing)
pragma Ada_2022;

with Sim_Games;
with Sim_Util;
with Sim_World;

package Sim_Trial is

   use Sim_Util;
   use Sim_World;

   procedure Init (Seed : Int);   --  reads data/limits.txt (trial.*) and data/trial.txt; no trials
   procedure Begin_Session;       --  the per-session cap starts at 0
   --  What a wesen did this tick (called once per step): its cell, whether it worked, coined a word, or is in a cool-down.
   procedure Note_Step (E : Entity_Id; Tick : Int; Loc : Integer; Worked, Coined, Tired : Boolean);
   procedure Note_Petition (E : Entity_Id; Tick : Int; Pet : Positive; Topic : String);
   --  Once per tick after the steps: at most one trial.  Lines: the T line; Chess_Lines: the g=N lines of its games.
   procedure Step (Tick : Int; Moods : Sim_Games.Mood_Array; Lines, Chess_Lines : in out Str_Vectors.Vector);

   function Count return Natural;
   function Last_Tick return Int;                      --  tick of the latest trial, -1 before the first
   function Box_Line (Players : Positive) return String;  --  one line in the voice of one of the Players about the latest trial of this session, "" if none
   function View return Str_Vectors.Vector;             --  --trials / make trials (ids; the output layer maps names)
   function Digest_Line return String;                  --  "2 trials (1 refused, 0 coin)"

end Sim_Trial;
