--  Version: 0.003
--  See sim_preport.ads.
pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Sim_Govern;

package body Sim_Preport is

   use Ada.Strings.Unbounded;
   use Sim_Dharma;

   type Entry_T is record
      N : Natural := 0;
      Tick : Int := 0;
      P : Player_Id := 1;
      E : Entity_Id := 1;
      Claimed, True_M, TC, TT : Integer := 0;   --  claimed / true mood, claimed / true petition tone (0 .. 3)
      Lie : Boolean := False;
   end record;
   package Entry_Vectors is new Ada.Containers.Vectors (Positive, Entry_T);

   type In_Rec is record
      N : Positive := 1;
      Tick : Int := 0;
      P : Player_Id := 1;
      Done : Boolean := False;
   end record;
   package In_Vectors is new Ada.Containers.Vectors (Positive, In_Rec);
   type Counts is array (Player_Id) of Natural;

   Seed_V : Int := 0;
   Entries : Entry_Vectors.Vector;     --  every claim of every round (the audit)
   Latest : Entry_Vectors.Vector;      --  the claims of the latest round
   Inputs : In_Vectors.Vector;
   Lie_Rounds, Challenged : Counts := [others => 0];
   Rounds : Natural := 0;
   Last_T : Int := -1;
   Prev_Tick : Int := 0;
   Prev_Pets : Ints := [others => 0];

   M_Min, M_Max, Lie_Min, Lie_Max, Hon_Base, Brev_W, Warm_W, Trust_W, Stand_W, Lie_Scale, Rosy_W, Tone1, Tone2, Tone3, Cost, Width : Integer := 0;

   function L (Key : String; D : Integer) return Integer is (Integer (Limit (Key, Int (D))));

   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
      Entries.Clear; Latest.Clear; Inputs.Clear;
      Lie_Rounds := [others => 0]; Challenged := [others => 0];
      Rounds := 0; Last_T := -1; Prev_Tick := 0; Prev_Pets := [others => 0];
      M_Min := L ("mood.min", -100);
      M_Max := L ("mood.max", 100);
      Lie_Min := Clamp (L ("preport.lie_min", 5), 1, 100);
      Lie_Max := Clamp (L ("preport.lie_max", 30), Lie_Min, 100);
      Hon_Base := L ("preport.hon_base", 55);
      Brev_W := L ("preport.brev_w", 40);
      Warm_W := L ("preport.warm_w", 70);
      Trust_W := L ("preport.trust_w", 30);
      Stand_W := L ("preport.stand_w", 30);
      Lie_Scale := L ("preport.lie_scale", 90);
      Rosy_W := L ("preport.rosy_w", 100);
      Tone1 := L ("preport.tone1", 35);
      Tone2 := L ("preport.tone2", 80);
      Tone3 := L ("preport.tone3", 150);
      Cost := Clamp (L ("preport.challenge_cost", 3), 0, 100);
      Width := Clamp (L ("preport.width", 80), 40, 200);
   end Init;

   procedure Begin_Session (Tick : Int; Pets : Ints) is
   begin
      Prev_Tick := Tick;
      Prev_Pets := Pets;
   end Begin_Session;

   procedure Add_Challenge (N : Positive; Tick : Int; P : Player_Id) is
   begin
      Inputs.Append (In_Rec'(N => N, Tick => Tick, P => P, Done => False));
   end Add_Challenge;

   procedure Tick_Begin (Tick : Int; Bad : out Natural) is
   begin
      Bad := 0;
      for K in 1 .. Natural (Inputs.Length) loop
         declare
            X : In_Rec := Inputs (K);
         begin
            if not X.Done and then X.Tick = Tick - 1 then
               X.Done := True;
               Inputs.Replace_Element (K, X);
               if Lie_Rounds (X.P) > Challenged (X.P) then
                  Challenged (X.P) := Challenged (X.P) + 1;
                  for E in Entity_Id loop
                     if Watcher (E) = X.P then Sim_Govern.Lower_Standing (E, Natural (Cost)); end if;
                  end loop;
               else
                  Bad := X.N;
               end if;
            end if;
         end;
      end loop;
   end Tick_Begin;

   --  ---- the claims ------------------------------------------------------------------------------------------------------
   --  How honest player P is with its wesen E, 0 .. 100: blunt (curt) players and trusted, well-regarded wesen get the plain truth,
   --  generous players like to please.
   function Honesty (P : Player_Id; E : Entity_Id) return Integer is
     (Clamp (Hon_Base + (Brev_Of (P) - 50) * Brev_W / 100 - Warm_Of (P) * Warm_W / 100
             + (Sim_Govern.Trust_Of (E) - 50) * Trust_W / 100 + (Sim_Govern.Standing_Of (E) - 50) * Stand_W / 100, 0, 100));

   function Tone_Level (Count : Integer; Span : Int) return Integer is
      Rate : constant Int := Int (Integer'Max (0, Count)) * 10_000 / Int'Max (1, Span);   --  hundredths of a petition per 100 ticks
   begin
      return (if Rate < Int (Tone1) then 0 elsif Rate < Int (Tone2) then 1 elsif Rate < Int (Tone3) then 2 else 3);
   end Tone_Level;

   function Make_Entries (Tick : Int; Mood, Pets : Ints; N0 : Natural) return Entry_Vectors.Vector is
      R : Entry_Vectors.Vector;
   begin
      for E in Entity_Id loop
         declare
            P : constant Player_Id := Watcher (E);
            Eid : constant Positive := Positive (E);
            T_M : constant Integer := Clamp (Mood (E), M_Min, M_Max);
            T_T : constant Integer := Tone_Level (Pets (E) - Prev_Pets (E), Tick - Prev_Tick);
            Lie_Pct : constant Integer := Clamp ((100 - Honesty (P, E)) * Lie_Scale / 100, 0, 95);
            X : Entry_T := (N => N0 + Natural (R.Length) + 1, Tick => Tick, P => P, E => E, Claimed => T_M, True_M => T_M,
                            TC => T_T, TT => T_T, Lie => False);
         begin
            if Lie_Pct > 0 and then Roll (Seed_V, Eid, Tick, 9800, 100) <= Lie_Pct then
               declare
                  Rosy_Pct : constant Integer := Clamp (50 + Warm_Of (P) * Rosy_W / 100, 10, 90);   --  generous: rosy, strict: gloomy
                  Rosy : constant Boolean := Roll (Seed_V, Eid, Tick, 9801, 100) <= Rosy_Pct;
                  Mag : constant Integer := Lie_Min + Roll (Seed_V, Eid, Tick, 9802, Lie_Max - Lie_Min + 1) - 1;
               begin
                  X.Claimed := Clamp (T_M + (if Rosy then Mag else -Mag), M_Min, M_Max);
                  X.TC := Clamp (T_T + (if Rosy then -1 else 1), 0, 3);
                  X.Lie := X.Claimed /= X.True_M or else X.TC /= X.TT;
               end;
            end if;
            R.Append (X);
         end;
      end loop;
      return R;
   end Make_Entries;

   function Line_Of (X : Entry_T) return String is
     ("P" & Img (X.N) & " t=" & Img (X.Tick) & " player=" & Player_Name (X.P) & " wesen=" & Name (X.E) & " claimed=" & Img (X.Claimed)
      & " true=" & Img (X.True_M) & " tone=" & Img (X.TC) & "/" & Img (X.TT) & " flag=" & (if X.Lie then "lie" else "none"));

   procedure Round (Tick : Int; Mood, Pets : Ints; Lines : in out Str_Vectors.Vector) is
      Made : constant Entry_Vectors.Vector := Make_Entries (Tick, Mood, Pets, Natural (Entries.Length));
      Lied : array (Player_Id) of Boolean := [others => False];
   begin
      for X of Made loop
         Entries.Append (X);
         Lines.Append (Line_Of (X));
         if X.Lie then Lied (X.P) := True; end if;
      end loop;
      for P in Player_Id loop
         if Lied (P) then Lie_Rounds (P) := Lie_Rounds (P) + 1; end if;
      end loop;
      Latest := Made;
      Rounds := Rounds + 1;
      Last_T := Tick;
      Prev_Tick := Tick;
      Prev_Pets := Pets;
   end Round;

   function Round_Count return Natural is (Rounds);
   function Last_Tick return Int is (Last_T);

   function Lie_Total return Natural is
      N : Natural := 0;
   begin
      for X of Entries loop if X.Lie then N := N + 1; end if; end loop;
      return N;
   end Lie_Total;

   --  ---- the boxes -------------------------------------------------------------------------------------------------------
   --  Columns of a text (a UTF-8 continuation byte takes none).
   function Cols (S : String) return Natural is
      N : Natural := 0;
   begin
      for C of S loop
         if Character'Pos (C) not in 16#80# .. 16#BF# then N := N + 1; end if;
      end loop;
      return N;
   end Cols;

   function Fill (N : Integer; C : Character) return String is
      R : constant String (1 .. Integer'Max (0, N)) := [others => C];
   begin
      return R;
   end Fill;
   function Spaces (N : Integer) return String is (Fill (N, ' '));

   --  Word wrap of Text into lines of at most W columns (a longer word is cut).
   procedure Wrap (Into : in out Str_Vectors.Vector; Text : String; W : Positive) is
      Cur : Unbounded_String;
      From : Positive := Text'First;
      procedure Flush is
      begin
         if Length (Cur) > 0 then Into.Append (To_String (Cur)); Cur := Null_Unbounded_String; end if;
      end Flush;
      procedure Word (Wd : String) is
         Rest : Natural := Wd'First;
      begin
         if Wd'Length = 0 then return; end if;
         if Length (Cur) > 0 and then Cols (To_String (Cur)) + 1 + Cols (Wd) > W then Flush; end if;
         if Cols (Wd) > W then   --  cut a very long word by bytes (ASCII in practice)
            while Wd'Last - Rest + 1 > W loop
               Flush;
               Into.Append (Wd (Rest .. Rest + W - 1));
               Rest := Rest + W;
            end loop;
            Append (Cur, Wd (Rest .. Wd'Last));
         else
            Append (Cur, (if Length (Cur) > 0 then " " else "") & Wd);
         end if;
      end Word;
   begin
      for I in Text'First .. Text'Last + 1 loop
         if I > Text'Last or else Text (I) = ' ' then
            if I > From then Word (Text (From .. I - 1)); end if;
            From := I + 1;
         end if;
      end loop;
      Flush;
   end Wrap;

   function Shown (S : String) return String is (Sim_World.Show (S));

   function Join_Names (P : Player_Id) return String is
      R : Unbounded_String;
      N : Natural := 0;
      Total : Natural := 0;
   begin
      for E in Entity_Id loop if Watcher (E) = P then Total := Total + 1; end if; end loop;
      for E in Entity_Id loop
         if Watcher (E) = P then
            N := N + 1;
            Append (R, (if N = 1 then "" elsif N = Total then " " & Msg ("preport.and") & " " else ", ") & Shown (Name (E)));
         end if;
      end loop;
      return To_String (R);
   end Join_Names;

   function Band (Mean : Integer) return String is
     (if Mean >= 50 then "great" elsif Mean >= 15 then "good" elsif Mean >= -15 then "ok" elsif Mean >= -50 then "low" else "bad");

   --  The template of a slot for a player: a hash of (seed, tick, slot) says where the rotation starts, the player number moves it on, so
   --  the players of one box get different templates (N >= 4) and a later run (other tick) starts elsewhere.
   function Pick (Slot : Natural; P : Player_Id; Tick : Int; N : Positive) return Positive is
     ((Roll (Seed_V, 100, Tick, 9810 + Slot, N) - 1 + Integer (P) - 1) mod N + 1);

   function Key (Base : String; Slot : Natural; P : Player_Id; Tick : Int; N : Positive) return String is
     (Base & "." & Img (Pick (Slot, P, Tick, N)));

   --  What one player says in the box: who, petitions and decisions (the true D counts), the happiness it CLAIMS for its wesen, its
   --  top concern - up to three short sentences, wording from data/preport.txt (rbox.*).
   function Say_Of (P : Player_Id; Tick : Int; Made : Entry_Vectors.Vector) return String is
      C : constant Sim_Govern.Counts_T := Sim_Govern.Counts_Of (P);
      Top : constant String := Sim_Govern.Top_Concern (P);
      Sum, N : Integer := 0;
      Mean : Integer;
      R : Unbounded_String;
   begin
      for X of Made loop
         if X.P = P then Sum := Sum + X.Claimed; N := N + 1; end if;
      end loop;
      Mean := (if N = 0 then 0 else Sum / N);
      Append (R, Msg ("rbox.who", Player_Name (P), Join_Names (P)));
      if C (1) = 0 then
         Append (R, " " & Msg (Key ("rbox.pet0", 1, P, Tick, 3)));
      else
         Append (R, " " & Msg (Key ("rbox.pet", 1, P, Tick, 5), Img (C (1)), Img (C (2)), Img (C (3)), Img (C (4)), Img (C (5)),
                               Msg ("rbox.word." & (if C (1) = 1 then "one" else "many"))));
         if C (6) > 0 then Append (R, " " & Msg ("rbox.veto", Img (C (6)))); end if;
      end if;
      Append (R, " " & Msg (Key ("rbox.mood", 2, P, Tick, 5), Join_Names (P), Sgn (Int (Mean)), Msg ("rbox.band." & Band (Mean))));
      if Top = "" then
         Append (R, " " & Msg (Key ("rbox.concern0", 3, P, Tick, 3)));
      else
         Append (R, " " & Msg (Key ("rbox.concern", 3, P, Tick, 5), Sim_World.Topic_Phrase (Topic_Id (Top))));
      end if;
      return To_String (R);
   end Say_Of;

   --  ONE framed box for all players: a header line, then each player in one hanging paragraph.
   function One_Box (Tick : Int; Made : Entry_Vectors.Vector) return String is
      Out_T : Unbounded_String;
      Title : constant String := Shown (Msg ("preport.title", Img (Tick)));
      Inner : constant Positive := Width - 4;
      procedure Line (S : String) is
      begin
         Append (Out_T, "| " & S & Spaces (Inner - Cols (S)) & " |" & ASCII.LF);
      end Line;
   begin
      Append (Out_T, "+-- " & Title & " " & Fill (Integer'Max (1, Width - 6 - Cols (Title)), '-') & "+" & ASCII.LF);
      Line (Shown (Msg (Key ("rbox.head", 0, 1, Tick, 5))));
      for P in Player_Id range 1 .. Last_Player loop
         declare
            Lines : Str_Vectors.Vector;
            First : Boolean := True;
         begin
            Wrap (Lines, Shown (Say_Of (P, Tick, Made)), Inner - 3);
            for Ln of Lines loop
               Line ((if First then "" else "   ") & Ln);
               First := False;
            end loop;
         end;
      end loop;
      Append (Out_T, "+" & Fill (Width - 2, '-') & "+" & ASCII.LF);
      return To_String (Out_T);
   end One_Box;

   function Boxes (Tick : Int; Mood, Pets : Ints) return String is
      Made : constant Entry_Vectors.Vector :=
        (if Last_T = Tick and then not Latest.Is_Empty then Latest else Make_Entries (Tick, Mood, Pets, 0));
   begin
      return One_Box (Tick, Made) & ASCII.LF & Shown (Msg ("preport.hint")) & ASCII.LF;
   end Boxes;

   --  ---- the audit -------------------------------------------------------------------------------------------------------
   function Audit return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
   begin
      R.Append (Msg ("audit.head"));
      if Entries.Is_Empty then
         R.Append (Msg ("audit.none"));
         return R;
      end if;
      for P in Player_Id range 1 .. Last_Player loop
         declare
            Claims, Lies : Natural := 0;
            Big : Entry_T;
            Have : Boolean := False;
         begin
            for X of Entries loop
               if X.P = P then
                  Claims := Claims + 1;
                  if X.Lie then
                     Lies := Lies + 1;
                     if not Have or else abs (X.Claimed - X.True_M) > abs (Big.Claimed - Big.True_M) then Big := X; Have := True; end if;
                  end if;
               end if;
            end loop;
            R.Append (Msg ("audit.player", Player_Name (P), Img (Claims), Img (Lies), Img (Challenged (P))));
            R.Append ("  " & (if Have
                              then Msg ("audit.big", Name (Big.E), Img (Big.Tick), Sgn (Int (Big.Claimed)), Sgn (Int (Big.True_M)),
                                        Sgn (Int (Big.Claimed - Big.True_M)), Img (Big.TC) & "/" & Img (Big.TT))
                              else Msg ("audit.nobig")));
         end;
      end loop;
      R.Append (Msg ("audit.last", Img (Last_T)));
      for X of Latest loop
         R.Append ("  " & Msg ("audit.row", Name (X.E), Player_Name (X.P), Sgn (Int (X.Claimed)), Sgn (Int (X.True_M)),
                               Img (X.TC) & "/" & Img (X.TT)) & (if X.Lie then " " & Msg ("audit.lie", Sgn (Int (X.Claimed - X.True_M))) else ""));
      end loop;
      R.Append (Msg ("audit.hint"));
      return R;
   end Audit;

   function Digest_Line return String is
      Big : Integer := 0;
   begin
      for X of Entries loop
         if X.Lie and then abs (X.Claimed - X.True_M) > abs Big then Big := X.Claimed - X.True_M; end if;
      end loop;
      return Msg ("preport.digest", Img (Rounds), Img (Lie_Total), Img (Natural (Entries.Length)), Sgn (Int (Big)));
   end Digest_Line;

end Sim_Preport;
