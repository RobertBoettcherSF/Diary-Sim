--  Version: 0.004
pragma Ada_2022;

with Sim_Ckpt;

with Ada.Containers.Ordered_Maps, Ada.Strings.Fixed, Ada.Strings.Unbounded;
use Ada.Strings.Unbounded;

package body Sim_Things is

   package Fx renames Ada.Strings.Fixed;

   Seed_V : Int := 0;

   --  ---- data/things.txt -------------------------------------------------------------------------
   type List_Kind is (L_Material, L_Shape, L_Quality, L_Feel, L_Taste, L_Social, L_Syllable, L_Biome, L_Drift);
   Lists : array (List_Kind) of Str_Vectors.Vector;

   function Low (K : List_Kind) return String is
     (case K is when L_Material => "material", when L_Shape => "shape", when L_Quality => "quality",
                when L_Feel => "feel", when L_Taste => "taste", when L_Social => "social",
                when L_Syllable => "syllable", when L_Biome => "biome", when L_Drift => "drift");

   --  PROOF-LATER: Importance 2/10, Urgency 1/10, SPARK2 (parsing of data/things.txt)
   procedure Load (Lines : Str_Vectors.Vector) is
      Cur : Natural := 0;
      Have : Boolean := False;
   begin
      for K in List_Kind loop Lists (K).Clear; end loop;
      for L of Lines loop
         declare
            T : constant String := Fx.Trim (L, Ada.Strings.Both);
         begin
            if T'Length >= 3 and then T (T'First) = '[' and then T (T'Last) = ']' then
               Have := False;
               for K in List_Kind loop
                  if T = "[" & Low (K) & "]" then Cur := List_Kind'Pos (K); Have := True; end if;
               end loop;
            elsif Have and then T'Length > 0 and then T (T'First) /= '#' and then Fx.Index (T, " = ") = 0
              and then Fx.Index (T, "--") /= 1
            then
               Lists (List_Kind'Val (Cur)).Append (T);
            end if;
         end;
      end loop;
   end Load;

   function Loaded return Boolean is
     ((for all K in List_Kind => not Lists (K).Is_Empty) and then Natural (Lists (L_Syllable).Length) >= 20
      and then Natural (Lists (L_Biome).Length) >= 1);

   --  One entry of a 60-entry list by a base-60 pick (short lists wrap).
   function Pick (K : List_Kind; Ent : Positive; Sub : Int; Salt : Natural) return Natural is
     (Pick60 (Seed_V, Ent, Sub, Salt) mod Natural (Lists (K).Length));
   function Entry_Of (K : List_Kind; I : Natural) return String is (Lists (K) (Lists (K).First_Index + I));

   --  ---- tunables ----------------------------------------------------------------------------------------
   Chunk, Pct1, Pct2, Churn_Period, Appear, Wear, Radius, Leash, Sense, Mut_Pct : Integer := 1;
   LM_X, LM_Y : array (0 .. 3) of Integer := [others => 0];

   --  ---- state ----------------------------------------------------------------------------------------------
   PX, PY : Pos_Array := [others => 0];
   Is_Placed : Placed_Array := [others => False];

   type Edit_Rec is record
      Op : Edit_Op := Gone;
      T : Thing;
      X, Y : Integer := 0;
   end record;
   package Edit_Vectors is new Ada.Containers.Vectors (Positive, Edit_Rec);
   package Chunk_Maps is new Ada.Containers.Ordered_Maps (Long_Long_Integer, Edit_Vectors.Vector, "<" => "<", "=" => Edit_Vectors."=");
   Chunk_Edits : Chunk_Maps.Map;
   Log : Str_Vectors.Vector;
   package Name_Maps is new Ada.Containers.Ordered_Maps (Long_Long_Integer, Positive);
   Names : Name_Maps.Map;

   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
      Chunk := Clamp (Integer (Limit ("world.chunk", 8)), 2, 64);
      Pct1 := Clamp (Integer (Limit ("world.thing_percent", 30)), 0, 100);
      Pct2 := Clamp (Integer (Limit ("world.thing2_percent", 10)), 0, 100);
      Churn_Period := Clamp (Integer (Limit ("world.churn", 100)), 0, 1_000_000);
      Appear := Clamp (Integer (Limit ("world.churn.appear", 45)), 0, 100);
      Wear := Clamp (Integer (Limit ("world.churn.wear", 30)), 0, 100 - Appear);
      Radius := Clamp (Integer (Limit ("world.churn.radius", 3)), 1, 20);
      Leash := Clamp (Integer (Limit ("world.leash", 24)), 1, 10_000);
      Sense := Clamp (Integer (Limit ("world.sense", 12)), 1, 10_000);
      Mut_Pct := Clamp (Integer (Limit ("world.mutate_percent", 20)), 0, 100);
      for L in 0 .. 3 loop
         LM_X (L) := Integer (Limit ("world.lm" & Img (L) & ".x", Int (if L mod 2 = 0 then -6 else 6)));
         LM_Y (L) := Integer (Limit ("world.lm" & Img (L) & ".y", Int (if L < 2 then -6 else 6)));
      end loop;
      PX := [others => 0];
      PY := [others => 0];
      Is_Placed := [others => False];
      Chunk_Edits.Clear;
      Log.Clear;
      Names.Clear;
   end Init;

   --  ---- cells ----------------------------------------------------------------------------------------------
   --  Hash key of a cell: 1 .. 2**30 (coordinates wrap at +-16384, far beyond any walk).
   function Cell_Key (X, Y : Integer) return Positive is
     (1 + ((X + 16384) mod 32768) + 32768 * ((Y + 16384) mod 32768));
   function Floor_Div (A, B : Integer) return Integer is (if A >= 0 then A / B else -((-A + B - 1) / B));
   function Chunk_Key (X, Y : Integer) return Long_Long_Integer is
     (Long_Long_Integer (Floor_Div (X, Chunk)) * 1_000_003 + Long_Long_Integer (Floor_Div (Y, Chunk)));
   function G_Key (T : Thing) return Long_Long_Integer is (Long_Long_Integer (T.Ent) * 16_777_216 + T.Sub);

   function Biome_Index (X, Y : Integer) return Natural is (Pick (L_Biome, Cell_Key (X, Y), 0, 8000));
   function Biome_Entry (X, Y : Integer) return String is (Entry_Of (L_Biome, Biome_Index (X, Y)));
   function Biome (X, Y : Integer) return String is
      B : constant String := Biome_Entry (X, Y);
      Sp : constant Natural := Fx.Index (B, " ");
   begin
      return (if Sp > 0 then B (B'First .. Sp - 1) else B);
   end Biome;
   function Biome_Glyph (X, Y : Integer) return Character is
      B : constant String := Biome_Entry (X, Y);
   begin
      return B (B'Last);
   end Biome_Glyph;

   function Things_At (X, Y : Integer) return Thing_Vectors.Vector is
      Res : Thing_Vectors.Vector;
      K : constant Positive := Cell_Key (X, Y);
      C : constant Chunk_Maps.Cursor := Chunk_Edits.Find (Chunk_Key (X, Y));
   begin
      if Roll (Seed_V, K, 1, 8100, 100) <= Pct1 then Res.Append (Thing'(Ent => K, Sub => 1)); end if;
      if Roll (Seed_V, K, 2, 8100, 100) <= Pct2 then Res.Append (Thing'(Ent => K, Sub => 2)); end if;
      if Chunk_Maps.Has_Element (C) then
         for E of Chunk_Maps.Element (C) loop
            if E.X = X and then E.Y = Y then
               declare
                  Idx : Natural := 0;
               begin
                  for I in 1 .. Natural (Res.Length) loop
                     if Res (I) = E.T then Idx := I; end if;
                  end loop;
                  if E.Op = Gone then
                     if Idx > 0 then Res.Delete (Idx); end if;
                  elsif Idx = 0 then
                     Res.Append (E.T);
                  end if;
               end;
            end if;
         end loop;
      end if;
      return Res;
   end Things_At;

   --  ---- thing facts ---------------------------------------------------------------------------------------
   function Quality_Text (T : Thing) return String is (Entry_Of (L_Quality, Pick (L_Quality, T.Ent, T.Sub, 7100)));
   function Feel_Text (T : Thing) return String is (Entry_Of (L_Feel, Pick (L_Feel, T.Ent, T.Sub, 7150)));
   function Taste_Text (T : Thing) return String is (Entry_Of (L_Taste, Pick (L_Taste, T.Ent, T.Sub, 7200)));
   function Description (T : Thing) return String is
     (Quality_Text (T) & " " & Entry_Of (L_Shape, Pick (L_Shape, T.Ent, T.Sub, 7050)) & " "
      & Entry_Of (L_Material, Pick (L_Material, T.Ent, T.Sub, 7000)));
   --  Which block of 20 of the 60-entry list the pick fell in (the lists are ordered pleasant, neutral, unpleasant).
   function Feel_Class (T : Thing) return Natural is (Pick60 (Seed_V, T.Ent, T.Sub, 7150) / 20);
   function Taste_Class (T : Thing) return Natural is (Pick60 (Seed_V, T.Ent, T.Sub, 7200) / 20);

   function Syllable (T : Thing; I : Natural) return String is
     (Entry_Of (L_Syllable, Pick (L_Syllable, T.Ent, T.Sub, 7300 + 50 * (I mod 4))));
   function Thing_Key (X, Y : Integer; T : Thing) return String is
     (Img (X) & "," & Img (Y) & "/" & Img (T.Ent) & "." & Img (T.Sub));
   function Blend_Syllable (E : Entity_Id; Tick : Int; Salt : Natural) return String is
     (Entry_Of (L_Syllable, Pick (L_Syllable, Positive (E), Tick, Salt)));
   function Name_Text (T : Thing) return String is
      N : constant Positive := (if Roll (Seed_V, T.Ent, T.Sub, 7290, 4) = 4 then 3 else 2);
      R : Unbounded_String;
   begin
      for I in 0 .. N - 1 loop Append (R, Syllable (T, I)); end loop;
      return To_String (R);
   end Name_Text;

   function Social_Text (E : Entity_Id; Tick : Int) return String is
     (Entry_Of (L_Social, Pick (L_Social, Positive (E), Tick, 7800)));

   --  ---- words -------------------------------------------------------------------------------------------------
   function Name_Word (T : Thing) return Positive is
      C : constant Name_Maps.Cursor := Names.Find (G_Key (T));
   begin
      if Name_Maps.Has_Element (C) then return Name_Maps.Element (C); end if;
      declare
         Desc : constant String := Description (T);
         Text : Unbounded_String := To_Unbounded_String (Name_Text (T));
         Tries : Natural := 0;
         Id : Natural := Find (To_String (Text));
      begin
         while Id /= 0 and then Tries < 5
           and then not (Kind_Of (Id) in 1 | 3 and then Meaning_Of (Id) = Desc)
         loop   --  a different thing already has this name: one more syllable
            Append (Text, Entry_Of (L_Syllable, Pick (L_Syllable, T.Ent, T.Sub, 7500 + 50 * Tries)));
            Tries := Tries + 1;
            Id := Find (To_String (Text));
         end loop;
         if Id = 0 then Id := Add_World_Word (To_String (Text), Desc, 1); end if;
         Names.Insert (G_Key (T), Id);
         return Id;
      end;
   end Name_Word;

   function Name_Known (E : Entity_Id; T : Thing) return Boolean is
      C : constant Name_Maps.Cursor := Names.Find (G_Key (T));
   begin
      return Name_Maps.Has_Element (C) and then Knows (E, Name_Maps.Element (C));
   end Name_Known;

   function Prop_Word (Text, Meaning : String) return Positive is
      Id : constant Natural := Find (Text);
   begin
      return (if Id /= 0 then Id else Add_World_Word (Text, Meaning, 2));
   end Prop_Word;

   --  The letter a dialect changes it to ('>' pairs of the [drift] list), or ' '.
   function Drift_Of (C : Character) return Character is
   begin
      for P of Lists (L_Drift) loop
         if P'Length >= 3 and then P (P'First) = C and then P (P'First + 1) = '>' then return P (P'First + 2); end if;
      end loop;
      return ' ';
   end Drift_Of;

   function Mutate (W : Positive; E : Entity_Id; Tick : Int) return Positive is
      T : constant String := Word (W);
      K : Natural := 0;
   begin
      if Kind_Of (W) not in 1 | 3 or else Roll (Seed_V, Positive (E), Tick, 8400, 100) > Mut_Pct then return W; end if;
      for C of T loop if Drift_Of (C) /= ' ' then K := K + 1; end if; end loop;
      if K = 0 then return W; end if;
      declare
         Pick_I : constant Positive := Roll (Seed_V, Positive (E), Tick, 8401, K);
         N : Natural := 0;
         New_T : String := T;
      begin
         for I in T'Range loop
            if Drift_Of (T (I)) /= ' ' then
               N := N + 1;
               if N = Pick_I then New_T (I) := Drift_Of (T (I)); end if;
            end if;
         end loop;
         declare
            Id : constant Natural := Find (New_T);
         begin
            if Id /= 0 then
               return (if Kind_Of (Id) in 1 | 3 and then Meaning_Of (Id) = Meaning_Of (W) then Id else W);
            end if;
            return Add_World_Word (New_T, Meaning_Of (W), 3, W);
         end;
      end;
   end Mutate;

   --  ---- places and walking ------------------------------------------------------------------------------
   function Placed (E : Entity_Id) return Boolean is (Is_Placed (E));
   function X (E : Entity_Id) return Integer is (PX (E));
   function Y (E : Entity_Id) return Integer is (PY (E));

   function Region (X, Y : Integer) return Natural is
      Best : Natural := 0;
      Best_D : Integer := Integer'Last;
   begin
      for L in 0 .. 3 loop
         declare
            D : constant Integer := abs (X - LM_X (L)) + abs (Y - LM_Y (L));
         begin
            if D < Best_D then Best_D := D; Best := L; end if;
         end;
      end loop;
      return Best;
   end Region;
   function Region_Of (E : Entity_Id) return Natural is (Region (PX (E), PY (E)));

   procedure Place (E : Entity_Id; Tick : Int; Landmark : Natural) is
      L : constant Natural := Natural'Min (Landmark, 3);
   begin
      PX (E) := LM_X (L) + Roll (Seed_V, Positive (E), Tick, 7910, 5) - 3;
      PY (E) := LM_Y (L) + Roll (Seed_V, Positive (E), Tick, 7911, 5) - 3;
      Is_Placed (E) := True;
   end Place;

   Dir_X : constant array (0 .. 3) of Integer := [0, 1, 0, -1];
   Dir_Y : constant array (0 .. 3) of Integer := [-1, 0, 1, 0];

   procedure Walk (E : Entity_Id; Tick : Int; Seek : Boolean) is
      W : array (0 .. 3) of Natural := [others => 20];
      Total : Natural := 0;
      Near : Natural := 0;
      Near_D : Integer := Integer'Last;
   begin
      if not Is_Placed (E) then return; end if;
      if Seek then
         for O in Entity_Id loop
            if O /= E and then Is_Placed (O) then
               declare
                  D : constant Integer := abs (PX (O) - PX (E)) + abs (PY (O) - PY (E));
               begin
                  if D < Near_D then Near_D := D; Near := Natural (O); end if;
               end;
            end if;
         end loop;
      end if;
      if Near /= 0 and then Near_D <= Sense then
         declare
            O : constant Entity_Id := Entity_Id (Near);
            Dx : constant Integer := PX (O) - PX (E);
            Dy : constant Integer := PY (O) - PY (E);
            Along_X : constant Boolean := abs Dx > abs Dy or else (abs Dx = abs Dy and then Roll (Seed_V, Positive (E), Tick, 7921, 2) = 1);
         begin
            if Along_X and then Dx /= 0 then W (if Dx > 0 then 1 else 3) := W (if Dx > 0 then 1 else 3) + 200;
            elsif Dy /= 0 then W (if Dy > 0 then 2 else 0) := W (if Dy > 0 then 2 else 0) + 200;
            end if;
         end;
      else
         W (Core_Percent (Seed_V, E) / 25 mod 4) := W (Core_Percent (Seed_V, E) / 25 mod 4) + 20;   --  the personality leans one way
         if abs PX (E) + abs PY (E) > Leash then   --  a pull home beyond the leash
            if PX (E) > 0 then W (3) := W (3) + 30; elsif PX (E) < 0 then W (1) := W (1) + 30; end if;
            if PY (E) > 0 then W (0) := W (0) + 30; elsif PY (E) < 0 then W (2) := W (2) + 30; end if;
         end if;
      end if;
      for D in 0 .. 3 loop Total := Total + W (D); end loop;
      declare
         R : constant Positive := Roll (Seed_V, Positive (E), Tick, 7920, Total);
         Acc : Natural := 0;
      begin
         for D in 0 .. 3 loop
            Acc := Acc + W (D);
            if R <= Acc then
               PX (E) := PX (E) + Dir_X (D);
               PY (E) := PY (E) + Dir_Y (D);
               return;
            end if;
         end loop;
      end;
   end Walk;

   function Adjacent (A, B : Entity_Id) return Boolean is
     (Is_Placed (A) and then Is_Placed (B) and then abs (PX (A) - PX (B)) + abs (PY (A) - PY (B)) <= 1);

   function Facing (E : Entity_Id; Tick : Int) return Natural is (Roll (Seed_V, Positive (E), Tick, 6310, 4) - 1);

   function Reach (E : Entity_Id) return Reach_Vectors.Vector is
      Res : Reach_Vectors.Vector;
   begin
      if not Is_Placed (E) then return Res; end if;
      for D in -1 .. 3 loop   --  own cell, then N E S W
         declare
            Cx : constant Integer := PX (E) + (if D < 0 then 0 else Dir_X (D));
            Cy : constant Integer := PY (E) + (if D < 0 then 0 else Dir_Y (D));
         begin
            for T of Things_At (Cx, Cy) loop Res.Append (Reach_Item'(T => T, X => Cx, Y => Cy)); end loop;
         end;
      end loop;
      return Res;
   end Reach;

   --  ---- edits ---------------------------------------------------------------------------------------------------
   function Op_Text (Op : Edit_Op) return String is (if Op = Gone then "gone" else "add");
   function Thing_Text (T : Thing) return String is (Img (Integer (T.Ent)) & "." & Img (T.Sub));

   procedure Store (R : Edit_Rec) is
      K : constant Long_Long_Integer := Chunk_Key (R.X, R.Y);
      C : constant Chunk_Maps.Cursor := Chunk_Edits.Find (K);
   begin
      if Chunk_Maps.Has_Element (C) then
         declare
            V : Edit_Vectors.Vector := Chunk_Maps.Element (C);
         begin
            V.Append (R);
            Chunk_Edits.Replace_Element (C, V);
         end;
      else
         declare
            V : Edit_Vectors.Vector;
         begin
            V.Append (R);
            Chunk_Edits.Insert (K, V);
         end;
      end if;
   end Store;

   procedure Edit (Tick : Int; Op : Edit_Op; T : Thing; X, Y : Integer; By : String) is
   begin
      Store ((Op => Op, T => T, X => X, Y => Y));
      Log.Append ("X" & Img (Integer (Log.Length) + 1) & " t=" & Img (Tick) & " " & Op_Text (Op) & " " & Thing_Text (T) & " "
                  & Img (X) & "," & Img (Y) & " by=" & By);
   end Edit;

   function Edit_Count return Natural is (Natural (Log.Length));
   function Edit_Line (N : Positive) return String is (Log (N));

   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (parsing a stored edit line)
   procedure Apply_Line (L : String; OK : out Boolean) is
      Fields : Str_Vectors.Vector;
      From : Positive := L'First;
   begin
      OK := False;
      for I in L'First .. L'Last + 1 loop
         if I > L'Last or else L (I) = ' ' then
            if I > From then Fields.Append (L (From .. I - 1)); end if;
            From := I + 1;
         end if;
      end loop;
      if Natural (Fields.Length) < 5 or else Fields.Element (1) (Fields.Element (1)'First) /= 'X' then return; end if;
      declare
         Op : constant String := Fields.Element (3);
         Th : constant String := Fields.Element (4);
         Pos : constant String := Fields.Element (5);
         D1 : constant Natural := Fx.Index (Th, ".");
         C1 : constant Natural := Fx.Index (Pos, ",");
      begin
         if Op not in "gone" | "add" or else D1 < 2 or else C1 < 2 then return; end if;
         Store ((Op => (if Op = "gone" then Gone else Add),
                 T => (Ent => Positive'Value (Th (Th'First .. D1 - 1)), Sub => Int'Value (Th (D1 + 1 .. Th'Last))),
                 X => Integer'Value (Pos (Pos'First .. C1 - 1)), Y => Integer'Value (Pos (C1 + 1 .. Pos'Last))));
         OK := True;
      end;
   exception
      when Constraint_Error => OK := False;
   end Apply_Line;

   procedure Churn (Tick : Int) is
   begin
      if Churn_Period = 0 or else Tick mod Int (Churn_Period) /= 0 then return; end if;
      for E in Entity_Id loop
         if Is_Placed (E) then
            declare
               Cx : constant Integer := PX (E) + Roll (Seed_V, Positive (E), Tick, 8300, 2 * Radius + 1) - Radius - 1;
               Cy : constant Integer := PY (E) + Roll (Seed_V, Positive (E), Tick, 8301, 2 * Radius + 1) - Radius - 1;
               R : constant Positive := Roll (Seed_V, Positive (E), Tick, 8302, 100);
               Here : constant Thing_Vectors.Vector := Things_At (Cx, Cy);
               Fresh : constant Thing := (Ent => Cell_Key (Cx, Cy), Sub => 1000 + Tick);
               function Is_Here (T : Thing) return Boolean is (for some H of Here => H = T);
            begin
               if R <= Appear then   --  a new thing appears
                  if not Is_Here (Fresh) then Edit (Tick, Add, Fresh, Cx, Cy, "world"); end if;
               elsif R <= Appear + Wear then   --  a thing wears out
                  if not Here.Is_Empty then Edit (Tick, Gone, Here.First_Element, Cx, Cy, "world"); end if;
               elsif not Here.Is_Empty then   --  a thing changes into another
                  Edit (Tick, Gone, Here.First_Element, Cx, Cy, "world");
                  if not Is_Here (Fresh) then Edit (Tick, Add, Fresh, Cx, Cy, "world"); end if;
               end if;
            end;
         end if;
      end loop;
   end Churn;

   --  ---- the treadmill view ------------------------------------------------------------------------------
   function Glyph_Key (Key : String; Default : Character) return Character is
      M : constant String := Msg (Key);
   begin
      return (if M'Length >= 1 and then M (M'First) /= '[' then M (M'First) else Default);
   end Glyph_Key;

   function Treadmill (PX, PY : Pos_Array; Present : Placed_Array) return Str_Vectors.Vector is
      Res : Str_Vectors.Vector;
      Col : constant := 11;
      Thing_G : constant Character := Glyph_Key ("glyph.thing", '*');
      Digits_G : constant String := Msg ("glyph.wesen");
      Head, Pos_L, Near_L, Biome_L : Unbounded_String;
      function Pad (S : String) return String is (Fx.Head (S, Col));
   begin
      Append (Head, Pad (Msg ("map.label")));
      Append (Pos_L, Pad (Msg ("map.pos")));
      Append (Near_L, Pad (Msg ("map.near")));
      Append (Biome_L, Pad (Msg ("map.biome")));
      for E in Entity_Id loop
         Append (Head, Pad (Name (E)));
         if Present (E) then
            Append (Pos_L, Pad ("(" & Img (PX (E)) & "," & Img (PY (E)) & ")"));
            Append (Near_L, Pad (Msg ("loc." & Img (Region (PX (E), PY (E))))));
            Append (Biome_L, Pad (Biome (PX (E), PY (E))));
         else
            Append (Pos_L, Pad ("-"));
            Append (Near_L, Pad ("-"));
            Append (Biome_L, Pad ("-"));
         end if;
      end loop;
      Res.Append (Fx.Trim (To_String (Head), Ada.Strings.Right));
      Res.Append (Fx.Trim (To_String (Pos_L), Ada.Strings.Right));
      Res.Append (Fx.Trim (To_String (Near_L), Ada.Strings.Right));
      Res.Append (Fx.Trim (To_String (Biome_L), Ada.Strings.Right));
      for Row in -2 .. 2 loop
         declare
            Line : Unbounded_String := To_Unbounded_String (Pad (""));
         begin
            for E in Entity_Id loop
               declare
                  Cell : String (1 .. 5) := "     ";
               begin
                  if Present (E) then
                     for Cx in -2 .. 2 loop
                        declare
                           Gx : constant Integer := PX (E) + Cx;
                           Gy : constant Integer := PY (E) + Row;
                           G : Character := Biome_Glyph (Gx, Gy);
                        begin
                           if not Things_At (Gx, Gy).Is_Empty then G := Thing_G; end if;
                           for O in Entity_Id loop
                              if Present (O) and then PX (O) = Gx and then PY (O) = Gy then
                                 G := (if Natural (O) <= Digits_G'Length then Digits_G (Digits_G'First + Natural (O) - 1) else '@');
                              end if;
                           end loop;
                           if Gx = PX (E) and then Gy = PY (E) and then Natural (E) <= Digits_G'Length then
                              G := Digits_G (Digits_G'First + Natural (E) - 1);   --  one's own digit wins at the centre
                           end if;
                           Cell (Cx + 3) := G;
                        end;
                     end loop;
                  end if;
                  Append (Line, Pad (Cell));
               end;
            end loop;
            Res.Append (Fx.Trim (To_String (Line), Ada.Strings.Right));
         end;
      end loop;
      return Res;
   end Treadmill;

   function Treadmill_Now return Str_Vectors.Vector is (Treadmill (PX, PY, Is_Placed));


   function Landmark_X (L : Natural) return Integer is (LM_X (Natural'Min (L, 3)));
   function Landmark_Y (L : Natural) return Integer is (LM_Y (Natural'Min (L, 3)));
   function Near_Landmark (X, Y, Radius : Integer) return Boolean is
     (for some L in 0 .. 3 => abs (X - LM_X (L)) + abs (Y - LM_Y (L)) <= Radius);

   function Camera (X, Y : Integer; Centre : Character) return Str_Vectors.Vector is
      Res : Str_Vectors.Vector;
      Thing_G : constant Character := Glyph_Key ("glyph.thing", '*');
      Digits_G : constant String := Msg ("glyph.wesen");
   begin
      for Row in -2 .. 2 loop
         declare
            Line : String (1 .. 5);
         begin
            for Cx in -2 .. 2 loop
               declare
                  Gx : constant Integer := X + Cx;
                  Gy : constant Integer := Y + Row;
                  G : Character := Biome_Glyph (Gx, Gy);
               begin
                  if not Things_At (Gx, Gy).Is_Empty then G := Thing_G; end if;
                  for O in Entity_Id loop
                     if Is_Placed (O) and then PX (O) = Gx and then PY (O) = Gy then
                        G := (if Natural (O) <= Digits_G'Length then Digits_G (Digits_G'First + Natural (O) - 1) else '@');
                     end if;
                  end loop;
                  if Cx = 0 and then Row = 0 then G := Centre; end if;
                  Line (Cx + 3) := G;
               end;
            end loop;
            Res.Append (Line);
         end;
      end loop;
      return Res;
   end Camera;
   --  0.058: the checkpoint (the word lists of data/things.txt are read again at the start).
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Integer);
      procedure IO is new Sim_Ckpt.IO (Int);
      procedure IO is new Sim_Ckpt.IO (Pos_Array);
      procedure IO is new Sim_Ckpt.IO (Placed_Array);
      procedure IO is new Sim_Ckpt.IO (Chunk_Maps.Map);
      procedure IO is new Sim_Ckpt.IO (Str_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Name_Maps.Map);
   begin
      IO (S, Save, Seed_V);
      IO (S, Save, Chunk); IO (S, Save, Pct1); IO (S, Save, Pct2); IO (S, Save, Churn_Period); IO (S, Save, Appear);
      IO (S, Save, Wear); IO (S, Save, Radius); IO (S, Save, Leash); IO (S, Save, Sense); IO (S, Save, Mut_Pct);
      for I in 0 .. 3 loop IO (S, Save, LM_X (I)); IO (S, Save, LM_Y (I)); end loop;
      IO (S, Save, PX); IO (S, Save, PY);
      IO (S, Save, Is_Placed);
      IO (S, Save, Chunk_Edits);
      IO (S, Save, Log);
      IO (S, Save, Names);
   end State_IO;

end Sim_Things;
