--  Version: 0.002
--  See sim_chess.ads.
pragma Ada_2022;

with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Sim_Chess is

   use Interfaces;
   use Sim_Util;

   type Offset is record
      DF, DR : Integer;   --  file and rank step
   end record;
   type Offset_List is array (Positive range <>) of Offset;
   Knight_Steps : constant Offset_List := [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)];
   King_Steps   : constant Offset_List := [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];
   Rook_Dirs    : constant Offset_List := [(1, 0), (0, 1), (-1, 0), (0, -1)];
   Bishop_Dirs  : constant Offset_List := [(1, 1), (-1, 1), (-1, -1), (1, -1)];
   Two_Sides    : constant array (1 .. 2) of Integer := [-1, 1];
   Promotions   : constant array (1 .. 4) of Piece_Kind := [Queen, Rook, Bishop, Knight];

   function Steps_Of (K : Piece_Kind) return Offset_List is (if K = Knight then Knight_Steps else King_Steps);
   function Dirs_Of (Pass : Positive) return Offset_List is (if Pass = 1 then Rook_Dirs else Bishop_Dirs);

   function File_Of (S : Square) return Integer is (S mod 8);
   function Rank_Of (S : Square) return Integer is (S / 8);
   function Other (C : Colour) return Colour is (if C = White then Black else White);
   function On_Board (F, R : Integer) return Boolean is (F in 0 .. 7 and then R in 0 .. 7);

   function Start return Position is
      Fen_Start : constant String := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
      OK : Boolean;
   begin
      return From_Fen (Fen_Start, OK);
   end Start;

   function From_Fen (Fen : String; OK : out Boolean) return Position is
      P : Position;
      I : Positive := Fen'First;
      F : Integer := 0;
      R : Integer := 7;
   begin
      OK := False;
      P.Board := [others => (None, White)];
      while I <= Fen'Last and then Fen (I) /= ' ' loop
         declare
            C : constant Character := Fen (I);
         begin
            if C = '/' then
               R := R - 1;
               F := 0;
            elsif C in '1' .. '8' then
               F := F + Character'Pos (C) - Character'Pos ('0');
            else
               if not On_Board (F, R) then return P; end if;
               declare
                  Side : constant Colour := (if C in 'A' .. 'Z' then White else Black);
                  K : constant Piece_Kind :=
                    (case Ada.Characters.Handling.To_Lower (C) is
                        when 'p' => Pawn, when 'n' => Knight, when 'b' => Bishop, when 'r' => Rook,
                        when 'q' => Queen, when 'k' => King, when others => None);
               begin
                  if K = None then return P; end if;
                  P.Board (R * 8 + F) := (K, Side);
               end;
               F := F + 1;
            end if;
         end;
         I := I + 1;
      end loop;
      if I > Fen'Last then return P; end if;
      I := I + 1;
      if I > Fen'Last then return P; end if;
      P.To_Move := (if Fen (I) = 'b' then Black else White);
      I := I + 2;
      P.Castle := [others => False];
      while I <= Fen'Last and then Fen (I) /= ' ' loop
         case Fen (I) is
            when 'K' => P.Castle (1) := True;
            when 'Q' => P.Castle (2) := True;
            when 'k' => P.Castle (3) := True;
            when 'q' => P.Castle (4) := True;
            when others => null;
         end case;
         I := I + 1;
      end loop;
      I := I + 1;
      P.Ep := -1;
      if I + 1 <= Fen'Last and then Fen (I) in 'a' .. 'h' and then Fen (I + 1) in '1' .. '8' then
         P.Ep := (Character'Pos (Fen (I + 1)) - Character'Pos ('1')) * 8 + (Character'Pos (Fen (I)) - Character'Pos ('a'));
      end if;
      I := I + 2;
      P.Half := 0;
      P.Full := 1;
      declare   --  the two optional counters
         Num : Natural := 0;
         Have : Boolean := False;
         Which : Natural := 0;
      begin
         while I <= Fen'Last + 1 loop
            if I <= Fen'Last and then Fen (I) in '0' .. '9' then
               Num := Num * 10 + Character'Pos (Fen (I)) - Character'Pos ('0');
               Have := True;
            elsif Have then
               Which := Which + 1;
               if Which = 1 then P.Half := Num; elsif Which = 2 and then Num > 0 then P.Full := Num; end if;
               Num := 0;
               Have := False;
            end if;
            I := I + 1;
         end loop;
      end;
      OK := True;
      return P;
   end From_Fen;

   function To_Fen (P : Position) return String is
      use Ada.Strings.Unbounded;
      Res : Unbounded_String;
      Letters : constant array (Piece_Kind) of Character := [' ', 'p', 'n', 'b', 'r', 'q', 'k'];
   begin
      for R in reverse 0 .. 7 loop
         declare
            Empty : Natural := 0;
         begin
            for F in 0 .. 7 loop
               declare
                  C : constant Cell := P.Board (R * 8 + F);
               begin
                  if C.Kind = None then
                     Empty := Empty + 1;
                  else
                     if Empty > 0 then Append (Res, Character'Val (Character'Pos ('0') + Empty)); Empty := 0; end if;
                     Append (Res, (if C.Side = White then Ada.Characters.Handling.To_Upper (Letters (C.Kind)) else Letters (C.Kind)));
                  end if;
               end;
            end loop;
            if Empty > 0 then Append (Res, Character'Val (Character'Pos ('0') + Empty)); end if;
            if R > 0 then Append (Res, '/'); end if;
         end;
      end loop;
      Append (Res, (if P.To_Move = White then " w " else " b "));
      if P.Castle = [False, False, False, False] then
         Append (Res, '-');
      else
         if P.Castle (1) then Append (Res, 'K'); end if;
         if P.Castle (2) then Append (Res, 'Q'); end if;
         if P.Castle (3) then Append (Res, 'k'); end if;
         if P.Castle (4) then Append (Res, 'q'); end if;
      end if;
      Append (Res, ' ');
      if P.Ep < 0 then
         Append (Res, '-');
      else
         Append (Res, Character'Val (Character'Pos ('a') + File_Of (P.Ep)));
         Append (Res, Character'Val (Character'Pos ('1') + Rank_Of (P.Ep)));
      end if;
      Append (Res, " " & Img (P.Half) & " " & Img (P.Full));
      return To_String (Res);
   end To_Fen;

   --  Is Sq attacked by a piece of colour By?
   function Attacked (P : Position; Sq : Square; By : Colour) return Boolean is
      F : constant Integer := File_Of (Sq);
      R : constant Integer := Rank_Of (Sq);
      Dir : constant Integer := (if By = White then -1 else 1);   --  the rank a pawn of colour By attacks from
   begin
      for DF of Two_Sides loop
         if On_Board (F + DF, R + Dir) and then P.Board ((R + Dir) * 8 + F + DF) = (Pawn, By) then return True; end if;
      end loop;
      for O of Knight_Steps loop
         if On_Board (F + O.DF, R + O.DR) and then P.Board ((R + O.DR) * 8 + F + O.DF) = (Knight, By) then return True; end if;
      end loop;
      for O of King_Steps loop
         if On_Board (F + O.DF, R + O.DR) and then P.Board ((R + O.DR) * 8 + F + O.DF) = (King, By) then return True; end if;
      end loop;
      for O of Rook_Dirs loop
         declare
            X : Integer := F + O.DF;
            Y : Integer := R + O.DR;
         begin
            while On_Board (X, Y) loop
               declare
                  C : constant Cell := P.Board (Y * 8 + X);
               begin
                  if C.Kind /= None then
                     if C.Side = By and then C.Kind in Rook | Queen then return True; end if;
                     exit;
                  end if;
               end;
               X := X + O.DF;
               Y := Y + O.DR;
            end loop;
         end;
      end loop;
      for O of Bishop_Dirs loop
         declare
            X : Integer := F + O.DF;
            Y : Integer := R + O.DR;
         begin
            while On_Board (X, Y) loop
               declare
                  C : constant Cell := P.Board (Y * 8 + X);
               begin
                  if C.Kind /= None then
                     if C.Side = By and then C.Kind in Bishop | Queen then return True; end if;
                     exit;
                  end if;
               end;
               X := X + O.DF;
               Y := Y + O.DR;
            end loop;
         end;
      end loop;
      return False;
   end Attacked;

   function King_Square (P : Position; Side : Colour) return Integer is
   begin
      for S in Square loop
         if P.Board (S) = (King, Side) then return S; end if;
      end loop;
      return -1;
   end King_Square;

   function In_Check (P : Position; Side : Colour) return Boolean is
      K : constant Integer := King_Square (P, Side);
   begin
      return K >= 0 and then Attacked (P, K, Other (Side));
   end In_Check;

   function Play (P : Position; M : Move) return Position is
      N : Position := P;
      Mover : constant Cell := P.Board (M.From);
      Target : constant Cell := P.Board (M.To);
      Us : constant Colour := P.To_Move;
      Back : constant Integer := (if Us = White then 0 else 7);
   begin
      N.Board (M.From) := (None, White);
      N.Board (M.To) := (if M.Promo /= None then (M.Promo, Us) else Mover);
      if Mover.Kind = Pawn and then M.To = P.Ep and then Target.Kind = None and then File_Of (M.From) /= File_Of (M.To) then
         N.Board (M.From / 8 * 8 + File_Of (M.To)) := (None, White);   --  en passant: the passed pawn goes
      end if;
      if Mover.Kind = King and then abs (File_Of (M.To) - File_Of (M.From)) = 2 then   --  castling: the rook jumps
         if File_Of (M.To) = 6 then
            N.Board (Back * 8 + 5) := (Rook, Us);
            N.Board (Back * 8 + 7) := (None, White);
         else
            N.Board (Back * 8 + 3) := (Rook, Us);
            N.Board (Back * 8) := (None, White);
         end if;
      end if;
      if Mover.Kind = King then
         if Us = White then N.Castle (1) := False; N.Castle (2) := False; else N.Castle (3) := False; N.Castle (4) := False; end if;
      end if;
      for Pass in 1 .. 2 loop   --  a rook moved from, or was taken on, its corner
         case (if Pass = 1 then M.From else M.To) is
            when 7 => N.Castle (1) := False;
            when 0 => N.Castle (2) := False;
            when 63 => N.Castle (3) := False;
            when 56 => N.Castle (4) := False;
            when others => null;
         end case;
      end loop;
      N.Ep := (if Mover.Kind = Pawn and then abs (Rank_Of (M.To) - Rank_Of (M.From)) = 2 then (M.From + M.To) / 2 else -1);
      N.Half := (if Mover.Kind = Pawn or else Target.Kind /= None then 0 else P.Half + 1);
      if Us = Black then N.Full := P.Full + 1; end if;
      N.To_Move := Other (Us);
      return N;
   end Play;

   --  Pseudo-legal moves (the own king may be left in check); Legal filters them.
   procedure Generate (P : Position; L : in out Move_List) is
      Us : constant Colour := P.To_Move;
      Them : constant Colour := Other (Us);
      Fwd : constant Integer := (if Us = White then 1 else -1);
      Home_R : constant Integer := (if Us = White then 1 else 6);
      Last_R : constant Integer := (if Us = White then 7 else 0);
      Back : constant Integer := (if Us = White then 0 else 7);

      procedure Put (From, To : Square; Promo : Piece_Kind := None) is
      begin
         L.Count := L.Count + 1;
         L.Items (L.Count) := (From, To, Promo);
      end Put;

      procedure Put_Pawn (From, To : Square) is
      begin
         if Rank_Of (To) = Last_R then
            for K of Promotions loop Put (From, To, K); end loop;
         else
            Put (From, To);
         end if;
      end Put_Pawn;
   begin
      for S in Square loop
         declare
            C : constant Cell := P.Board (S);
            F : constant Integer := File_Of (S);
            R : constant Integer := Rank_Of (S);
         begin
            if C.Kind /= None and then C.Side = Us then
               case C.Kind is
                  when Pawn =>
                     if On_Board (F, R + Fwd) and then P.Board ((R + Fwd) * 8 + F).Kind = None then
                        Put_Pawn (S, (R + Fwd) * 8 + F);
                        if R = Home_R and then P.Board ((R + 2 * Fwd) * 8 + F).Kind = None then Put (S, (R + 2 * Fwd) * 8 + F); end if;
                     end if;
                     for DF of Two_Sides loop
                        if On_Board (F + DF, R + Fwd) then
                           declare
                              T : constant Square := (R + Fwd) * 8 + F + DF;
                           begin
                              if (P.Board (T).Kind /= None and then P.Board (T).Side = Them) or else T = P.Ep then Put_Pawn (S, T); end if;
                           end;
                        end if;
                     end loop;
                  when Knight | King =>
                     for O of Steps_Of (C.Kind) loop
                        if On_Board (F + O.DF, R + O.DR) then
                           declare
                              T : constant Square := (R + O.DR) * 8 + F + O.DF;
                           begin
                              if P.Board (T).Kind = None or else P.Board (T).Side = Them then Put (S, T); end if;
                           end;
                        end if;
                     end loop;
                  when Bishop | Rook | Queen =>
                     for Pass in 1 .. 2 loop
                        if (Pass = 1 and then C.Kind in Rook | Queen) or else (Pass = 2 and then C.Kind in Bishop | Queen) then
                           for O of Dirs_Of (Pass) loop
                              declare
                                 X : Integer := F + O.DF;
                                 Y : Integer := R + O.DR;
                              begin
                                 while On_Board (X, Y) loop
                                    declare
                                       T : constant Square := Y * 8 + X;
                                    begin
                                       if P.Board (T).Kind = None then
                                          Put (S, T);
                                       else
                                          if P.Board (T).Side = Them then Put (S, T); end if;
                                          exit;
                                       end if;
                                    end;
                                    X := X + O.DF;
                                    Y := Y + O.DR;
                                 end loop;
                              end;
                           end loop;
                        end if;
                     end loop;
                  when None => null;
               end case;
            end if;
         end;
      end loop;
      --  castling: rights, empty squares between, king not in check and not passing an attacked square
      declare
         K : constant Square := Back * 8 + 4;
         Base : constant Integer := (if Us = White then 0 else 2);
      begin
         if P.Board (K) = (King, Us) and then not Attacked (P, K, Them) then
            if P.Castle (Base + 1) and then P.Board (Back * 8 + 7) = (Rook, Us)
              and then P.Board (Back * 8 + 5).Kind = None and then P.Board (Back * 8 + 6).Kind = None
              and then not Attacked (P, Back * 8 + 5, Them) and then not Attacked (P, Back * 8 + 6, Them)
            then
               Put (K, Back * 8 + 6);
            end if;
            if P.Castle (Base + 2) and then P.Board (Back * 8) = (Rook, Us)
              and then P.Board (Back * 8 + 1).Kind = None and then P.Board (Back * 8 + 2).Kind = None and then P.Board (Back * 8 + 3).Kind = None
              and then not Attacked (P, Back * 8 + 3, Them) and then not Attacked (P, Back * 8 + 2, Them)
            then
               Put (K, Back * 8 + 2);
            end if;
         end if;
      end;
   end Generate;

   function Legal (P : Position) return Move_List is
      Raw, Res : Move_List;
   begin
      Generate (P, Raw);
      for I in 1 .. Raw.Count loop
         if not In_Check (Play (P, Raw.Items (I)), P.To_Move) then
            Res.Count := Res.Count + 1;
            Res.Items (Res.Count) := Raw.Items (I);
         end if;
      end loop;
      return Res;
   end Legal;

   function State_Of (P : Position) return Game_State is
      L : constant Move_List := Legal (P);
   begin
      if L.Count = 0 then return (if In_Check (P, P.To_Move) then Checkmate else Stalemate); end if;
      return (if P.Half >= 100 then Fifty_Moves else Ongoing);
   end State_Of;

   function Coord (M : Move) return String is
      Promo : constant String :=
        (case M.Promo is when Queen => "q", when Rook => "r", when Bishop => "b", when Knight => "n", when others => "");
   begin
      return [Character'Val (Character'Pos ('a') + File_Of (M.From)), Character'Val (Character'Pos ('1') + Rank_Of (M.From)),
              Character'Val (Character'Pos ('a') + File_Of (M.To)), Character'Val (Character'Pos ('1') + Rank_Of (M.To))] & Promo;
   end Coord;

   function Iccf (M : Move) return String is
      Promo : constant String :=
        (case M.Promo is when Queen => "1", when Rook => "2", when Bishop => "3", when Knight => "4", when others => "");
   begin
      return Img (File_Of (M.From) + 1) & Img (Rank_Of (M.From) + 1) & Img (File_Of (M.To) + 1) & Img (Rank_Of (M.To) + 1) & Promo;
   end Iccf;

   function Same (A, B : Move) return Boolean is (A.From = B.From and then A.To = B.To and then A.Promo = B.Promo);

   function Key (P : Position) return Unsigned_64 is
      H : Unsigned_64 := 14695981039346656037;
      procedure Mix (V : Unsigned_64) is
      begin
         H := (H xor V) * 1099511628211;
         H := H xor Shift_Right (H, 29);
      end Mix;
   begin
      for S in Square loop
         if P.Board (S).Kind /= None then
            Mix (Unsigned_64 (S) * 16 + Unsigned_64 (Piece_Kind'Pos (P.Board (S).Kind)) * 2 + Unsigned_64 (Colour'Pos (P.Board (S).Side)) + 1);
         end if;
      end loop;
      Mix (Unsigned_64 (Colour'Pos (P.To_Move)) + 1000);
      for I in Rights'Range loop
         if P.Castle (I) then Mix (2000 + Unsigned_64 (I)); end if;
      end loop;
      if P.Ep >= 0 then Mix (3000 + Unsigned_64 (P.Ep)); end if;
      return H;
   end Key;

   function Same_Key (A, B : Position) return Boolean is (Key (A) = Key (B));

   function Insufficient (P : Position) return Boolean is
      Minors : Natural := 0;
      Bishops : Natural := 0;
      First_Side : Colour := White;
      First_Shade, Shade : Integer := 0;
      Mixed : Boolean := False;
   begin
      for S in Square loop
         case P.Board (S).Kind is
            when Pawn | Rook | Queen => return False;
            when Knight => Minors := Minors + 1;
            when Bishop =>
               Minors := Minors + 1;
               Shade := (File_Of (S) + Rank_Of (S)) mod 2;
               if Bishops = 0 then
                  First_Side := P.Board (S).Side;
                  First_Shade := Shade;
               else
                  Mixed := First_Side = P.Board (S).Side or else First_Shade /= Shade;
               end if;
               Bishops := Bishops + 1;
            when None | King => null;
         end case;
      end loop;
      return Minors <= 1 or else (Minors = 2 and then Bishops = 2 and then not Mixed);
   end Insufficient;

   function Material (P : Position; Side : Colour) return Integer is
      Value : constant array (Piece_Kind) of Integer := [0, 1, 3, 3, 5, 9, 0];
      T : Integer := 0;
   begin
      for S in Square loop
         if P.Board (S).Kind /= None then T := T + (if P.Board (S).Side = Side then Value (P.Board (S).Kind) else -Value (P.Board (S).Kind)); end if;
      end loop;
      return T;
   end Material;

   function Perft (P : Position; Depth : Natural) return Natural is
      L : constant Move_List := Legal (P);
      N : Natural := 0;
   begin
      if Depth <= 1 then return (if Depth = 0 then 1 else L.Count); end if;
      for I in 1 .. L.Count loop N := N + Perft (Play (P, L.Items (I)), Depth - 1); end loop;
      return N;
   end Perft;

   function Choose (P : Position; Seed : Int; Entity : Positive; Tick : Int; Strength : Natural) return Move is
      L : constant Move_List := Legal (P);
      Best_V : Integer := Integer'First;
      Best_N : Natural := 0;
      Val : array (1 .. 256) of Integer := [others => 0];
   begin
      if L.Count = 0 then return (0, 0, None); end if;
      if Roll (Seed, Entity, Tick, 9500, 100) > Strength then   --  a random legal move
         return L.Items (Roll (Seed, Entity, Tick, 9501, L.Count));
      end if;
      for I in 1 .. L.Count loop   --  1-ply: material after the move; a mate is worth the most, a stalemate is level
         declare
            N : constant Position := Play (P, L.Items (I));
            S : constant Game_State := State_Of (N);
         begin
            Val (I) := (case S is when Checkmate => 10_000, when Stalemate | Fifty_Moves => 0, when Ongoing => Material (N, P.To_Move));
         end;
         if Val (I) > Best_V then Best_V := Val (I); Best_N := 0; end if;
         if Val (I) = Best_V then Best_N := Best_N + 1; end if;
      end loop;
      declare
         Pick : Positive := Roll (Seed, Entity, Tick, 9502, Best_N);   --  among the equally good ones
      begin
         for I in 1 .. L.Count loop
            if Val (I) = Best_V then
               if Pick = 1 then return L.Items (I); end if;
               Pick := Pick - 1;
            end if;
         end loop;
      end;
      return L.Items (1);
   end Choose;

end Sim_Chess;
