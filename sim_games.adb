--  Version: 0.005
--  See sim_games.ads.
pragma Ada_2022;

with Sim_Ckpt;

with Ada.Containers.Vectors;
with Interfaces;
with Sim_Chess;
with Sim_Dharma;
with Sim_Things;
use type Interfaces.Unsigned_64;

package body Sim_Games is

   use Ada.Strings.Unbounded;

   type Result_Kind is (Running, White_Wins, Black_Wins, Draw);
   package Key_Vectors is new Ada.Containers.Vectors (Positive, Interfaces.Unsigned_64);
   type Game_Rec is record
      W, B : Comp_Id := 1;
      Pos : Sim_Chess.Position;
      Keys : Key_Vectors.Vector;
      Moves : Str_Vectors.Vector;     --  coordinate notation
      Nums : Str_Vectors.Vector;      --  ICCF numeric
      Start, Last_Move : Int := 0;
      Idle : Natural := 0;            --  ticks the side to move has used
      Res : Result_Kind := Running;
      Why : Unbounded_String;
      Elo : Unbounded_String;         --  "ada=1200>1212 iris=1200>1188" once finished
   end record;
   package Game_Vectors is new Ada.Containers.Vectors (Positive, Game_Rec);

   type Ints is array (Comp_Id) of Int;
   type Counts is array (Comp_Id) of Natural;
   type Pair_Ints is array (Comp_Id, Comp_Id) of Int;
   type Pair_Counts is array (Comp_Id, Comp_Id) of Natural;
   type Table_Array is array (0 .. 32) of Natural;

   Games : Game_Vectors.Vector;
   --  0.060: every game before First_Run is finished (a finished game never runs again), so the clock and the search of a pair's
   --  running game start there instead of at game 1 (both scanned the whole history at every tick: O(games) per tick)
   First_Run : Positive := 1;

   procedure Skip_Done is
   begin
      if First_Run > Natural (Games.Length) + 1 then First_Run := 1; end if;
      while First_Run <= Natural (Games.Length) and then Games.Constant_Reference (First_Run).Res /= Running loop
         First_Run := First_Run + 1;
      end loop;
   end Skip_Done;

   procedure Reindex is
   begin
      First_Run := 1;
   end Reindex;
   Seed_V : Int := 0;
   Holiday_Until : Ints := [others => -1];
   Pending : array (Comp_Id) of Integer := [others => 0];
   Rate : array (Comp_Id) of Positive := [others => 1200];
   Last_End : Pair_Ints := [others => [others => -1_000_000]];
   Pair_Games : Pair_Counts := [others => [others => 0]];
   Won, Lost, Drawn, Made, Holidays, By_Time, By_Resign, Played_N : Counts := [others => 0];
   Table : Table_Array := [others => 0];
   Gap, Start_Pct, Pause, Timeout, Max_Plies, Repeat, Hol_Pct, Hol_Len, Smin, Smax, Win_Mood, Draw_Mood, Loss_Mood,
     Res_Pct, Res_Gap, Res_Mood, Res_Mood_Pct, Res_Min, PP_Pct, Elo_Start, Elo_K : Integer := 1;
   Forced : Natural := 0;     --  Play_Out: the game that Pair plays (0: the normal search and start)
   Quiet : Boolean := False;  --  Play_Out (a game of a trial): no chess mood
   Rules, Fives, Moves75, Claim_Pct, Claim_Behind : Integer := 0;   --  chessrules=2 (Set_Rules): 0 = the old rules

   procedure Set_Rules (V : Natural) is
   begin
      Rules := V;
   end Set_Rules;

   function L (Key : String; D, Lo, Hi : Integer) return Integer is
     (Integer'Max (Lo, Integer'Min (Hi, Integer (Limit (Key, Int (D))))));

   function Comp_Name (C : Comp_Id) return String is
     (if C <= 4 then Name (Entity_Id (C)) else Sim_Dharma.Player_Name (Sim_Dharma.Player_Id (C - 4)));

   Default_Table : constant Table_Array :=
     [500, 464, 429, 394, 360, 327, 297, 267, 240, 215, 192, 170, 151, 133, 118, 104, 91, 80, 70, 61, 53, 46, 40, 35, 31, 27, 23, 20, 17, 15, 13, 11, 10];

   --  data/chess.txt elo.table: 33 comma-separated thousandths (the weaker side's expectation at deficit 0, 25 .. 800).
   procedure Load_Table is
      T : constant String := Msg ("elo.table");
      From : Positive := T'First;
      N : Natural := 0;
      Loaded : Table_Array := [others => 0];
      OK : Boolean := T'Length > 0 and then T (T'First) /= '[';
   begin
      for I in T'First .. T'Last + 1 loop
         if I > T'Last or else T (I) = ',' then
            if OK and then I > From and then N <= Loaded'Last and then (for all C of T (From .. I - 1) => C in '0' .. '9' | ' ') then
               declare
                  V : Natural := 0;
               begin
                  for C of T (From .. I - 1) loop
                     if C /= ' ' then V := V * 10 + Character'Pos (C) - Character'Pos ('0'); end if;
                  end loop;
                  Loaded (N) := Natural'Min (V, 1000);
               end;
               N := N + 1;
            else
               OK := OK and then I <= From;
            end if;
            From := I + 1;
         end if;
      end loop;
      Table := (if OK and then N = Table'Length then Loaded else Default_Table);   --  a missing or damaged table: the built-in one
   end Load_Table;

   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
      Games.Clear;
      First_Run := 1;
      Holiday_Until := [others => -1];
      Pending := [others => 0];
      Last_End := [others => [others => -1_000_000]];
      Pair_Games := [others => [others => 0]];
      Won := [others => 0]; Lost := [others => 0]; Drawn := [others => 0]; Made := [others => 0]; Holidays := [others => 0];
      By_Time := [others => 0]; By_Resign := [others => 0]; Played_N := [others => 0];
      Gap := L ("chess.gap", 6, 1, 1000);
      Start_Pct := L ("chess.start_pct", 50, 0, 100);
      Pause := L ("chess.pause", 30, 0, 100_000);
      Timeout := L ("chess.timeout", 300, 10, 1_000_000);
      Max_Plies := L ("chess.max_plies", 160, 20, 1000);
      Repeat := L ("chess.repeat", 3, 1, 10);
      Hol_Pct := L ("chess.holiday_pct", 2, 0, 100);
      Hol_Len := L ("chess.holiday_len", 60, 1, 100_000);
      Smin := L ("chess.strength.min", 0, 0, 100);
      Smax := L ("chess.strength.max", 100, 0, 100);
      Win_Mood := L ("chess.win", 6, -100, 100);
      Draw_Mood := L ("chess.draw", 1, -100, 100);
      Loss_Mood := L ("chess.loss", -2, -100, 100);
      Res_Pct := L ("chess.resign_pct", 4, 0, 100);
      Res_Gap := L ("chess.resign_gap", 3, 1, 40);
      Res_Mood := L ("chess.resign_mood", -40, -100, 100);
      Res_Mood_Pct := L ("chess.resign_mood_pct", 5, 0, 100);
      Res_Min := L ("chess.resign_min_plies", 10, 0, 1000);
      PP_Pct := L ("chess.player_pct", 25, 0, 100);
      Elo_Start := L ("chess.elo.start", 1200, 100, 4000);
      Elo_K := L ("chess.elo.k", 24, 1, 200);
      Fives := L ("chess.fivefold", 5, 1, 50);
      Moves75 := L ("chess.moves75", 150, 1, 1000);
      Claim_Pct := L ("chess.claim_pct", 40, 0, 100);
      Claim_Behind := L ("chess.claim_behind", 40, 0, 100);
      Rules := 0;
      Rate := [others => Elo_Start];
      Load_Table;
   end Init;

   --  ---- Elo: integer table, thousandths ---------------------------------------------------------------------------
   --  Expected score of A against B in thousandths: the table holds the expectation of the weaker side by the rating
   --  deficit 0, 25, 50 .. 800 (linear in between); the stronger side gets the rest, so Expected (A, B) + Expected (B, A) = 1000.
   function Expected (A, B : Integer) return Natural is
      D : constant Integer := Integer'Min (800, abs (A - B));
      I : constant Natural := D / 25;
      F : constant Natural := D mod 25;
      Weak : constant Natural :=
        (if I >= 32 then Table (32) else (Table (I) * (25 - F) + Table (I + 1) * F + 12) / 25);
   begin
      return (if A >= B then 1000 - Weak else Weak);
   end Expected;

   function Rating_Delta (A, B, Score, K : Integer) return Integer is
      X : constant Integer := K * (Score - Integer (Expected (A, B)));   --  thousandths of a point
   begin
      return (if X >= 0 then (X + 500) / 1000 else -((-X + 500) / 1000));   --  nearest, halves away from zero
   end Rating_Delta;

   function Rating (C : Comp_Id) return Positive is (Rate (C));

   function Hex (K : Interfaces.Unsigned_64) return String is
      Digits_V : constant String := "0123456789abcdef";
      R : String (1 .. 16);
      V : Interfaces.Unsigned_64 := K;
   begin
      for I in reverse R'Range loop
         R (I) := Digits_V (Digits_V'First + Integer (V mod 16));
         V := V / 16;
      end loop;
      return R;
   end Hex;

   function On_Holiday (E : Entity_Id; Tick : Int) return Boolean is (Holiday_Until (Comp_Id (E)) >= Tick);
   function Holiday_C (C : Comp_Id; Tick : Int) return Boolean is (Holiday_Until (C) >= Tick);
   function Take_Mood (E : Entity_Id) return Integer is
      V : constant Integer := Pending (Comp_Id (E));
   begin
      Pending (Comp_Id (E)) := 0;
      return V;
   end Take_Mood;

   function Result_Text (R : Result_Kind) return String is
     (case R is when Running => "*", when White_Wins => "1-0", when Black_Wins => "0-1", when Draw => "1/2-1/2");

   --  Percent chance of the best 1-ply move: a wesen by its Rule 30 core personality, a player by a hashed birth value.
   function Strength_Of (C : Comp_Id) return Natural is
     (Natural (Smin + (Smax - Smin)
               * (if C <= 4 then Integer (Core_Percent (Seed_V, Entity_Id (C))) else Roll (Seed_V, 100 + C, 0, 9420, 101) - 1) / 100));

   --  Watching: a player is in range of wesen E when it watches E or a wesen next to E.
   function In_Range (P : Comp_Id; E : Entity_Id) return Boolean is
   begin
      for W in Entity_Id loop
         if Comp_Id (Sim_Dharma.Chess_Watcher (W)) + 4 = P and then (W = E or else Sim_Things.Adjacent (E, W)) then return True; end if;
      end loop;
      return False;
   end In_Range;

   --  Finish game I: result, mood (taken at the next step), Elo, pair pause, record line.
   procedure Finish (I : Positive; R : Result_Kind; Why : String; Tick : Int; Lines : in out Str_Vectors.Vector) is
      G : Game_Rec := Games (I);
      Sw : constant Integer := (case R is when White_Wins => 1000, when Black_Wins => 0, when others => 500);
      Dw : constant Integer := Rating_Delta (Rate (G.W), Rate (G.B), Sw, Elo_K);
      Ow : constant Positive := Rate (G.W);
      Ob : constant Positive := Rate (G.B);
      procedure Mood (C : Comp_Id; V : Integer) is
      begin
         if C <= 4 and then not Quiet then Pending (C) := Pending (C) + V; end if;
      end Mood;
      Winner : constant Natural := (case R is when White_Wins => G.W, when Black_Wins => G.B, when others => 0);
   begin
      G.Res := R;
      G.Why := To_Unbounded_String (Why);
      case R is
         when White_Wins | Black_Wins =>
            declare
               Loser : constant Comp_Id := (if Winner = G.W then G.B else G.W);
            begin
               Mood (Winner, Win_Mood); Mood (Loser, Loss_Mood);
               Won (Winner) := Won (Winner) + 1; Lost (Loser) := Lost (Loser) + 1;
               if Why = "timeout" then By_Time (Winner) := By_Time (Winner) + 1; end if;
               if Why = "resign" then By_Resign (Winner) := By_Resign (Winner) + 1; end if;
            end;
         when Draw =>
            Mood (G.W, Draw_Mood); Mood (G.B, Draw_Mood);
            Drawn (G.W) := Drawn (G.W) + 1; Drawn (G.B) := Drawn (G.B) + 1;
         when Running => null;
      end case;
      Rate (G.W) := Positive'Max (1, Ow + Dw);
      Rate (G.B) := Positive'Max (1, Ob - Dw);
      G.Elo := To_Unbounded_String (Comp_Name (G.W) & "=" & Img (Ow) & ">" & Img (Rate (G.W)) & " "
                                    & Comp_Name (G.B) & "=" & Img (Ob) & ">" & Img (Rate (G.B)));
      Played_N (G.W) := Played_N (G.W) + 1; Played_N (G.B) := Played_N (G.B) + 1;
      Last_End (G.W, G.B) := Tick; Last_End (G.B, G.W) := Tick;
      Games.Replace_Element (I, G);
      Lines.Append ("g=" & Img (I) & " end " & Result_Text (R) & " " & Why & " plies=" & Img (Natural (G.Moves.Length))
                    & " elo " & To_String (G.Elo));
   end Finish;

   --  The pair A, B meets at Tick: start a game if there is none, or make one move.  Report_To: the wesen whose diary tells it.
   procedure Pair (A, B : Comp_Id; Tick : Int; Moods : Mood_Array; Lines : in out Str_Vectors.Vector; Played : out Boolean;
                   Move_Text, Num_Text : out Unbounded_String; Detail : in out Unbounded_String; Tell : Boolean) is
      Gi : Natural := 0;
      procedure Say (T : String) is
      begin
         if Tell then Append (Detail, (if Length (Detail) > 0 then "; " else "") & T); end if;
      end Say;
   begin
      Played := False;
      Move_Text := Null_Unbounded_String;
      Num_Text := Null_Unbounded_String;
      if Forced /= 0 then
         Gi := Forced;
      else
         Skip_Done;
         for I in First_Run .. Natural (Games.Length) loop
            if Games (I).Res = Running and then ((Games (I).W = A and then Games (I).B = B) or else (Games (I).W = B and then Games (I).B = A)) then
               Gi := I;
            end if;
         end loop;
      end if;
      if Gi = 0 then   --  start a game (the pair has played Pair_Games times: the colours alternate)
         if Tick - Last_End (A, B) < Int (Pause) or else Int (Roll (Seed_V, A * 10 + B, Tick, 9401, 100)) > Int (Start_Pct) then return; end if;
         declare
            Lo : constant Comp_Id := Comp_Id'Min (A, B);
            Hi : constant Comp_Id := Comp_Id'Max (A, B);
            Flip : constant Boolean := Pair_Games (Lo, Hi) mod 2 = 1;
            G : Game_Rec;
         begin
            G.W := (if Flip then Hi else Lo);
            G.B := (if Flip then Lo else Hi);
            G.Pos := Sim_Chess.Start;
            G.Keys.Append (Sim_Chess.Key (G.Pos));
            G.Start := Tick;
            G.Last_Move := Tick - Int (Gap);
            Pair_Games (Lo, Hi) := Pair_Games (Lo, Hi) + 1;
            Games.Append (G);
            Gi := Natural (Games.Length);
            Lines.Append ("g=" & Img (Gi) & " start white=" & Comp_Name (G.W) & " black=" & Comp_Name (G.B));
            Say (Msg ("detail.chess_start", Comp_Name (B), (if G.W = A then Msg ("chess.white") else Msg ("chess.black"))));
         end;
      end if;
      if Tick - Games (Gi).Last_Move < Int (Gap) then return; end if;
      declare
         G : Game_Rec := Games (Gi);
         White_To_Move : constant Boolean := Sim_Chess."=" (G.Pos.To_Move, Sim_Chess.White);
         Mover : constant Comp_Id := (if White_To_Move then G.W else G.B);
         Bal : constant Integer := Sim_Chess.Material (G.Pos, G.Pos.To_Move);
         Plies : constant Natural := Natural (G.Moves.Length);
         Chance : Integer := 0;
      begin
         --  a resignation instead of a move: clearly behind in material (and, for a wesen, in low mood)
         if Plies >= Res_Min then
            if Bal <= -Res_Gap then Chance := Res_Pct * (-Bal) / Res_Gap; end if;
            if Mover <= 4 and then Moods (Entity_Id (Mover)) <= Res_Mood and then Bal < 0 then Chance := Chance + Res_Mood_Pct; end if;
         end if;
         if Chance > 0 and then Int (Roll (Seed_V, Mover, Tick, 9421, 100)) <= Int (Integer'Min (100, Chance)) then
            Finish (Gi, (if White_To_Move then Black_Wins else White_Wins), "resign", Tick, Lines);
            Say (Msg ("detail.chess_end", Result_Text (Games (Gi).Res), "resign", Comp_Name (B)));
            return;
         end if;
         declare
            M : constant Sim_Chess.Move := Sim_Chess.Choose (G.Pos, Seed_V, Mover, Tick, Strength_Of (Mover));
            C : constant String := Sim_Chess.Coord (M);
            N : constant String := Sim_Chess.Iccf (M);
            Nxt : constant Sim_Chess.Position := Sim_Chess.Play (G.Pos, M);
            State : constant Sim_Chess.Game_State := Sim_Chess.State_Of (Nxt);
            Reps : Natural := 0;
            use type Sim_Chess.Game_State;
         begin
            G.Pos := Nxt;
            G.Keys.Append (Sim_Chess.Key (Nxt));
            G.Moves.Append (C);
            G.Nums.Append (N);
            G.Last_Move := Tick;
            G.Idle := 0;
            Games.Replace_Element (Gi, G);
            Made (Mover) := Made (Mover) + 1;
            Lines.Append ("g=" & Img (Gi) & " move " & Img (Natural (G.Moves.Length)) & " " & Comp_Name (Mover) & " " & C & " " & N
                          & " k=" & Hex (G.Keys.Last_Element));
            Played := True;
            Move_Text := To_Unbounded_String (C);
            Num_Text := To_Unbounded_String (N);
            Say (Msg ("detail.chess_move", Comp_Name (B), C, N, Img (Natural (G.Moves.Length))));
            for K of G.Keys loop
               if K = G.Keys.Last_Element then Reps := Reps + 1; end if;
            end loop;
            if State = Sim_Chess.Checkmate then
               Finish (Gi, (if Mover = G.W then White_Wins else Black_Wins), "mate", Tick, Lines);
            elsif State = Sim_Chess.Stalemate then
               Finish (Gi, Draw, "stalemate", Tick, Lines);
            elsif Rules >= 2 then   --  all the rules: automatic draws, claims
               declare
                  Claimant : constant Comp_Id := (if Sim_Chess."=" (Nxt.To_Move, Sim_Chess.White) then G.W else G.B);
                  Chance : constant Integer :=
                    Claim_Pct + (if Sim_Chess.Material (Nxt, Nxt.To_Move) < 0 then Claim_Behind else 0);
                  Claimable : constant Boolean := Reps >= Repeat or else State = Sim_Chess.Fifty_Moves;
               begin
                  if Sim_Chess.Insufficient (Nxt) then
                     Finish (Gi, Draw, "material", Tick, Lines);
                  elsif Reps >= Fives then
                     Finish (Gi, Draw, "fivefold", Tick, Lines);
                  elsif Nxt.Half >= Moves75 then
                     Finish (Gi, Draw, "seventyfive", Tick, Lines);
                  elsif Claimable and then Int (Roll (Seed_V, Claimant, Tick, 9440, 100)) <= Int (Integer'Min (100, Chance)) then
                     Finish (Gi, Draw, (if Reps >= Repeat then "repetition" else "fifty"), Tick, Lines);
                  elsif Natural (G.Moves.Length) >= Max_Plies then
                     Finish (Gi, Draw, "cap", Tick, Lines);
                  end if;
               end;
            elsif State = Sim_Chess.Fifty_Moves then
               Finish (Gi, Draw, "fifty", Tick, Lines);
            elsif Reps >= Repeat then
               Finish (Gi, Draw, "repetition", Tick, Lines);
            elsif Natural (G.Moves.Length) >= Max_Plies then
               Finish (Gi, Draw, "cap", Tick, Lines);
            end if;
            if Games (Gi).Res /= Running then
               Say (Msg ("detail.chess_end", Result_Text (Games (Gi).Res), To_String (Games (Gi).Why), Comp_Name (B)));
            end if;
         end;
      end;
   end Pair;

   --  A whole game at once (a trial): White plays the white pieces against the other one of A, B.  Every move is made with the same
   --  rules and dice as a game over time (Pair), at the virtual ticks Tick, Tick + chess.gap, ...  No chess mood (the trial has its own),
   --  the pair pause is left as it was; Elo, the record lines and the counters are as for any game.  Winner: the competitor, 0 = draw.
   procedure Play_Out (A, B, White : Comp_Id; Tick : Int; Moods : Mood_Array; Lines : in out Str_Vectors.Vector;
                       Winner, Game_No : out Natural) is
      G : Game_Rec;
      Played : Boolean;
      Mv, Nm, Dt : Unbounded_String;
      Vt : Int := Tick;
      Was_End : constant Int := Last_End (A, B);
   begin
      G.W := White;
      G.B := (if White = A then B else A);
      G.Pos := Sim_Chess.Start;
      G.Keys.Append (Sim_Chess.Key (G.Pos));
      G.Start := Tick;
      G.Last_Move := Tick - Int (Gap);
      Games.Append (G);
      Game_No := Natural (Games.Length);
      Lines.Append ("g=" & Img (Game_No) & " start white=" & Comp_Name (G.W) & " black=" & Comp_Name (G.B));
      Forced := Game_No;
      Quiet := True;
      for Ply in 1 .. Max_Plies + 4 loop
         exit when Games (Game_No).Res /= Running;
         Pair (A, B, Vt, Moods, Lines, Played, Mv, Nm, Dt, False);
         Vt := Vt + Int (Gap);
      end loop;
      if Games (Game_No).Res = Running then Finish (Game_No, Draw, "cap", Vt, Lines); end if;
      Forced := 0;
      Quiet := False;
      Last_End (A, B) := Was_End; Last_End (B, A) := Was_End;
      Winner := (case Games (Game_No).Res is when White_Wins => G.W, when Black_Wins => G.B, when others => 0);
   end Play_Out;

   procedure Add_Mood (C : Comp_Id; V : Integer) is
   begin
      if C <= 4 then Pending (C) := Pending (C) + V; end if;
   end Add_Mood;

   procedure Turn (E : Entity_Id; Tick : Int; Moods : Mood_Array; Lines : in out Str_Vectors.Vector; Played : out Boolean;
                   Partner : out Comp_Id; Move_Text, Num_Text : out Unbounded_String;
                   Detail : in out Unbounded_String) is
      Eid : constant Positive := Positive (E);
      Me : constant Comp_Id := Comp_Id (E);
      Cand : array (Comp_Id) of Boolean := [others => False];
      N : Natural := 0;
      Ign : Boolean;
      U1, U2 : Unbounded_String;
   begin
      Played := False;
      Partner := Me;
      Move_Text := Null_Unbounded_String;
      Num_Text := Null_Unbounded_String;
      if Holiday_C (Me, Tick) then return; end if;
      --  a holiday notice: its clock stops while it is away and it plays no game
      if Int (Roll (Seed_V, Eid, Tick, 9410, 100)) <= Int (Hol_Pct) then
         Holiday_Until (Me) := Tick + Int (Hol_Len);
         Holidays (Me) := Holidays (Me) + 1;
         Lines.Append ("hol " & Name (E) & " until=" & Img (Holiday_Until (Me)));
         Append (Detail, (if Length (Detail) > 0 then "; " else "") & Msg ("detail.chess_holiday", Img (Holiday_Until (Me))));
         return;
      end if;
      for X in Entity_Id loop
         if X /= E and then not On_Holiday (X, Tick) and then Sim_Things.Adjacent (E, X) then Cand (Comp_Id (X)) := True; end if;
      end loop;
      for P in 5 .. 7 loop
         if In_Range (P, E) then Cand (P) := True; end if;
      end loop;
      for C of Cand loop N := N + Boolean'Pos (C); end loop;
      if N > 0 then
         declare
            K : Integer := Roll (Seed_V, Eid, Tick, 9400, N);
            O : Comp_Id := Me;
         begin
            for C in Comp_Id loop
               if Cand (C) then
                  K := K - 1;
                  if K = 0 then O := C; end if;
               end if;
            end loop;
            Pair (Me, O, Tick, Moods, Lines, Played, Move_Text, Num_Text, Detail, True);
            if Played then Partner := O; end if;
         end;
      end if;
      --  two players in range of E play each other
      declare
         Ps : array (1 .. 3) of Comp_Id;
         NP : Natural := 0;
      begin
         for P in 5 .. 7 loop
            if In_Range (P, E) then NP := NP + 1; Ps (NP) := P; end if;
         end loop;
         if NP >= 2 and then Int (Roll (Seed_V, Eid, Tick, 9430, 100)) <= Int (PP_Pct) then
            declare
               I : constant Positive := Roll (Seed_V, Eid, Tick, 9431, NP);
               J0 : constant Positive := Roll (Seed_V, Eid, Tick, 9432, NP - 1);
               J : constant Positive := (if J0 >= I then J0 + 1 else J0);
            begin
               Pair (Ps (I), Ps (J), Tick, Moods, Lines, Ign, U1, U2, Detail, False);
            end;
         end if;
      end;
   end Turn;

   --  The clock of the side to move runs every tick unless that side is on holiday; a flagged side loses on time.
   procedure Clock (Tick : Int; Lines : in out Str_Vectors.Vector) is
   begin
      Skip_Done;
      for I in First_Run .. Natural (Games.Length) loop
         if Games (I).Res = Running then
            declare   --  0.060: the idle count in place (was a copy of the whole game, moves and keys, per tick)
               White_To_Move : constant Boolean := Sim_Chess."=" (Games.Constant_Reference (I).Pos.To_Move, Sim_Chess.White);
               Mover : constant Comp_Id := (if White_To_Move then Games.Constant_Reference (I).W else Games.Constant_Reference (I).B);
               Idle : Natural;
            begin
               if not Holiday_C (Mover, Tick) then
                  Games.Reference (I).Idle := Games.Constant_Reference (I).Idle + 1;
                  Idle := Games.Constant_Reference (I).Idle;
                  if Idle >= Timeout then Finish (I, (if White_To_Move then Black_Wins else White_Wins), "timeout", Tick, Lines); end if;
               end if;
            end;
         end if;
      end loop;
   end Clock;

   function Game_Count return Natural is (Natural (Games.Length));
   function Finished_Count return Natural is
      N : Natural := 0;
   begin
      for G of Games loop N := N + Boolean'Pos (G.Res /= Running); end loop;
      return N;
   end Finished_Count;
   function Moves_Total return Natural is
      N : Natural := 0;
   begin
      for G of Games loop N := N + Natural (G.Moves.Length); end loop;
      return N;
   end Moves_Total;

   function Report (Full : Boolean) return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
   begin
      for I in 1 .. Natural (Games.Length) loop
         declare
            G : constant Game_Rec := Games (I);
            Mv : Unbounded_String;
            Shown : constant Natural := (if Full then Natural (G.Moves.Length) else Natural'Min (6, Natural (G.Moves.Length)));
         begin
            for K in 1 .. Shown loop
               Append (Mv, (if K = 1 then "" else " ") & G.Moves (K));
            end loop;
            R.Append (Msg ("chess.game", "G" & Img (I), Comp_Name (G.W) & "-" & Comp_Name (G.B), Result_Text (G.Res),
                           (if G.Res = Running then Msg ("chess.running") else To_String (G.Why)),
                           Img (Natural (G.Moves.Length)), To_String (Mv) & (if Shown < Natural (G.Moves.Length) then " ..." else "")));
         end;
      end loop;
      return R;
   end Report;

   function Summary (C : Comp_Id) return String is
     (Msg ("chess.sum", Comp_Name (C), Img (Rate (C)), Img (Won (C)), Img (Drawn (C)), Img (Lost (C)),
           Msg ("chess.sum2", Img (By_Time (C)), Img (By_Resign (C)), Img (Made (C)), Img (Holidays (C)))));

   --  Best rating first (ties: the lower id).
   function Ranking return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
      Taken : array (Comp_Id) of Boolean := [others => False];
   begin
      R.Append (Msg ("elo.head", Img (Elo_Start), Img (Elo_K)));
      for Place in Comp_Id loop
         declare
            Best : Natural := 0;
         begin
            for C in Comp_Id loop
               if not Taken (C) and then (Best = 0 or else Rate (C) > Rate (Best)) then Best := C; end if;
            end loop;
            Taken (Best) := True;
            R.Append (Msg ("elo.row", Img (Place), Comp_Name (Best), Img (Rate (Best)),
                           Sgn (Int (Rate (Best)) - Int (Elo_Start)),
                           Img (Won (Best)) & "/" & Img (Drawn (Best)) & "/" & Img (Lost (Best)),
                           Img (By_Time (Best)) & "/" & Img (By_Resign (Best))));
         end;
      end loop;
      return R;
   end Ranking;

   function Digest_Line return String is
      R : Unbounded_String;
      Taken : array (Comp_Id) of Boolean := [others => False];
   begin
      for Place in Comp_Id loop
         declare
            Best : Natural := 0;
         begin
            for C in Comp_Id loop
               if not Taken (C) and then (Best = 0 or else Rate (C) > Rate (Best)) then Best := C; end if;
            end loop;
            Taken (Best) := True;
            Append (R, (if Place = 1 then "" else " ") & Comp_Name (Best) & " " & Img (Rate (Best)));
         end;
      end loop;
      return Msg ("elo.digest", To_String (R));
   end Digest_Line;

   --  0.058: the checkpoint.
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Integer);
      procedure IO is new Sim_Ckpt.IO (Int);
      procedure IO is new Sim_Ckpt.IO (Boolean);
      procedure IO is new Sim_Ckpt.IO (Game_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Ints);
      procedure IO is new Sim_Ckpt.IO (Counts);
      procedure IO is new Sim_Ckpt.IO (Pair_Ints);
      procedure IO is new Sim_Ckpt.IO (Pair_Counts);
      procedure IO is new Sim_Ckpt.IO (Table_Array);
   begin
      IO (S, Save, Games);
      IO (S, Save, Seed_V);
      IO (S, Save, Holiday_Until);
      for C in Comp_Id loop IO (S, Save, Pending (C)); IO (S, Save, Rate (C)); end loop;
      IO (S, Save, Last_End);
      IO (S, Save, Pair_Games);
      IO (S, Save, Won); IO (S, Save, Lost); IO (S, Save, Drawn); IO (S, Save, Made); IO (S, Save, Holidays); IO (S, Save, By_Time);
      IO (S, Save, By_Resign); IO (S, Save, Played_N);
      IO (S, Save, Table);
      IO (S, Save, Gap); IO (S, Save, Start_Pct); IO (S, Save, Pause); IO (S, Save, Timeout); IO (S, Save, Max_Plies); IO (S, Save, Repeat);
      IO (S, Save, Hol_Pct); IO (S, Save, Hol_Len); IO (S, Save, Smin); IO (S, Save, Smax); IO (S, Save, Win_Mood); IO (S, Save, Draw_Mood);
      IO (S, Save, Loss_Mood); IO (S, Save, Res_Pct); IO (S, Save, Res_Gap); IO (S, Save, Res_Mood); IO (S, Save, Res_Mood_Pct);
      IO (S, Save, Res_Min); IO (S, Save, PP_Pct); IO (S, Save, Elo_Start); IO (S, Save, Elo_K);
      IO (S, Save, Forced);
      IO (S, Save, Quiet);
      IO (S, Save, Rules); IO (S, Save, Fives); IO (S, Save, Moves75); IO (S, Save, Claim_Pct); IO (S, Save, Claim_Behind);
   end State_IO;

end Sim_Games;
