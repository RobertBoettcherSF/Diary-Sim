--  Version: 0.006
--  The chess games of diary_sim (chess=1 sessions), a rest activity of the four wesen and the three players.
--  A competitor is a wesen (1 .. 4) or a player (5 .. 7: Player 1, Player 2, Player 3 = iris, sol, noor; player 4 does not play chess).  A player is "in range" of a wesen
--  that it watches or that stands in the same or a neighbouring cell as one it watches.  When a wesen rests, it may play a
--  correspondence game against a wesen next to it or a player in range (a game starts if there is none; one move is made when
--  they meet again after chess.gap ticks), and two players in range of it may play each other.  The side to move chooses by hash
--  dice (Sim_Chess.Choose; strength from the Rule 30 core personality of a wesen, a hashed birth value of a player).  A game ends
--  by mate, stalemate, the 50-move rule, repetition, the ply cap, a RESIGNATION (chance when clearly behind in material or, for a
--  wesen, in low mood) or a TIMEOUT (the side to move has taken chess.timeout ticks; its clock stops while it is on holiday).  Results:
--  win, loss, draw, win by timeout, win by resignation.  Every finished game updates the Elo ratings of both (integer table,
--  standard expectation; the two changes are exactly opposite).  Record lines (text only, no key or tick) go to diary_sim, which
--  stores them in diaries/chess.txt (Sim_Store, replay-verified).  A win brings mood to a wesen, a draw a little, a loss costs a
--  little (Take_Mood, applied at its next step).  Salts 9400 .. 9599 are this unit's own.
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (game bookkeeping, bounded vectors)
--  PROOF-LATER: Importance 4/10, Urgency 3/10, SPARK2 (Elo: integer table lookup, rounding, symmetric deltas)
pragma Ada_2022;

with Ada.Strings.Unbounded;
with Sim_Util;
with Sim_World;

package Sim_Games is

   use Sim_Util;
   use Sim_World;

   subtype Comp_Id is Positive range 1 .. 7;   --  1 .. 4 = Entity_Id, 5 .. 7 = players
   type Mood_Array is array (Entity_Id) of Integer;

   --  chessrules=2 sessions: all the rules.  Besides mate, stalemate and the ply cap (the old rules): a draw by insufficient material
   --  (Sim_Chess.Insufficient) is automatic; fivefold repetition (chess.fivefold) and the 75-move rule (chess.moves75 half-moves
   --  without a pawn move or capture) are automatic; threefold repetition (chess.repeat) and the 50-move rule are CLAIMS of the side
   --  to move, made with the chance chess.claim_pct (+ chess.claim_behind when it is behind in material; own salt 9440), else the
   --  game goes on.  Rules 0 (no marker) = the old rules exactly (threefold and 50 moves end the game at once).
   procedure Set_Rules (V : Natural);
   procedure Init (Seed : Int);   --  no games, start ratings; reads data/limits.txt (chess.*) and data/chess.txt (elo.table)

   function Comp_Name (C : Comp_Id) return String;   --  ids: ada .. robert, iris sol noor (display names are applied on output)
   function Is_Wesen (C : Comp_Id) return Boolean is (C <= 4);
   function As_Comp (E : Entity_Id) return Comp_Id is (Comp_Id (E));

   --  E rests (a chess turn): may announce a holiday, start a game, or make one move (against a wesen or a player), and the
   --  players in range may play each other.  Lines: record lines (text only).  Played: E's game had a move with Partner
   --  (Move_Text = "e2e4", Num_Text = "5254"); Detail: sentence for E's diary line (appended).
   procedure Turn (E : Entity_Id; Tick : Int; Moods : Mood_Array; Lines : in out Str_Vectors.Vector; Played : out Boolean;
                   Partner : out Comp_Id; Move_Text, Num_Text : out Ada.Strings.Unbounded.Unbounded_String;
                   Detail : in out Ada.Strings.Unbounded.Unbounded_String);
   --  Once per tick before the wesen: the clock of the side to move in every running game (timeout).
   procedure Clock (Tick : Int; Lines : in out Str_Vectors.Vector);
   --  Mood from finished games, handed over once (at the wesen's step).
   function Take_Mood (E : Entity_Id) return Integer;
   function On_Holiday (E : Entity_Id; Tick : Int) return Boolean;

   function Rating (C : Comp_Id) return Positive;
   function Game_Count return Natural;
   function Finished_Count return Natural;
   function Moves_Total return Natural;
   --  Elo expectation of a player rated A against one rated B, in thousandths (the table lookup), and the rating change of A
   --  for a result of Score thousandths (1000 win, 500 draw, 0 loss) with factor K; the other side's change is its negative.
   function Expected (A, B : Integer) return Natural;
   function Rating_Delta (A, B, Score, K : Integer) return Integer;
   --  Games, results and moves for the end report (Full: every move), one line per competitor, the ranking table.
   function Report (Full : Boolean) return Str_Vectors.Vector;
   function Summary (C : Comp_Id) return String;
   function Ranking return Str_Vectors.Vector;     --  the table of --elo / make elo
   function Digest_Line return String;             --  "elo Ruth 1230 Abel 1215 ..." best first

end Sim_Games;
