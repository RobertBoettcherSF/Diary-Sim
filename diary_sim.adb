--  Version: 0.009
--  diary_sim v1: four independent entities, one diary line per tick each.
--  Every random choice is hash (seed, entity, tick, salt): no RNG stream, so
--  any tick can be recomputed alone.  Diaries are append-only JSONL.  Every run
--  replays ticks 1 .. N from scratch (words, lessons and coined words cannot be
--  read back from a diary line): a tick already on disk is compared with the
--  regenerated line instead of written, a tick beyond the disk is appended.
--  Session length: without --ticks / --more the four entities vote (Kalpas, data/kalpas.txt)
--  and the median is the number of new ticks; diaries/sessions.txt records every session
--  and is verified on import (see README).
--  entities/<id>/words.txt and bench.txt are append-only working files (NOT a VM):
--  a line the replay produces and the file lacks is appended, so they can be
--  rebuilt from nothing.  Bench hook for later: see README (PROOF-LATER).
--  Ctrl-C and SIGTERM are caught (Sim_Quit); the runtime reserves them unless released here.
pragma Interrupt_State (SIGINT, USER);
pragma Interrupt_State (SIGTERM, USER);
pragma Ada_2022;

with Ada.Characters.Handling, Ada.Command_Line, Ada.Containers.Indefinite_Hashed_Sets, Ada.Containers.Vectors, Ada.Directories,
     Ada.Exceptions, Ada.Strings.Fixed, Ada.Strings.Hash, Ada.Strings.Unbounded, Ada.Text_IO,
     GNAT.Traceback.Symbolic, Sim_Quit, Sim_Util, Sim_World;
use Ada.Strings.Unbounded, Sim_Util, Sim_World;

