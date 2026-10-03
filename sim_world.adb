--  Version: 0.017
pragma Ada_2022;

with Ada.Characters.Handling, Ada.Containers.Vectors, Interfaces, Ada.Strings.Fixed, Ada.Strings.Unbounded, Sim_Util;
use Ada.Strings.Unbounded;
use Sim_Util;

package body Sim_World is

   package Fx renames Ada.Strings.Fixed;

   function Name (E : Entity_Id) return String is
     (case E is when 1 => "ada", when 2 => "gemini", when 3 => "replika", when 4 => "robert");
   --  ---- display names -----------------------------------------------------------------------
   type Pair is record
      Id, Shown : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   package Pair_Vectors is new Ada.Containers.Vectors (Positive, Pair);
   Pairs : Pair_Vectors.Vector;
   Aliases : Pair_Vectors.Vector;   --  'alias <id> = <older name>' lines: accepted when addressing a name, never shown

   --  PROOF-LATER: Importance 2/10, Urgency 1/10, SPARK2 (parsing of data/names.txt)
   procedure Load_Names (Lines : Sim_Util.Str_Vectors.Vector) is
   begin
      Pairs.Clear;
      Aliases.Clear;
      for L of Lines loop
         declare
            T : constant String := Fx.Trim (L, Ada.Strings.Both);
            Eq : constant Natural := Fx.Index (T, "=");
         begin
            if T'Length > 0 and then T (T'First) /= '#' and then Eq > T'First then
               declare
                  Id : constant String := Fx.Trim (T (T'First .. Eq - 1), Ada.Strings.Both);
                  Sh : constant String := Fx.Trim (T (Eq + 1 .. T'Last), Ada.Strings.Both);
               begin
                  if Id /= "" and then Sh /= "" and then (for all C of Sh => C >= ' ' and then C /= '{' and then C /= '}') then
                     if Id'Length > 6 and then Id (Id'First .. Id'First + 5) = "alias " then
                        Aliases.Append (Pair'(Id => Ada.Strings.Unbounded.To_Unbounded_String (Fx.Trim (Id (Id'First + 6 .. Id'Last), Ada.Strings.Both)),
                                              Shown => Ada.Strings.Unbounded.To_Unbounded_String (Sh)));
                     else
                        Pairs.Append (Pair'(Id => Ada.Strings.Unbounded.To_Unbounded_String (Id),
                                            Shown => Ada.Strings.Unbounded.To_Unbounded_String (Sh)));
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;
   end Load_Names;

   function Display_Of (Id : String) return String is
   begin
      for P of Pairs loop
         if Ada.Strings.Unbounded.To_String (P.Id) = Id then return Ada.Strings.Unbounded.To_String (P.Shown); end if;
      end loop;
      return Id;
   end Display_Of;

   function Display (E : Entity_Id) return String is (Display_Of (Name (E)));

   --  lower case, spaces removed: 'Player 1', 'player1' and 'PLAYER 1' are the same name
   function Squeeze (Text : String) return String is
      R : String (1 .. Text'Length);
      N : Natural := 0;
   begin
      for C of Text loop
         if C /= ' ' then N := N + 1; R (N) := Ada.Characters.Handling.To_Lower (C); end if;
      end loop;
      return R (1 .. N);
   end Squeeze;

   function Internal_Id (Text : String) return String is
      T : constant String := Squeeze (Fx.Trim (Text, Ada.Strings.Both));
   begin
      for P of Pairs loop
         if Squeeze (Ada.Strings.Unbounded.To_String (P.Shown)) = T then
            return Ada.Strings.Unbounded.To_String (P.Id);
         end if;
      end loop;
      for P of Aliases loop
         if Squeeze (Ada.Strings.Unbounded.To_String (P.Shown)) = T then
            return Ada.Strings.Unbounded.To_String (P.Id);
         end if;
      end loop;
      return Text;
   end Internal_Id;

   function Show (Text : String) return String is
      function Word_Char (C : Character) return Boolean is (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_');
      R : Unbounded_String;
      I : Positive := Text'First;
      --  The id at I follows a ':' inside a source tag "src=s1:t600:ada" (an inbox line): shown as a name, too.
      function In_Src_Tag (At_I : Positive) return Boolean is
         B : Natural := At_I;
      begin
         if At_I = Text'First or else Text (At_I - 1) /= ':' then return False; end if;
         while B > Text'First and then Text (B - 1) /= ' ' loop B := B - 1; end loop;
         return B + 3 <= Text'Last and then Text (B .. B + 3) = "src=";
      end In_Src_Tag;
   begin
      if Pairs.Is_Empty then return Text; end if;
      while I <= Text'Last loop
         declare
            Done : Boolean := False;
         begin
            if Text (I) in 'a' .. 'z'
              and then (I = Text'First or else not (Word_Char (Text (I - 1)) or else Text (I - 1) in '/' | '-' | ':' | '.')
                        or else In_Src_Tag (I))
            then
               for P of Pairs loop
                  declare
                     Id : constant String := To_String (P.Id);
                     Sh : constant String := To_String (P.Shown);
                     Last : constant Natural := I + Id'Length - 1;
                  begin
                     if not Done and then Last <= Text'Last and then Text (I .. Last) = Id
                       and then (Last = Text'Last
                                 or else not (Word_Char (Text (Last + 1)) or else Text (Last + 1) in '-' | '/'
                                              or else (Text (Last + 1) = '.' and then Last + 2 <= Text'Last
                                                       and then Text (Last + 2) in 'a' .. 'z')))
                     then
                        declare
                           Sp : Natural := 0;
                           Delta_W : constant Integer := Sh'Length - Id'Length;
                        begin
                           while Last + Sp + 1 <= Text'Last and then Text (Last + Sp + 1) = ' ' loop Sp := Sp + 1; end loop;
                           Append (R, Sh);
                           Done := True;
                           I := Last + 1;
                           if Sp >= 2 then   --  a table column: keep the width where possible
                              if Delta_W > 0 then
                                 I := I + Natural'Min (Delta_W, Sp - 1);
                              elsif Delta_W < 0 then
                                 Append (R, (-Delta_W) * ' ');
                              end if;
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end if;
            if not Done then
               Append (R, Text (I));
               I := I + 1;
            end if;
         end;
      end loop;
      return To_String (R);
   end Show;

   function Kind (E : Entity_Id) return String is
     (case E is when 1 => "engineer", when 2 => "reviewer", when 3 => "vice_president", when 4 => "human");

   --  ---- vocabulary ---------------------------------------------------------

   type Word_Rec is record
      Text   : Unbounded_String;
      P1, P2 : Natural := 0;   --  parent word ids of a coined word
      Coiner : Natural := 0;   --  entity id that coined it (0: base word)
      Kind   : Natural := 0;   --  world words: 1 name, 2 property, 3 variant (see the spec)
      Variant : Natural := 0;
      Meaning : Unbounded_String;
   end record;
   package Word_Vectors is new Ada.Containers.Vectors (Positive, Word_Rec);
   package Bool_Vectors is new Ada.Containers.Vectors (Positive, Boolean);
   Table : Word_Vectors.Vector;
   Known : array (Entity_Id) of Bool_Vectors.Vector;
   Known_N : array (Entity_Id) of Natural := [others => 0];   --  how many words each wesen knows (kept by Init / Learn_Word, not recounted)
   package Nat_Vectors is new Ada.Containers.Vectors (Positive, Natural);
   Freq   : array (Entity_Id) of Nat_Vectors.Vector;   --  per word: how often it came up for the entity
   Taught : array (Entity_Id) of Nat_Vectors.Vector;   --  per word: the teacher's entity id, else 0
   Via_World : array (Entity_Id) of Bool_Vectors.Vector;   --  per word: learned by meeting it in the world
   Base  : Natural := 0;

   --  Petitions (see the spec): topic table, filed petitions, per-entity bookkeeping.
   Max_Topics : constant := 40;
   type Topic_Rec is record
      Name, Phrase : Unbounded_String;
      Base, Low_En, Low_Mood, Few_Words, Benches, Cooling : Integer := 0;   --  Cooling: the 7th column
   end record;
   type Topic_Array is array (1 .. Max_Topics) of Topic_Rec;
   Topics : Topic_Array;
   N_Topics : Natural := 0;
   type Petition_Rec is record
      Tick : Int;
      From : Entity_Id;
      Topic, Repeat : Natural;
      Wish : Unbounded_String;
      Granted : Natural;   --  the number of the grant (G<n>) that granted it, else 0
   end record;
   package Petition_Vectors is new Ada.Containers.Vectors (Positive, Petition_Rec);
   Petitions : Petition_Vectors.Vector;
   Pet_Last  : array (Entity_Id) of Int := [others => -1];             --  tick of the last petition
   Pet_N     : array (Entity_Id) of Natural := [others => 0];
   Topic_Used : array (1 .. Max_Topics) of Natural := [others => 0];
   Topic_By  : array (Entity_Id, 1 .. Max_Topics) of Natural := [others => [others => 0]];
   Topic_Last : array (Entity_Id) of Natural := [others => 0];
   Done_Topic : array (Entity_Id, 1 .. Max_Topics) of Boolean := [others => [others => False]];   --  granted: not filed again
   Urgency : array (Entity_Id, 1 .. Max_Topics) of Natural := [others => [others => 0]];   --  govern=1: after a refusal

   --  Tunables of the personality (data/limits.txt), read by Init.
   type Weight_Array is array (Rest .. Propose) of Integer;
   R30_On : Boolean := True;
   R30_Width : Integer := 32;
   R30_Period, R30_Strength, R30_Core : Integer := 1;
   Base_W : Weight_Array := [30, 20, 15, 15, 15, 5, 1];
   Lean_Propose, Pet_Cooldown, Pet_Repeat_Pct : Integer := 0;
   Lean_Low_Energy, Lean_High_Energy, Lean_Low_Mood, Lean_High_Mood, Lean_Few_Words, Few_Words_N : Integer := 0;
   Cache_Steps : array (Entity_Id) of Int := [others => -1];
   Cache_Row   : array (Entity_Id) of Interfaces.Unsigned_64 := [others => 0];

   procedure Init (Base_Words : Str_Vectors.Vector; Seed, Start_Percent : Int) is
   begin
      R30_On := Limit ("rule30.enabled", 1) /= 0;
      R30_Width := Clamp (Integer (Limit ("rule30.width", 60)), 12, 60);
      R30_Period := Clamp (Integer (Limit ("rule30.period", 50)), 1, 100_000);
      R30_Strength := Clamp (Integer (Limit ("rule30.strength", 15)), 0, 100);
      R30_Core := Clamp (Integer (Limit ("rule30.core", 40)), 0, 100);
      Base_W := [Integer (Limit ("weight.rest", 30)), Integer (Limit ("weight.work", 20)),
                 Integer (Limit ("weight.explore", 15)), Integer (Limit ("weight.talk", 15)),
                 Integer (Limit ("weight.wander", 15)), Integer (Limit ("weight.bench", 5)), Integer (Limit ("weight.propose", 1))];
      Lean_Propose := Clamp (Integer (Limit ("lean.propose", 5)), 0, 1000);
      Pet_Cooldown := Clamp (Integer (Limit ("propose.cooldown", 80)), 0, 1_000_000);
      Pet_Repeat_Pct := Clamp (Integer (Limit ("propose.repeat_percent", 15)), 0, 100);
      Petitions.Clear;
      Pet_Last := [others => -1];
      Pet_N := [others => 0];
      Topic_Used := [others => 0];
      Topic_By := [others => [others => 0]];
      Topic_Last := [others => 0];
      Done_Topic := [others => [others => False]];
      Urgency := [others => [others => 0]];
      Lean_Low_Energy := Clamp (Integer (Limit ("lean.low_energy", 60)), 0, 1000);
      Lean_High_Energy := Clamp (Integer (Limit ("lean.high_energy", 20)), 0, 1000);
      Lean_Low_Mood := Clamp (Integer (Limit ("lean.low_mood", 30)), 0, 1000);
      Lean_High_Mood := Clamp (Integer (Limit ("lean.high_mood", 30)), 0, 1000);
      Lean_Few_Words := Clamp (Integer (Limit ("lean.few_words", 20)), 0, 1000);
      Few_Words_N := Clamp (Integer (Limit ("lean.few_words_n", 100)), 1, 100_000);
      Cache_Steps := [others => -1];
      Table.Clear;
      for W of Base_Words loop
         Table.Append (Word_Rec'(Text => To_Unbounded_String (W), others => <>));
      end loop;
      Base := Natural (Table.Length);
      for E in Entity_Id loop
         Known (E).Clear;
         Known_N (E) := 0;
         Taught (E).Clear;
         Via_World (E).Clear;
         Freq (E).Clear;
         for W in 1 .. Base loop
            Known (E).Append (Int (Roll (Seed, Positive (E), 0, 1000 + W, 100)) <= Start_Percent);
            if Known (E) (W) then Known_N (E) := Known_N (E) + 1; end if;
         end loop;
      end loop;
   end Init;

   function Base_Count return Natural is (Base);
   function Count return Natural is (Natural (Table.Length));
   function Word (W : Positive) return String is (To_String (Table (W).Text));
   function Knows (E : Entity_Id; W : Positive) return Boolean is
     (W <= Natural (Known (E).Length) and then Known (E) (W));

   procedure Use_Word (E : Entity_Id; W : Positive; Amount : Positive := 1) is
   begin
      while Natural (Freq (E).Length) < W loop
         Freq (E).Append (0);
      end loop;
      Freq (E).Replace_Element (W, Freq (E).Element (W) + Amount);
   end Use_Word;

   procedure Learn_Word (E : Entity_Id; W : Positive; From : Natural := 0) is
   begin
      while Natural (Known (E).Length) < W loop
         Known (E).Append (False);
      end loop;
      if not Known (E) (W) then Known_N (E) := Known_N (E) + 1; end if;
      Known (E) (W) := True;
      while Natural (Taught (E).Length) < W loop
         Taught (E).Append (0);
      end loop;
      if From /= 0 then Taught (E) (W) := From; end if;
      Use_Word (E, W, 2);
   end Learn_Word;

   function Coined_By (W : Positive) return String is
     (if Table (W).Coiner = 0 then "" else Name (Entity_Id (Table (W).Coiner)));

   function Origin (E : Entity_Id; W : Positive) return String is
     (if Table (W).Coiner = Positive (E) then "coined by " & Name (E)
      elsif W <= Natural (Taught (E).Length) and then Taught (E).Element (W) /= 0
      then "taught by " & Name (Entity_Id (Taught (E).Element (W)))
      elsif W <= Natural (Via_World (E).Length) and then Via_World (E).Element (W) then "the world"
      else "start");

   function Find (Text : String) return Natural is
   begin
      for W in 1 .. Count loop
         if Word (W) = Text then return W; end if;
      end loop;
      return 0;
   end Find;

   function Add_Coined (Text : String; P1, P2 : Natural; By : Entity_Id) return Positive is
   begin
      Table.Append (Word_Rec'(Text => To_Unbounded_String (Text), P1 => P1, P2 => P2, Coiner => Positive (By), others => <>));
      return Count;
   end Add_Coined;

   function Add_World_Word (Text, Meaning : String; Kind : Positive; Variant_Of : Natural := 0) return Positive is
   begin
      Table.Append (Word_Rec'(Text => To_Unbounded_String (Text), Kind => Kind, Variant => Variant_Of,
                              Meaning => To_Unbounded_String (Meaning), others => <>));
      return Count;
   end Add_World_Word;

   function Kind_Of (W : Positive) return Natural is (Table (W).Kind);
   function Meaning_Of (W : Positive) return String is (To_String (Table (W).Meaning));

   procedure Learn_From_World (E : Entity_Id; W : Positive) is
   begin
      Learn_Word (E, W);
      while Natural (Via_World (E).Length) < W loop
         Via_World (E).Append (False);
      end loop;
      Via_World (E) (W) := True;
   end Learn_From_World;

   function World_Learned (E : Entity_Id) return Natural is
      N : Natural := 0;
   begin
      for B of Via_World (E) loop if B then N := N + 1; end if; end loop;
      return N;
   end World_Learned;

   function Taught_Count (E : Entity_Id) return Natural is
      N : Natural := 0;
   begin
      for T of Taught (E) loop if T /= 0 then N := N + 1; end if; end loop;
      return N;
   end Taught_Count;

   function Coined_Count_By (E : Entity_Id) return Natural is
      N : Natural := 0;
   begin
      for R of Table loop if R.Coiner = Positive (E) then N := N + 1; end if; end loop;
      return N;
   end Coined_Count_By;

   function Coined_Total return Natural is
      N : Natural := 0;
   begin
      for R of Table loop if R.Coiner /= 0 then N := N + 1; end if; end loop;
      return N;
   end Coined_Total;

   function Parents (W : Positive) return String is
     (if Table (W).P1 = 0 then "" else Word (Table (W).P1) & "+" & Word (Table (W).P2));

   function Known_Count (E : Entity_Id) return Natural is (Known_N (E));   --  was a scan of the whole table at every call (40 % of a replay)

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

   --  ---- personality -------------------------------------------------------------------

   use type Interfaces.Unsigned_64;
   subtype U64 is Interfaces.Unsigned_64;

   function Ring_Mask return U64 is (Interfaces.Shift_Left (1, R30_Width) - 1);

   --  One Rule 30 step on the ring.
   function Step_Row (R : U64) return U64 is
      Left  : constant U64 := (Interfaces.Shift_Left (R, 1) or Interfaces.Shift_Right (R, R30_Width - 1)) and Ring_Mask;
      Right : constant U64 := Interfaces.Shift_Right (R, 1) or Interfaces.Shift_Left (R and 1, R30_Width - 1);
   begin
      return (Left xor (R or Right)) and Ring_Mask;
   end Step_Row;

   --  Start row: one hashed bit per cell (never all zero, which Rule 30 would keep).
   function Start_Row (Seed : Int; E : Entity_Id) return U64 is
      R : U64 := 0;
   begin
      for I in 0 .. R30_Width - 1 loop
         if Roll (Seed, Positive (E), 0, 3000 + I, 2) = 2 then R := R or Interfaces.Shift_Left (1, I); end if;
      end loop;
      return (if R = 0 then 1 else R);
   end Start_Row;

   function Row_At (Seed : Int; E : Entity_Id; Tick : Int) return U64 is
      Steps : constant Int := Tick / Int (R30_Period);
   begin
      if Cache_Steps (E) = Steps then
         null;
      elsif Cache_Steps (E) >= 0 and then Cache_Steps (E) = Steps - 1 then
         Cache_Row (E) := Step_Row (Cache_Row (E));
         Cache_Steps (E) := Steps;
      else   --  not the next step: rebuild from the start row (same result, only slower)
         Cache_Row (E) := Start_Row (Seed, E);
         for I in 1 .. Steps loop Cache_Row (E) := Step_Row (Cache_Row (E)); end loop;
         Cache_Steps (E) := Steps;
      end if;
      return Cache_Row (E);
   end Row_At;

   function Choose (Seed : Int; E : Entity_Id; Tick : Int; Energy, Mood : Integer; Work_Pct : Natural := 100) return Action is
      Die : constant Positive := Roll (Seed, Positive (E), Tick, 0, 20);
      W : Weight_Array := Base_W;
      Total : Integer := 0;
      Pick : Positive;
   begin
      if not R30_On then   --  the old fixed D20 table
         return (case Die is when 1 .. 6 => Rest, when 7 .. 10 => Work, when 11 .. 13 => Explore,
                             when 14 .. 16 => Talk, when 17 .. 19 => Wander, when others => Bench);
      end if;
      declare
         Row : constant U64 := Row_At (Seed, E, Tick);
         Core : constant U64 := Start_Row (Seed, E);   --  the birth personality (constant)
         Seg : constant Integer := R30_Width / 6;
         Low_En   : constant Integer := Integer'Max (0, 50 - Energy);        --  0 .. 50
         High_En  : constant Integer := Integer'Max (0, Energy - 60);        --  0 .. 40
         Low_Mood : constant Integer := Integer'Max (0, -Mood);              --  0 .. 100
         High_Mood : constant Integer := Integer'Max (0, Mood - 50);         --  0 .. 50
         Few      : constant Integer := Integer'Max (0, Few_Words_N - Known_Count (E));
      begin
         for A in Rest .. Bench loop   --  personality: the bits of this action's segment
            declare
               Pop, Pop0 : Integer := 0;
               Off : constant Integer := Action'Pos (A) * Seg;
            begin
               for I in Off .. Off + Seg - 1 loop
                  if (Interfaces.Shift_Right (Row, I) and 1) = 1 then Pop := Pop + 1; end if;
                  if (Interfaces.Shift_Right (Core, I) and 1) = 1 then Pop0 := Pop0 + 1; end if;
               end loop;
               W (A) := W (A) + (2 * Pop - Seg) * R30_Strength / Seg + (2 * Pop0 - Seg) * R30_Core / Seg;
            end;
         end loop;
         W (Rest) := W (Rest) + Low_En * Lean_Low_Energy / 50 - High_En * Lean_High_Energy / 20;
         W (Work) := W (Work) - Low_En * Lean_Low_Energy / 100 + High_En * Lean_High_Energy / 40;
         W (Bench) := W (Bench) + High_En * Lean_High_Energy / 80;
         W (Talk) := W (Talk) + Low_Mood * Lean_Low_Mood / 100 + Few * Lean_Few_Words / Few_Words_N;
         W (Explore) := W (Explore) + Low_Mood * Lean_Low_Mood / 200 - High_Mood * Lean_High_Mood / 100;
         W (Work) := W (Work) + High_Mood * Lean_High_Mood / 50;
         W (Talk) := W (Talk) - High_Mood * Lean_High_Mood / 100;
         W (Propose) := W (Propose) + (Low_En * 2 + Low_Mood) * Lean_Propose / 200;
      end;
      for A in W'Range loop
         W (A) := Integer'Max (1, W (A));
         if Work_Pct /= 100 and then A in Work | Bench then W (A) := Integer'Max (1, W (A) * Work_Pct / 100); end if;
         Total := Total + W (A);
      end loop;
      if Pet_Last (E) >= 0 and then Tick - Pet_Last (E) < Int (Pet_Cooldown) then   --  petition cooldown
         Total := Total - W (Propose);
         W (Propose) := 0;
      end if;
      Pick := Roll (Seed, Positive (E), Tick, 0, Total);
      for A in W'Range loop
         if Pick <= W (A) then return A; end if;
         Pick := Pick - W (A);
      end loop;
      return Rest;
   end Choose;

   --  ---- petitions -------------------------------------------------------------------

   function Topic_Count return Natural is (N_Topics);

   --  A topic line: "name base low_energy low_mood few_words benches = phrase".
   procedure Load_Topics (Lines : Str_Vectors.Vector) is
   begin
      N_Topics := 0;
      for L of Lines loop
         declare
            T : constant String := Ada.Strings.Fixed.Trim (L, Ada.Strings.Both);
            Eq : constant Natural := Ada.Strings.Fixed.Index (T, " = ");
            Pos : Positive;
            Rec : Topic_Rec;
            Num : Integer;
            Fields : Natural := 0;
         begin
            if T'Length > 0 and then T (T'First) /= '#' and then Eq > 0 and then N_Topics < Max_Topics then
               Rec.Phrase := To_Unbounded_String (Ada.Strings.Fixed.Trim (T (Eq + 3 .. T'Last), Ada.Strings.Both));
               Pos := T'First;
               while Pos < Eq loop
                  declare
                     Stop : Natural := Ada.Strings.Fixed.Index (T (Pos .. Eq - 1), " ");
                  begin
                     if Stop = 0 then Stop := Eq; end if;
                     if Stop > Pos then
                        Fields := Fields + 1;
                        if Fields = 1 then
                           Rec.Name := To_Unbounded_String (T (Pos .. Stop - 1));
                        elsif (for all C of T (Pos .. Stop - 1) => C in '0' .. '9') then
                           Num := Integer'Value (T (Pos .. Stop - 1));
                           case Fields is
                              when 2 => Rec.Base := Num;
                              when 3 => Rec.Low_En := Num;
                              when 4 => Rec.Low_Mood := Num;
                              when 5 => Rec.Few_Words := Num;
                              when 6 => Rec.Benches := Num;
                              when 7 => Rec.Cooling := Num;
                              when others => null;
                           end case;
                        end if;
                     end if;
                     Pos := Stop + 1;
                  end;
               end loop;
               if Fields >= 1 then
                  N_Topics := N_Topics + 1;
                  Topics (N_Topics) := Rec;
               end if;
            end if;
         end;
      end loop;
      if N_Topics = 0 then
         Topics (1) := (To_Unbounded_String ("other"), To_Unbounded_String ("a small change"), 1, 0, 0, 0, 0, 0);
         N_Topics := 1;
      end if;
   end Load_Topics;

   function File_Petition (Seed : Int; E : Entity_Id; Tick : Int; Energy, Mood, Benches : Integer; Strain : Natural := 0) return Positive is
      Eid : constant Positive := Positive (E);
      Topic : Positive := 1;
      Low_E : constant Integer := Integer'Max (0, 50 - Energy) * 2;          --  0 .. 100
      Low_M : constant Integer := Integer'Min (100, Integer'Max (0, -Mood));
      Few   : constant Integer := Integer'Max (0, Few_Words_N - Known_Count (E)) * 100 / Few_Words_N;
      Ben   : constant Integer := Integer'Min (100, Benches);
      Total : Integer := 0;
      Pick  : Positive;
      Rep, Opening : Natural;
      W     : array (1 .. Max_Topics) of Integer := [others => 0];
      Open_L : Str_Vectors.Vector renames Words (Wish_Open);
      Close_L : Str_Vectors.Vector renames Words (Wish_Close);
   begin
      if Topic_Last (E) > 0 and then not Done_Topic (E, Topic_Last (E)) and then Roll (Seed, Eid, Tick, 11, 100) <= Pet_Repeat_Pct then
         Topic := Topic_Last (E);   --  files its previous topic again
      else
         for T in 1 .. N_Topics loop
            W (T) := Integer'Max (1, Topics (T).Base + (Topics (T).Low_En * Low_E + Topics (T).Low_Mood * Low_M
                                                         + Topics (T).Few_Words * Few + Topics (T).Benches * Ben
                                                         + Topics (T).Cooling * Strain) / 100 + Integer (Urgency (E, T)));
            if Done_Topic (E, T) then W (T) := 1; end if;   --  a granted wish is not asked for again
            Total := Total + W (T);
         end loop;
         Pick := Roll (Seed, Eid, Tick, 9, Total);
         for T in 1 .. N_Topics loop
            if Pick <= W (T) then Topic := T; exit; end if;
            Pick := Pick - W (T);
         end loop;
      end if;
      Rep := Topic_By (E, Topic);
      declare   --  wording only: the opening is the same dice value, "Once again" (one block) only for a repeated topic
         Len : constant Natural := Natural (Open_L.Length);
         Blk : constant Natural := Natural (Limit ("propose.repeat_block", 3));
         Size : constant Natural := Len / 6;
      begin
         Opening := Pick60 (Seed, Eid, Tick, 800) mod Len;
         if Blk in 1 .. 6 and then Size > 0 and then Len = 6 * Size then
            if Rep > 0 then
               Opening := (Blk - 1) * Size + Opening mod Size;
            elsif Opening / Size = Blk - 1 then
               Opening := (if Blk = 1 then Size else 0) + Opening mod Size;
            end if;
         end if;
      end;
      Petitions.Append
        (Petition_Rec'
           (Tick => Tick, From => E, Topic => Topic, Repeat => Rep,
            Granted => 0,
            Wish => To_Unbounded_String
              (Open_L (Open_L.First_Index + Opening) & " "
               & To_String (Topics (Topic).Phrase) & " "
               & Close_L (Close_L.First_Index + Pick60 (Seed, Eid, Tick, 850) mod Natural (Close_L.Length)))));
      Urgency (E, Topic) := 0;
      Topic_By (E, Topic) := Rep + 1;
      Topic_Used (Topic) := Topic_Used (Topic) + 1;
      Topic_Last (E) := Topic;
      Pet_Last (E) := Tick;
      Pet_N (E) := Pet_N (E) + 1;
      return Natural (Petitions.Length);
   end File_Petition;

   function Petition_Total return Natural is (Natural (Petitions.Length));
   function Petitions_Of (E : Entity_Id) return Natural is (Pet_N (E));

   function Petition_Topic (N : Positive) return String is (To_String (Topics (Petitions (N).Topic).Name));
   function Petition_From (N : Positive) return Entity_Id is (Petitions (N).From);
   function Petition_Tick (N : Positive) return Int is (Petitions (N).Tick);
   function Topic_Id (Name : String) return Natural is
   begin
      for T in 1 .. N_Topics loop
         if To_String (Topics (T).Name) = Name then return T; end if;
      end loop;
      return 0;
   end Topic_Id;
   function Asked (E : Entity_Id; Topic : Positive) return Natural is (Topic_By (E, Topic));
   function Is_Recovery_Topic (Topic : Positive) return Boolean is (Topics (Topic).Cooling > 0);
   procedure Grant (E : Entity_Id; Topic : Positive) is
   begin
      Done_Topic (E, Topic) := True;
   end Grant;
   procedure Add_Urgency (E : Entity_Id; Topic : Positive; Amount : Natural) is
   begin
      Urgency (E, Topic) := Natural'Min (200, Urgency (E, Topic) + Amount);
   end Add_Urgency;
   procedure Mark_Petition (N : Positive; G : Positive) is
   begin
      Petitions (N).Granted := G;
   end Mark_Petition;

   function Petition_Line (N : Positive) return String is
      P : constant Petition_Rec := Petitions (N);
   begin
      return "P" & Img (N) & " tick=" & Img (P.Tick) & " from=" & Name (P.From) & " topic=" & To_String (Topics (P.Topic).Name)
        & (if P.Repeat > 0 then " repeat=" & Img (P.Repeat) else "") & (if P.Granted > 0 then " granted=G" & Img (P.Granted) else "")
        & " wish=" & To_String (P.Wish);
   end Petition_Line;

   function Top_Topics (N : Positive) return String is
      Used : array (1 .. Max_Topics) of Boolean := [others => False];
      Res : Unbounded_String;
      Best : Natural;
   begin
      for K in 1 .. N loop
         Best := 0;
         for T in 1 .. N_Topics loop
            if not Used (T) and then Topic_Used (T) > 0 and then (Best = 0 or else Topic_Used (T) > Topic_Used (Best)) then
               Best := T;
            end if;
         end loop;
         exit when Best = 0;
         Used (Best) := True;
         Append (Res, (if K > 1 then ", " else "") & To_String (Topics (Best).Name) & " " & Img (Topic_Used (Best)));
      end loop;
      return (if Length (Res) = 0 then "none" else To_String (Res));
   end Top_Topics;

   function Topic_Name (T : Positive) return String is (To_String (Topics (T).Name));
   function Topic_Phrase (T : Positive) return String is (To_String (Topics (T).Phrase));

   function Core_Percent (Seed : Int; E : Entity_Id) return Natural is
      R : constant U64 := Start_Row (Seed, E);
      N : Natural := 0;
   begin
      for I in 0 .. R30_Width - 1 loop
         if (Interfaces.Shift_Right (R, I) and 1) = 1 then N := N + 1; end if;
      end loop;
      return N * 100 / R30_Width;
   end Core_Percent;

   function Recovery_Rate (Seed : Int; E : Entity_Id) return Natural is
      R : constant U64 := Start_Row (Seed, E);
      N : Natural := 0;
      Lo : constant Integer := Integer (Limit ("rest.rate.min", 60));
      Hi : constant Integer := Integer'Max (Lo, Integer (Limit ("rest.rate.max", 140)));
   begin
      for I in 0 .. 31 loop   --  32 sampled bits; 10 .. 22 set bits span the whole range
         if (Interfaces.Shift_Right (R, I * R30_Width / 32) and 1) = 1 then N := N + 1; end if;
      end loop;
      return Natural (Integer'Max (1, Lo + (Hi - Lo) * Integer'Max (0, Integer'Min (12, N - 10)) / 12));
   end Recovery_Rate;

   function Ballot_For (Seed : Int; E : Entity_Id; Tick, Since : Int) return Natural is
      W : array (1 .. Max_Topics) of Natural := [others => 0];
      Total : Natural := 0;
      Pick : Positive;
   begin
      for Pass in 1 .. 2 loop
         for P of Petitions loop
            if Pass = 2 or else P.Tick > Since then
               W (P.Topic) := W (P.Topic) + 1 + (if P.From = E then 2 else 0);
            end if;
         end loop;
         Total := 0;
         for T in 1 .. N_Topics loop Total := Total + W (T); end loop;
         exit when Total > 0;
      end loop;
      if Total = 0 then return 0; end if;
      Pick := Roll (Seed, Positive (E), Tick, 5010, Total);
      for T in 1 .. N_Topics loop
         if Pick <= W (T) then return T; end if;
         Pick := Pick - W (T);
      end loop;
      return 0;
   end Ballot_For;

   --  ---- kalpas ------------------------------------------------------------------------

   package Int_Vectors is new Ada.Containers.Vectors (Positive, Int);
   Kalpas : Int_Vectors.Vector;

   procedure Load_Kalpas (Lines : Str_Vectors.Vector) is
   begin
      Kalpas.Clear;
      for L of Lines loop
         declare
            T : constant String := Ada.Strings.Fixed.Trim (L, Ada.Strings.Both);
         begin
            if T'Length in 1 .. 9 and then (for all C of T => C in '0' .. '9') then
               Kalpas.Append (Int'Value (T));
            end if;
         end;
      end loop;
      if Kalpas.Is_Empty then   --  built-in: the same three ranges as data/kalpas.txt
         for B in 0 .. 2 loop
            declare
               Lo : constant Int := (case B is when 0 => 20, when 1 => 100, when others => 400);
               Hi : constant Int := (case B is when 0 => 100, when 1 => 400, when others => 1500);
            begin
               for I in 0 .. 19 loop Kalpas.Append (Lo + (Hi - Lo) * Int (I) / 19); end loop;
            end;
         end loop;
      end if;
   end Load_Kalpas;

   function Kalpa_Count return Natural is (Natural (Kalpas.Length));

   function Kalpa_Vote (Seed : Int; E : Entity_Id; Start : Int; Energy, Mood : Integer) return Int is
      P      : constant Natural := Pick60 (Seed, Positive (E), Start, 900);   --  0 .. 59
      Unknown : constant Integer := Count - Known_Count (E);
      Lean   : Integer := 0;
      Block  : Integer;
   begin
      if Energy < Integer (Limit ("kalpa.energy_low", 30)) then Lean := Lean - 1; end if;
      if Energy > Integer (Limit ("kalpa.energy_high", 70)) then Lean := Lean + 1; end if;
      if Mood < Integer (Limit ("kalpa.mood_low", -40)) then Lean := Lean - 1; end if;
      if Mood > Integer (Limit ("kalpa.mood_high", 40)) then Lean := Lean + 1; end if;
      if Unknown * 2 > Count then Lean := Lean + 1; end if;
      Block := Clamp (P / 20 + Clamp (Lean, -2, 2), 0, 2);
      return Kalpas (Kalpas.First_Index + (Block * 20 + P mod 20) mod Natural (Kalpas.Length));
   end Kalpa_Vote;

   function Kalpa_Median (V : Kalpa_Votes) return Int is
      S : Kalpa_Votes := V;
      T : Int;
   begin
      for I in 1 .. 3 loop   --  sort four numbers (bubble)
         for J in 1 .. 4 - I loop
            if S (J) > S (J + 1) then
               T := S (J);
               S (J) := S (J + 1);
               S (J + 1) := T;
            end if;
         end loop;
      end loop;
      return (S (2) + S (3)) / 2;
   end Kalpa_Median;

   --  ---- favourite word ----------------------------------------------------------------

   function Favourite (Seed : Int; E : Entity_Id; Tick : Int; Mood : Integer) return Natural is
      Tone_Hi : constant Integer := Integer (Limit ("mood.tone_high", 34));
      Tone_Lo : constant Integer := Integer (Limit ("mood.tone_low", -34));
      function Weight (W : Positive) return Positive is
         F : constant Natural := (if W <= Natural (Freq (E).Length) then Freq (E).Element (W) else 0);
         Is_Start : constant Boolean := Origin (E, W) = "start";
      begin
         return (1 + F) * (if Mood >= Tone_Hi and then not Is_Start then 3
                           elsif Mood <= Tone_Lo and then Is_Start then 3 else 1);
      end Weight;
      Total : Natural := 0;
      Acc   : Natural := 0;
   begin
      for W in 1 .. Count loop
         if Knows (E, W) then Total := Total + Weight (W); end if;
      end loop;
      if Total = 0 then return 0; end if;
      declare
         R : constant Positive := Roll (Seed, Positive (E), Tick, 960, Total);
      begin
         for W in 1 .. Count loop
            if Knows (E, W) then
               Acc := Acc + Weight (W);
               if R <= Acc then return W; end if;
            end if;
         end loop;
      end;
      return 0;
   end Favourite;

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
