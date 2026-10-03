--  Version: 0.004
--  diary_sim v1: four independent entities, one diary line per tick each.
--  Every random choice is hash (seed, entity, tick, salt): no RNG stream, so
--  any tick can be recomputed alone.  Diaries are append-only JSONL.  Every run
--  replays ticks 1 .. N from scratch (words, lessons and coined words cannot be
--  read back from a diary line): a tick already on disk is compared with the
--  regenerated line instead of written, a tick beyond the disk is appended.
--  entities/<id>/words.txt and bench.txt are append-only working files (NOT a VM):
--  a line the replay produces and the file lacks is appended, so they can be
--  rebuilt from nothing.  Bench hook for later: see README (PROOF-LATER).
pragma Ada_2022;

with Ada.Characters.Handling, Ada.Command_Line, Ada.Containers.Indefinite_Hashed_Sets, Ada.Directories,
     Ada.Exceptions, Ada.Strings.Fixed, Ada.Strings.Hash, Ada.Strings.Unbounded, Ada.Text_IO,
     GNAT.Traceback.Symbolic, Sim_Util, Sim_World;
use Ada.Strings.Unbounded, Sim_Util, Sim_World;

procedure Diary_Sim is
   package TIO renames Ada.Text_IO;
   package Fx renames Ada.Strings.Fixed;
   use type Ada.Directories.File_Size;

   type State is record
      Energy, Mood, Location : Integer;   --  ranges: data/limits.txt; location: office lab cafe home
   end record;
   --  Rest Work Explore Talk Wander Bench Learn.  Learn keeps the location (Home -1).
   Energy_D : constant array (Action) of Integer := [14, -8, -10, -2, -3, -4, -1];
   Mood_D   : constant array (Action) of Integer := [1, -4, 3, 2, -1, -1, 1];
   Home     : constant array (Action) of Integer := [3, 0, 1, 2, 0, 1, -1];   --  wander: rolled

   Usage_Error, Diary_Error : exception;
   Seed, Ticks, Every, Seed_Opt, Crash_At : Int := -1;
   Fresh, Seed_Shown : Boolean := False;
   --  Limits, built-in values; data/limits.txt overrides them.
   E_Min, E_Max, M_Min, M_Max, L_Max, Tone_Low, Tone_High : Integer := 0;
   Start_Pct, Teach_Pct, Coin_Pct, Coin_Cap, Bench_Steps : Int := 0;
   Vocab    : Str_Vectors.Vector;
   Disk     : array (Entity_Id) of Str_Vectors.Vector;      --  complete lines on disk
   St       : array (Entity_Id) of State := [others => (80, 0, 3)];
   Out_File : array (Entity_Id) of TIO.File_Type;
   Pending  : Unbounded_String;                             --  output held until the seed line
   Warnings, Events, Written, Verified : Natural := 0;
   Cur_Tick : Int := 0;
   Cur_Name : Unbounded_String := To_Unbounded_String ("-");

   --  Lessons: Pending_Word (E) /= 0 means E's next event is "learn" (from Pending_From).
   Pending_Word : array (Entity_Id) of Natural := [others => 0];
   Pending_From : array (Entity_Id) of Entity_Id := [others => 1];
   Did_Learn, Did_Coin, Did_Bench : Boolean := False;   --  what the last Step did
   Votes_Of : All_Stats;

   --  Working folder files, append-only, "ensure present" (see header).
   package Str_Sets is new Ada.Containers.Indefinite_Hashed_Sets (String, Ada.Strings.Hash, "=");
   type Side_Kind is (Words_File, Bench_File);
   Side_Have : array (Entity_Id, Side_Kind) of Str_Sets.Set;
   Side_Out  : array (Entity_Id, Side_Kind) of TIO.File_Type;
   function Path (E : Entity_Id) return String is ("diaries/" & Name (E) & ".jsonl");
   function Side_Path (E : Entity_Id; K : Side_Kind) return String is
     ("entities/" & Name (E) & (if K = Words_File then "/words.txt" else "/bench.txt"));
   function Low (A : List_Id) return String is (Ada.Characters.Handling.To_Lower (A'Image));
   function Low_Kernel (K : Kernel) return String is (Ada.Characters.Handling.To_Lower (K'Image));
   function Built_In (A : List_Id) return String is
     (case A is when Rest => "rested a while", when Work => "did some work", when Explore => "explored a little",
                when Talk => "wanted to talk to someone", when Wander => "wandered around",
                when Bench => "ran a small benchmark", when Learn => "learned something new",
                when Reason_Low => "it was hard", when Reason_Mid => "it was fine", when Reason_High => "it was good",
                when Mood_Low => "feeling low", when Mood_Neutral => "feeling steady", when Mood_High => "feeling good");

   procedure Say (Line : String) is   --  console output, held back until the seed line is out
   begin
      if Seed_Shown then TIO.Put_Line (Line); else Append (Pending, Line & ASCII.LF); end if;
   end Say;

   procedure Warn (Line : String) is
   begin
      Warnings := Warnings + 1;
      Say (Line);
   end Warn;

   procedure Load_Data is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Sec   : Integer := -1;
   begin
      Read_Lines (Data_Path ("messages.txt"), Lines, Found);
      if not Found then Warn ("warning: data/messages.txt not found; messages show their keys"); end if;
      Read_Lines (Data_Path ("limits.txt"), Lines, Found);
      if not Found then Warn (Msg ("warn.limits_file")); end if;
      Load_Keys (Lines);
      E_Min := Integer (Limit ("energy.min", 0));
      E_Max := Integer (Limit ("energy.max", 100));
      M_Min := Integer (Limit ("mood.min", -100));
      M_Max := Integer (Limit ("mood.max", 100));
      L_Max := Integer (Limit ("location.max", 3));
      Tone_Low := Integer (Limit ("mood.tone_low", -34));    --  mood <= this: low tone
      Tone_High := Integer (Limit ("mood.tone_high", 34));   --  mood >= this: high tone
      Start_Pct := Int'Min (100, Limit ("start_percent", 25));   --  share of the vocabulary known at tick 0
      Teach_Pct := Limit ("teach_percent", 50);
      Coin_Pct := Limit ("coin_percent", 20);
      Coin_Cap := Limit ("coin_cap", 40);
      Bench_Steps := Int'Max (1, Limit ("bench_steps", 2000));
      Lines.Clear;
      Read_Lines (Data_Path ("words.txt"), Lines, Found);
      for L of Lines loop
         if L'Length > 2 and then L (L'First) = '[' then
            Sec := -1;
            for A in List_Id loop
               if L = "[" & Low (A) & "]" then Sec := List_Id'Pos (A); end if;
            end loop;
         elsif L'Length > 0 and then L (L'First) /= '#' and then Sec >= 0 then
            Words (List_Id'Val (Sec)).Append (L);
         end if;
      end loop;
      if not Found or else (for all A in List_Id => Words (A).Is_Empty) then
         Warn (Msg ("warn.words_file"));
         Found := False;
      end if;
      for A in List_Id loop
         if Words (A).Is_Empty then
            if Found then Warn (Msg ("warn.words_empty", Low (A))); end if;
            Words (A).Append (Built_In (A));
         elsif Natural (Words (A).Length) /= 60 and then A in Action | Reason_Low | Reason_Mid | Reason_High | Mood_Low
           | Mood_Neutral | Mood_High
         then
            Warn (Msg ("warn.words_list", Low (A), Img (Integer (Words (A).Length))));
         end if;
      end loop;
      --  Vocabulary: one English word per line, id = line order; '#' and blank lines ignored.
      Lines.Clear;
      Read_Lines (Data_Path ("vocab.txt"), Lines, Found);
      for L of Lines loop
         declare
            T : constant String := Fx.Trim (L, Ada.Strings.Both);
         begin
            if T'Length > 0 and then T (T'First) /= '#' then Vocab.Append (T); end if;
         end;
      end loop;
      if Vocab.Is_Empty then
         Warn (Msg ("warn.vocab_file"));
         for W of Str_Vectors.Vector'(["hand", "phone", "house", "water", "go", "see", "eat", "sleep", "work", "talk",
                                       "home", "book"]) loop
            Vocab.Append (W);
         end loop;
      end if;
   end Load_Data;

   --  ---- working folder files -------------------------------------------------------

   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (parsing of the '# seed N' header)
   procedure Open_Side (E : Entity_Id; K : Side_Kind) is
      P     : constant String := Side_Path (E, K);
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Mark  : constant String := "# seed ";
   begin
      if Ada.Directories.Exists (P) and then Ada.Directories.Size (P) > 0 then
         Read_Lines (P, Lines, Found);
         if not Lines.Is_Empty and then Fx.Index (Lines.First_Element, Mark) = 1
           and then Lines.First_Element /= Mark & Img (Seed)
         then
            raise Diary_Error with Msg ("err.entities_seed", P, Lines.First_Element (Mark'Length + 1 .. Lines.First_Element'Last));
         end if;
         for L of Lines loop Side_Have (E, K).Include (L); end loop;
         declare
            Needs_Lf : constant Boolean := not Ends_With_Lf (P);
         begin
            TIO.Open (Side_Out (E, K), TIO.Append_File, P);
            if Needs_Lf then TIO.New_Line (Side_Out (E, K)); end if;
         end;
      else
         TIO.Create (Side_Out (E, K), TIO.Out_File, P);
         TIO.Put_Line (Side_Out (E, K), Mark & Img (Seed));
         TIO.Put_Line (Side_Out (E, K), Msg (if K = Words_File then "hdr.words" else "hdr.bench"));
         TIO.Flush (Side_Out (E, K));
      end if;
   end Open_Side;

   --  Append Line unless the file already has it; flushed at once.
   procedure Ensure (E : Entity_Id; K : Side_Kind; Line : String) is
   begin
      if not Side_Have (E, K).Contains (Line) then
         TIO.Put_Line (Side_Out (E, K), Line);
         TIO.Flush (Side_Out (E, K));
         Side_Have (E, K).Include (Line);
      end if;
   end Ensure;

   function Words_Line (W : Positive; How : String; Tick : Int; Extra : String) return String is
     (Img (W) & " " & Word (W) & " " & How & " " & Img (Tick) & (if Extra = "" then "" else " " & Extra));

   --  Advance entity E by one tick; returns its diary line.  Teaching, coining and
   --  bench happen here; their working-folder lines are ensured as they occur.
   function Step (E : Entity_Id; Tick : Int) return String is
      Die : constant Positive := Roll (Seed, Positive (E), Tick, 0, 20);
      A   : constant Action :=
        (if Pending_Word (E) /= 0 then Learn
         else (case Die is when 1 .. 6 => Rest, when 7 .. 10 => Work, when 11 .. 13 => Explore,
                           when 14 .. 16 => Talk, when 17 .. 19 => Wander, when others => Bench));
      S   : State renames St (E);
      Detail : Unbounded_String;
      Eid : constant Positive := Positive (E);

      --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (pick indices stay inside 1 .. count)
      procedure Teach is
         P : constant Entity_Id := Entity_Id ((Integer (E) - 1 + Roll (Seed, Eid, Tick, 3, 3)) mod 4 + 1);
         N : constant Natural := Teachable_Count (E, P);
      begin
         if Int (Roll (Seed, Eid, Tick, 2, 100)) <= Teach_Pct and then Pending_Word (P) = 0 and then N > 0 then
            Pending_Word (P) := Nth_Teachable (E, P, Roll (Seed, Eid, Tick, 4, N));
            Pending_From (P) := E;
            Detail := To_Unbounded_String (Msg ("detail.taught", Name (P), Word (Pending_Word (P))));
         end if;
      end Teach;

      procedure Coin is
         K : constant Natural := Known_Count (E);
      begin
         if Int (Roll (Seed, Eid, Tick, 5, 100)) <= Coin_Pct and then K >= 2
           and then Int (Count - Base_Count) < Coin_Cap
         then
            declare
               Ia : constant Positive := Roll (Seed, Eid, Tick, 6, K);
               Ib0 : constant Positive := Roll (Seed, Eid, Tick, 7, K - 1);
               Ib : constant Positive := (if Ib0 >= Ia then Ib0 + 1 else Ib0);
               Pa : constant Positive := Nth_Known (E, Ia);
               Pb : constant Positive := Nth_Known (E, Ib);
               Text : constant String := Word (Pa) & Word (Pb);
            begin
               if Text'Length <= 24 and then Find (Text) = 0 then
                  declare
                     W : constant Positive := Add_Coined (Text, Pa, Pb);
                  begin
                     Learn_Word (E, W);
                     Ensure (E, Words_File, Words_Line (W, "coined", Tick, Parents (W)));
                     Detail := To_Unbounded_String (Msg ("detail.coined", Text, Word (Pa), Word (Pb)));
                     Did_Coin := True;
                  end;
               end if;
            end;
         end if;
      end Coin;

   begin
      Did_Learn := False;
      Did_Coin := False;
      Did_Bench := False;
      S.Energy := Clamp (S.Energy + Energy_D (A), E_Min, E_Max);
      S.Mood := Clamp (S.Mood + Mood_D (A), M_Min, M_Max);
      if A = Wander then
         S.Location := Roll (Seed, Eid, Tick, 1, 4) - 1;
      elsif Home (A) >= 0 then
         S.Location := Home (A);
      end if;
      S.Location := Clamp (S.Location, 0, L_Max);
      case A is
         when Talk => Teach;
         when Explore | Wander => Coin;
         when Learn =>
            declare
               W : constant Positive := Pending_Word (E);
            begin
               Learn_Word (E, W);
               Ensure (E, Words_File, Words_Line (W, "taught", Tick, Name (Pending_From (E))));
               Detail := To_Unbounded_String (Msg ("detail.learned", Word (W), Name (Pending_From (E))));
               Pending_Word (E) := 0;
               Did_Learn := True;
            end;
         when Bench =>
            declare
               R : constant Bench_Result := Run_Bench (Seed, E, Tick, Bench_Steps);
            begin
               Ensure (E, Bench_File, Img (Tick) & " " & Low_Kernel (R.Which) & " " & Img (R.Steps) & " "
                       & Img (R.Result) & " " & Img (R.Checksum));
               Detail := To_Unbounded_String (Msg ("detail.bench", Low_Kernel (R.Which), Img (R.Steps), Img (R.Result),
                                                   Img (R.Checksum)));
               Did_Bench := True;
            end;
         when others => null;
      end case;
      declare
         Tone : constant List_Id := (if S.Mood <= Tone_Low then Mood_Low elsif S.Mood >= Tone_High then Mood_High
                                     else Mood_Neutral);
         Text : constant String := Words (A) (Words (A).First_Index + Pick60 (Seed, Eid, Tick, 10) mod Natural (Words (A).Length))
           & ", " & Words (Tone) (Words (Tone).First_Index + Pick60 (Seed, Eid, Tick, 100) mod Natural (Words (Tone).Length))
           & (if Length (Detail) > 0 then "; " & To_String (Detail) else "");
      begin
         return "{""v"":1,""seed"":" & Img (Seed) & ",""tick"":" & Img (Tick) & ",""ts"":""" & Stamp
           & """,""t"":""" & Low (A) & """,""text"":""" & Esc (Text)
           & """,""state"":{""energy"":" & Img (S.Energy) & ",""mood"":" & Img (S.Mood)
           & ",""location"":" & Img (S.Location) & "}}";
      end;
   end Step;

   function Forced (Tick : Int) return Natural is (Natural'Value ("tick " & Img (Tick)));   --  always fails

   procedure Load_Diary (E : Entity_Id; Disk_Seed : in out Int) is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      Read_Lines (Path (E), Lines, Found);
      for I in 1 .. Natural (Lines.Length) loop
         declare
            L : constant String := Lines (I);
            N : constant Int := Int (Disk (E).Length) + 1;
         begin
            if Complete (L) then
               if Field (L, "tick") /= N then
                  raise Diary_Error with Msg ("err.gap", Name (E), Img (I), Img (Field (L, "tick")), Img (N));
               elsif Disk_Seed >= 0 and then Field (L, "seed") /= Disk_Seed then
                  raise Diary_Error with Msg ("err.seed", Name (E), Img (I), Img (Field (L, "seed")), Img (Disk_Seed));
               end if;
               Disk_Seed := Field (L, "seed");
               Disk (E).Append (L);
            elsif L'Length > 0 then
               Warn (Msg ("warn.bad_line", Name (E), Img (I)));   --  e.g. a half-written last line
            end if;
         end;
      end loop;
   end Load_Diary;

   --  last_error.txt gets everything; the console the first 14 lines (+ a note).
   procedure Report (E : Ada.Exceptions.Exception_Occurrence) is
      Raw  : constant String := GNAT.Traceback.Symbolic.Symbolic_Traceback (E);
      Text : constant String := Msg ("err.head", Ada.Exceptions.Exception_Message (E)) & ASCII.LF
        & Msg ("err.where", Img (Seed), Img (Cur_Tick), To_String (Cur_Name), Ada.Exceptions.Exception_Name (E))
        & ASCII.LF & Msg ("err.trace") & ASCII.LF & Frames (Raw);
      F : TIO.File_Type;
      Count : Natural := 0;
      From  : Positive := Text'First;
   begin
      TIO.Create (F, TIO.Out_File, "last_error.txt");
      TIO.Put (F, Text & Msg ("err.raw") & ASCII.LF & Raw);
      TIO.Close (F);
      for I in Text'Range loop
         if Text (I) = ASCII.LF then
            Count := Count + 1;
            if Count <= 14 then TIO.Put_Line (Text (From .. I - 1)); end if;
            From := I + 1;
         end if;
      end loop;
      if Count > 14 then TIO.Put_Line (Msg ("err.more", Img (Count - 14))); end if;
   end Report;

   function Number (Opt, Text : String) return Int is
   begin
      if Text'Length not in 1 .. 15 or else (for some C of Text => C not in '0' .. '9') then
         raise Usage_Error with Msg ("err.number", Opt, Text);
      end if;
      return Int'Value (Text);
   end Number;

   Disk_Seed : Int := -1;
   Common, Longest : Natural := 0;
   Names : Unbounded_String;
   I : Positive := 1;
begin
   Load_Data;
   while I <= Ada.Command_Line.Argument_Count loop
      declare
         A   : constant String := Ada.Command_Line.Argument (I);
         Eq  : constant Natural := Fx.Index (A, "=");
         Opt : constant String := (if Eq > 0 then A (A'First .. Eq - 1) else A);
         Num : constant Boolean := Opt in "--ticks" | "--seed" | "--every" | "--crash-at";
         Sep : constant Boolean := Num and then Eq = 0 and then I < Ada.Command_Line.Argument_Count;   --  --ticks 200
         Val : constant String := (if Eq > 0 then A (Eq + 1 .. A'Last) elsif Sep then Ada.Command_Line.Argument (I + 1) else "");
         Help  : Str_Vectors.Vector;
         Found : Boolean;
      begin
         if Sep then I := I + 1; end if;
         if Opt = "--help" or else Opt = "-h" then
            Read_Lines (Data_Path ("help.txt"), Help, Found);
            for L of Help loop TIO.Put_Line (L); end loop;
            if not Found then TIO.Put_Line ("diary_sim: data/help.txt not found (--ticks --seed --every --fresh --crash-at)"); end if;
            return;
         elsif Opt = "--fresh" then Fresh := True;
         elsif Opt = "--ticks" then Ticks := Number (Opt, Val);
         elsif Opt = "--seed" then Seed_Opt := Number (Opt, Val);
         elsif Opt = "--every" then Every := Number (Opt, Val);
         elsif Opt = "--crash-at" then Crash_At := Number (Opt, Val);
         else raise Usage_Error with Msg ("err.option", A);
         end if;
      end;
      I := I + 1;
   end loop;
   Ticks := (if Ticks < 0 then 1000 else Ticks);
   Every := (if Every < 0 then 100 else Int'Max (1, Every));

   if Fresh and then (Ada.Directories.Exists ("diaries") or else Ada.Directories.Exists ("entities")) then
      declare
         Old : constant String := "diaries_old_" & Plain_Stamp;
      begin
         if Ada.Directories.Exists ("diaries") then
            Ada.Directories.Rename ("diaries", Old);
         else
            Ada.Directories.Create_Path (Old);
         end if;
         if Ada.Directories.Exists ("entities") then Ada.Directories.Rename ("entities", Old & "/entities"); end if;
         Say (Msg ("fresh.moved", Old));
      end;
   end if;
   Ada.Directories.Create_Path ("diaries");
   for E in Entity_Id loop
      Cur_Name := To_Unbounded_String (Name (E));
      Load_Diary (E, Disk_Seed);
      Common := (if E = 1 then Natural (Disk (E).Length) else Natural'Min (Common, Natural (Disk (E).Length)));
      Longest := Natural'Max (Longest, Natural (Disk (E).Length));
      Append (Names, (if E = 1 then "" else " ") & Name (E) & "(" & Kind (E) & ")");
   end loop;
   Cur_Name := To_Unbounded_String ("-");

   Seed := (if Disk_Seed >= 0 then Disk_Seed elsif Seed_Opt >= 0 then Seed_Opt else 42);
   TIO.Put_Line (Msg ("seed", Img (Seed), Msg (if Disk_Seed >= 0 then "seed.disk" elsif Seed_Opt >= 0 then "seed.option"
                                                else "seed.default")));
   Seed_Shown := True;
   TIO.Put (To_String (Pending));
   if Disk_Seed >= 0 and then Seed_Opt >= 0 and then Seed_Opt /= Disk_Seed then
      Warn (Msg ("warn.seed_ignored", Img (Seed_Opt), Img (Disk_Seed)));
   end if;
   TIO.Put_Line (Msg ("entities", To_String (Names)));
   for E in Entity_Id loop
      if Natural (Disk (E).Length) < Longest then
         Warn (Msg ("warn.behind", Name (E), Img (Integer (Disk (E).Length)), Img (Longest), Img (Common)));
      end if;
   end loop;
   TIO.Put_Line (Msg ((if Common = 0 then "resume" else "verifying"), Img (Common), Img (Ticks)));

   --  Every run starts from the vocabulary and replays from tick 1.
   Sim_World.Init (Vocab, Seed, Start_Pct);
   for E in Entity_Id loop
      Cur_Name := To_Unbounded_String (Name (E));
      Ada.Directories.Create_Path ("entities/" & Name (E));
      for K in Side_Kind loop Open_Side (E, K); end loop;
      for W in 1 .. Base_Count loop
         if Knows (E, W) then Ensure (E, Words_File, Words_Line (W, "start", 0, "")); end if;
      end loop;
   end loop;
   Cur_Name := To_Unbounded_String ("-");
   for E in Entity_Id loop
      if Ada.Directories.Exists (Path (E)) then
         declare
            Needs_Lf : constant Boolean := Ada.Directories.Size (Path (E)) > 0 and then not Ends_With_Lf (Path (E));
         begin
            TIO.Open (Out_File (E), TIO.Append_File, Path (E));
            if Needs_Lf then TIO.New_Line (Out_File (E)); end if;   --  never glue onto a half line
         end;
      else
         TIO.Create (Out_File (E), TIO.Out_File, Path (E));
      end if;
   end loop;

   for Tick in Int range 1 .. Ticks loop
      Cur_Tick := Tick;
      for E in Entity_Id loop      --  fixed id order
         Cur_Name := To_Unbounded_String (Name (E));
         if Tick = Crash_At and then Tick > Int (Common) and then E = 1 then Events := Forced (Tick); end if;
         declare
            Line : constant String := Step (E, Tick);
         begin
            if Tick <= Int (Disk (E).Length) then   --  already on disk: compare, do not write
               if No_Ts (Line) /= No_Ts (Disk (E) (Positive (Tick))) then
                  raise Diary_Error with Msg ("err.drift", Name (E), Img (Tick),
                                              Diff_At (No_Ts (Disk (E) (Positive (Tick))), No_Ts (Line)));
               end if;
               Verified := Verified + 1;
            else
               TIO.Put_Line (Out_File (E), Line);
               TIO.Flush (Out_File (E));
               Written := Written + 1;
            end if;
            Events := Written + Verified;
            Record_Tick (Votes_Of (E), St (E).Location, St (E).Mood, St (E).Energy, Did_Learn, Did_Coin, Did_Bench);
         end;
      end loop;
      if Tick > Int (Common) and then Tick mod Every = 0 then
         TIO.Put_Line (Msg ("progress", Img (Tick), Img (Ticks), Img (Integer (Entity_Id'Last)), Img (Events)));
      end if;
   end loop;
   for F of Out_File loop TIO.Close (F); end loop;
   for F of Side_Out loop TIO.Close (F); end loop;
   TIO.Put_Line (Msg ("summary", Img (Int'Min (Int (Common) + 1, Ticks)), Img (Ticks), Img (Integer (Entity_Id'Last)),
                      Img (Events), Img (Written), Img (Verified), Img (Warnings)));
   declare
      Console, Text, Json : Unbounded_String;
      procedure Save (File : String; Content : Unbounded_String) is
         F : TIO.File_Type;
      begin
         TIO.Create (F, TIO.Out_File, File);
         TIO.Put (F, To_String (Content));
         TIO.Close (F);
      end Save;
   begin
      Summarize (Seed, Ticks, Votes_Of, Console, Text, Json);
      Save ("summary.txt", Text);
      Save ("summary.jsonl", Json);
      TIO.Put (To_String (Console));
      TIO.Put_Line (Msg ("summary.files"));
   end;
exception
   when E : Usage_Error =>
      TIO.Put_Line (TIO.Standard_Error, Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (2);
   when E : others =>
      Report (E);
      Ada.Command_Line.Set_Exit_Status (1);
end Diary_Sim;