procedure Diary_Sim is
   package TIO renames Ada.Text_IO;
   package Fx renames Ada.Strings.Fixed;
   use type Ada.Directories.File_Size;

   type State is record
      Energy, Mood, Location : Integer;   --  ranges: data/limits.txt; location: office lab cafe home
   end record;
   --  Rest Work Explore Talk Wander Bench Propose Learn.  Propose and Learn keep the location (Home -1).
   Energy_D : constant array (Action) of Integer := [14, -8, -10, -2, -3, -4, -1, -1];
   Mood_D   : constant array (Action) of Integer := [1, -4, 3, 2, -1, -1, 2, 1];
   Home     : constant array (Action) of Integer := [3, 0, 1, 2, 0, 1, -1, -1];   --  wander: rolled

   Build : constant String := "0.009";   --  = the Version header of this file (make version-check)
   Usage_Error, Diary_Error : exception;
   Seed, Ticks, Every, Seed_Opt, Crash_At, More : Int := -1;   --  More: --more N = N new ticks on top of the disk
   Fresh, Seed_Shown : Boolean := False;
   Explicit : Boolean := False;        --  --ticks or --more given: no vote
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
   Act_Count : array (Entity_Id, Action) of Natural := [others => [others => 0]];   --  all ticks replayed
   Last_Act : Action := Rest;
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
                when Propose => "filed a petition", when Wish_Open => "I would like", when Wish_Close => "so my days go better",
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
         elsif Natural (Words (A).Length) /= 60 then
            Warn (Msg ("warn.words_list", Low (A), Img (Integer (Words (A).Length))));
         end if;
      end loop;
      Lines.Clear;
      Read_Lines (Data_Path ("topics.txt"), Lines, Found);
      Load_Topics (Lines);
      if Topic_Count = 1 and then (not Found or else Lines.Is_Empty) then Warn (Msg ("warn.topics_file")); end if;
      Lines.Clear;
      Read_Lines (Data_Path ("kalpas.txt"), Lines, Found);
      Load_Kalpas (Lines);
      if not Found then
         Warn (Msg ("warn.kalpas_file"));
      elsif Kalpa_Count /= 60 then
         Warn (Msg ("warn.kalpas_count", Img (Kalpa_Count)));
      end if;
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
      A   : constant Action :=
        (if Pending_Word (E) /= 0 then Learn else Choose (Seed, E, Tick, St (E).Energy, St (E).Mood));
      Pre_En : constant Integer := St (E).Energy;     --  state before this action
      Pre_Mo : constant Integer := St (E).Mood;
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
      Last_Act := A;
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
         when Propose =>
            declare
               N : constant Positive := File_Petition (Seed, E, Tick, Pre_En, Pre_Mo, Act_Count (E, Bench));
            begin
               Detail := To_Unbounded_String (Msg ("detail.petition", Img (N), Petition_Topic (N)));
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

   --  last_error.txt gets everything; the console the first 11 lines (+ a note) and two hints.
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
            if Count <= 11 then TIO.Put_Line (Text (From .. I - 1)); end if;
            From := I + 1;
         end if;
      end loop;
      if Count > 11 then TIO.Put_Line (Msg ("err.more", Img (Count - 11))); end if;
      TIO.Put_Line (Msg ("crash.paste"));
      TIO.Put_Line (Msg ("crash.backup"));
   end Report;

   --  "error: NAME: message" and the top 5 frames, for debug.txt.
   function Error_Brief (E : Ada.Exceptions.Exception_Occurrence) return String is
      Fr : constant String := Frames (GNAT.Traceback.Symbolic.Symbolic_Traceback (E));
      Res : Unbounded_String;
      From : Positive := Fr'First;
      N : Natural := 0;
   begin
      for I in Fr'Range loop
         if Fr (I) = ASCII.LF and then N < 5 then
            Append (Res, (if N = 0 then "" else " < ") & Fr (From .. I - 1));
            N := N + 1;
            From := I + 1;
         end if;
      end loop;
      return "error: " & Ada.Exceptions.Exception_Name (E) & ": " & Ada.Exceptions.Exception_Message (E)
        & ASCII.LF & "at: " & To_String (Res);
   end Error_Brief;

   --  A pasted backup in the wrong place: diaries/diaries, Diaries/, DIARIES/ ...
   --  Stops (Diary_Error) when diaries/ holds no *.jsonl but a misplaced folder is found;
   --  otherwise only warns.  PROOF-LATER: Importance 2/10, Urgency 2/10, SPARK2 (directory scan)
   procedure Check_Layout is
      use Ada.Directories;
      Has_Jsonl : Boolean := False;
      Hint : Unbounded_String;
      S : Search_Type;
      D : Directory_Entry_Type;
      function Lower (X : String) return String is (Ada.Characters.Handling.To_Lower (X));
   begin
      if Exists ("diaries") and then Kind ("diaries") = Directory then
         Start_Search (S, "diaries", "*.jsonl");
         Has_Jsonl := More_Entries (S);
         End_Search (S);
         if Exists ("diaries/diaries") then Hint := To_Unbounded_String ("diaries/diaries"); end if;
      end if;
      Start_Search (S, ".", "*", [Directory => True, others => False]);
      while More_Entries (S) loop
         Get_Next_Entry (S, D);
         if Lower (Simple_Name (D)) in "diaries" | "entities" and then Simple_Name (D) not in "diaries" | "entities"
           and then Length (Hint) = 0
         then
            Hint := To_Unbounded_String (Simple_Name (D) & "/");   --  wrong case
         end if;
      end loop;
      End_Search (S);
      if Length (Hint) > 0 then
         if Has_Jsonl then
            Warn (Msg ("warn.nested", To_String (Hint)));
         else
            raise Diary_Error with Msg ("err.nested", To_String (Hint));
         end if;
      end if;
      if Exists ("entities/entities") then Warn (Msg ("warn.nested", "entities/entities")); end if;
   end Check_Layout;

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
   Import_Block, Kalpa_Line : Unbounded_String;
   I : Positive := 1;
   Verify_To : Natural := 0;           --  ticks replayed (verify only) before the import line
   Import_Done : Boolean := False;
   Ent_Missing : Natural := 0;         --  entity folders without words.txt/bench.txt at start
   Start_Known : array (Entity_Id) of Natural := [others => 0];
   Run_Learn, Run_Coin, Run_Bench_N : array (Entity_Id) of Natural := [others => 0];
   Last_Done : Int := 0;                --  last tick finished for all entities
   Export_Line, Vote_Line : Unbounded_String;
   Quit_Seen : Boolean := False;

   --  debug.txt: ONE small file (<= 1500 bytes) on every exit path; Status is
   --  RUN (stub, refreshed every --every ticks), OK, QUIT, CRASH, DRIFT or USAGE.
   --  Parts are kept by priority (header, ticks, error, entities, votes, import,
   --  export); what does not fit is cut, the file never exceeds the cap.
   --  Written to debug.tmp, flushed, then renamed over debug.txt.
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (length cap, text assembly)
   procedure Write_Debug (Status, Err : String) is
      Cap : constant := 1500;
      type Part_Id is (Head, Ticks_P, Kalpa_P, Import_P, Export_P, Ents, Mix_P, Topics_P, Votes, Error_P);
      Part : array (Part_Id) of Unbounded_String;
      Order : constant array (1 .. 10) of Part_Id := [Head, Ticks_P, Kalpa_P, Error_P, Ents, Mix_P, Topics_P, Votes, Import_P, Export_P];
      Used : Natural := 0;
      Out_Text : Unbounded_String;
      F : TIO.File_Type;
   begin
      Part (Head) := To_Unbounded_String (Status & " v" & Build & " seed " & (if Seed < 0 then "?" else Img (Seed)) & ASCII.LF);
      Part (Ticks_P) := To_Unbounded_String
        ((if Last_Done > Int (Common)
          then Msg ("debug.ticks", Img (Int (Common) + 1), Img (Last_Done), Img (Last_Done - Int (Common)), Img (Common))
          else Msg ("debug.ticks_v", Img (Last_Done), Img (Common))) & ASCII.LF);
      if Length (Kalpa_Line) > 0 then Part (Kalpa_P) := Kalpa_Line & ASCII.LF; end if;
      Part (Import_P) := To_Unbounded_String ((if Length (Import_Block) > 0 then To_String (Import_Block) else Msg ("debug.pending", "import"))
                                              & ASCII.LF);
      Part (Export_P) := To_Unbounded_String ((if Length (Export_Line) > 0 then To_String (Export_Line) else Msg ("debug.pending", "export"))
                                              & ASCII.LF);
      for E in Entity_Id loop
         Append (Part (Ents), Msg ("debug.entity", Name (E), Img (Start_Known (E)), Img (Known_Count (E)), Img (Run_Learn (E)),
                                   Img (Run_Coin (E)), Img (Run_Bench_N (E)), Sgn (Int (St (E).Mood)) & " en " & Img (St (E).Energy) & " pet " & Img (Petitions_Of (E)))
                 & ASCII.LF);
      end loop;
      for E in Entity_Id loop
         Append (Part (Mix_P), Msg ("debug.mix", Name (E), Img (Act_Count (E, Rest)), Img (Act_Count (E, Work)),
                                    Img (Act_Count (E, Explore)), Img (Act_Count (E, Talk)), Img (Act_Count (E, Wander)),
                                    Img (Act_Count (E, Bench)) & " p" & Img (Act_Count (E, Propose)) & " l" & Img (Act_Count (E, Learn)))
                 & ASCII.LF);
      end loop;
      Part (Topics_P) := To_Unbounded_String ("topics " & Top_Topics (3) & ASCII.LF);
      if Length (Vote_Line) > 0 then Part (Votes) := Vote_Line & ASCII.LF; end if;
      if Err'Length > 0 then Part (Error_P) := To_Unbounded_String (Err & ASCII.LF); end if;
      for P of Order loop
         declare
            Room : constant Integer := Cap - Used;
            T : constant String := To_String (Part (P));
         begin
            if Room <= 0 then
               Part (P) := Null_Unbounded_String;
            elsif T'Length > Room then
               Part (P) := To_Unbounded_String (T (T'First .. T'First + Room - 1));
               Used := Cap;
            else
               Used := Used + T'Length;
            end if;
         end;
      end loop;
      for P in Part_Id loop Append (Out_Text, Part (P)); end loop;
      TIO.Create (F, TIO.Out_File, "debug.tmp");
      TIO.Put (F, To_String (Out_Text));
      TIO.Flush (F);
      TIO.Close (F);
      begin
         Ada.Directories.Rename ("debug.tmp", "debug.txt");
      exception
         when others =>   --  a rename that will not replace: delete first
            Ada.Directories.Delete_File ("debug.txt");
            Ada.Directories.Rename ("debug.tmp", "debug.txt");
      end;
   exception
      when others => TIO.Put_Line (Msg ("debug.failed"));
   end Write_Debug;

   --  One tick for all entities in id order: compare with the disk or append.
   procedure Do_Tick (Tick : Int) is
   begin
      Cur_Tick := Tick;
      for E in Entity_Id loop
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
            Act_Count (E, Last_Act) := Act_Count (E, Last_Act) + 1;
            Record_Tick (Votes_Of (E), St (E).Location, St (E).Mood, St (E).Energy, Did_Learn, Did_Coin, Did_Bench);
            if Tick > Int (Common) then
               Run_Learn (E) := Run_Learn (E) + Boolean'Pos (Did_Learn);
               Run_Coin (E) := Run_Coin (E) + Boolean'Pos (Did_Coin);
               Run_Bench_N (E) := Run_Bench_N (E) + Boolean'Pos (Did_Bench);
            end if;
         end;
      end loop;
      Last_Done := Tick;
   end Do_Tick;

   --  petitions.txt: a view of the petitions the replay filed (the last propose.file_cap lines;
   --  the oldest drop out of the file, never out of the diaries).  Rewritten atomically.
   procedure Write_Petitions is
      Cap : constant Natural := Natural (Int'Max (1, Limit ("propose.file_cap", 40)));
      Total : constant Natural := Petition_Total;
      First : constant Natural := (if Total > Cap then Total - Cap + 1 else 1);
      F : TIO.File_Type;
   begin
      TIO.Create (F, TIO.Out_File, "petitions.tmp");
      TIO.Put_Line (F, Msg ("pet.head", Img (Seed), Img (Integer (Total) - First + 1), Img (Total)));
      for N in First .. Total loop TIO.Put_Line (F, Petition_Line (N)); end loop;
      TIO.Flush (F);
      TIO.Close (F);
      begin
         Ada.Directories.Rename ("petitions.tmp", "petitions.txt");
      exception
         when others =>
            Ada.Directories.Delete_File ("petitions.txt");
            Ada.Directories.Rename ("petitions.tmp", "petitions.txt");
      end;
   exception
      when others => TIO.Put_Line (Msg ("debug.failed"));
   end Write_Petitions;

   --  Re-open what the run wrote and count it (not just a print).  Fails gets one
   --  fragment per problem.  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (file reading, counts)
   procedure Check_File (P : String; Expect : Integer; Kind : Character; Lines : out Natural;
                         Fails : in out Unbounded_String)
   is
      V : Str_Vectors.Vector;
      Found : Boolean;
   begin   --  Kind: 'd' diary (complete lines, exact count), 's' side file (# seed header), 't' text (not empty)
      Lines := 0;
      if not Ada.Directories.Exists (P) or else Ada.Directories.Size (P) = 0 then
         Append (Fails, " " & P & " missing or empty;");
         return;
      end if;
      Read_Lines (P, V, Found);
      for L of V loop
         if (if Kind = 'd' then Complete (L) else L'Length > 0) then Lines := Lines + 1; end if;
      end loop;
      if Kind = 'd' and then Lines /= Expect then
         Append (Fails, " " & P & " has" & Lines'Image & " lines, expected" & Expect'Image & ";");
      elsif Kind = 's' and then (V.Is_Empty or else V.First_Element /= "# seed " & Img (Seed)) then
         Append (Fails, " " & P & " has no '# seed " & Img (Seed) & "' header;");
      elsif Expect > 0 and then Lines /= Expect then
         Append (Fails, " " & P & " has" & Lines'Image & " lines, expected" & Expect'Image & ";");
      end if;
   end Check_File;

   --  The import block (printed once the stored ticks 1..Verify_To replayed without drift).
   function Import_Text (Total_Lines : Natural) return String is
      Have : Natural := 0;
      Know : Unbounded_String;
   begin
      for E in Entity_Id loop
         if not Disk (E).Is_Empty then Have := Have + 1; end if;
         Append (Know, (if E = 1 then "" else " ") & Name (E) & " " & Img (Known_Count (E)));
      end loop;
      if Total_Lines = 0 then return Msg ("import.none", Img (Seed)); end if;
      return Msg ("import.ok", Img (Have), Img (Verify_To), Img (Int (Common) + 1), Img (Total_Lines), Img (Longest))
        & ASCII.LF
        & Msg ("import.entities",
               (if Ent_Missing = 0 then Msg ("ent.present", "4") else Msg ("ent.rebuilt", Img (Ent_Missing))),
               Img (Verify_To), To_String (Know));
   end Import_Text;

   --  ---- sessions (kalpas) -----------------------------------------------------------------
   type Session_Rec is record
      N : Positive := 1;
      Start, Len : Int := 0;
      Votes : Kalpa_Votes := [others => 0];
      By_Vote : Boolean := False;       --  src=vote (else explicit)
   end record;
   package Session_Vectors is new Ada.Containers.Vectors (Positive, Session_Rec);
   Sessions : Session_Vectors.Vector;
   Sessions_Path : constant String := "diaries/sessions.txt";

   function Votes_Text (V : Kalpa_Votes) return String is
     (Img (V (1)) & "/" & Img (V (2)) & "/" & Img (V (3)) & "/" & Img (V (4)));
   function Session_Line (R : Session_Rec) return String is
     ("S" & Img (R.N) & " start=" & Img (R.Start) & " votes=" & Votes_Text (R.Votes) & " len=" & Img (R.Len)
      & " src=" & (if R.By_Vote then "vote" else "explicit"));
   function Yuga (N : Positive) return String is (Msg ("yuga." & Img ((N - 1) mod 4)));
   --  The four votes of a session that starts after tick Start (state: St, known words).
   function Votes_At (Start : Int) return Kalpa_Votes is
      V : Kalpa_Votes;
   begin
      for E in Entity_Id loop
         V (Integer (E)) := Kalpa_Vote (Seed, E, Start, St (E).Energy, St (E).Mood);
      end loop;
      return V;
   end Votes_At;
   function Decided (V : Kalpa_Votes) return Int is
     (Int'Max (Limit ("kalpa.min", 20), Int'Min (Limit ("kalpa.max", 1500), Kalpa_Median (V))));

   --  "key=value" token of a session line; "" if missing.  PROOF-LATER: Importance 3/10, Urgency 2/10,
   --  SPARK2 (parsing of the sessions.txt record)
   function Token (L, Key : String) return String is
      P : constant Natural := Fx.Index (L, " " & Key & "=");
   begin
      if P = 0 then return ""; end if;
      declare
         First : constant Positive := P + Key'Length + 2;
         Stop  : constant Natural := Fx.Index (L, " ", First);
      begin
         return L (First .. (if Stop = 0 then L'Last else Stop - 1));
      end;
   end Token;
   function To_Num (T : String) return Int is
     (if T'Length in 1 .. 15 and then (for all C of T => C in '0' .. '9') then Int'Value (T) else -1);

   procedure Parse_Session (L : String; R : out Session_Rec; OK : out Boolean) is
      Sp : constant Natural := Fx.Index (L, " ");
      V  : constant String := Token (L, "votes");
      Pos : Positive := V'First;
      K  : Natural := 0;
   begin
      R := (others => <>);
      OK := L'Length > 2 and then L (L'First) = 'S' and then Sp > 2;
      if not OK then return; end if;
      R.N := Positive (Int'Max (1, To_Num (L (L'First + 1 .. Sp - 1))));
      R.Start := To_Num (Token (L, "start"));
      R.Len := To_Num (Token (L, "len"));
      R.By_Vote := Token (L, "src") = "vote";
      OK := To_Num (L (L'First + 1 .. Sp - 1)) > 0 and then R.Start >= 0 and then R.Len > 0
        and then Token (L, "src") in "vote" | "explicit" and then V'Length > 0;
      while OK and then K < 4 loop
         declare
            Stop : constant Natural := Fx.Index (V, "/", Pos);
            Last : constant Natural := (if Stop = 0 then V'Last else Stop - 1);
         begin
            K := K + 1;
            R.Votes (K) := (if Last >= Pos then To_Num (V (Pos .. Last)) else -1);
            OK := R.Votes (K) >= 0 and then (K = 4 or else Stop > 0);
            Pos := Last + 2;
         end;
      end loop;
   end Parse_Session;

   procedure Load_Sessions is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Mark  : constant String := "# seed ";
      R     : Session_Rec;
      OK    : Boolean;
   begin
      Sessions.Clear;
      if not Ada.Directories.Exists (Sessions_Path) then return; end if;
      Read_Lines (Sessions_Path, Lines, Found);
      for I in 1 .. Natural (Lines.Length) loop
         declare
            L : constant String := Lines (I);
         begin
            if L'Length >= Mark'Length and then L (L'First .. L'First + Mark'Length - 1) = Mark then
               if L /= Mark & Img (Seed) then
                  raise Diary_Error with Msg ("err.session_seed", L (L'First + Mark'Length .. L'Last));
               end if;
            elsif L'Length > 0 and then L (L'First) = 'S' then
               Parse_Session (L, R, OK);
               if OK then Sessions.Append (R); else Warn (Msg ("warn.session_bad", Img (I))); end if;
            elsif L'Length > 0 and then L (L'First) /= '#' then
               Warn (Msg ("warn.session_bad", Img (I)));
            end if;
         end;
      end loop;
   end Load_Sessions;

   --  A stored session must reproduce its votes when the replay reaches its start tick.
   procedure Check_Sessions_At (T : Int) is
   begin
      for R of Sessions loop
         if R.Start = T then
            declare
               V : constant Kalpa_Votes := Votes_At (T);
            begin
               if V /= R.Votes then
                  raise Diary_Error with Msg ("err.session", Img (R.N), Img (R.Start), "votes " & Votes_Text (R.Votes),
                                              "votes " & Votes_Text (V));
               end if;
            end;
         end if;
      end loop;
   end Check_Sessions_At;

   procedure Append_Session (R : Session_Rec) is
      F : TIO.File_Type;
   begin
      if Ada.Directories.Exists (Sessions_Path) and then Ada.Directories.Size (Sessions_Path) > 0 then
         declare
            Needs_Lf : constant Boolean := not Ends_With_Lf (Sessions_Path);
         begin
            TIO.Open (F, TIO.Append_File, Sessions_Path);
            if Needs_Lf then TIO.New_Line (F); end if;
         end;
      else
         TIO.Create (F, TIO.Out_File, Sessions_Path);
         TIO.Put_Line (F, "# seed " & Img (Seed));
         TIO.Put_Line (F, Msg ("hdr.sessions"));
      end if;
      TIO.Put_Line (F, Session_Line (R));
      TIO.Flush (F);
      TIO.Close (F);
      Sessions.Append (R);
   end Append_Session;

   --  After the replay of 1 .. Common: resume the unfinished session, or start one
   --  (explicit length, else the vote).  Sets Ticks and Kalpa_Line.
   procedure Decide_Session is
      Last_Ok : Natural := 0;     --  newest session that starts at or before Common
      V       : constant Kalpa_Votes := Votes_At (Int (Common));
      Next_N  : constant Positive := (if Sessions.Is_Empty then 1 else Sessions.Last_Element.N + 1);
      R       : Session_Rec;
   begin
      for I in 1 .. Natural (Sessions.Length) loop
         if Sessions (I).Start <= Int (Common) then
            Last_Ok := I;
         else
            Warn (Msg ("warn.session_ahead", Img (Sessions (I).N), Img (Sessions (I).Start), Img (Common)));
         end if;
      end loop;
      if Explicit then
         R := (N => Next_N, Start => Int (Common), Len => Int'Max (0, Ticks - Int (Common)), Votes => V, By_Vote => False);
         if R.Len > 0 then Append_Session (R); end if;
         Kalpa_Line := To_Unbounded_String
           ((if R.Len > 0 then Msg ("kalpa.explicit", Img (Next_N), Yuga (Next_N), Img (R.Len), Votes_Text (V))
             else Msg ("kalpa.none", Votes_Text (V))));
      elsif Last_Ok > 0 and then Sessions (Last_Ok).Start + Sessions (Last_Ok).Len > Int (Common) then
         R := Sessions (Last_Ok);   --  an unfinished session (crash, quit): same target as decided
         Ticks := R.Start + R.Len;
         Kalpa_Line := To_Unbounded_String (Msg ("kalpa.resume", Img (R.N), Yuga (R.N), Votes_Text (R.Votes), Img (R.Len), Img (Ticks)));
      else
         R := (N => Next_N, Start => Int (Common), Len => Decided (V), Votes => V, By_Vote => True);
         Ticks := Int (Common) + R.Len;
         Append_Session (R);
         Kalpa_Line := To_Unbounded_String (Msg ("kalpa.vote", Img (Next_N), Yuga (Next_N), Votes_Text (V), Img (R.Len)));
      end if;
   end Decide_Session;
begin
   Load_Data;
   while I <= Ada.Command_Line.Argument_Count loop
      declare
         A   : constant String := Ada.Command_Line.Argument (I);
         Eq  : constant Natural := Fx.Index (A, "=");
         Opt : constant String := (if Eq > 0 then A (A'First .. Eq - 1) else A);
         Num : constant Boolean := Opt in "--ticks" | "--seed" | "--every" | "--crash-at" | "--more";
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
         elsif Opt = "--more" then More := Number (Opt, Val);
         else raise Usage_Error with Msg ("err.option", A);
         end if;
      end;
      I := I + 1;
   end loop;
   Explicit := Ticks >= 0 or else More >= 0;   --  otherwise the entities vote on the session length
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
   Check_Layout;
   Ada.Directories.Create_Path ("diaries");
   for E in Entity_Id loop
      Cur_Name := To_Unbounded_String (Name (E));
      Load_Diary (E, Disk_Seed);
      Common := (if E = 1 then Natural (Disk (E).Length) else Natural'Min (Common, Natural (Disk (E).Length)));
      Longest := Natural'Max (Longest, Natural (Disk (E).Length));
      Append (Names, (if E = 1 then "" else " ") & Name (E) & "(" & Kind (E) & ")");
   end loop;
   Cur_Name := To_Unbounded_String ("-");
   if More >= 0 then Ticks := Int (Common) + More; end if;   --  --more N: N new ticks after the lowest common tick

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

   --  Every run starts from the vocabulary and replays from tick 1.
   Sim_World.Init (Vocab, Seed, Start_Pct);
   for E in Entity_Id loop
      Cur_Name := To_Unbounded_String (Name (E));
      Ada.Directories.Create_Path ("entities/" & Name (E));
      if (for some K in Side_Kind =>
            not Ada.Directories.Exists (Side_Path (E, K)) or else Ada.Directories.Size (Side_Path (E, K)) = 0)
      then
         Ent_Missing := Ent_Missing + 1;
      end if;
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

   Load_Sessions;
   Write_Debug ("RUN", "");   --  stub: a kill -9 still leaves a file

   --  Phase 1: replay what every diary has (verify only), then confirm the import.
   Verify_To := (if Explicit then Natural'Min (Common, Natural (Ticks)) else Common);
   Check_Sessions_At (0);
   for Tick in Int range 1 .. Int (Verify_To) loop
      Do_Tick (Tick);
      Check_Sessions_At (Tick);
      Quit_Seen := Sim_Quit.Requested;
      exit when Quit_Seen;
   end loop;
   if not Quit_Seen then
      declare
         Total : Natural := 0;
      begin
         for E in Entity_Id loop Total := Total + Natural (Disk (E).Length); end loop;
         Import_Done := True;
         Import_Block := To_Unbounded_String (Import_Text (Total));
         TIO.Put_Line (To_String (Import_Block));
      end;
      for E in Entity_Id loop Start_Known (E) := Known_Count (E); end loop;
      Decide_Session;
      TIO.Put_Line (To_String (Kalpa_Line));
   end if;

   --  Phase 2: the rest of the run (ticks beyond the common tick are appended where missing).
   if not Quit_Seen then
      for Tick in Int range Int (Verify_To) + 1 .. Ticks loop
         Do_Tick (Tick);
         if Tick > Int (Common) and then Tick mod Every = 0 then
            TIO.Put_Line (Msg ("progress", Img (Tick), Img (Ticks), Img (Integer (Entity_Id'Last)), Img (Events)));
            Write_Debug ("RUN", "");   --  refresh the stub
         end if;
         Quit_Seen := Sim_Quit.Requested;
         exit when Quit_Seen;
      end loop;
   end if;
   for F of Out_File loop TIO.Close (F); end loop;
   for F of Side_Out loop TIO.Close (F); end loop;
   if Quit_Seen then   --  Ctrl-C / SIGTERM: everything written so far is flushed; a rerun resumes
      TIO.Put_Line (Msg ("quit", Sim_Quit.Which, Img (Last_Done)));
      Write_Petitions;
      Write_Debug ("QUIT", Msg ("debug.quit", Sim_Quit.Which, Img (Last_Done)));
      TIO.Put_Line (Msg ("debug.attach"));
      Ada.Command_Line.Set_Exit_Status (130);
      return;
   end if;

   declare
      Console, Text, Json, Rep, Fails : Unbounded_String;
      D_Files, D_Lines, E_Files, N, Js_Lines : Natural := 0;
      procedure Save (File : String; Content : Unbounded_String) is
         F : TIO.File_Type;
      begin
         TIO.Create (F, TIO.Out_File, File);
         TIO.Put (F, To_String (Content));
         TIO.Flush (F);
         TIO.Close (F);
      end Save;
   begin
      Summarize (Seed, Ticks, Votes_Of, Console, Text, Json);
      Save ("summary.txt", Text);
      Save ("summary.jsonl", Json);
      --  Export check: re-open and count what is on disk now.
      for E in Entity_Id loop
         Check_File (Path (E), Natural'Max (Natural (Disk (E).Length), Natural (Ticks)), 'd', N, Fails);
         D_Files := D_Files + 1;
         D_Lines := D_Lines + N;
         for K in Side_Kind loop
            Check_File (Side_Path (E, K), 0, 's', N, Fails);
            E_Files := E_Files + 1;
         end loop;
      end loop;
      if not Sessions.Is_Empty then Check_File (Sessions_Path, 0, 's', N, Fails); end if;
      Check_File ("summary.txt", 0, 't', N, Fails);
      Check_File ("summary.jsonl", 5, 't', Js_Lines, Fails);
      Rep := To_Unbounded_String (Msg ("report.head", Img (Int'Max (0, Ticks - Int (Common))), Img (Int'Min (Int (Common) + 1, Ticks)),
                                       Img (Ticks), Img (Common), Img (Written), Img (Verified),
                                       Img (Warnings)) & ASCII.LF & Msg ("report.cols") & ASCII.LF);
      for E in Entity_Id loop
         Append (Rep, Fx.Head (Name (E), 10) & Fx.Tail (Img (Start_Known (E)), 8) & " ->" & Fx.Tail (Img (Known_Count (E)), 6)
                 & Fx.Tail (Img (Run_Learn (E)), 9) & Fx.Tail (Img (Run_Coin (E)), 7) & Fx.Tail (Img (Run_Bench_N (E)), 6)
                 & " | " & Fx.Tail (Sgn (Int (St (E).Mood)), 5) & Fx.Tail (Img (St (E).Energy), 7)
                 & Fx.Tail (Img (Petitions_Of (E)), 5) & ASCII.LF);
      end loop;
      Append (Rep, Msg ("report.mixcols") & ASCII.LF);
      for E in Entity_Id loop
         Append (Rep, Fx.Head (Name (E), 10));
         for A in Action loop Append (Rep, Fx.Tail (Img (Act_Count (E, A)), (if A in Explore | Propose then 8 else 7))); end loop;
         Append (Rep, ASCII.LF);
      end loop;
      declare
         Per : Unbounded_String;
      begin
         for E in Entity_Id loop
            Append (Per, (if E = 1 then "" else " ") & Name (E) & " " & Img (Petitions_Of (E)));
         end loop;
         Append (Rep, Msg ("report.pet", Img (Petition_Total), To_String (Per), Top_Topics (3)) & ASCII.LF);
      end;
      if Length (Fails) = 0 then
         Export_Line := To_Unbounded_String
           (Msg ("report.export", Img (D_Files), Img (D_Lines), Img (E_Files),
                 Img (Int (Ada.Directories.Size ("summary.txt"))), Img (Int (Ada.Directories.Size ("summary.jsonl")))));
      else
         Export_Line := To_Unbounded_String (Msg ("export.failed", To_String (Fails)));
         Ada.Command_Line.Set_Exit_Status (1);
      end if;
      Append (Rep, Export_Line & ASCII.LF);
      declare   --  the last two lines of the vote table: favourite, disagreement
         C : constant String := To_String (Console);
         Cut : Natural := 0;
         Seen : Natural := 0;
      begin
         for I in reverse C'Range loop
            if C (I) = ASCII.LF then
               Seen := Seen + 1;
               if Seen = 3 then Cut := I + 1; exit; end if;
            end if;
         end loop;
         if Cut > 0 then
            Vote_Line := To_Unbounded_String (C (Cut .. C'Last - 1));
            for I in 1 .. Length (Vote_Line) loop
               if Element (Vote_Line, I) = ASCII.LF then Replace_Element (Vote_Line, I, '|'); end if;
            end loop;
         end if;
      end;
      Save ("run_report.txt", Import_Block & ASCII.LF & Kalpa_Line & ASCII.LF & Rep & Console);
      if not Ada.Directories.Exists ("run_report.txt") or else Ada.Directories.Size ("run_report.txt") = 0 then
         Append (Rep, Msg ("export.failed", "run_report.txt not written") & ASCII.LF);
         Ada.Command_Line.Set_Exit_Status (1);
      end if;
      Write_Petitions;
      Write_Debug ((if Length (Fails) = 0 then "OK" else "DRIFT"), (if Length (Fails) = 0 then "" else "error: " & To_String (Export_Line)));
      TIO.Put (To_String (Rep));
      TIO.Put (To_String (Console));
      TIO.Put_Line (Msg ("debug.attach"));
      TIO.Put_Line (Msg ("pet.file", Img (Integer'Min (Petition_Total, Integer (Limit ("propose.file_cap", 40)))),
                         Img (Petition_Total), Ada.Directories.Full_Name ("petitions.txt")));
      TIO.Put_Line (Msg ("pet.attach"));
   end;
exception
   when E : Usage_Error =>
      TIO.Put_Line (TIO.Standard_Error, Ada.Exceptions.Exception_Message (E));
      Write_Debug ("USAGE", "error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (2);
   when E : Diary_Error =>   --  drift, bad diary, seed mismatch: a validation stop
      if not Import_Done then TIO.Put_Line (Msg ("import.failed", Ada.Exceptions.Exception_Message (E))); end if;
      if Import_Done then Write_Petitions; end if;
      Write_Debug ("DRIFT", Error_Brief (E));
      Report (E);
      Ada.Command_Line.Set_Exit_Status (1);
   when E : others =>
      if not Import_Done then TIO.Put_Line (Msg ("import.failed", Ada.Exceptions.Exception_Message (E))); end if;
      if Import_Done then Write_Petitions; end if;
      Write_Debug ("CRASH", Error_Brief (E));
      Report (E);
      Ada.Command_Line.Set_Exit_Status (1);
end Diary_Sim;
