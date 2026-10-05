--  Version: 0.001
--  The evolution preview (make evolve, make active): READ-ONLY and pure.  Nothing in here changes a save or rolls a die.
--  (a) Words: every word of every wesen gets a fitness per session from its recorded uses (docs/EVOLVE.md 3): a running average of
--  the points it earned (uses, granted petitions, an agreed dictionary meaning); a word that does not earn more than its upkeep for
--  `idle` sessions in a row, after its probation, would become DORMANT (never a base word, never below `min_active`, at most
--  `retire_max` per session; with a cap, the lowest fitness above the cap goes first).  The caller feeds the words and their events from
--  the files; this package only counts.  (b) Chess: the move features of a game are counted again from the recorded moves
--  (Sim_Chess), and the weight table each competitor WOULD hold after learning from its results is worked out with the rules of
--  docs/EVOLVE.md 4.2 (no mutation, no decay, no copying: those need dice).  The Elo curve is the rating after the last game of each session.
--  PROOF-LATER: Importance 2/10, Urgency 1/10, SPARK2 (bounded integer counting; clamps on weights and fitness)
pragma Ada_2022;

with Ada.Containers.Vectors;
with Sim_Chess;

package Sim_Evolve is

   Max_Ent : constant := 4;     --  the wesen
   Max_Comp : constant := 7;    --  wesen 1 .. 4 and players 5 .. 7 (the chess competitors)

   package Int_Vectors is new Ada.Containers.Vectors (Positive, Integer);

   --  ---- words ------------------------------------------------------------------------------------------------
   type Event_Kind is (Mention, Granted, Agreed);   --  a plain use, a mention in a granted petition, the meaning of an agreed dictionary entry
   type Word_Params is record
      Use_Pts, Use_Cap, Grant_Pts, Agree_Pts : Natural := 0;   --  points per use, most use points per word and session, granted, agreed
      Line10 : Natural := 3;            --  the upkeep line in tenths of a point: a word must earn more than this per session (running average)
      Fit_Cap : Natural := 200;
      Probation, Idle : Natural := 0;   --  sessions before a word may go; sessions in a row at or under the line
      Retire_Max, Min_Active, Cap : Natural := 0;   --  per session; floor; active words above Cap go (0: no cap)
   end record;

   procedure Words_Reset (Pr : Word_Params; Starts : Int_Vectors.Vector);   --  Starts: the first tick of every session (ascending, the first is 0)
   --  A word of wesen E: the learning tick, Base = never retired (a start word), Symbol = a chess or number string (not a word here).
   procedure Add_Word (E : Positive; Tick : Natural; Base, Symbol : Boolean);   --  the N-th call for E is word N
   procedure Add_Event (E : Positive; Word : Positive; Tick : Natural; Kind : Event_Kind);
   procedure Words_Run;

   type Word_Result is record
      Fit10      : Natural := 0;   --  running fitness in tenths of a point per session
      Dormant_In : Natural := 0;   --  session in which it would have become dormant (0: still active)
      Fit_Then   : Natural := 0;   --  Fit10 at that moment
      Uses       : Natural := 0;   --  events in all
      Sessions   : Natural := 0;   --  sessions with an event
      Later      : Natural := 0;   --  events after it would have gone dormant (it would have woken)
      Born       : Natural := 0;   --  session in which it was learned
   end record;
   type Word_Totals is record
      Known, Symbols, Base, Active, Dormant, Woken_Later, Over_Cap, Held : Natural := 0;   --  Held: idle long enough to go, but kept (the floor or the per-session limit)
        --  Active and Dormant: words only, Base included in Active
      Fit10_Sum : Natural := 0;     --  of the active words, no symbols
      Cap_Reached : Natural := 0;   --  first session in which the active words were at or under Cap (0: never / no cap)
   end record;
   function Count (E : Positive) return Natural;
   function Result (E : Positive; Word : Positive) return Word_Result;
   function Is_Base (E : Positive; Word : Positive) return Boolean;
   function Is_Symbol (E : Positive; Word : Positive) return Boolean;
   function Totals (E : Positive) return Word_Totals;
   function Sessions return Natural;

   --  ---- chess ------------------------------------------------------------------------------------------------
   Features : constant := 35;
   subtype Feature is Positive range 1 .. Features;
   type Feature_Counts is array (Feature) of Natural;
   type Weight_Table is array (Feature) of Integer;
   --  1 .. 6 piece moved (pawn .. king), 7 .. 11 piece taken (pawn .. queen), 12 gives check, 13 castles, 14 promotes, 15 centre square,
   --  16 ring around the centre, 17 pawn two-step, 18 minor piece leaves its back rank, 19 king walk in the first ten moves,
   --  20 .. 35 opening bucket (16, a hash of the move text, first three moves of a side).
   procedure Move_Features (P : Sim_Chess.Position; M : Sim_Chess.Move; Side_Ply : Positive; Into : in out Feature_Counts);

   type Chess_Params is record
      Use_Cap, Step, Big_Elo, W_Max, Sess_Max, Sess_Total, Elo_Start : Natural := 0;
   end record;
   procedure Chess_Reset (Pr : Chess_Params; Starts : Int_Vectors.Vector);
   procedure Chess_Start (G : Positive; White, Black : Positive);
   procedure Chess_Move (G : Positive; Coord : String);
   --  Result_White: +1 white won, 0 draw, -1 black won; Delta_White: the Elo change of white in this game.
   procedure Chess_End (G : Positive; Tick : Natural; Result_White, Delta_White : Integer);
   procedure Elo_Point (Comp : Positive; Tick : Natural; Rating : Positive);   --  rating of Comp after a game that ended at Tick
   procedure Chess_Finish;   --  the last session's changes

   function Weight (Comp : Positive; F : Feature) return Integer;
   function Games_Of (Comp : Positive) return Natural;
   function Wins_Of (Comp : Positive) return Natural;
   function Draws_Of (Comp : Positive) return Natural;
   function Moves_Seen return Natural;
   function Bounded_Hits return Natural;   --  how often a weight sat at the limit when a change tried to push it further
   function Elo_Sessions return Natural;
   function Elo_At (Comp : Positive; Session : Positive) return Positive;   --  carried forward from the last game; the start rating before the first

end Sim_Evolve;
