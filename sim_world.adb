--  Version: 0.001
pragma Ada_2022;

with Ada.Containers.Vectors, Ada.Strings.Fixed, Ada.Strings.Unbounded, Sim_Util;
use Ada.Strings.Unbounded;
use Sim_Util;

package body Sim_World is

   package Fx renames Ada.Strings.Fixed;

   function Name (E : Entity_Id) return String is
     (case E is when 1 => "ada", when 2 => "gemini", when 3 => "replika", when 4 => "robert");
   function Kind (E : Entity_Id) return String is
     (case E is when 1 => "engineer", when 2 => "reviewer", when 3 => "vice_president", when 4 => "human");

   --  ---- vocabulary ---------------------------------------------------------

   type Word_Rec is record
      Text   : Unbounded_String;
      P1, P2 : Natural := 0;   --  parent word ids of a coined word
   end record;
   package Word_Vectors is new Ada.Containers.Vectors (Positive, Word_Rec);
   package Bool_Vectors is new Ada.Containers.Vectors (Positive, Boolean);
   Table : Word_Vectors.Vector;
   Known : array (Entity_Id) of Bool_Vectors.Vector;
   Base  : Natural := 0;

   procedure Init (Base_Words : Str_Vectors.Vector; Seed, Start_Percent : Int) is
   begin
      Table.Clear;
      for W of Base_Words loop
         Table.Append (Word_Rec'(Text => To_Unbounded_String (W), P1 => 0, P2 => 0));
      end loop;
      Base := Natural (Table.Length);
      for E in Entity_Id loop
         Known (E).Clear;
         for W in 1 .. Base loop
            Known (E).Append (Int (Roll (Seed, Positive (E), 0, 1000 + W, 100)) <= Start_Percent);
         end loop;
      end loop;
   end Init;

   function Base_Count return Natural is (Base);
   function Count return Natural is (Natural (Table.Length));
   function Word (W : Positive) return String is (To_String (Table (W).Text));
   function Knows (E : Entity_Id; W : Positive) return Boolean is
     (W <= Natural (Known (E).Length) and then Known (E) (W));

   procedure Learn_Word (E : Entity_Id; W : Positive) is
   begin
      while Natural (Known (E).Length) < W loop
         Known (E).Append (False);
      end loop;
      Known (E) (W) := True;
   end Learn_Word;

   function Find (Text : String) return Natural is
   begin
      for W in 1 .. Count loop
         if Word (W) = Text then return W; end if;
      end loop;
      return 0;
   end Find;

   function Add_Coined (Text : String; P1, P2 : Natural) return Positive is
   begin
      Table.Append (Word_Rec'(To_Unbounded_String (Text), P1, P2));
      return Count;
   end Add_Coined;

   function Parents (W : Positive) return String is
     (if Table (W).P1 = 0 then "" else Word (Table (W).P1) & "+" & Word (Table (W).P2));

   function Known_Count (E : Entity_Id) return Natural is
      N : Natural := 0;
   begin
      for W in 1 .. Count loop
         if Knows (E, W) then N := N + 1; end if;
      end loop;
      return N;
   end Known_Count;

   function Nth_Known (E : Entity_Id; N : Positive) return Positive is
      K : Natural := 0;
   begin
      for W in 1 .. Count loop
         if Knows (E, W) then
            K := K + 1;
            if K = N then return W; end if;
         end if;
      end loop;
      return 1;
   end Nth_Known;

   function Teachable_Count (From, To : Entity_Id) return Natural is
      N : Natural := 0;
   begin
      for W in 1 .. Count loop
         if Knows (From, W) and then not Knows (To, W) then N := N + 1; end if;
      end loop;
      return N;
   end Teachable_Count;

   function Nth_Teachable (From, To : Entity_Id; N : Positive) return Positive is
      K : Natural := 0;
   begin
      for W in 1 .. Count loop
         if Knows (From, W) and then not Knows (To, W) then
            K := K + 1;
            if K = N then return W; end if;
         end if;
      end loop;
      return 1;
   end Nth_Teachable;

   --  ---- bench --------------------------------------------------------------------

   Modulus : constant Int := 1_000_003;

   function Run_Bench (Seed : Int; E : Entity_Id; Tick, Budget : Int) return Bench_Result is
      R     : Bench_Result;
      Limit : constant Int := Int'Max (1, Budget);
   begin
      R.Which := Kernel'Val (Roll (Seed, Positive (E), Tick, 8, 3) - 1);
      case R.Which is
         when Sum =>    --  sum of squares mod 1_000_003, one step per term
            for I in 1 .. Limit loop
               R.Result := (R.Result + I * I) mod Modulus;
            end loop;
            R.Steps := Limit;
            R.Checksum := (R.Result * 31 + Limit) mod Modulus;
         when Sort =>   --  insertion sort of 32 rolled numbers, one step per comparison
            declare
               A : array (1 .. 32) of Int;
               Key : Int;
               J : Integer;
            begin
               for I in A'Range loop
                  A (I) := Int (Roll (Seed, Positive (E), Tick, 200 + I, 1000));
               end loop;
               for I in 2 .. A'Last loop
                  Key := A (I);
                  J := I - 1;
                  while J >= 1 and then R.Steps < Limit loop
                     R.Steps := R.Steps + 1;
                     exit when A (J) <= Key;
                     A (J + 1) := A (J);
                     J := J - 1;
                  end loop;
                  A (J + 1) := Key;
                  exit when R.Steps >= Limit;
               end loop;
               R.Result := A (1);
               for V of A loop
                  R.Checksum := (R.Checksum * 31 + V) mod Modulus;
               end loop;
            end;
         when Sieve =>  --  sieve of Eratosthenes up to 500, one step per scan or mark
            declare
               N : constant := 500;
               Marked : array (2 .. N) of Boolean := [others => False];
               J : Integer;
            begin
               for I in Marked'Range loop
                  exit when R.Steps >= Limit;
                  R.Steps := R.Steps + 1;
                  if not Marked (I) and then I * I <= N then
                     J := I * I;
                     while J <= N and then R.Steps < Limit loop
                        Marked (J) := True;
                        R.Steps := R.Steps + 1;
                        J := J + I;
                     end loop;
                  end if;
               end loop;
               for I in Marked'Range loop
                  if not Marked (I) then
                     R.Result := R.Result + 1;
                     R.Checksum := (R.Checksum + Int (I)) mod Modulus;
                  end if;
               end loop;
            end;
      end case;
      return R;
   end Run_Bench;

   --  ---- votes ------------------------------------------------------------------------

   procedure Record_Tick (S : in out Stats; Loc, Mood, Energy : Integer; Learned, Coined, Bench : Boolean) is
      L : Loc_Stats renames S (Loc);
   begin
      L.N := L.N + 1;
      L.Mood := L.Mood + Int (Mood);
      L.Energy := L.Energy + Int (Energy);
      L.Learned := L.Learned + Boolean'Pos (Learned);
      L.Coined := L.Coined + Boolean'Pos (Coined);
      L.Benches := L.Benches + Boolean'Pos (Bench);
   end Record_Tick;

   --  Average mood * 2/3, plus (average energy - 50) / 3, plus up to 25 for what was
   --  done (Acts: words learned + 2 * words coined + benches, as a share of the visits).
   function Score (N, Mood, Energy, Acts : Int) return Int is
     (if N = 0 then 0
      else Int (Clamp (Integer (Mood / N * 2 / 3 + (Energy / N - 50) / 3
                                + Int (Clamp (Integer (100 * Acts / (2 * N)), 0, 25))), -100, 100)));

   function Vote (S : Loc_Stats) return Int is
     (Score (S.N, S.Mood, S.Energy, S.Learned + 2 * S.Coined + S.Benches));

   function Run_Vote (S : Stats) return Int is
      T : Loc_Stats;
   begin
      for L of S loop
         T := (T.N + L.N, T.Mood + L.Mood, T.Energy + L.Energy, T.Learned + L.Learned,
               T.Coined + L.Coined, T.Benches + L.Benches);
      end loop;
      return Vote (T);
   end Run_Vote;

   procedure Summarize
     (Seed, Ticks : Int; Data : All_Stats; Console, Text, Json : out Unbounded_String)
   is
      type Votes is array (0 .. 4) of Int;   --  four locations, then the whole run
      V   : array (Entity_Id) of Votes;
      Sum_L : array (0 .. 3) of Int := [others => 0];
      Fav, Dis : Natural := 0;
      Dis_Spread : Int := -1;
      Hi, Lo : Entity_Id := 1;
      Low_V  : constant Int := Limit ("vote.low", -20);    --  vote <= this: low reason list
      High_V : constant Int := Limit ("vote.high", 20);   --  vote >= this: high reason list

      function Loc (L : Natural) return String is (if L = 4 then "run" else Msg ("loc." & Img (L)));
      function Reason (E : Entity_Id; L : Natural) return String is
         Id : constant List_Id := (if V (E) (L) <= Low_V then Reason_Low elsif V (E) (L) >= High_V then Reason_High else Reason_Mid);
      begin
         return Words (Id) (Words (Id).First_Index + Pick60 (Seed, Positive (E), Ticks, 500 + 60 * L) mod Natural (Words (Id).Length));
      end Reason;
      function Learned (E : Entity_Id) return Int is (Data (E) (0).Learned + Data (E) (1).Learned + Data (E) (2).Learned + Data (E) (3).Learned);
      function Coined (E : Entity_Id) return Int is (Data (E) (0).Coined + Data (E) (1).Coined + Data (E) (2).Coined + Data (E) (3).Coined);
      function Benches (E : Entity_Id) return Int is (Data (E) (0).Benches + Data (E) (1).Benches + Data (E) (2).Benches + Data (E) (3).Benches);
   begin
      for E in Entity_Id loop
         for L in 0 .. 3 loop
            V (E) (L) := Vote (Data (E) (L));
            Sum_L (L) := Sum_L (L) + V (E) (L);
         end loop;
         V (E) (4) := Run_Vote (Data (E));
      end loop;
      for L in 0 .. 3 loop
         if Sum_L (L) > Sum_L (Fav) then Fav := L; end if;
         declare
            H : Entity_Id := 1;
            M : Entity_Id := 1;
         begin
            for E in Entity_Id loop
               if V (E) (L) > V (H) (L) then H := E; end if;
               if V (E) (L) < V (M) (L) then M := E; end if;
            end loop;
            if V (H) (L) - V (M) (L) > Dis_Spread then
               Dis_Spread := V (H) (L) - V (M) (L);
               Dis := L;
               Hi := H;
               Lo := M;
            end if;
         end;
      end loop;
      Console := To_Unbounded_String (Msg ("summary.head", Img (Seed), Img (Ticks)) & ASCII.LF & Msg ("summary.cols") & ASCII.LF);
      for E in Entity_Id loop
         Append (Console, Fx.Head (Name (E), 10));
         for L in 0 .. 3 loop
            Append (Console, " " & Fx.Tail (Sgn (V (E) (L)), 6));
         end loop;
         Append (Console, " | " & Fx.Tail (Sgn (V (E) (4)), 6) & " | " & Fx.Tail (Img (Learned (E)), 7) & " "
                 & Fx.Tail (Img (Coined (E)), 6) & " " & Fx.Tail (Img (Benches (E)), 5) & ASCII.LF);
      end loop;
      Append (Console, Msg ("summary.fav", Loc (Fav), Sgn (Sum_L (Fav))) & ASCII.LF);
      Append (Console, Msg ("summary.dis", Loc (Dis), Img (Dis_Spread), Name (Hi), Sgn (V (Hi) (Dis)),
                            Name (Lo), Sgn (V (Lo) (Dis))) & ASCII.LF);
      Text := Console;
      Json := Null_Unbounded_String;
      for E in Entity_Id loop
         Append (Text, ASCII.LF & Name (E) & " (" & Kind (E) & ")" & ASCII.LF);
         Append (Json, "{""v"":1,""seed"":" & Img (Seed) & ",""ticks"":" & Img (Ticks) & ",""entity"":""" & Name (E)
                 & """,""kind"":""" & Kind (E) & """,""votes"":{");
         for L in 0 .. 4 loop
            Append (Text, Msg ("summary.reason", Loc (L), Sgn (V (E) (L)), Reason (E, L)) & ASCII.LF);
            Append (Json, (if L > 0 then "," else "") & """" & Loc (L) & """:" & Img (V (E) (L)));
         end loop;
         Append (Json, "},""reasons"":{");
         for L in 0 .. 4 loop
            Append (Json, (if L > 0 then "," else "") & """" & Loc (L) & """:""" & Esc (Reason (E, L)) & """");
         end loop;
         Append (Json, "},""learned"":" & Img (Learned (E)) & ",""coined"":" & Img (Coined (E))
                 & ",""benches"":" & Img (Benches (E)) & "}" & ASCII.LF);
      end loop;
      Append (Json, "{""v"":1,""seed"":" & Img (Seed) & ",""favourite"":""" & Loc (Fav) & """,""favourite_sum"":"
              & Img (Sum_L (Fav)) & ",""disagreement"":{""location"":""" & Loc (Dis) & """,""spread"":" & Img (Dis_Spread)
              & ",""high"":""" & Name (Hi) & """,""low"":""" & Name (Lo) & """}}" & ASCII.LF);
   end Summarize;

end Sim_World;
