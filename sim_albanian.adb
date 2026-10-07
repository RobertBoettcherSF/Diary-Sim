--  Version: 0.001
--  Albanian of diary_sim (alb=1 sessions): see sim_albanian.ads.
pragma Ada_2022;

with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Interfaces;

with Sim_Ckpt;
with Sim_World;

package body Sim_Albanian is

   use Ada.Strings.Unbounded;
   use Sim_World;
   use type Interfaces.Unsigned_32;

   B2_Max : constant := 64;                      --  ending classes of two letters (the most common in sq_nouns.txt)
   B1_Max : constant := 32;                      --  ... and of one letter
   Bucket_Max : constant := B2_Max + B1_Max;
   Mem_Max : constant := 256;                    --  the memory of one wesen (albanian.memory_cap, at most this)

   type Gender is (M, F);
   type Count_Table is array (Entity_Id, 1 .. Bucket_Max, Gender) of Natural;
   type Mem_Entry is record
      Lemma : Natural := 0;
      Cm, Cf : Natural := 0;
   end record;
   type Mem_Array is array (1 .. Mem_Max) of Mem_Entry;
   type Mem_Table is array (Entity_Id) of Mem_Array;
   type Nat_Per is array (Entity_Id) of Natural;
   type Two_Classes is array (1 .. 2) of Natural;

   --  the state
   Found_N : Natural := 0;
   Pos : Nat_Per := [others => 0];               --  the last sentence heard (0: none yet)
   Ends : Count_Table := [others => [others => [others => 0]]];
   Mem : Mem_Table := [others => [others => (others => <>)]];
   Mem_N : Nat_Per := [others => 0];
   Heard_N, Said_N : Nat_Per := [others => 0];

   --  the data (read once)
   type Noun is record
      Lemma : Unbounded_String;
      G : Character := '-';                       --  m f n
      B2, B1 : Natural := 0;                      --  ending classes (0: none)
      Held : Boolean := False;
      In_Book : Boolean := False;
   end record;
   package Noun_Vectors is new Ada.Containers.Vectors (Positive, Noun);
   package Id_Maps is new Ada.Containers.Indefinite_Hashed_Maps (String, Positive, Ada.Strings.Hash, "=");
   type Cue is record
      Lemma : Positive;
      G : Gender;
   end record;
   package Cue_Vectors is new Ada.Containers.Vectors (Positive, Cue);
   package Nat_Vectors is new Ada.Containers.Vectors (Positive, Positive);
   type Sentence is record
      Id : Unbounded_String;
      Held : Boolean := False;
      C_From : Positive := 1;
      C_To : Natural := 0;                         --  its cues: Cues (C_From .. C_To)
      Nouns_From : Positive := 1;
      Nouns_To : Natural := 0;                     --  the nouns in it: Book_Nouns_Of (..)
   end record;
   package Sent_Vectors is new Ada.Containers.Vectors (Positive, Sentence);

   Loaded : Boolean := False;
   Nouns : Noun_Vectors.Vector;
   Lemma_Id : Id_Maps.Map;
   Form_Lemma : Id_Maps.Map;                      --  a form -> its lemma
   Form_Def : Id_Maps.Map;                        --  a definite singular form -> its lemma
   Ending_Id : Id_Maps.Map;                       --  "b2:ar" / "b1:r" -> class
   Book : Sent_Vectors.Vector;
   Cues : Cue_Vectors.Vector;
   Sent_Nouns : Nat_Vectors.Vector;
   Book_List, Held_List : Nat_Vectors.Vector;    --  m / f nouns of the book, the held-back ones
   Adjs : Str_Vectors.Vector;
   T_Hear, T_Say, T_Held, T_Cap, T_Self : Natural := 0;

   function Lower (S : String) return String is
      R : String := S;
   begin
      for I in R'Range loop
         if R (I) in 'A' .. 'Z' then
            R (I) := Character'Val (Character'Pos (R (I)) + 32);
         elsif I > R'First and then Character'Pos (R (I - 1)) = 16#C3# and then Character'Pos (R (I)) in 16#80# .. 16#9E# then
            R (I) := Character'Val (Character'Pos (R (I)) + 32);   --  UTF-8 upper case letters of Latin-1 (Ë, Ç)
         end if;
      end loop;
      return R;
   end Lower;

   --  the last N letters (a letter is one byte, or two of UTF-8 after C3); "" when shorter
   function Last_Letters (S : String; N : Positive) return String is
      I : Integer := S'Last;
      K : Natural := 0;
   begin
      while I >= S'First and then K < N loop
         if I > S'First and then Character'Pos (S (I)) >= 16#80# and then Character'Pos (S (I - 1)) = 16#C3# then I := I - 2;
         else I := I - 1;
         end if;
         K := K + 1;
      end loop;
      return (if K = N and then I >= S'First - 1 then S (I + 1 .. S'Last) else "");
   end Last_Letters;

   function Hash32 (S : String) return Interfaces.Unsigned_32 is   --  FNV-1a
      H : Interfaces.Unsigned_32 := 2166136261;
   begin
      for C of S loop
         H := (H xor Interfaces.Unsigned_32 (Character'Pos (C))) * 16777619;
      end loop;
      return H;
   end Hash32;

   procedure Split_Tabs (L : String; Parts : in out Str_Vectors.Vector) is
      From : Positive := L'First;
   begin
      Parts.Clear;
      for I in L'Range loop
         if L (I) = ASCII.HT then
            Parts.Append (L (From .. I - 1));
            From := I + 1;
         end if;
      end loop;
      Parts.Append (L (From .. L'Last));
   end Split_Tabs;

   procedure Words_Of (L : String; Into : in out Str_Vectors.Vector) is   --  lower case words, letters only
      I : Integer := L'First;
      W : Unbounded_String;
   begin
      Into.Clear;
      while I <= L'Last loop
         if L (I) in 'a' .. 'z' | 'A' .. 'Z' then
            Append (W, L (I));
            I := I + 1;
         elsif Character'Pos (L (I)) = 16#C3# and then I < L'Last then
            Append (W, L (I .. I + 1));
            I := I + 2;
         else
            if Length (W) > 0 then Into.Append (Lower (To_String (W))); W := Null_Unbounded_String; end if;
            I := I + 1;
         end if;
      end loop;
      if Length (W) > 0 then Into.Append (Lower (To_String (W))); end if;
   end Words_Of;

   procedure Load is
      function Nat (Key : String; Default : Int; Hi : Natural) return Natural is (Natural (Int'Max (0, Int'Min (Int (Hi), Limit (Key, Default)))));
      Lines, Parts, Ws : Str_Vectors.Vector;
      Ok : Boolean;
      type Ending_Count is record
         Key : Unbounded_String;
         N : Natural := 0;
      end record;
      package EC_Vectors is new Ada.Containers.Vectors (Positive, Ending_Count);
      Cnt : Id_Maps.Map;
      ECs : EC_Vectors.Vector;
   begin
      if Loaded then return; end if;
      Loaded := True;
      T_Hear := Nat ("albanian.hear_per_session", 6, 100);
      T_Say := Nat ("albanian.say_per_session", 4, 50);
      T_Held := Nat ("albanian.held_pct", 20, 100);
      T_Cap := Nat ("albanian.memory_cap", 200, Mem_Max);
      T_Self := Nat ("albanian.self_min", 3, 100_000);
      Read_Lines (Data_Path ("sq_nouns.txt"), Lines, Ok);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) /= '#' then
            Split_Tabs (L, Parts);
            if Natural (Parts.Length) >= 4 and then not Lemma_Id.Contains (Parts (1)) and then Parts.Element (2)'Length = 1 then
               Nouns.Append (Noun'(Lemma => To_Unbounded_String (Parts (1)), G => Parts.Element (2) (Parts.Element (2)'First), others => <>));
               Lemma_Id.Insert (Parts (1), Nouns.Last_Index);
               if Parts (4) /= "-" and then not Form_Def.Contains (Parts (4)) then Form_Def.Insert (Parts (4), Nouns.Last_Index); end if;
            end if;
         end if;
      end loop;
      Read_Lines (Data_Path ("sq_noun_forms.txt"), Lines, Ok);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) /= '#' then
            Split_Tabs (L, Parts);
            if Natural (Parts.Length) >= 2 and then Lemma_Id.Contains (Parts (2)) and then not Form_Lemma.Contains (Parts (1)) then
               Form_Lemma.Insert (Parts (1), Lemma_Id.Element (Parts (2)));
            end if;
         end if;
      end loop;
      --  the ending classes: the most common last two letters, then last letters, of the m / f nouns (ties: alphabetical)
      for Two in Boolean loop
         Cnt.Clear;
         ECs.Clear;
         for Nn of Nouns loop
            if Nn.G in 'm' | 'f' then
               declare
                  E : constant String := Last_Letters (To_String (Nn.Lemma), (if Two then 2 else 1));
               begin
                  if E /= "" then
                     if Cnt.Contains (E) then Cnt.Replace (E, Cnt.Element (E) + 1); else Cnt.Insert (E, 1); end if;
                  end if;
               end;
            end if;
         end loop;
         for C in Cnt.Iterate loop ECs.Append (Ending_Count'(To_Unbounded_String (Id_Maps.Key (C)), Id_Maps.Element (C))); end loop;
         declare
            function Before (A, B : Ending_Count) return Boolean is (A.N > B.N or else (A.N = B.N and then A.Key < B.Key));
            package Sorting is new EC_Vectors.Generic_Sorting (Before);
            Max : constant Natural := (if Two then B2_Max else B1_Max);
            Base : constant Natural := (if Two then 0 else B2_Max);
         begin
            Sorting.Sort (ECs);
            for I in 1 .. Natural'Min (Max, Natural (ECs.Length)) loop
               exit when ECs (I).N < 2;
               Ending_Id.Insert ((if Two then "b2:" else "b1:") & To_String (ECs (I).Key), Base + I);
            end loop;
         end;
      end loop;
      for Nn of Nouns loop
         declare
            L : constant String := To_String (Nn.Lemma);
            K2 : constant String := "b2:" & Last_Letters (L, 2);
            K1 : constant String := "b1:" & Last_Letters (L, 1);
         begin
            Nn.B2 := (if Ending_Id.Contains (K2) then Ending_Id.Element (K2) else 0);
            Nn.B1 := (if Ending_Id.Contains (K1) then Ending_Id.Element (K1) else 0);
            Nn.Held := Nn.G in 'm' | 'f' and then Natural (Hash32 ("held:" & L) mod 100) < T_Held;
         end;
      end loop;
      --  the book: per sentence its nouns and its cues
      Read_Lines (Data_Path ("sq_book.txt"), Lines, Ok);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) /= '#' then
            Split_Tabs (L, Parts);
            if Natural (Parts.Length) >= 2 then
               declare
                  S : Sentence := (Id => To_Unbounded_String (Parts (1)), C_From => Natural (Cues.Length) + 1,
                                   Nouns_From => Natural (Sent_Nouns.Length) + 1, others => <>);
               begin
                  Words_Of (Parts (2), Ws);
                  for I in 1 .. Natural (Ws.Length) loop
                     if Form_Lemma.Contains (Ws (I)) then
                        declare
                           Li : constant Positive := Form_Lemma.Element (Ws (I));
                           Nx : constant String := (if I < Natural (Ws.Length) then Ws (I + 1) else "");
                           Def : constant Boolean := Form_Def.Contains (Ws (I)) and then Form_Def.Element (Ws (I)) = Li;
                           Last : constant String := Last_Letters (Ws (I), 1);
                           Sg : constant Boolean := Def or else Ws (I) = To_String (Nouns (Li).Lemma);
                        begin
                           Sent_Nouns.Append (Li);
                           if Nouns (Li).Held then S.Held := True; end if;
                           if Def and then Last in "i" | "u" then Cues.Append (Cue'(Li, M));
                           elsif Def and then Last = "a" then Cues.Append (Cue'(Li, F));
                           elsif Sg and then Nx = "i" then Cues.Append (Cue'(Li, M));
                           elsif Sg and then Nx = "e" then Cues.Append (Cue'(Li, F));
                           end if;
                        end;
                     end if;
                  end loop;
                  S.C_To := Natural (Cues.Length);
                  S.Nouns_To := Natural (Sent_Nouns.Length);
                  Book.Append (S);
               end;
            end if;
         end if;
      end loop;
      for S of Book loop
         for I in S.Nouns_From .. S.Nouns_To loop
            Nouns (Sent_Nouns (I)).In_Book := True;
         end loop;
      end loop;
      for I in 1 .. Natural (Nouns.Length) loop
         if Nouns (I).In_Book and then Nouns (I).G in 'm' | 'f' then
            Book_List.Append (I);
            if Nouns (I).Held then Held_List.Append (I); end if;
         end if;
      end loop;
      Read_Lines (Data_Path ("sq_adj.txt"), Lines, Ok);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) /= '#' then Adjs.Append (L); end if;
      end loop;
      if Adjs.Is_Empty then Adjs.Append ("mirë"); end if;
   end Load;

   procedure Reset is
   begin
      Found_N := 0;
      Pos := [others => 0];
      Ends := [others => [others => [others => 0]]];
      Mem := [others => [others => (others => <>)]];
      Mem_N := [others => 0];
      Heard_N := [others => 0];
      Said_N := [others => 0];
   end Reset;

   function Zero return Boolean is
     (Found_N = 0 and then Pos = [Entity_Id => 0] and then Mem_N = [Entity_Id => 0] and then Heard_N = [Entity_Id => 0]
      and then Said_N = [Entity_Id => 0] and then (for all E in Entity_Id => (for all B in 1 .. Bucket_Max => Ends (E, B, M) = 0 and then Ends (E, B, F) = 0)));

   function Found return Natural is (Found_N);

   function Genders_Now return String is
      Lines : Str_Vectors.Vector;
      Ok : Boolean;
      R : String (1 .. Natural (Entity_Id'Last)) := [others => '-'];
   begin
      Read_Lines (Data_Path ("wesen_gender.txt"), Lines, Ok);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) /= '#' then
            declare
               Sp : Natural := 0;
            begin
               for I in reverse L'Range loop
                  if L (I) = ' ' or else L (I) = ASCII.HT then Sp := I; exit; end if;
               end loop;
               if Sp > L'First then
                  declare
                     Who : constant String := Internal_Id (L (L'First .. Sp - 1));
                     G : constant String := Lower (L (Sp + 1 .. L'Last));
                  begin
                     for E in Entity_Id loop
                        if Name (E) = Who then
                           R (Integer (E)) := (if G = "m" then 'm' elsif G = "f" then 'f' elsif G = "none" then 'n' else '-');
                        end if;
                     end loop;
                  end;
               end if;
            end;
         end if;
      end loop;
      return R;
   end Genders_Now;

   procedure Session (Seed : Int; N : Positive; Start : Int; Genders : String; Lines : in out Str_Vectors.Vector) is
      Nb : Natural;
   begin
      Load;
      Nb := Natural (Book.Length);
      if Nb = 0 then return; end if;
      if Found_N = 0 then
         Found_N := N;
         declare
            H : Unbounded_String;
         begin
            for I of Held_List loop Append (H, (if Length (H) > 0 then "," else "") & To_String (Nouns (I).Lemma)); end loop;
            Lines.Append ("B S" & Img (N) & " t=" & Img (Start) & " ts=" & Stamp & " book=" & Img (Nb) & " nouns="
                          & Img (Natural (Book_List.Length)) & " held=" & Img (Natural (Held_List.Length)) & " " & To_String (H));
         end;
      end if;
      for E in Entity_Id loop
         declare
            Eid : constant Positive := Positive (E);
            Ids : Unbounded_String;
            Got, Cue_N : Natural := 0;
         begin
            for K in 1 .. T_Hear loop   --  in book order: a die of 1 .. 2 sentences ahead, a held-back one is passed over
               declare
                  P : Natural := (Pos (E) + Roll (Seed, Eid, Start, 24000 + K, 2) - 1) mod Nb + 1;
                  Tries : Natural := 0;
               begin
                  while Book (P).Held and then Tries < Nb loop
                     P := P mod Nb + 1;
                     Tries := Tries + 1;
                  end loop;
                  exit when Book (P).Held;
                  Pos (E) := P;
                  Got := Got + 1;
                  Append (Ids, (if Got > 1 then "," else "") & To_String (Book (P).Id));
                  for C in Book (P).C_From .. Book (P).C_To loop
                     declare
                        X : constant Cue := Cues (C);
                        Nn : constant Noun := Nouns (X.Lemma);
                        Slot : Natural := 0;
                     begin
                        Cue_N := Cue_N + 1;
                        if Nn.B2 /= 0 then Ends (E, Nn.B2, X.G) := Ends (E, Nn.B2, X.G) + 1; end if;
                        if Nn.B1 /= 0 then Ends (E, Nn.B1, X.G) := Ends (E, Nn.B1, X.G) + 1; end if;
                        for J in 1 .. Mem_N (E) loop
                           if Mem (E) (J).Lemma = X.Lemma then Slot := J; exit; end if;
                        end loop;
                        if Slot = 0 and then Mem_N (E) < T_Cap then   --  a full memory keeps what it has
                           Mem_N (E) := Mem_N (E) + 1;
                           Slot := Mem_N (E);
                           Mem (E) (Slot).Lemma := X.Lemma;
                        end if;
                        if Slot /= 0 then
                           if X.G = M then Mem (E) (Slot).Cm := Mem (E) (Slot).Cm + 1; else Mem (E) (Slot).Cf := Mem (E) (Slot).Cf + 1; end if;
                        end if;
                     end;
                  end loop;
               end;
            end loop;
            Heard_N (E) := Heard_N (E) + Got;
            Lines.Append ("H S" & Img (N) & " " & Name (E) & " heard=" & Img (Got) & " cues=" & Img (Cue_N) & " ids="
                          & (if Got = 0 then "-" else To_String (Ids)));
            for K in 1 .. T_Say loop
               exit when Book_List.Is_Empty;
               declare
                  From_Held : constant Boolean := K = 1 and then not Held_List.Is_Empty;
                  Li : constant Positive :=
                    (if From_Held then Held_List (Roll (Seed, Eid, Start, 24100, Natural (Held_List.Length)))
                     else Book_List (Roll (Seed, Eid, Start, 24100 + K, Natural (Book_List.Length))));
                  Nn : constant Noun := Nouns (Li);
                  Adj : constant String := Adjs (Roll (Seed, Eid, Start, 24200 + K, Natural (Adjs.Length)));
                  Art : Character := 'i';
                  Src : Unbounded_String := To_Unbounded_String ("def");
               begin
                  for J in 1 .. Mem_N (E) loop
                     if Mem (E) (J).Lemma = Li then
                        Art := (if Mem (E) (J).Cf > Mem (E) (J).Cm then 'e' else 'i');
                        Src := To_Unbounded_String ("mem");
                        exit;
                     end if;
                  end loop;
                  if To_String (Src) = "def" then
                     for B of Two_Classes'[Nn.B2, Nn.B1] loop
                        if B /= 0 and then Ends (E, B, M) + Ends (E, B, F) > 0 then
                           Art := (if Ends (E, B, F) > Ends (E, B, M) then 'e' else 'i');
                           Src := To_Unbounded_String (if B = Nn.B2 then "end2" else "end1");
                           exit;
                        end if;
                     end loop;
                  end if;
                  Said_N (E) := Said_N (E) + 1;
                  Lines.Append ("U S" & Img (N) & " " & Name (E) & " " & To_String (Nn.Lemma) & " " & Art & " " & Adj & " src="
                                & To_String (Src) & " held=" & (if Nn.Held then "1" else "0"));
               end;
            end loop;
            declare
               G : constant Character := (if Genders'Length >= Eid then Genders (Genders'First + Eid - 1) else '-');
               Own, Seen : Natural := 0;
            begin
               if G in 'm' | 'f' then   --  its own gender's article once it heard enough cues of that gender (else i)
                  for B in B2_Max + 1 .. Bucket_Max loop Own := Own + Ends (E, B, (if G = 'm' then M else F)); end loop;
                  for B in 1 .. B2_Max loop Seen := Seen + Ends (E, B, (if G = 'm' then M else F)); end loop;
                  Own := Natural'Max (Own, Seen);
                  Lines.Append ("J S" & Img (N) & " " & Name (E) & " jam " & (if Own >= T_Self and then G = 'f' then 'e' else 'i') & " "
                                & Adjs (Roll (Seed, Eid, Start, 24300, Natural (Adjs.Length))) & " g=" & G);
               end if;
            end;
         end;
      end loop;
   end Session;

   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Natural);
      procedure IO is new Sim_Ckpt.IO (Nat_Per);
      procedure IO is new Sim_Ckpt.IO (Count_Table);
      procedure IO is new Sim_Ckpt.IO (Mem_Table);
   begin
      IO (S, Save, Found_N);
      IO (S, Save, Pos);
      IO (S, Save, Ends);
      IO (S, Save, Mem);
      IO (S, Save, Mem_N);
      IO (S, Save, Heard_N);
      IO (S, Save, Said_N);
   end State_IO;

end Sim_Albanian;
