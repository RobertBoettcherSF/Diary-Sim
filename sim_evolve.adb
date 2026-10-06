--  Version: 0.002
--  See the spec.  Counting only: integer arithmetic, no dice, no clock, no files.
pragma Ada_2022;


package body Sim_Evolve is

   use Sim_Chess;

   --  ---- words ------------------------------------------------------------------------------------------------
   type Event is record
      Sess : Natural := 0;
      Tick : Natural := 0;
      Kind : Event_Kind := Mention;
   end record;
   package Event_Vectors is new Ada.Containers.Vectors (Positive, Event);
   function Before (A, B : Event) return Boolean is (A.Sess < B.Sess or else (A.Sess = B.Sess and then A.Tick < B.Tick));
   package Event_Sort is new Event_Vectors.Generic_Sorting ("<" => Before);

   type Word_Rec is record
      Tick : Natural := 0;
      Base, Symbol : Boolean := False;
      Ev : Event_Vectors.Vector;
      R : Word_Result;
      Idle_Run : Natural := 0;
      Paid : Boolean := False;
   end record;
   package Word_Vectors is new Ada.Containers.Vectors (Positive, Word_Rec);
   Words : array (1 .. Max_Ent) of Word_Vectors.Vector;
   Tot : array (1 .. Max_Ent) of Word_Totals;
   Pr : Word_Params;
   Starts : Int_Vectors.Vector;

   function Session_Of (Tick : Natural) return Positive is   --  the session whose ticks are (start, start + len]: the last start below Tick
      Lo : Natural := 1;
      Hi : Natural := Natural (Starts.Length);
      Best : Positive := 1;
   begin
      while Lo <= Hi loop
         declare
            Mid : constant Positive := (Lo + Hi) / 2;
         begin
            if Starts.Element (Mid) < Integer (Tick) then
               Best := Mid;
               Lo := Mid + 1;
            else
               Hi := Mid - 1;
            end if;
         end;
      end loop;
      return Best;
   end Session_Of;

   function Sessions return Natural is (Natural'Max (1, Natural (Starts.Length)));

   procedure Words_Reset (Pr : Word_Params; Starts : Int_Vectors.Vector) is
   begin
      for E in Words'Range loop Words (E).Clear; Tot (E) := (others => <>); end loop;
      Sim_Evolve.Pr := Pr;
      Sim_Evolve.Starts := Starts;
      if Sim_Evolve.Starts.Is_Empty then Sim_Evolve.Starts.Append (0); end if;
   end Words_Reset;

   procedure Add_Word (E : Positive; Tick : Natural; Base, Symbol : Boolean) is
   begin
      Words (E).Append (Word_Rec'(Tick => Tick, Base => Base, Symbol => Symbol, others => <>));
   end Add_Word;

   procedure Add_Event (E : Positive; Word : Positive; Tick : Natural; Kind : Event_Kind) is
   begin
      if E <= Max_Ent and then Word <= Natural (Words (E).Length) then
         Words (E) (Word).Ev.Append (Event'(Sess => 0, Tick => Tick, Kind => Kind));
      end if;
   end Add_Event;

   type Cand is record
      Fit : Natural;
      Idx : Positive;
   end record;
   package Cand_Vectors is new Ada.Containers.Vectors (Positive, Cand);
   function Weaker (A, B : Cand) return Boolean is (A.Fit < B.Fit or else (A.Fit = B.Fit and then A.Idx < B.Idx));
   package Cand_Sort is new Cand_Vectors.Generic_Sorting ("<" => Weaker);

   --  0.057: the sessions loop visits only the LIVE words (not a symbol, born, not dormant) instead of every word of the list: the
   --  same result (every live word is updated on its own; the candidates are sorted by fitness and index), but a long save no
   --  longer costs words x sessions (make evolve / make active scaled with both).
   package Idx_Vectors is new Ada.Containers.Vectors (Positive, Positive);
   procedure Run_One (E : Positive) is
      Ws : Word_Vectors.Vector renames Words (E);
      Cursor : array (1 .. Natural'Max (1, Natural (Ws.Length))) of Natural := [others => 1];
      Active : Natural := 0;
      Was_Above : Boolean := False;
      Born_In : array (1 .. Sessions) of Idx_Vectors.Vector;   --  the non-symbol words born in each session, in index order
      Live, Kept : Idx_Vectors.Vector;                         --  the live words, in index order
   begin
      for W of Ws loop
         W.R.Born := Session_Of (W.Tick);
         for Ev of W.Ev loop Ev.Sess := Session_Of (Ev.Tick); end loop;
         Event_Sort.Sort (W.Ev);
      end loop;
      for I in 1 .. Natural (Ws.Length) loop
         if not Ws (I).Symbol and then Ws (I).R.Born in Born_In'Range then Born_In (Ws (I).R.Born).Append (I); end if;
      end loop;
      for K in 1 .. Sessions loop
         declare
            Retire_Left : Natural := Pr.Retire_Max;
            Idle_C, Cap_C : Cand_Vectors.Vector;
            Births : constant Natural := Natural (Born_In (K).Length);
         begin
            if Births > 0 then   --  the newborn join the live words (index order kept: a merge)
               Kept.Clear;
               declare
                  A, B : Positive := 1;
               begin
                  while A <= Natural (Live.Length) or else B <= Births loop
                     if B > Births or else (A <= Natural (Live.Length) and then Live (A) < Born_In (K) (B)) then
                        Kept.Append (Live (A)); A := A + 1;
                     else
                        Kept.Append (Born_In (K) (B)); B := B + 1;
                     end if;
                  end loop;
               end;
               Live.Move (Kept);
            end if;
            for I of Live loop
               declare
                  W : Word_Rec renames Ws (I);
                  U, G, A : Natural := 0;
               begin
                  if not W.Symbol and then W.R.Born <= K and then W.R.Dormant_In = 0 then
                     while Cursor (I) <= Natural (W.Ev.Length) and then W.Ev (Cursor (I)).Sess <= K loop
                        case W.Ev (Cursor (I)).Kind is
                           when Mention => U := U + 1;
                           when Granted => G := G + 1;
                           when Agreed => A := A + 1;
                        end case;
                        Cursor (I) := Cursor (I) + 1;
                     end loop;
                     declare
                        Pts : constant Natural := Natural'Min (Pr.Use_Cap, U) * Pr.Use_Pts + G * Pr.Grant_Pts
                                                  + (if A > 0 and then not W.Paid then Pr.Agree_Pts else 0);
                     begin
                        if A > 0 then W.Paid := True; end if;
                        W.R.Uses := W.R.Uses + U + G + A;
                        if U + G + A > 0 then W.R.Sessions := W.R.Sessions + 1; end if;
                        W.R.Fit10 := Natural'Min (Pr.Fit_Cap * 10, (3 * W.R.Fit10 + 40 * Pts) / 4);
                        if not W.Base and then K - W.R.Born >= Pr.Probation and then W.R.Fit10 <= Pr.Line10 then
                           W.Idle_Run := W.Idle_Run + 1;
                        else
                           W.Idle_Run := 0;
                        end if;
                     end;
                  end if;
               end;
            end loop;
            Active := Active + Births;
            if Pr.Cap > 0 and then Active > Pr.Cap then Was_Above := True; end if;
            for I of Live loop
               declare
                  W : Word_Rec renames Ws (I);
               begin
                  if not W.Symbol and then not W.Base and then W.R.Born <= K and then W.R.Dormant_In = 0 then
                     if W.Idle_Run >= Natural'Max (1, Pr.Idle) then Idle_C.Append (Cand'(W.R.Fit10, I)); end if;
                     if Pr.Cap > 0 and then K - W.R.Born >= Pr.Probation then Cap_C.Append (Cand'(W.R.Fit10, I)); end if;
                  end if;
               end;
            end loop;
            Cand_Sort.Sort (Idle_C);
            Cand_Sort.Sort (Cap_C);
            for C of Idle_C loop
               exit when Retire_Left = 0 or else Active <= Pr.Min_Active;
               Ws (C.Idx).R.Dormant_In := K;
               Ws (C.Idx).R.Fit_Then := Ws (C.Idx).R.Fit10;
               Active := Active - 1;
               Retire_Left := Retire_Left - 1;
            end loop;
            if Pr.Cap > 0 then
               for C of Cap_C loop
                  exit when Retire_Left = 0 or else Active <= Pr.Cap;
                  if Ws (C.Idx).R.Dormant_In = 0 then
                     Ws (C.Idx).R.Dormant_In := K;
                     Ws (C.Idx).R.Fit_Then := Ws (C.Idx).R.Fit10;
                     Active := Active - 1;
                     Retire_Left := Retire_Left - 1;
                  end if;
               end loop;
               if Was_Above and then Active <= Pr.Cap and then Tot (E).Cap_Reached = 0 then Tot (E).Cap_Reached := K; end if;
            end if;
            Kept.Clear;   --  the words that went dormant leave the live list
            for I of Live loop
               if Ws (I).R.Dormant_In = 0 then Kept.Append (I); end if;
            end loop;
            Live.Move (Kept);
         end;
      end loop;
      for W of Ws loop
         Tot (E).Known := Tot (E).Known + 1;
         if W.Symbol then
            Tot (E).Symbols := Tot (E).Symbols + 1;
         elsif W.R.Dormant_In = 0 then
            Tot (E).Active := Tot (E).Active + 1;
            if W.Base then Tot (E).Base := Tot (E).Base + 1; end if;
            Tot (E).Fit10_Sum := Tot (E).Fit10_Sum + W.R.Fit10;
            if not W.Base and then W.Idle_Run >= Natural'Max (1, Pr.Idle) then Tot (E).Held := Tot (E).Held + 1; end if;
         else
            Tot (E).Dormant := Tot (E).Dormant + 1;
            for Ev of W.Ev loop
               if Ev.Sess > W.R.Dormant_In then W.R.Later := W.R.Later + 1; end if;
            end loop;
            if W.R.Later > 0 then Tot (E).Woken_Later := Tot (E).Woken_Later + 1; end if;
         end if;
      end loop;
      Tot (E).Over_Cap := (if Pr.Cap > 0 and then Tot (E).Active > Pr.Cap then Tot (E).Active - Pr.Cap else 0);
   end Run_One;

   procedure Words_Run is
   begin
      for E in Words'Range loop Run_One (E); end loop;
   end Words_Run;

   function Count (E : Positive) return Natural is (Natural (Words (E).Length));
   function Result (E : Positive; Word : Positive) return Word_Result is (Words (E) (Word).R);
   function Is_Base (E : Positive; Word : Positive) return Boolean is (Words (E) (Word).Base);
   function Is_Symbol (E : Positive; Word : Positive) return Boolean is (Words (E) (Word).Symbol);
   function Totals (E : Positive) return Word_Totals is (Tot (E));

   --  ---- chess ------------------------------------------------------------------------------------------------
   function Opening_Bucket (Coord : String) return Natural is
      H : Natural := 0;
   begin
      for C of Coord loop H := (H * 31 + Character'Pos (C)) mod 65521; end loop;
      return H mod 16;
   end Opening_Bucket;

   procedure Move_Features (P : Position; M : Move; Side_Ply : Positive; Into : in out Feature_Counts) is
      C : constant Cell := P.Board (M.From);
      T : constant Cell := P.Board (M.To);
      Taken : Piece_Kind := (if T.Kind /= None and then T.Side /= C.Side then T.Kind else None);
      From_File : constant Integer := M.From mod 8;
      To_File : constant Integer := M.To mod 8;
      To_Rank : constant Integer := M.To / 8;
      Q : constant Position := Play (P, M);
      Castles : constant Boolean := C.Kind = King and then abs (M.To - M.From) = 2;
      Centre : constant Boolean := M.To in 27 | 28 | 35 | 36;

      procedure Hit (F : Feature) is
      begin
         Into (F) := Into (F) + 1;
      end Hit;
   begin
      if C.Kind = Pawn and then T.Kind = None and then From_File /= To_File then Taken := Pawn; end if;   --  en passant
      Hit (Piece_Kind'Pos (C.Kind));
      if Taken in Pawn .. Queen then Hit (6 + Piece_Kind'Pos (Taken)); end if;
      if In_Check (Q, Q.To_Move) then Hit (12); end if;
      if Castles then Hit (13); end if;
      if M.Promo /= None then Hit (14); end if;
      if Centre then Hit (15); elsif To_File in 2 .. 5 and then To_Rank in 2 .. 5 then Hit (16); end if;
      if C.Kind = Pawn and then abs (M.To - M.From) = 16 then Hit (17); end if;
      if C.Kind in Knight | Bishop and then M.From / 8 = (if C.Side = White then 0 else 7) then Hit (18); end if;
      if C.Kind = King and then not Castles and then Side_Ply <= 10 then Hit (19); end if;
      if Side_Ply <= 3 then
         declare
            Text : constant String := [Character'Val (Character'Pos ('a') + From_File), Character'Val (Character'Pos ('1') + M.From / 8),
                                       Character'Val (Character'Pos ('a') + To_File), Character'Val (Character'Pos ('1') + To_Rank)];
         begin
            Hit (20 + Opening_Bucket (Text));
         end;
      end if;
   end Move_Features;

   type Side_Uses is array (Colour) of Feature_Counts;
   type Game_Rec is record
      Open : Boolean := False;
      White, Black : Natural := 0;
      Pos : Position;
      Plies : Natural := 0;
      Uses : Side_Uses := [others => [others => 0]];
   end record;
   package Game_Vectors is new Ada.Containers.Vectors (Positive, Game_Rec);
   Games : Game_Vectors.Vector;
   type Comp_Weights is array (1 .. Max_Comp) of Weight_Table;
   Weights, Pending : Comp_Weights := [others => [others => 0]];
   type Comp_Counts is array (1 .. Max_Comp) of Natural;
   N_Games, N_Wins, N_Draws : Comp_Counts := [others => 0];
   type Comp_Sums is array (1 .. Max_Comp) of Feature_Counts;
   Sum_Uses : Comp_Sums := [others => [others => 0]];   --  uses of each feature in all games of a competitor so far (its usual number per game)
   Cp : Chess_Params;
   C_Starts : Int_Vectors.Vector;
   Cur_Sess : Natural := 0;
   Moves_N, Hits_N : Natural := 0;
   Curve : array (1 .. Max_Comp) of Int_Vectors.Vector;
   Last_Rating : array (1 .. Max_Comp) of Positive := [others => 1];

   function C_Session_Of (Tick : Natural) return Positive is   --  the last start below Tick (the starts ascend: a binary search, 0.057)
      Lo : Natural := 1;
      Hi : Natural := Natural (C_Starts.Length);
      Best : Positive := 1;
   begin
      while Lo <= Hi loop
         declare
            Mid : constant Positive := (Lo + Hi) / 2;
         begin
            if C_Starts.Element (Mid) < Integer (Tick) then
               Best := Mid;
               Lo := Mid + 1;
            else
               Hi := Mid - 1;
            end if;
         end;
      end loop;
      return Best;
   end C_Session_Of;

   procedure Chess_Reset (Pr : Chess_Params; Starts : Int_Vectors.Vector) is
   begin
      Games.Clear;
      Weights := [others => [others => 0]];
      Pending := [others => [others => 0]];
      N_Games := [others => 0];
      N_Wins := [others => 0];
      N_Draws := [others => 0];
      Sum_Uses := [others => [others => 0]];
      Cp := Pr;
      C_Starts := Starts;
      if C_Starts.Is_Empty then C_Starts.Append (0); end if;
      Cur_Sess := 0;
      Moves_N := 0;
      Hits_N := 0;
      for C in Curve'Range loop Curve (C).Clear; Last_Rating (C) := Positive'Max (1, Pr.Elo_Start); end loop;
   end Chess_Reset;

   procedure Flush is
   begin
      for C in 1 .. Max_Comp loop
         declare
            Total : Natural := 0;
         begin
            for F in Feature loop
               Pending (C) (F) := Integer'Max (-Integer (Cp.Sess_Max), Integer'Min (Integer (Cp.Sess_Max), Pending (C) (F)));
               Total := Total + abs Pending (C) (F);
            end loop;
            for F in Feature loop
               declare
                  D : constant Integer := (if Total > Cp.Sess_Total and then Total > 0 then Pending (C) (F) * Integer (Cp.Sess_Total) / Integer (Total)
                                           else Pending (C) (F));
                  W : constant Integer := Weights (C) (F) + D;
               begin
                  if abs W > Integer (Cp.W_Max) then Hits_N := Hits_N + 1; end if;
                  Weights (C) (F) := Integer'Max (-Integer (Cp.W_Max), Integer'Min (Integer (Cp.W_Max), W));
                  Pending (C) (F) := 0;
               end;
            end loop;
         end;
      end loop;
   end Flush;

   procedure Chess_Start (G : Positive; White, Black : Positive) is
   begin
      while Natural (Games.Length) < G loop Games.Append (Game_Rec'(others => <>)); end loop;
      Games (G) := (Open => White <= Max_Comp and then Black <= Max_Comp, White => White, Black => Black, Pos => Start, Plies => 0, others => <>);
   end Chess_Start;

   procedure Chess_Move (G : Positive; Coord : String) is
   begin
      if G > Natural (Games.Length) or else not Games (G).Open or else Coord'Length not in 4 .. 5 then return; end if;
      declare
         Gm : Game_Rec renames Games (G);
         function Sq (F, R : Character) return Integer is
           ((Character'Pos (R) - Character'Pos ('1')) * 8 + Character'Pos (F) - Character'Pos ('a'));
         From : constant Integer := Sq (Coord (Coord'First), Coord (Coord'First + 1));
         To : constant Integer := Sq (Coord (Coord'First + 2), Coord (Coord'First + 3));
         Promo : constant Piece_Kind :=
           (if Coord'Length = 5 then (case Coord (Coord'Last) is when 'q' => Queen, when 'r' => Rook, when 'b' => Bishop, when 'n' => Knight, when others => None)
            else None);
      begin
         if From not in Square or else To not in Square then return; end if;
         declare
            L : constant Move_List := Legal (Gm.Pos);
            Side : constant Colour := Gm.Pos.To_Move;
         begin
            for I in 1 .. L.Count loop
               if L.Items (I).From = From and then L.Items (I).To = To and then L.Items (I).Promo = Promo then
                  Move_Features (Gm.Pos, L.Items (I), Gm.Plies / 2 + 1, Gm.Uses (Side));
                  Gm.Pos := Play (Gm.Pos, L.Items (I));
                  Gm.Plies := Gm.Plies + 1;
                  Moves_N := Moves_N + 1;
                  return;
               end if;
            end loop;
         end;
      end;
   end Chess_Move;

   procedure Chess_End (G : Positive; Tick : Natural; Result_White, Delta_White : Integer) is
      S : constant Positive := C_Session_Of (Tick);
   begin
      if G > Natural (Games.Length) or else not Games (G).Open then return; end if;
      if Cur_Sess /= 0 and then S > Cur_Sess then Flush; end if;
      Cur_Sess := S;
      declare
         Gm : Game_Rec renames Games (G);
         Step : constant Integer := Integer (Cp.Step) * (if abs Delta_White >= Integer (Cp.Big_Elo) then 2 else 1);
      begin
         for Side in Colour loop
            declare
               C : constant Positive := (if Side = White then Gm.White else Gm.Black);
               Sign : constant Integer := (if Side = White then Result_White else -Result_White);
            begin
               --  credit for what was DIFFERENT in this game: the uses of a feature minus its usual number of uses for this competitor
               --  (a feature used the same way in every game, like "a pawn moved", teaches nothing)
               for F in Feature loop
                  declare
                     Usual : constant Integer := (if N_Games (C) = 0 then Integer (Gm.Uses (Side) (F))
                                                  else (Integer (Sum_Uses (C) (F)) + Integer (N_Games (C)) / 2) / Integer (N_Games (C)));
                     Dev : constant Integer := Integer'Max (-Integer (Cp.Use_Cap), Integer'Min (Integer (Cp.Use_Cap), Integer (Gm.Uses (Side) (F)) - Usual));
                  begin
                     Pending (C) (F) := Pending (C) (F) + Sign * Dev * Step;
                     Sum_Uses (C) (F) := Sum_Uses (C) (F) + Gm.Uses (Side) (F);
                  end;
               end loop;
               N_Games (C) := N_Games (C) + 1;
               if Sign > 0 then N_Wins (C) := N_Wins (C) + 1; elsif Sign = 0 then N_Draws (C) := N_Draws (C) + 1; end if;
            end;
         end loop;
         Gm.Open := False;
      end;
   end Chess_End;

   procedure Chess_Finish is
   begin
      if Cur_Sess /= 0 then Flush; end if;
   end Chess_Finish;

   procedure Elo_Point (Comp : Positive; Tick : Natural; Rating : Positive) is
      S : constant Positive := C_Session_Of (Tick);
   begin
      if Comp > Max_Comp then return; end if;
      while Natural (Curve (Comp).Length) < S - 1 loop Curve (Comp).Append (Integer (Last_Rating (Comp))); end loop;
      if Natural (Curve (Comp).Length) >= S then Curve (Comp).Replace_Element (S, Integer (Rating)); else Curve (Comp).Append (Integer (Rating)); end if;
      Last_Rating (Comp) := Rating;
   end Elo_Point;

   function Weight (Comp : Positive; F : Feature) return Integer is (Weights (Comp) (F));
   function Games_Of (Comp : Positive) return Natural is (N_Games (Comp));
   function Wins_Of (Comp : Positive) return Natural is (N_Wins (Comp));
   function Draws_Of (Comp : Positive) return Natural is (N_Draws (Comp));
   function Moves_Seen return Natural is (Moves_N);
   function Bounded_Hits return Natural is (Hits_N);
   function Elo_Sessions return Natural is (Natural (C_Starts.Length));
   function Elo_At (Comp : Positive; Session : Positive) return Positive is
     (if Session <= Natural (Curve (Comp).Length) then Positive (Curve (Comp).Element (Session)) else Last_Rating (Comp));

end Sim_Evolve;
