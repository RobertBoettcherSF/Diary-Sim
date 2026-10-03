--  Version: 0.023
--  diary_sim v1: four independent entities, one diary line per tick each.
--  Every random choice is hash (seed, entity, tick, salt): no RNG stream, so
--  any tick can be recomputed alone.  Diaries are append-only JSONL.  Every run
--  replays ticks 1 .. N from scratch (words, lessons and coined words cannot be
--  read back from a diary line): a tick already on disk is compared with the
--  regenerated line instead of written, a tick beyond the disk is appended.
--  Session length: without --ticks / --more the four entities vote (Kalpas, data/kalpas.txt)
--  and the median is the number of new ticks; diaries/sessions.txt records every session
--  and is verified on import (see README).
--  Menu and words: only --menu (make menu) and the bare program on a terminal show the main menu (Sim_Menu); make run auto-loads
--  (header Save folder / Found N sessions). At the end of every session each wesen names a favourite word (Sim_World.Favourite,
--  its own hash salt, so old diaries stay valid), recorded as a W line in diaries/sessions.txt.
--  Buddhism layer and players (Sim_Dharma, record-first): karma, reincarnation values, unrest, the
--  commitment ladder, awareness and the in-sim players' inbox are replayed like everything else and
--  recorded as D / C / Y lines in diaries/sessions.txt, diaries/inbox.txt and diaries/says.txt (what
--  Robert said); a replay that differs is DRIFT.  They never change the action table or the old dice.
--  Where it saves: everything (diaries/, entities/, debug.txt, reports) lives in ONE save folder:
--  --home DIR, else $DIARY_HOME, else ../diary-data next to the source folder, so the source
--  folder can be deleted and replaced after every build (see README).
--  entities/<id>/words.txt and bench.txt are append-only working files (NOT a VM):
--  a line the replay produces and the file lacks is appended, so they can be
--  rebuilt from nothing.  Bench hook for later: see README (PROOF-LATER).
--  Ctrl-C and SIGTERM are caught (Sim_Quit); the runtime reserves them unless released here.
pragma Interrupt_State (SIGINT, USER);
pragma Interrupt_State (SIGTERM, USER);
pragma Ada_2022;

with Ada.Characters.Handling, Ada.Command_Line, Ada.Containers.Indefinite_Hashed_Sets, Ada.Containers.Vectors, Ada.Directories, Ada.Environment_Variables,
     Ada.Exceptions, Ada.Strings.Fixed, Ada.Strings.Hash, Ada.Strings.Unbounded, Ada.Text_IO,
     GNAT.Traceback.Symbolic, Sim_Dharma, Sim_Ledger, Sim_Chess, Sim_Games, Sim_Menu, Sim_Quit, Sim_Screen, Sim_Store, Sim_Things, Sim_Util, Sim_World;
use Ada.Strings.Unbounded, Sim_Util, Sim_World;

procedure Diary_Sim is
   package TIO renames Ada.Text_IO;
   package Fx renames Ada.Strings.Fixed;
   use type Ada.Directories.File_Size;

   --  Everything printed for people goes through Con: internal ids become display names (data/names.txt).
   --  Files that are replay-verified or hashed (diaries, sessions.txt, inbox.txt, world.txt) never do.
   package Con is
      procedure Put_Line (S : String);
      procedure Put (S : String);
   end Con;
   package body Con is
      procedure Put_Line (S : String) is begin TIO.Put_Line (Sim_World.Show (S)); end Put_Line;
      procedure Put (S : String) is begin TIO.Put (Sim_World.Show (S)); end Put;
   end Con;

   type State is record
      Energy, Mood, Location : Integer;   --  ranges: data/limits.txt; location: office lab cafe home
   end record;
   --  Rest Work Explore Talk Wander Bench Propose Learn.  Propose and Learn keep the location (Home -1).
   Energy_D : constant array (Action) of Integer := [14, -8, -10, -2, -3, -4, -1, -1];
   Mood_D   : constant array (Action) of Integer := [1, -4, 3, 2, -1, -1, 2, 1];
   Home     : constant array (Action) of Integer := [3, 0, 1, 2, 0, 1, -1, -1];   --  wander: rolled

   Build : constant String := "0.023";   --  = the Version header of this file (make version-check)
   Usage_Error, Diary_Error : exception;
   Drift_Error : exception;   --  stored lines or sessions differ from the replay: expected, no traceback
   Seed, Ticks, Every, Seed_Opt, Crash_At, More : Int := -1;   --  More: --more N = N new ticks on top of the disk
   Fresh, Seed_Shown : Boolean := False;
   Src_Root : constant String := Project_Root;   --  the source folder, fixed before any cd
   Home_Opt, Home_Path : Unbounded_String;      --  --home DIR / the save folder in use
   Session_N : Natural := 0;                    --  this run's session number (sessions.txt)
   Snap_Mood, Snap_Energy : array (Entity_Id) of Integer := [others => 0];   --  state at the session start
   Snap_Pet : array (Entity_Id) of Natural := [others => 0];
   Snap_Votes : All_Stats;
   Since_Head, Saved_Line, Words_Text : Unbounded_String;   --  for debug.txt; Words_Text: the word vote line
   Preview : Boolean := False;         --  --preview: simulate in memory, write nothing, show excerpts
   Sample : array (Entity_Id) of Str_Vectors.Vector;   --  preview: every diary line
   Yes : Boolean := False;             --  --yes: no question when there is no previous diary
   Menu_Wanted : Boolean := False;
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
   Did_Learn, Did_Coin, Did_Bench, Did_Teach : Boolean := False;   --  what the last Step did
   Pre_Energy_G : Integer := 0;   --  energy before the last Step's action
   Inbox_Bad : Boolean := False;   --  inbox.txt differs from the replay: it is left as it is
   Debug_On : Boolean := False;                            --  --debug: write debug_digest.txt (make run DEBUG=1)
   Section_Opt : Unbounded_String;                         --  --debug-section NAME
   Menu_Opt : Boolean := False;                            --  --menu: show the main menu (make menu)
   Say_Mode, Answer_Mode, Inbox_Mode : Boolean := False;   --  --say / --answer / --inbox
   Say_To, Say_Text, Say_By, Grant_Opt : Unbounded_String;
   Grant_Mode : Boolean := False;   --  --grant P<n>
   Act_Count : array (Entity_Id, Action) of Natural := [others => [others => 0]];   --  all ticks replayed
   Last_Act : Action := Rest;
   Votes_Of : All_Stats;
   --  The treadmill world (Sim_Things): on in sessions that carry world=1; Last_Verb is the last Step's verb
   --  (the base action, or Examine / Push / Eat / Greet); Verb_Count counts the verbs of all ticks replayed.
   World_Active : Boolean := False;
   Last_Verb : List_Id := Rest;
   Verb_Count : array (Entity_Id, World_Verb) of Natural := [others => [others => 0]];

   --  ---- rest and cool-down (rest=1 sessions): a recovery rate per wesen, a trade-off for rests, a refractory
   --  period after a work burst (data/limits.txt rest.*).  All of it is a function of the replayed actions. ------
   Rest_Active, Grant_Active : Boolean := False;
   --  screen=1 sessions (Sim_Screen): record lines of every screen change go to diaries/screens.txt (Sim_Store), replay-verified.
   Screen_Active : Boolean := False;
   Screens_Path : constant String := "diaries/screens.txt";
   Screen_Store : Sim_Store.Store;
   Screen_N : Natural := 0;                      --  the key number of the next K line
   Scr_Lines : Str_Vectors.Vector;               --  record lines of the last Step (text without key and tick)
   --  chess=1 sessions (Sim_Games, Sim_Chess): games of the wesen and the players, Elo; records C lines in diaries/chess.txt.
   Chess_Active : Boolean := False;
   Chess_Path : constant String := "diaries/chess.txt";
   Chess_Store : Sim_Store.Store;
   Chess_N : Natural := 0;
   Chess_Lines : Str_Vectors.Vector;
   Elo_View, Perft_Mode : Boolean := False;      --  --elo (replay, then the ranking) / --perft (the move generator checks)
   Screens_View : Boolean := False;              --  --screens: replay, then show the screens (a view like --ledger)
   Rate_Pct, Load, Hist, Cool, Streak, Since_Work, Cool_N, Cut_N, Quick_N : array (Entity_Id) of Natural := [others => 0];
   function RL (Key : String; Default : Integer) return Integer is (Integer (Limit (Key, Int (Default))));
   function Cool_Len (E : Entity_Id) return Positive is
     (Positive'Max (1, RL ("rest.cool", 16) * 100 / Natural'Max (1, Rate_Pct (E))));   --  slow recoverers cool longer
   function Work_Keep (E : Entity_Id) return Natural is   --  percent of the work / bench weights kept
     (if Rest_Active and then Cool (E) > 0 then Natural (Integer'Max (1, RL ("rest.cool.work_pct", 35))) else 100);
   --  0 .. 100: how long this wesen's cool-down is (a long one petitions more often)
   function Rest_Strain (E : Entity_Id) return Natural is
     (if Rest_Active then Natural'Min (100, Cool_Len (E) * 100 / Positive'Max (1, RL ("rest.petition_ref", 30)) + (if Cool (E) > 0 then 20 else 0))
      else 0);

   --  The energy and mood change of a rest: personal rate, quick / calm, diminishing returns.
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (integer percent arithmetic)
   Ledger_Mode, Ledger_Full : Boolean := False;   --  --ledger[=full]: replay, then print the mood ledger (report only)
   Ledger_From : Int := 0;   --  the last session starts after this tick (the ledger's second scope)
   Last_Phase : Integer := 0;   --  the last rest: -1 quick, +1 calm, 0 between (for the ledger)
   procedure Rest_Effect (E : Entity_Id; En, Mo : in out Integer) is
      Phase : Integer := 100;
   begin
      Last_Phase := 0;
      if Since_Work (E) < Natural (RL ("rest.quick", 3)) then
         Phase := RL ("rest.quick.energy_pct", 60);
         Mo := Mo + RL ("rest.quick.mood", -1);
         Last_Phase := -1;
         Quick_N (E) := Quick_N (E) + 1;
      elsif Since_Work (E) >= Natural (RL ("rest.calm", 8)) then
         Phase := RL ("rest.calm.energy_pct", 120);
         Mo := Mo + RL ("rest.calm.mood", 2);
         Last_Phase := 1;
      end if;
      En := En * Integer (Rate_Pct (E)) * Phase / 10_000;
      for K in 1 .. Natural'Min (Streak (E), 12) loop En := En * RL ("rest.repeat_pct", 80) / 100; end loop;
   end Rest_Effect;

   --  After the action: work load, cool-down, rest streaks.
   procedure Rest_After (E : Entity_Id; A : Action; Mood : Integer) is
      Started : Boolean := False;
   begin
      if A in Work | Bench then
         if Streak (E) in 1 .. RL ("rest.min_ticks", 2) - 1 then Cut_N (E) := Cut_N (E) + 1; end if;
         Streak (E) := 0;
         Since_Work (E) := 0;
      else
         Since_Work (E) := Natural'Min (1000, Since_Work (E) + 1);
         Streak (E) := (if A = Rest then Streak (E) + 1 else 0);
      end if;
      --  the work load: work or bench ticks among the last rest.window ticks (a bit history)
      Hist (E) := (Hist (E) * 2 + (if A in Work | Bench then 1 else 0)) mod 2 ** Natural'Min (28, Natural'Max (1, RL ("rest.window", 12)));
      Load (E) := 0;
      for I in 0 .. 27 loop
         if (Hist (E) / 2 ** I) mod 2 = 1 then Load (E) := Load (E) + 1; end if;
      end loop;
      if Cool (E) = 0 and then Load (E) >= Natural (RL ("rest.burst", 5)) then   --  a work burst: cool down
         Cool (E) := Cool_Len (E);
         Hist (E) := 0;
         Load (E) := 0;
         Cool_N (E) := Cool_N (E) + 1;
         Started := True;
      end if;
      if Cool (E) > 0 and then not Started then
         Cool (E) := Natural'Max (0, Cool (E) - (if Mood >= RL ("rest.cool.good_mood", 40) then 2 else 1));
      end if;
   end Rest_After;

   function Rest_Text (E : Entity_Id) return String is
     (Msg ("rest.line", Name (E), Img (Rate_Pct (E)), Img (Cool_Len (E)), Img (Cool_N (E)), Img (Cut_N (E)), Img (Quick_N (E))));

   procedure Rest_Begin (Seed : Int) is   --  the first rest=1 session: fresh counters (later sessions continue them)
   begin
      for E in Entity_Id loop
         Rate_Pct (E) := Recovery_Rate (Seed, E);
         Load (E) := 0;
         Hist (E) := 0;
         Cool (E) := 0;
         Streak (E) := 0;
         Since_Work (E) := 1000;
         Cool_N (E) := 0;
         Cut_N (E) := 0;
         Quick_N (E) := 0;
      end loop;
   end Rest_Begin;

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
                when Mood_Low => "feeling low", when Mood_Neutral => "feeling steady", when Mood_High => "feeling good",
                when Examine => "looked closely at something", when Push => "pushed something", when Eat => "tasted something",
                when Greet => "said hello");

   procedure Say (Line : String) is   --  console output, held back until the seed line is out
   begin
      if Seed_Shown then Con.Put_Line (Line); else Append (Pending, Line & ASCII.LF); end if;
   end Say;

   procedure Warn (Line : String) is
   begin
      Warnings := Warnings + 1;
      Say (Line);
   end Warn;

   --  The rule limits of data/limits.txt (read again after the Settings menu).
   procedure Read_Limits is
   begin
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
   end Read_Limits;

   procedure Load_Data is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Sec   : Integer := -1;
   begin
      Read_Lines (Data_Path ("messages.txt"), Lines, Found);
      if not Found then Warn ("warning: data/messages.txt not found; messages show their keys"); end if;
      Read_Lines (Data_Path ("limits.txt"), Lines, Found);
      if not Found then Warn (Msg ("warn.limits_file")); end if;
      Read_Lines (Data_Path ("menu.txt"), Lines, Found);   --  menu text: keys only, a missing file shows the keys
      for F of Str_Vectors.Vector'(["karma.txt", "dharma.txt", "players.txt", "things.txt", "ledger.txt", "screens.txt", "chess.txt"]) loop   --  the Buddhism layer: numbers, wording, players
         Read_Lines (Data_Path (F), Lines, Found);
         if not Found then Warn (Msg ("warn.dharma_file", F)); end if;
      end loop;
      Load_Keys (Lines);
      Read_Limits;
      Lines.Clear;
      Read_Lines (Data_Path ("names.txt"), Lines, Found);
      if not Found then Warn (Msg ("warn.names_file")); end if;
      Load_Names (Lines);
      Lines.Clear;
      Read_Lines (Data_Path ("things.txt"), Lines, Found);
      Sim_Things.Load (Lines);
      if not Sim_Things.Loaded then Warn (Msg ("warn.things_file")); end if;
      Lines.Clear;
      Read_Lines (Data_Path ("fonts.txt"), Lines, Found);
      Sim_Menu.Load_Font (Lines);
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
      if Preview then return; end if;
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
        (if Pending_Word (E) /= 0 then Learn else Choose (Seed, E, Tick, St (E).Energy, St (E).Mood, Work_Keep (E)));
      Pre_En : constant Integer := St (E).Energy;     --  state before this action
      Pre_Mo : constant Integer := St (E).Mood;
      S   : State renames St (E);
      Detail, Learned : Unbounded_String;
      Eid : constant Positive := Positive (E);
      World_Mode : constant Boolean := World_Active;
      Verb : List_Id := A;
      Eff_En : Integer := Energy_D (A);   --  a rest=1 rest changes these (Rest_Effect)
      Eff_Mo : Integer := Mood_D (A);
      --  the mood ledger (report only, Sim_Ledger): where this tick's mood change came from
      Was_Cool : constant Boolean := Rest_Active and then Cool (E) > 0;
      Led_Phase, Push_Nom : Integer := 0;
      Push_Feel : Integer := -1;
      Chess_Fx, Chess_Nom : Integer := 0;   --  mood of finished chess games, taken at this step
      M_Base, M_After_Base : Integer;

      procedure Add (Text : String) is
      begin
         Append (Detail, (if Length (Detail) > 0 then "; " else "") & Text);
      end Add;

      --  ---- the treadmill world (world=1 sessions): things are met, named and learned ----------
      procedure Meet (W : Positive) is
      begin
         if not Knows (E, W) then
            Learn_From_World (E, W);
            Ensure (E, Words_File, Words_Line (W, "world", Tick, Meaning_Of (W)));
            Append (Learned, (if Length (Learned) > 0 then ", " else "") & Word (W));
         end if;
      end Meet;

      procedure Report_New is
      begin
         if Length (Learned) > 0 then Add (Msg ("detail.new", To_String (Learned))); end if;
      end Report_New;

      --  A thing within reach (own cell, 4 neighbours) by dice; Found False when there is none.
      procedure Pick_Thing (It : out Sim_Things.Reach_Item; Found : out Boolean) is
         R : constant Sim_Things.Reach_Vectors.Vector := Sim_Things.Reach (E);
      begin
         Found := not R.Is_Empty;
         It := (if Found then R (Roll (Seed, Eid, Tick, 6302, Natural (R.Length))) else (others => <>));
      end Pick_Thing;

      Dir_X : constant array (0 .. 3) of Integer := [0, 1, 0, -1];
      Dir_Y : constant array (0 .. 3) of Integer := [-1, 0, 1, 0];

      procedure Do_Examine is
         It : Sim_Things.Reach_Item;
         Found : Boolean;
      begin
         Pick_Thing (It, Found);
         if not Found then Add (Msg ("detail.nothing")); return; end if;
         Meet (Sim_Things.Name_Word (It.T));
         if Screen_Active then Sim_Screen.Note (E, Sim_Things.Name_Word (It.T), "thing"); end if;
         Meet (Sim_Things.Prop_Word (Sim_Things.Quality_Text (It.T), "quality"));
         Add (Msg ("detail.examine", Sim_Things.Description (It.T), Sim_Things.Name_Text (It.T)));
         Report_New;
      end Do_Examine;

      procedure Do_Push is
         It : Sim_Things.Reach_Item;
         Found : Boolean;
      begin
         Pick_Thing (It, Found);
         if not Found then Add (Msg ("detail.nothing")); return; end if;
         Meet (Sim_Things.Prop_Word (Sim_Things.Feel_Text (It.T), "feel"));
         Push_Feel := Sim_Things.Feel_Class (It.T);
         Push_Nom := Integer (Limit ("world.push.mood." & Img (Push_Feel), 0));
         S.Mood := Clamp (S.Mood + Push_Nom, M_Min, M_Max);
         declare
            D : constant Natural := Sim_Things.Facing (E, Tick);
         begin
            Sim_Things.Edit (Tick, Sim_Things.Gone, It.T, It.X, It.Y, Name (E));
            Sim_Things.Edit (Tick, Sim_Things.Add, It.T, It.X + Dir_X (D), It.Y + Dir_Y (D), Name (E));
         end;
         Add (Msg ("detail.push", Sim_Things.Description (It.T), Sim_Things.Feel_Text (It.T)));
         Report_New;
      end Do_Push;

      procedure Do_Eat is
         It : Sim_Things.Reach_Item;
         Found : Boolean;
      begin
         Pick_Thing (It, Found);
         if not Found then Add (Msg ("detail.noeat")); return; end if;
         Meet (Sim_Things.Prop_Word (Sim_Things.Taste_Text (It.T), "taste"));
         S.Energy := Clamp (S.Energy + Integer (Limit ("world.eat.energy." & Img (Sim_Things.Taste_Class (It.T)), 0)), E_Min, E_Max);
         Sim_Things.Edit (Tick, Sim_Things.Gone, It.T, It.X, It.Y, Name (E));
         Add (Msg ("detail.eat", Sim_Things.Description (It.T), Sim_Things.Taste_Text (It.T)));
         Report_New;
      end Do_Eat;

      procedure Do_Greet is
         Hello : constant Positive := Sim_Things.Prop_Word (Sim_Things.Social_Text (E, Tick), "social");
         Adj : Natural := 0;
         K : Integer := 0;
         Who : Entity_Id := E;
         It : Sim_Things.Reach_Item;
         Found : Boolean;
      begin
         Meet (Hello);
         for O in Entity_Id loop
            if O /= E and then Sim_Things.Adjacent (E, O) then Adj := Adj + 1; end if;
         end loop;
         if Adj > 0 then
            K := Roll (Seed, Eid, Tick, 7810, Adj);
            for O in Entity_Id loop
               if O /= E and then Sim_Things.Adjacent (E, O) then
                  K := K - 1;
                  if K = 0 then Who := O; end if;
               end if;
            end loop;
            Add (Msg ("detail.greet.wesen", Name (Who), Word (Hello)));
         else
            Pick_Thing (It, Found);
            Add (if Found then Msg ("detail.greet.thing", Sim_Things.Description (It.T), Word (Hello))
                 else Msg ("detail.greet.air", Word (Hello)));
         end if;
         Report_New;
      end Do_Greet;

      --  Which verb refines the base action (world sessions): examine / push / eat / greet, weighted by
      --  the personality (Rule 30 core) and the energy / mood leans.  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2
      function Choose_Verb return List_Id is
         Core : constant Natural := Core_Percent (Seed, E);
      begin
         if A not in Rest | Explore | Talk | Wander
           or else Int (Roll (Seed, Eid, Tick, 6300, 100)) > Limit ("world.verb." & Low (A), 0)
         then
            return A;
         end if;
         case A is
            when Talk => return Greet;
            when Rest => return Eat;
            when others =>
               declare
                  We : constant Positive := 50 + Core / 2;
                  Wp : constant Positive := 30 + (100 - Core) / 2 + (if S.Mood > 0 then 10 else 0);
                  Wa : constant Natural := (if A = Wander then 10 + Integer'Max (0, E_Max - S.Energy) / 2 else 0);
                  R : constant Positive := Roll (Seed, Eid, Tick, 6301, We + Wp + Wa);
               begin
                  return (if R <= We then Examine elsif R <= We + Wp then Push else Eat);
               end;
         end case;
      end Choose_Verb;

      --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (pick indices stay inside 1 .. count)
      --  In a world session the pupil is a wesen on the same or a neighbouring cell (none: no lesson) and the
      --  word may drift into a dialect variant on its way (Sim_Things.Mutate).
      procedure Teach is
         P : Entity_Id := Entity_Id ((Integer (E) - 1 + Roll (Seed, Eid, Tick, 3, 3)) mod 4 + 1);
         Adj : Natural := 0;
      begin
         if World_Mode then
            for O in Entity_Id loop
               if O /= E and then Sim_Things.Adjacent (E, O) then Adj := Adj + 1; end if;
            end loop;
            if Adj = 0 then return; end if;
            declare
               K : Integer := Roll (Seed, Eid, Tick, 3, Adj);
            begin
               for O in Entity_Id loop
                  if O /= E and then Sim_Things.Adjacent (E, O) then
                     K := K - 1;
                     if K = 0 then P := O; end if;
                  end if;
               end loop;
            end;
         end if;
         if Int (Roll (Seed, Eid, Tick, 2, 100)) <= Teach_Pct and then Pending_Word (P) = 0 and then Teachable_Count (E, P) > 0 then
            declare
               N : constant Natural := Teachable_Count (E, P);
               W0 : constant Positive := Nth_Teachable (E, P, Roll (Seed, Eid, Tick, 4, N));
               W : constant Positive := (if World_Mode then Sim_Things.Mutate (W0, E, Tick) else W0);
            begin
               Pending_Word (P) := W;
               Pending_From (P) := E;
               Did_Teach := True;
               Use_Word (E, W0);   --  the teacher mentions it too
               Add (Msg ("detail.taught", Name (P), Word (W)));
            end;
         end if;
      end Teach;

      procedure Coin is
         K : constant Natural := Known_Count (E);
      begin
         if Int (Roll (Seed, Eid, Tick, 5, 100)) <= Coin_Pct and then K >= 2
           and then Int (Coined_Total) < Coin_Cap
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
                     W : constant Positive := Add_Coined (Text, Pa, Pb, E);
                  begin
                     Use_Word (E, Pa);
                     Use_Word (E, Pb);
                     Learn_Word (E, W);
                     if Screen_Active then Sim_Screen.Note (E, W, "coined"); end if;
                     Ensure (E, Words_File, Words_Line (W, "coined", Tick, Parents (W)));
                     Add (Msg ("detail.coined", Text, Word (Pa), Word (Pb)));
                     Did_Coin := True;
                  end;
               end if;
            end;
         end if;
      end Coin;

   begin
      Last_Act := A;
      Pre_Energy_G := Pre_En;
      Did_Teach := False;
      Did_Learn := False;
      Did_Coin := False;
      Did_Bench := False;
      if World_Mode and then (not Sim_Things.Placed (E) or else Sim_Things.Region_Of (E) /= S.Location) then
         Sim_Things.Place (E, Tick, Clamp (S.Location, 0, 3));   --  first step in the world, or reborn elsewhere
      end if;
      if Rest_Active and then A = Rest then Rest_Effect (E, Eff_En, Eff_Mo); Led_Phase := Last_Phase; end if;
      M_Base := Clamp (Pre_Mo + Mood_D (A), M_Min, M_Max) - Pre_Mo;   --  ledger: the action's own part, after the bounds
      S.Energy := Clamp (S.Energy + Eff_En, E_Min, E_Max);
      S.Mood := Clamp (S.Mood + Eff_Mo, M_Min, M_Max);
      M_After_Base := S.Mood;
      if World_Mode then   --  one step on the grid; the place is the nearest landmark region
         if A in Explore | Wander then
            Sim_Things.Walk (E, Tick, False);
         elsif A = Talk and then not (for some O in Entity_Id => O /= E and then Sim_Things.Adjacent (E, O)) then
            Sim_Things.Walk (E, Tick, True);   --  towards the nearest wesen
         end if;
         S.Location := Sim_Things.Region_Of (E);
         Verb := Choose_Verb;
         case Verb is
            when Examine => Do_Examine;
            when Push => Do_Push;
            when Eat => Do_Eat;
            when Greet => Do_Greet;
            when others => null;
         end case;
      else
         if A = Wander then
            S.Location := Roll (Seed, Eid, Tick, 1, 4) - 1;
         elsif Home (A) >= 0 then
            S.Location := Home (A);
         end if;
      end if;
      Last_Verb := Verb;
      S.Location := Clamp (S.Location, 0, L_Max);
      case A is
         when Talk => Teach;
         when Explore | Wander => Coin;
         when Learn =>
            declare
               W : constant Positive := Pending_Word (E);
            begin
               Learn_Word (E, W, Natural (Pending_From (E)));
               Ensure (E, Words_File, Words_Line (W, "taught", Tick, Name (Pending_From (E))));
               Add (Msg ("detail.learned", Word (W), Name (Pending_From (E))));
               Pending_Word (E) := 0;
               Did_Learn := True;
               if Screen_Active then Sim_Screen.Note (E, W, "taught"); end if;
            end;
         when Bench =>
            declare
               R : constant Bench_Result := Run_Bench (Seed, E, Tick, Bench_Steps);
            begin
               Ensure (E, Bench_File, Img (Tick) & " " & Low_Kernel (R.Which) & " " & Img (R.Steps) & " "
                       & Img (R.Result) & " " & Img (R.Checksum));
               Add (Msg ("detail.bench", Low_Kernel (R.Which), Img (R.Steps), Img (R.Result), Img (R.Checksum)));
               Did_Bench := True;
            end;
         when Propose =>
            declare
               N : constant Positive := File_Petition (Seed, E, Tick, Pre_En, Pre_Mo, Act_Count (E, Bench), Rest_Strain (E));
            begin
               Add (Msg ("detail.petition", Img (N), Petition_Topic (N)));
            end;
         when others => null;
      end case;
      if Rest_Active then Rest_After (E, A, S.Mood); end if;
      if Chess_Active and then World_Mode then   --  chess: a rest beside someone may be a move; a finished game brings mood
         declare
            Moods : Sim_Games.Mood_Array;
            Played : Boolean;
            Partner : Sim_Games.Comp_Id;
            Mv, Num : Unbounded_String;
            Want : constant Integer := Sim_Games.Take_Mood (E);
            Got : constant Integer := Clamp (S.Mood + Want, M_Min, M_Max) - S.Mood;
         begin
            for X in Entity_Id loop Moods (X) := St (X).Mood; end loop;
            if A = Rest then
               Sim_Games.Turn (E, Tick, Moods, Chess_Lines, Played, Partner, Mv, Num, Detail);
               if Played then
                  S.Energy := Clamp (S.Energy + RL ("chess.energy", 1), E_Min, E_Max);
                  for Who in Entity_Id loop   --  playing is restful: the cool-down and the work load of both players shrink
                     if Rest_Active and then (Who = E or else Sim_Games.As_Comp (Who) = Partner) then
                        Cool (Who) := Cool (Who) - Natural'Min (Cool (Who), Natural (Integer'Max (0, RL ("chess.cool_cut", 3))));
                        Hist (Who) := Hist (Who) / 2 ** Natural (Integer'Max (0, Integer'Min (20, RL ("chess.hist_shift", 2))));
                     end if;
                  end loop;
                  for T of Str_Vectors.Vector'([To_String (Mv), To_String (Num)]) loop   --  the move and its numeric string are words
                     declare
                        W : constant Positive := Sim_Things.Prop_Word (T, Msg ("chess.word"));
                     begin
                        Meet (W);
                        if Sim_Games.Is_Wesen (Partner) and then not Knows (Entity_Id (Partner), W) then
                           Learn_From_World (Entity_Id (Partner), W);
                           Ensure (Entity_Id (Partner), Words_File, Words_Line (W, "world", Tick, Meaning_Of (W)));
                        end if;
                        if Screen_Active then Sim_Screen.Note (E, W, "chess"); end if;
                     end;
                  end loop;
               end if;
            end if;
            S.Mood := S.Mood + Got;
            Chess_Fx := Got;
            Chess_Nom := Want;
         end;
      end if;
      if Screen_Active and then World_Mode then   --  the screen: pin, drop, show, read, leave, blend (no effect on mood)
         declare
            Learned_Now : Sim_Screen.Learn_Vectors.Vector;
            Said : Unbounded_String;
         begin
            Sim_Screen.Step (E, Tick, Scr_Lines, Learned_Now, Said);
            for X of Learned_Now loop
               Ensure (X.Who, Words_File, (if X.Coined then Words_Line (X.W, "coined", Tick, Parents (X.W))
                                           else Words_Line (X.W, "screen", Tick, Name (Entity_Id (X.From)))));
            end loop;
            if Length (Said) > 0 then Add (To_String (Said)); end if;
         end;
      end if;
      Sim_Ledger.Add (E, Tick, A, Verb, S.Location, M_Base, M_After_Base - Pre_Mo - M_Base, S.Mood - M_After_Base - Chess_Fx,
                      Eff_Mo + Push_Nom + Chess_Nom, Led_Phase, Was_Cool, Push_Feel, Chess_Fx);
      declare
         Tone : constant List_Id := (if S.Mood <= Tone_Low then Mood_Low elsif S.Mood >= Tone_High then Mood_High
                                     else Mood_Neutral);
         Text : constant String := Words (Verb) (Words (Verb).First_Index + Pick60 (Seed, Eid, Tick, 10) mod Natural (Words (Verb).Length))
           & ", " & Words (Tone) (Words (Tone).First_Index + Pick60 (Seed, Eid, Tick, 100) mod Natural (Words (Tone).Length))
           & (if Length (Detail) > 0 then "; " & To_String (Detail) else "");
      begin
         return "{""v"":1,""seed"":" & Img (Seed) & ",""tick"":" & Img (Tick) & ",""ts"":""" & Stamp
           & """,""t"":""" & Low (Verb) & """,""text"":""" & Esc (Text)
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
      if not Preview then
         TIO.Create (F, TIO.Out_File, "last_error.txt");
         TIO.Put (F, Text & Msg ("err.raw") & ASCII.LF & Raw);
         TIO.Close (F);
      end if;
      for I in Text'Range loop
         if Text (I) = ASCII.LF then
            Count := Count + 1;
            if Count <= 11 then Con.Put_Line (Text (From .. I - 1)); end if;
            From := I + 1;
         end if;
      end loop;
      if Count > 11 then Con.Put_Line (Msg ("err.more", Img (Count - 11))); end if;
      Con.Put_Line (Msg ("crash.paste"));
      Con.Put_Line (Msg ("crash.backup"));
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

   --  True when diaries/ holds at least one *.jsonl (a missing or empty folder: no previous diary).
   function Has_Diaries return Boolean is
      use Ada.Directories;
      S : Search_Type;
      Res : Boolean := False;
   begin
      if Exists ("diaries") and then Kind ("diaries") = Directory then
         Start_Search (S, "diaries", "*.jsonl");
         Res := More_Entries (S);
         End_Search (S);
      end if;
      return Res;
   end Has_Diaries;

   --  No previous diary and no --fresh / --yes: ask on a terminal.  True = go on.  Nothing is
   --  written before the answer (no diaries/, no debug.txt), and nothing for an N.
   function Ask_Yes (Prompt : String) return Boolean is
   begin
      Con.Put (Prompt & " ");
      TIO.Flush;
      declare
         Answer : constant String :=
           Ada.Characters.Handling.To_Lower (Ada.Strings.Fixed.Trim (TIO.Get_Line, Ada.Strings.Both));
      begin
         return Answer in "y" | "yes";
      end;
   exception
      when TIO.End_Error =>
         TIO.New_Line;
         return False;
   end Ask_Yes;

   function Confirm_New return Boolean is (Ask_Yes (Msg ("ask.prompt", Ada.Directories.Full_Name ("diaries"))));

   function Has_Jsonl_In (Dir : String) return Boolean is
      use Ada.Directories;
      S : Search_Type;
      Res : Boolean := False;
   begin
      if Exists (Dir) and then Kind (Dir) = Directory then
         Start_Search (S, Dir, "*.jsonl");
         Res := More_Entries (S);
         End_Search (S);
      end if;
      return Res;
   end Has_Jsonl_In;

   --  The save folder: --home DIR, else $DIARY_HOME, else ../diary-data next to the source folder
   --  (so the source folder can be replaced at will).  A save inside the source folder is COPIED
   --  there on a yes (never moved or deleted); without a terminal only a hint is printed.
   --  Then every relative path of the program is relative to it (cd).
   procedure Resolve_Home (Header : Boolean) is
      Env : constant String := Ada.Environment_Variables.Value ("DIARY_HOME", "");
      Def : constant String := Ada.Directories.Containing_Directory (Src_Root) & "/diary-data";
   begin
      if Length (Home_Opt) > 0 then
         Home_Path := To_Unbounded_String (Ada.Directories.Full_Name (To_String (Home_Opt)));
         if Header then Con.Put_Line (Msg ("start.folder", To_String (Home_Path))); TIO.Flush; end if;
      elsif Env /= "" then
         Home_Path := To_Unbounded_String (Ada.Directories.Full_Name (Env));
         if Header then Con.Put_Line (Msg ("start.folder", To_String (Home_Path))); TIO.Flush; end if;
      else
         Home_Path := To_Unbounded_String (Def);
         if Header then Con.Put_Line (Msg ("start.folder", Def)); TIO.Flush; end if;
         if Ada.Directories.Exists (Src_Root & "/diaries") and then not Has_Jsonl_In (Def & "/diaries") then
            if Is_Tty (0) and then Is_Tty (1) then
               if Ask_Yes (Msg ("migrate.ask")) then
                  Copy_Tree (Src_Root & "/diaries", Def & "/diaries");
                  if Ada.Directories.Exists (Src_Root & "/entities") then Copy_Tree (Src_Root & "/entities", Def & "/entities"); end if;
                  Con.Put_Line (Msg ("migrate.done", Src_Root & "/diaries", Def));
               end if;
            else
               Con.Put_Line (Msg ("migrate.hint", Src_Root & "/diaries", Def, Src_Root));
            end if;
         end if;
      end if;
      Ada.Directories.Create_Path (To_String (Home_Path));
      Ada.Directories.Set_Directory (To_String (Home_Path));
   end Resolve_Home;

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
   Disk_Build : Unbounded_String;      --  '# build' of diaries/sessions.txt (empty: unknown, older file)
   I : Positive := 1;
   Verify_To : Natural := 0;           --  ticks replayed (verify only) before the import line
   Import_Done : Boolean := False;
   Ent_Missing : Natural := 0;         --  entity folders without words.txt/bench.txt at start
   Start_Known, Start_World : array (Entity_Id) of Natural := [others => 0];
   Run_Learn, Run_Coin, Run_Bench_N : array (Entity_Id) of Natural := [others => 0];
   Last_Done : Int := 0;                --  last tick finished for all entities
   Export_Line, Vote_Line : Unbounded_String;
   Quit_Seen : Boolean := False;

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
   --  ---- debug digest (--debug / make run DEBUG=1 / make demo DEBUG=1) --------------------------
   --  debug_digest.txt: line 1 = one-line status (<= 200 bytes), then anomalies, then only what
   --  changed since the last digest (hashes in debug_digest.prev, save folder only), repeated
   --  lines folded into counts, at most debug.digest_bytes (data/limits.txt) bytes: the least
   --  important lines go first and a last line says what was dropped.  The full record is
   --  debug_full.txt ([section] blocks, run only); --debug-section NAME prints one block.
   Sections : constant String := "status drift trace players inbox run ledger";
   Digest_Note : Unbounded_String;       --  "debug digest: <abs path>", printed before "Saved to"
   Prev_Loaded : Boolean := False;
   Prev_Hashes : Str_Vectors.Vector;

   type Dg_Entry is record
      Sec, Key, Text : Unbounded_String;
      Prio  : Positive := 5;         --  1 = most important, dropped last
      Anom  : Boolean := False;      --  anomaly: always shown
      Full_Only : Boolean := False;  --  only in debug_full.txt
      Count : Positive := 1;         --  folded repeats
   end record;
   package Dg_Vectors is new Ada.Containers.Vectors (Positive, Dg_Entry);
   package Dg_Names is new Ada.Containers.Vectors (Positive, Unbounded_String);
   package Dg_Counts is new Ada.Containers.Vectors (Positive, Positive);

   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (hash, folding, byte cap)
   function Hash_Of (S : String) return String is
     (Fx.Trim (Ada.Containers.Hash_Type'Image (Ada.Strings.Hash (S)), Ada.Strings.Both));

   function Digits_Off (S : String) return String is
      R : String := S;
   begin
      for C of R loop if C in '0' .. '9' then C := '#'; end if; end loop;
      return R;
   end Digits_Off;

   function Shown_Text (E : Dg_Entry) return String is
     (To_String (E.Text) & (if E.Count > 1 then " x" & Img (E.Count) else ""));

   procedure Dg_Add (V : in out Dg_Vectors.Vector; Sec, Key, Raw_Text : String; Prio : Positive;
                     Anom : Boolean := False; Full_Only : Boolean := False; Fold : Boolean := False) is
      Text : constant String := Sim_World.Show (Raw_Text);   --  the cap counts the bytes that are written (display names)
      K : constant String := (if Fold then "f:" & Digits_Off (Text) else Key);
   begin
      if Text = "" then return; end if;
      for E of V loop
         if Fold and then To_String (E.Sec) = Sec and then To_String (E.Key) = K and then E.Full_Only = Full_Only then
            E.Count := E.Count + 1;
            E.Text := To_Unbounded_String (Text);
            return;
         end if;
      end loop;
      V.Append (Dg_Entry'(Sec => To_Unbounded_String (Sec), Key => To_Unbounded_String (K), Text => To_Unbounded_String (Text),
                          Prio => Prio, Anom => Anom, Full_Only => Full_Only, Count => 1));
   end Dg_Add;

   --  Every line of a multi-line text as its own entry (keys Key.1, Key.2, ...).
   procedure Dg_Lines (V : in out Dg_Vectors.Vector; Sec, Key, Text : String; Prio : Positive; Anom : Boolean := False) is
      From : Positive := Text'First;
      N : Natural := 0;
   begin
      if Text'Length = 0 then return; end if;
      for I in Text'First .. Text'Last + 1 loop
         if I > Text'Last or else Text (I) = ASCII.LF then
            if I > From then
               N := N + 1;
               Dg_Add (V, Sec, Key & "." & Img (N), Text (From .. I - 1), Prio, Anom);
            end if;
            From := I + 1;
         end if;
      end loop;
   end Dg_Lines;

   function Sev_Of (L : String) return String is
      Sp : constant Natural := Fx.Index (L, " ");
      Sp2 : constant Natural := (if Sp > 0 then Fx.Index (L, " ", Sp + 1) else 0);
   begin
      return (if Sp > 0 and then Sp2 > Sp then L (Sp + 1 .. Sp2 - 1) else "");
   end Sev_Of;

   --  The inbox line "I5 note from=iris s2 t600 | text | src=..." as "note iris text".
   function Inbox_Brief (L : String) return String is
      A : constant Natural := Fx.Index (L, " | ");
      B : constant Natural := (if A > 0 then Fx.Index (L, " | ", A + 3) else 0);
      Sev : constant String := Sev_Of (L);
   begin
      if A = 0 or else B = 0 or else Sev = "" then return L; end if;
      return Sev & " " & Token (L, "from") & " " & L (A + 3 .. B - 1);
   end Inbox_Brief;

   procedure Digest_Entries (V : in out Dg_Vectors.Vector; Status, Err : String) is
      Table : constant Str_Vectors.Vector := Sim_Dharma.Table_Lines;
      Box   : constant Str_Vectors.Vector := Sim_Dharma.Inbox_Tail (Positive (Int'Max (1, Limit ("inbox.view", 40))));
      Trace : Str_Vectors.Vector;
      Found : Boolean;
      N : Natural := 0;
   begin
      --  anomalies
      if Status = "DRIFT" then Dg_Lines (V, "drift", "err", Err, 1, True);
      elsif Status = "CRASH" then Dg_Lines (V, "trace", "err", Err, 1, True);
      elsif Status = "QUIT" then Dg_Lines (V, "drift", "err", Err, 2, True);
      end if;
      if Status = "CRASH" then
         Read_Lines ("last_error.txt", Trace, Found);
         for L of Trace loop
            N := N + 1;
            Dg_Add (V, "trace", "tr" & Img (N), L, (if N <= 4 then 2 else 3), Full_Only => N > 4);
         end loop;
      end if;
      if Warnings > 0 then Dg_Add (V, "drift", "warn", "warnings: " & Img (Warnings), 2, True); end if;
      if Ent_Missing > 0 and then Disk_Seed >= 0 then Dg_Add (V, "drift", "entmiss", "entity folders rebuilt: " & Img (Ent_Missing), 3, True); end if;
      if Inbox_Bad then Dg_Add (V, "drift", "inbox", "inbox.txt differs from the replay (left as it is)", 1, True); end if;
      --  state
      Dg_Add (V, "run", "ticks",
              (if Preview then "preview: ticks 1.." & Img (Ticks) & " in memory, nothing written"
               elsif Last_Done > Int (Common) then "ticks " & Img (Int (Common) + 1) & ".." & Img (Last_Done) & " new, resumed from " & Img (Common)
               else "ticks " & Img (Last_Done) & " (verify only)"), 3);
      Dg_Lines (V, "run", "kalpa", To_String (Kalpa_Line), 5);
      Dg_Lines (V, "run", "words", To_String (Words_Text), 4);
      if Sim_Dharma.Debug_Line /= "" then Dg_Add (V, "players", "dharma", Msg ("debug.dharma", Sim_Dharma.Debug_Line), 4); end if;
      for L of Table loop
         if L'Length > 8 and then (L (L'First .. L'First + 7) = "players:" or else L (L'First .. L'First + 6) = "anchor:") then
            Dg_Add (V, "players", "t" & Digits_Off (L (L'First .. L'First + 6)), L, 4);
         end if;
      end loop;
      for I in 1 .. Natural (Box.Length) loop   --  raw lines: full record; folded lines: digest
         declare
            L : constant String := Box (I);
            Sev : constant String := Sev_Of (L);
            Alert : constant Boolean := Sev = Msg ("sev.3");
         begin
            Dg_Add (V, "inbox", "raw" & Img (I), L, 9, Full_Only => True);
            Dg_Add (V, "inbox", "", Inbox_Brief (L), (if Alert then 2 elsif Sev = Msg ("sev.2") then 5 else 7), Alert, Fold => True);
         end;
      end loop;
      Dg_Lines (V, "run", "import", To_String (Import_Block), 6);
      Dg_Add (V, "run", "export", To_String (Export_Line), 7);
      for E in Entity_Id loop
         Dg_Add (V, "run", "ent." & Name (E),
                 Msg ("debug.entity", Name (E), Img (Start_Known (E)), Img (Known_Count (E)), Img (Run_Learn (E)),
                      Img (Run_Coin (E)), Img (Run_Bench_N (E)), Sgn (Int (St (E).Mood)) & " en " & Img (St (E).Energy) & " pet " & Img (Petitions_Of (E))
                      & (if World_Active then " w" & Img (World_Learned (E)) else "")), 6);
         Dg_Add (V, "run", "mix." & Name (E),
                 Msg ("debug.mix", Name (E), Img (Act_Count (E, Rest)), Img (Act_Count (E, Work)), Img (Act_Count (E, Explore)),
                      Img (Act_Count (E, Talk)), Img (Act_Count (E, Wander)), Img (Act_Count (E, Bench)) & " p" & Img (Act_Count (E, Propose))
                      & " l" & Img (Act_Count (E, Learn))), 8);
      end loop;
      if World_Active then
         declare
            Sum : Unbounded_String;
         begin
            for E in Entity_Id loop
               Append (Sum, (if E = 1 then "" else " ") & Name (E) & " " & Img (Known_Count (E)) & "(w" & Img (World_Learned (E)) & ")");
            end loop;
            Dg_Add (V, "run", "wordsum", Msg ("debug.wordsum", To_String (Sum)), 3);
         end;
         for E in Entity_Id loop
            Dg_Add (V, "run", "world." & Name (E),
                    Msg ("debug.world", Name (E), Img (World_Learned (E)), Img (Verb_Count (E, Examine)), Img (Verb_Count (E, Push)),
                         Img (Verb_Count (E, Eat)), Img (Verb_Count (E, Greet)),
                         Img (Sim_Things.X (E)) & "," & Img (Sim_Things.Y (E)) & " " & Msg ("loc." & Img (Sim_Things.Region_Of (E)))), 7);
         end loop;
         for L of Sim_Things.Treadmill_Now loop Dg_Add (V, "run", "map." & L, L, 9); end loop;
      end if;
      if Rest_Active then
         for E in Entity_Id loop Dg_Add (V, "run", "rest." & Name (E), Rest_Text (E), 7); end loop;
      end if;
      if Chess_Active then Dg_Add (V, "run", "elo", Sim_Games.Digest_Line, 5); end if;
      for E in Entity_Id loop   --  the mood ledger: one line each (the first to go when the cap is tight); the rest in the full record
         Dg_Add (V, "ledger", "led." & Name (E), Sim_Ledger.Digest_Line (E, Ledger_From), 9);
         Dg_Add (V, "ledger", "sen." & Name (E), Sim_Ledger.Sentence (E), 9, Full_Only => True);
      end loop;
      declare
         T : constant String := Sim_Ledger.Report (Seed, Ledger_From, True) & ASCII.LF;
         From : Positive := T'First;
         N : Natural := 0;
      begin
         for I in T'Range loop
            if T (I) = ASCII.LF then
               N := N + 1;
               Dg_Add (V, "ledger", "full" & Img (N), T (From .. I - 1), 9, Full_Only => True);
               From := I + 1;
            end if;
         end loop;
      end;
      Dg_Add (V, "run", "topics", "topics " & Top_Topics (3), 8);
      Dg_Lines (V, "run", "votes", To_String (Vote_Line), 8);
   end Digest_Entries;

   procedure Write_Plain (Name, Text : String) is
      F : TIO.File_Type;
   begin
      TIO.Create (F, TIO.Out_File, Name & ".tmp");
      TIO.Put (F, Sim_World.Show (if Text'Length > 0 and then Text (Text'Last) = ASCII.LF then Text (Text'First .. Text'Last - 1) else Text));
      TIO.Close (F);   --  Text_IO ends the last line itself
      if Ada.Directories.Exists (Name) then Ada.Directories.Delete_File (Name); end if;
      Ada.Directories.Rename (Name & ".tmp", Name);
   end Write_Plain;

   procedure Load_Prev is
      Found : Boolean;
   begin
      if not Prev_Loaded then
         Prev_Loaded := True;
         if not Preview then Read_Lines ("debug_digest.prev", Prev_Hashes, Found); end if;
      end if;
   end Load_Prev;

   procedure Write_Digest (Status, Err : String) is
      Cap : constant Natural := Natural (Int'Max (300, Limit ("debug.digest_bytes", 1500)));
      V, Keep : Dg_Vectors.Vector;
      Gone : Natural := 0;
      Gone_By, Drop_Sec : Unbounded_String;
      Gone_Secs : Dg_Names.Vector;
      Gone_N : Dg_Counts.Vector;
      Unchanged : Natural := 0;
      Total : Natural := 0;
      Head, Out_Text, Full, Prev_New : Unbounded_String;
      Anoms : Natural := 0;
      First_Anom : Unbounded_String;

      function Hash_Line (E : Dg_Entry) return String is (To_String (E.Key) & "=" & Hash_Of (Shown_Text (E)));
   begin
      if not Debug_On or else Status in "RUN" | "USAGE" then return; end if;
      Load_Prev;
      Digest_Entries (V, Status, Err);
      for E of V loop
         if E.Anom and then not E.Full_Only then
            Anoms := Anoms + 1;
            if Length (First_Anom) = 0 then First_Anom := E.Text; end if;
         end if;
      end loop;
      --  keep: anomalies and changed lines (not in the previous digest); the rest is counted
      for E of V loop
         if not E.Full_Only then
            if E.Anom or else not Prev_Hashes.Contains (Hash_Line (E)) then
               Keep.Append (E);
               Total := Total + Shown_Text (E)'Length + 1;
            else
               Unchanged := Unchanged + 1;
            end if;
         end if;
      end loop;
      Head := To_Unbounded_String
        (Fx.Head (Status & " v" & Build & " seed " & Img (Seed) & " | session " & Img (Session_N) & " | ticks " & Img (if Preview then Ticks else Last_Done)
                  & (if Preview then " (preview)" elsif Last_Done = 0 then " (stopped before any tick)" else " (resumed from " & Img (Common) & ")") & " | "
                  & (if Anoms = 0 then Msg ("digest.fine") else "anomalies " & Img (Anoms) & ": " & Fx.Head (To_String (First_Anom), 70)), 200, ' '));
      Head := To_Unbounded_String (Fx.Trim (To_String (Head), Ada.Strings.Right));
      --  the byte cap: the least important lines (highest Prio, the latest) go first
      declare
         Note_Room : constant Natural := 190;   --  the "unchanged" and "dropped" notes
         Used : constant Natural := Length (Head) + 1 + Note_Room;
      begin
         if Total + Used > Cap then
            while Total + Used > Cap and then not Keep.Is_Empty loop
               declare
                  Worst : Natural := 0;
               begin
                  for I in 1 .. Natural (Keep.Length) loop
                     if Worst = 0 or else Keep (I).Prio >= Keep (Worst).Prio then Worst := I; end if;
                  end loop;
                  Total := Total - (Shown_Text (Keep (Worst))'Length + 1);
                  Gone := Gone + 1;
                  Drop_Sec := Keep (Worst).Sec;
                  Keep.Delete (Worst);
                  declare
                     Seen : Boolean := False;
                  begin
                     for I in 1 .. Natural (Gone_Secs.Length) loop
                        if Gone_Secs (I) = Drop_Sec then Gone_N (I) := Gone_N (I) + 1; Seen := True; end if;
                     end loop;
                     if not Seen then Gone_Secs.Append (Drop_Sec); Gone_N.Append (1); end if;
                  end;
               end;
            end loop;
         end if;
      end;
      Out_Text := Head & ASCII.LF;
      for P in 1 .. 9 loop   --  anomalies first, then by importance; unchanged order inside
         for E of Keep loop
            if E.Prio = P and then E.Anom then Append (Out_Text, Shown_Text (E) & ASCII.LF); end if;
         end loop;
      end loop;
      for P in 1 .. 9 loop
         for E of Keep loop
            if E.Prio = P and then not E.Anom then Append (Out_Text, Shown_Text (E) & ASCII.LF); end if;
         end loop;
      end loop;
      if Unchanged > 0 then Append (Out_Text, Msg ("digest.unchanged", Img (Unchanged)) & ASCII.LF); end if;
      for I in 1 .. Natural (Gone_Secs.Length) loop
         Append (Gone_By, (if I = 1 then "" else ", ") & To_String (Gone_Secs (I)) & " " & Img (Gone_N (I)));
      end loop;
      if Gone > 0 then Append (Out_Text, Msg ("digest.dropped", Img (Gone), To_String (Gone_By)) & ASCII.LF); end if;
      declare
         T : constant String := To_String (Out_Text);
      begin
         Out_Text := To_Unbounded_String (if T'Length > Cap then T (T'First .. T'First + Cap - 1) else T);   --  the hard cap
      end;
      for E of V loop Append (Prev_New, Hash_Line (E) & ASCII.LF); end loop;
      --  the full record
      Append (Full, "[status]" & ASCII.LF & To_String (Head) & ASCII.LF);
      declare
         Name : Unbounded_String;
         Rest_S : constant String := Sections;
         From : Positive := Rest_S'First;
      begin
         for I in Rest_S'First .. Rest_S'Last + 1 loop
               if I > Rest_S'Last or else Rest_S (I) = ' ' then
                  Name := To_Unbounded_String (Rest_S (From .. I - 1));
                  From := I + 1;
                  if To_String (Name) /= "status" then
                     Append (Full, "[" & To_String (Name) & "]" & ASCII.LF);
                     declare
                        Raw : Boolean := False;
                     begin
                        for E of V loop   --  the inbox: the raw lines of the full record, not the folded ones
                           if To_String (E.Sec) = To_String (Name) and then (To_String (Name) /= "inbox" or else E.Full_Only) then
                              Append (Full, Shown_Text (E) & ASCII.LF);
                              Raw := True;
                           end if;
                        end loop;
                        if not Raw then Append (Full, Msg ("digest.empty") & ASCII.LF); end if;
                     end;
                  end if;
               end if;
         end loop;
      end;
      if Length (Section_Opt) > 0 then   --  --debug-section NAME with --preview: just that block
         declare
            Wanted : constant String := To_String (Section_Opt);
            Body_S : Unbounded_String;
            In_It : Boolean := False;
            Pos : Natural := 1;
            F : constant String := To_String (Full);
         begin
            for I in F'Range loop
               if F (I) = ASCII.LF then
                  declare
                     L : constant String := F (Pos .. I - 1);
                  begin
                     if L'Length > 0 and then L (L'First) = '[' then In_It := L = "[" & Wanted & "]";
                     elsif In_It then Append (Body_S, L & ASCII.LF);
                     end if;
                  end;
                  Pos := I + 1;
               end if;
            end loop;
            Out_Text := To_Unbounded_String ("section " & Wanted & ASCII.LF) & Body_S;
            Con.Put (To_String (Out_Text));
         end;
      end if;
      Write_Plain ("debug_digest.txt", To_String (Out_Text));
      if not Preview then
         Write_Plain ("debug_full.txt", To_String (Full));
         Write_Plain ("debug_digest.prev", To_String (Prev_New));
      end if;
      Digest_Note := To_Unbounded_String (Msg ("digest.path", Ada.Directories.Full_Name ("debug_digest.txt")));
   exception
      when others => Con.Put_Line (Msg ("debug.failed"));
   end Write_Digest;

   --  The last console line(s): the digest path (only with --debug), then "Saved to <path>".
   procedure Put_Saved is
   begin
      if Length (Digest_Note) > 0 then Con.Put_Line (To_String (Digest_Note)); end if;
      Con.Put_Line (To_String (Saved_Line));
   end Put_Saved;

   --  --debug-section NAME on a saved run (nothing is simulated): print that block of debug_full.txt
   --  and write it to debug_digest.txt.
   procedure Print_Section (Name : String) is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      In_It : Boolean := False;
      Out_Text : Unbounded_String;
   begin
      Read_Lines ("debug_full.txt", Lines, Found);
      if not Found then
         TIO.Put_Line (TIO.Standard_Error, Msg ("digest.nofull", Ada.Directories.Full_Name ("debug_full.txt")));
         Ada.Command_Line.Set_Exit_Status (2);
         return;
      end if;
      Out_Text := To_Unbounded_String ("section " & Name & ASCII.LF);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) = '[' then In_It := L = "[" & Name & "]";
         elsif In_It then Append (Out_Text, L & ASCII.LF);
         end if;
      end loop;
      Write_Plain ("debug_digest.txt", To_String (Out_Text));
      Con.Put (To_String (Out_Text));
      Con.Put_Line (Msg ("digest.path", Ada.Directories.Full_Name ("debug_digest.txt")));
   end Print_Section;

   --  debug.txt: ONE small file (<= 1500 bytes) on every exit path; Status is
   --  RUN (stub, refreshed every --every ticks), OK, QUIT, CRASH, DRIFT or USAGE.
   --  Parts are kept by priority (header, ticks, error, entities, votes, import,
   --  export); what does not fit is cut, the file never exceeds the cap.
   --  Written to debug.tmp, flushed, then renamed over debug.txt.
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (length cap, text assembly)
   procedure Write_Debug (Status, Err : String) is
      Cap : constant := 1500;
      type Part_Id is (Head, Ticks_P, Kalpa_P, Since_P, Words_P, Dharma_P, Import_P, Export_P, Ents, Mix_P, Topics_P, Votes, Error_P);
      Part : array (Part_Id) of Unbounded_String;
      Order : constant array (1 .. 13) of Part_Id := [Head, Ticks_P, Kalpa_P, Since_P, Words_P, Dharma_P, Error_P, Ents, Mix_P, Topics_P, Votes, Import_P, Export_P];
      Used : Natural := 0;
      Out_Text : Unbounded_String;
      F : TIO.File_Type;
   begin
      if Preview then return; end if;   --  preview writes nothing
      Part (Head) := To_Unbounded_String (Status & " v" & Build & " seed " & (if Seed < 0 then "?" else Img (Seed)) & ASCII.LF);
      Part (Ticks_P) := To_Unbounded_String
        ((if Last_Done > Int (Common)
          then Msg ("debug.ticks", Img (Int (Common) + 1), Img (Last_Done), Img (Last_Done - Int (Common)), Img (Common))
          else Msg ("debug.ticks_v", Img (Last_Done), Img (Common))) & ASCII.LF);
      if Length (Kalpa_Line) > 0 then Part (Kalpa_P) := Kalpa_Line & ASCII.LF; end if;
      if Length (Since_Head) > 0 then
         declare
            T : constant String := To_String (Since_Head);
         begin
            Part (Since_P) := To_Unbounded_String (T (T'First .. Fx.Index (T, "" & ASCII.LF) - 1) & ASCII.LF);
         end;
      end if;
      if Length (Saved_Line) > 0 then Append (Part (Since_P), To_String (Saved_Line) & ASCII.LF); end if;
      if Length (Words_Text) > 0 then Part (Words_P) := Words_Text & ASCII.LF; end if;
      if Sim_Dharma.Debug_Line /= "" then Part (Dharma_P) := To_Unbounded_String (Msg ("debug.dharma", Sim_Dharma.Debug_Line) & ASCII.LF); end if;
      Part (Import_P) := To_Unbounded_String ((if Length (Import_Block) > 0 then To_String (Import_Block) else Msg ("debug.pending", "import"))
                                              & ASCII.LF);
      Part (Export_P) := To_Unbounded_String ((if Length (Export_Line) > 0 then To_String (Export_Line) else Msg ("debug.pending", "export"))
                                              & ASCII.LF);
      for E in Entity_Id loop
         Append (Part (Ents), Msg ("debug.entity", Name (E), Img (Start_Known (E)), Img (Known_Count (E)), Img (Run_Learn (E)),
                                   Img (Run_Coin (E)), Img (Run_Bench_N (E)), Sgn (Int (St (E).Mood)) & " en " & Img (St (E).Energy) & " pet " & Img (Petitions_Of (E))
                      & (if World_Active then " w" & Img (World_Learned (E)) else ""))
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
      declare
         Shown : constant String := Sim_World.Show (To_String (Out_Text));   --  display names are longer than ids: cap again
      begin
         TIO.Put (F, (if Shown'Length > Cap then Shown (Shown'First .. Shown'First + Cap - 1) else Shown));
      end;
      TIO.Flush (F);
      TIO.Close (F);
      begin
         Ada.Directories.Rename ("debug.tmp", "debug.txt");
      exception
         when others =>   --  a rename that will not replace: delete first
            Ada.Directories.Delete_File ("debug.txt");
            Ada.Directories.Rename ("debug.tmp", "debug.txt");
      end;
      Write_Digest (Status, Err);   --  only with --debug, and only for a final status
   exception
      when others => Con.Put_Line (Msg ("debug.failed"));
   end Write_Debug;

   --  One tick for all entities in id order: compare with the disk or append.
   --  ---- the edit log of the world (diaries/world.txt) -------------------------------------------------
   --  Only edits are stored: a thing eaten, pushed or worn out, a new thing from churn.  The replay
   --  regenerates them; a stored line that differs is DRIFT, a missing one is appended (record-first).
   World_Path : constant String := "diaries/world.txt";
   World_Stored : Str_Vectors.Vector;   --  X lines of the file
   World_Flushed : Natural := 0;        --  edits of the replay already compared / written

   procedure Flush_Edits is
      F : TIO.File_Type;
      Opened : Boolean := False;
   begin
      while World_Flushed < Sim_Things.Edit_Count loop
         World_Flushed := World_Flushed + 1;
         declare
            L : constant String := Sim_Things.Edit_Line (World_Flushed);
         begin
            if World_Flushed <= Natural (World_Stored.Length) then
               if World_Stored (World_Flushed) /= L then
                  raise Drift_Error with Msg ("err.world", Img (World_Flushed), Diff_At (World_Stored (World_Flushed), L));
               end if;
            else
               World_Stored.Append (L);
               if not Preview then
                  if not Opened then
                     Opened := True;
                     if Ada.Directories.Exists (World_Path) and then Ada.Directories.Size (World_Path) > 0 then
                        declare
                           Needs_Lf : constant Boolean := not Ends_With_Lf (World_Path);
                        begin
                           TIO.Open (F, TIO.Append_File, World_Path);
                           if Needs_Lf then TIO.New_Line (F); end if;
                        end;
                     else
                        TIO.Create (F, TIO.Out_File, World_Path);
                        TIO.Put_Line (F, "# seed " & Img (Seed));
                        TIO.Put_Line (F, Msg ("hdr.world"));
                     end if;
                  end if;
                  TIO.Put_Line (F, L);
               end if;
            end if;
         end;
      end loop;
      if Opened then TIO.Close (F); end if;
   end Flush_Edits;

   --  The stored edits up to tick Upto must all have been regenerated (an invented or moved line is DRIFT).
   procedure Verify_Edits (Upto : Int) is
   begin
      for K in Sim_Things.Edit_Count + 1 .. Natural (World_Stored.Length) loop
         declare
            L : constant String := World_Stored (K);
            T : constant String := Token (L, "t");
         begin
            if T'Length = 0 or else (for some C of T => C not in '0' .. '9') or else Int'Value (T) <= Upto then
               raise Drift_Error with Msg ("err.world", Img (K), Diff_At (L, "(not in the replay)"));
            end if;
         end;
      end loop;
   end Verify_Edits;

   --  The stored file, read once before the replay (a missing file is simply regenerated).
   procedure Load_World_File is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      World_Stored.Clear;
      World_Flushed := 0;
      if not Ada.Directories.Exists (World_Path) then return; end if;
      Read_Lines (World_Path, Lines, Found);
      for L of Lines loop
         if L'Length >= 7 and then L (L'First .. L'First + 6) = "# seed " then
            if L /= "# seed " & Img (Seed) then
               raise Diary_Error with Msg ("err.session_seed", L (L'First + 7 .. L'Last));
            end if;
         elsif L'Length > 0 and then L (L'First) = 'X' then
            World_Stored.Append (L);
         end if;
      end loop;
   end Load_World_File;

   --  ---- grants (grant=1 sessions): Robert grants a petition (make grant PETITION=P<n>) ------------------------
   --  diaries/grants.txt: G<n> lines are his input (applied after the tick they carry); E<n> lines are the effect the
   --  replay computes (rate old>new per wesen, record-first like world.txt): a differing or invented line is DRIFT.
   Grants_Path : constant String := "diaries/grants.txt";
   function To_Num_Safe (T : String) return Int is
     (if T'Length in 1 .. 15 and then (for all C of T => C in '0' .. '9') then Int'Value (T) else -1);
   type Grant_Rec is record
      N : Positive := 1;
      Tick : Int := 0;
      Pet : Positive := 1;
      Who : Entity_Id := 1;
      Topic : Positive := 1;
      Done : Boolean := False;
   end record;
   package Grant_Vectors is new Ada.Containers.Vectors (Positive, Grant_Rec);
   Grants : Grant_Vectors.Vector;
   Eff_Stored : Str_Vectors.Vector;
   Eff_Hit : array (1 .. 1000) of Boolean := [others => False];
   Grant_Report : Str_Vectors.Vector;

   procedure Load_Grants is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      Grants.Clear;
      Eff_Stored.Clear;
      Grant_Report.Clear;
      if not Ada.Directories.Exists (Grants_Path) then return; end if;
      Read_Lines (Grants_Path, Lines, Found);
      for L of Lines loop
         if L'Length > 7 and then L (L'First .. L'First + 6) = "# seed " then
            if L /= "# seed " & Img (Seed) then raise Diary_Error with Msg ("err.session_seed", L (L'First + 7 .. L'Last)); end if;
         elsif L'Length > 1 and then L (L'First) = 'E' then
            Eff_Stored.Append (L);
         elsif L'Length > 1 and then L (L'First) = 'G' and then Fx.Index (L, " ") > 2 then
            declare
               Sp : constant Natural := Fx.Index (L, " ");
               Pt : constant String := Token (L, "petition");
               N : constant Int := (if Sp > 2 then Int'Max (-1, To_Num_Safe (L (L'First + 1 .. Sp - 1))) else -1);
               Tk : constant Int := To_Num_Safe (Token (L, "tick"));
               Pn : constant Int := (if Pt'Length > 1 and then Pt (Pt'First) = 'P' then To_Num_Safe (Pt (Pt'First + 1 .. Pt'Last)) else -1);
               W : constant Natural := Sim_Dharma.Find_Wesen (Token (L, "wesen"));
               T : constant Natural := Topic_Id (Token (L, "topic"));
            begin
               if N > 0 and then Tk >= 0 and then Pn > 0 and then W > 0 and then T > 0 then
                  Grants.Append (Grant_Rec'(N => Positive (N), Tick => Tk, Pet => Positive (Pn), Who => Entity_Id (W), Topic => T, Done => False));
               else
                  Warn (Msg ("warn.grants_bad", L));
               end if;
            end;
         end if;
      end loop;
   end Load_Grants;

   --  Before tick Tick: the grants recorded at tick Tick - 1 take effect.
   procedure Apply_Grants (Tick : Int) is
   begin
      for I in 1 .. Natural (Grants.Length) loop
         declare
            G : Grant_Rec := Grants (I);
         begin
            if not G.Done and then G.Tick = Tick - 1 then
               if Petition_Total < G.Pet or else Petition_From (G.Pet) /= G.Who or else Petition_Topic (G.Pet) /= Topic_Name (G.Topic)
                 or else Petition_Tick (G.Pet) > G.Tick
               then
                  raise Drift_Error with Msg ("err.grant", "G" & Img (G.N), "P" & Img (G.Pet), Name (G.Who), Topic_Name (G.Topic));
               end if;
               declare
                  Active : constant Boolean := Grant_Active and then Rest_Active;
                  Max_A : Natural := 0;
                  Buf : Unbounded_String;
                  Line : Unbounded_String;
               begin
                  for E in Entity_Id loop Max_A := Natural'Max (Max_A, Asked (E, G.Topic)); end loop;
                  for E in Entity_Id loop
                     declare
                        A : constant Natural := Asked (E, G.Topic);
                        Old : constant Natural := Rate_Pct (E);
                        Cap : constant Natural := Natural (Integer'Max (1, RL ("grant.cap", 170)));
                        Step : constant Natural := (if A > 0 and then Max_A > 0 then Natural'Max (1, Natural (Integer'Max (0, RL ("grant.step", 6))) * A / Max_A) else 0);
                        Now : constant Natural := (if Active and then Is_Recovery_Topic (G.Topic) and then Old < Cap then Natural'Min (Cap, Old + Step) else Old);
                     begin
                        Rate_Pct (E) := Now;
                        if Active and then A > 0 then Sim_World.Grant (E, G.Topic); end if;
                        Append (Buf, " " & Name (E) & "=" & Img (Old) & ">" & Img (Now) & "/" & Img (A));
                     end;
                  end loop;
                  if Active then Mark_Petition (G.Pet, G.N); end if;
                  Line := To_Unbounded_String ("E" & Img (G.N) & " tick=" & Img (G.Tick) & " g=G" & Img (G.N) & " topic=" & Topic_Name (G.Topic)
                                               & " applied=" & (if Active then "1" else "0") & To_String (Buf));
                  Grant_Report.Append (To_String (Line));
                  declare
                     Found_At : Natural := 0;
                  begin
                     for K in 1 .. Natural (Eff_Stored.Length) loop
                        declare
                           Pfx : constant String := "E" & Img (G.N) & " ";
                           SL : constant String := Eff_Stored (K);
                        begin
                           if SL'Length >= Pfx'Length and then SL (SL'First .. SL'First + Pfx'Length - 1) = Pfx then Found_At := K; end if;
                        end;
                     end loop;
                     if Found_At > 0 then
                        if Eff_Stored (Found_At) /= To_String (Line) then
                           raise Drift_Error with Msg ("err.grant_fx", "E" & Img (G.N), Diff_At (Eff_Stored (Found_At), To_String (Line)));
                        end if;
                        if Found_At <= Eff_Hit'Last then Eff_Hit (Found_At) := True; end if;
                     elsif not Preview and then not Ledger_Mode then   --  record-first: the effect is written when it first happens
                        declare
                           F : TIO.File_Type;
                        begin
                           if Ada.Directories.Exists (Grants_Path) then
                              TIO.Open (F, TIO.Append_File, Grants_Path);
                           else
                              TIO.Create (F, TIO.Out_File, Grants_Path);
                              TIO.Put_Line (F, "# seed " & Img (Seed));
                           end if;
                           TIO.Put_Line (F, To_String (Line));
                           TIO.Close (F);
                           Eff_Stored.Append (To_String (Line));
                           if Natural (Eff_Stored.Length) <= Eff_Hit'Last then Eff_Hit (Natural (Eff_Stored.Length)) := True; end if;
                        end;
                     end if;
                  end;
               end;
               G.Done := True;
               Grants.Replace_Element (I, G);
            end if;
         end;
      end loop;
   end Apply_Grants;

   --  After the replay: a stored effect line the replay did not produce (its grant was removed or changed) is DRIFT.
   procedure Verify_Grants (Upto : Int) is
   begin
      for K in 1 .. Natural (Eff_Stored.Length) loop
         declare
            L : constant String := Eff_Stored (K);
            T : constant Int := To_Num_Safe (Token (L, "tick"));
         begin
            if (K > Eff_Hit'Last or else not Eff_Hit (K)) and then T in 0 .. Upto - 1 then
               raise Drift_Error with Msg ("err.grant_fx", L (L'First .. Fx.Index (L, " ") - 1), Diff_At (L, "(not in the replay)"));
            end if;
         end;
      end loop;
   end Verify_Grants;

   --  Every change of a screen is a K line in diaries/screens.txt: "K12 t=300 ada add w=7 src=taught s=3,*7".  The replay
   --  compares each one with the stored line (DRIFT if different) and appends a missing one.
   procedure Emit_Screen_Lines (Tick : Int) is
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      for T of Scr_Lines loop
         Screen_N := Screen_N + 1;
         declare
            Line : constant String := "K" & Img (Screen_N) & " t=" & Img (Tick) & " " & T;
         begin
            Sim_Store.Emit (Screen_Store, Line, not Preview and then not Ledger_Mode, Result, Old);
            if Sim_Store."=" (Result, Sim_Store.Differs) then
               raise Drift_Error with Msg ("err.screens", "K" & Img (Screen_N), Diff_At (To_String (Old), Line));
            end if;
         end;
      end loop;
      Scr_Lines.Clear;
   end Emit_Screen_Lines;

   --  After the replay: a stored K line the replay did not produce is DRIFT.
   procedure Verify_Screens (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Screen_Store, Upto);
   begin
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.screens", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Screens;

   --  Every chess record (start, move, end with the new ratings, holiday) is a C line in diaries/chess.txt: replay-verified.
   procedure Emit_Chess_Lines (Tick : Int) is
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      for T of Chess_Lines loop
         Chess_N := Chess_N + 1;
         declare
            Line : constant String := "C" & Img (Chess_N) & " t=" & Img (Tick) & " " & T;
         begin
            Sim_Store.Emit (Chess_Store, Line, not Preview and then not Ledger_Mode, Result, Old);
            if Sim_Store."=" (Result, Sim_Store.Differs) then
               raise Drift_Error with Msg ("err.chess", "C" & Img (Chess_N), Diff_At (To_String (Old), Line));
            end if;
         end;
      end loop;
      Chess_Lines.Clear;
   end Emit_Chess_Lines;

   procedure Verify_Chess (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Chess_Store, Upto);
   begin
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.chess", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Chess;

   procedure Do_Tick (Tick : Int) is
   begin
      Cur_Tick := Tick;
      Sim_Dharma.Tick_Begin (Tick);
      Apply_Grants (Tick);
      if Chess_Active then   --  the clocks of the running games (a timeout ends one)
         Sim_Games.Clock (Tick, Chess_Lines);
         Emit_Chess_Lines (Tick);
      end if;
      for E in Entity_Id loop
         Cur_Name := To_Unbounded_String (Name (E));
         if Tick = Crash_At and then Tick > Int (Common) and then E = 1 then Events := Forced (Tick); end if;
         declare
            Line : constant String := Step (E, Tick);
         begin
            Emit_Screen_Lines (Tick);
            Emit_Chess_Lines (Tick);
            if Tick <= Int (Disk (E).Length) then   --  already on disk: compare, do not write
               if No_Ts (Line) /= No_Ts (Disk (E) (Positive (Tick))) then
                  raise Drift_Error with Msg ("err.drift", Name (E), Img (Tick),
                                              Diff_At (No_Ts (Disk (E) (Positive (Tick))), No_Ts (Line)));
               end if;
               Verified := Verified + 1;
            else
               if Preview then
                  Sample (E).Append (Line);
               else
                  TIO.Put_Line (Out_File (E), Line);
                  TIO.Flush (Out_File (E));
               end if;
               Written := Written + 1;
            end if;
            Events := Written + Verified;
            Act_Count (E, Last_Act) := Act_Count (E, Last_Act) + 1;
            if Last_Verb in World_Verb then Verb_Count (E, Last_Verb) := Verb_Count (E, Last_Verb) + 1; end if;
            Sim_Dharma.Deed (E, Last_Act, Pre_Energy_G, Did_Teach, Did_Coin);
            Record_Tick (Votes_Of (E), St (E).Location, St (E).Mood, St (E).Energy, Did_Learn, Did_Coin, Did_Bench);
            if Tick > Int (Common) then
               Run_Learn (E) := Run_Learn (E) + Boolean'Pos (Did_Learn);
               Run_Coin (E) := Run_Coin (E) + Boolean'Pos (Did_Coin);
               Run_Bench_N (E) := Run_Bench_N (E) + Boolean'Pos (Did_Bench);
            end if;
         end;
      end loop;
      if World_Active then Sim_Things.Churn (Tick); end if;   --  things come and go near the wesen
      Flush_Edits;
      Sim_Dharma.Tick_End (Tick);
      Last_Done := Tick;
   end Do_Tick;

   --  The Elo ranking of the wesen and the players after the replay (--elo / make elo).
   function Elo_Text return String is
      R : Unbounded_String;
   begin
      if not Chess_Active then return Msg ("elo.none") & ASCII.LF; end if;
      for L of Sim_Games.Ranking loop Append (R, L & ASCII.LF); end loop;
      Append (R, Msg ("elo.games", Img (Sim_Games.Game_Count), Img (Sim_Games.Finished_Count), Img (Sim_Games.Moves_Total)) & ASCII.LF);
      return To_String (R);
   end Elo_Text;

   --  --perft: the move generator against the reference counts in data/chess.txt; exit 1 if one differs.
   procedure Do_Perft is
      Fails, Total : Natural := 0;
      function Word_At (T : String; N : Positive) return String is
         From : Natural := T'First;
         Count_W : Natural := 0;
      begin
         for I in T'First .. T'Last + 1 loop
            if I > T'Last or else T (I) = ' ' then
               if I > From then
                  Count_W := Count_W + 1;
                  if Count_W = N then return T (From .. I - 1); end if;
               end if;
               From := I + 1;
            end if;
         end loop;
         return "";
      end Word_At;
      function After (T : String; N : Positive) return String is   --  the text after the first N words
         Count_W : Natural := 0;
         In_W : Boolean := False;
      begin
         for I in T'Range loop
            if T (I) /= ' ' and then not In_W then In_W := True; Count_W := Count_W + 1;
            elsif T (I) = ' ' and then In_W then
               In_W := False;
               if Count_W = N then return T (I + 1 .. T'Last); end if;
            end if;
         end loop;
         return "";
      end After;
      procedure Check (Ok : Boolean; Label, Want, Got : String) is
      begin
         Total := Total + 1;
         if Ok then
            Con.Put_Line (Msg ("perft.ok", Label));
         else
            Fails := Fails + 1;
            Con.Put_Line (Msg ("perft.fail", Label, Want, Got));
         end if;
      end Check;
      function Pos_Of (Fen : String) return Sim_Chess.Position is
         Ok : Boolean;
         P : constant Sim_Chess.Position := Sim_Chess.From_Fen (Fen, Ok);
      begin
         if not Ok then raise Usage_Error with Msg ("perft.badfen", Fen); end if;
         return P;
      end Pos_Of;
   begin
      Con.Put_Line (Msg ("perft.head"));
      for N in 1 .. 99 loop   --  perft.N = depth count FEN
         declare
            T : constant String := Msg ("perft." & Img (N));
         begin
            exit when T (T'First) = '[';
            declare
               Depth : constant Natural := Natural (Int'Max (0, To_Num_Safe (Word_At (T, 1))));
               Want : constant Natural := Natural (Int'Max (0, To_Num_Safe (Word_At (T, 2))));
               Got : constant Natural := Sim_Chess.Perft (Pos_Of (After (T, 2)), Depth);
            begin
               Check (Got = Want, "perft " & Img (Depth) & " " & Img (Want) & " " & After (T, 2), Img (Want), Img (Got));
            end;
         end;
      end loop;
      for N in 1 .. 99 loop   --  perft.state.N = state FEN
         declare
            T : constant String := Msg ("perft.state." & Img (N));
         begin
            exit when T (T'First) = '[';
            declare
               Want : constant String := Word_At (T, 1);
               S : constant Sim_Chess.Game_State := Sim_Chess.State_Of (Pos_Of (After (T, 1)));
               Got : constant String :=
                 (case S is when Sim_Chess.Ongoing => "ongoing", when Sim_Chess.Checkmate => "checkmate",
                            when Sim_Chess.Stalemate => "stalemate", when Sim_Chess.Fifty_Moves => "fifty");
            begin
               Check (Got = Want, "state " & Want & " " & After (T, 1), Want, Got);
            end;
         end;
      end loop;
      for N in 1 .. 99 loop   --  perft.note.N = coordinate iccf FEN
         declare
            T : constant String := Msg ("perft.note." & Img (N));
         begin
            exit when T (T'First) = '[';
            declare
               Coord : constant String := Word_At (T, 1);
               Want : constant String := Word_At (T, 2);
               L : constant Sim_Chess.Move_List := Sim_Chess.Legal (Pos_Of (After (T, 2)));
               Got : Unbounded_String := To_Unbounded_String ("(not legal)");
            begin
               for I in 1 .. L.Count loop
                  if Sim_Chess.Coord (L.Items (I)) = Coord then Got := To_Unbounded_String (Sim_Chess.Iccf (L.Items (I))); end if;
               end loop;
               Check (To_String (Got) = Want, "move " & Coord & " = " & Want, Want, To_String (Got));
            end;
         end;
      end loop;
      Con.Put_Line (Msg ("perft.sum", Img (Total), Img (Fails)));
      if Fails > 0 then Ada.Command_Line.Set_Exit_Status (1); end if;
   end Do_Perft;

   --  The screens of every wesen after the replay (--screens / make screens) and the notes lying on things.
   function Screens_Text return String is
      R : Unbounded_String;
   begin
      if not Screen_Active then return Msg ("screen.none") & ASCII.LF; end if;
      Append (R, Msg ("screen.head", Img (Last_Done)) & ASCII.LF);
      for E in Entity_Id loop
         Append (R, Sim_Screen.Summary (E) & ASCII.LF);
         for L of Sim_Screen.Box (E) loop Append (R, L & ASCII.LF); end loop;
      end loop;
      Append (R, Msg ("screen.notes", Img (Sim_Screen.Notes_Now)) & ASCII.LF);
      return To_String (R);
   end Screens_Text;

   --  diaries/inbox.txt: the newest inbox.view lines of the players' reports to Robert (a view; the
   --  replay regenerates all of them and import compares the stored lines).  Rewritten atomically.
   procedure Write_Inbox is
      View : constant Positive := Positive (Int'Max (1, Limit ("inbox.view", 40)));
      F : TIO.File_Type;
   begin
      if Preview or else Inbox_Bad or else Sim_Dharma.Inbox_Count = 0 or else Last_Done < Int (Common) then return; end if;
      TIO.Create (F, TIO.Out_File, "diaries/inbox.tmp");
      TIO.Put_Line (F, Msg ("hdr.inbox", Img (View)));
      for L of Sim_Dharma.Inbox_Tail (View) loop TIO.Put_Line (F, L); end loop;
      TIO.Flush (F);
      TIO.Close (F);
      begin
         Ada.Directories.Rename ("diaries/inbox.tmp", "diaries/inbox.txt");
      exception
         when others =>
            Ada.Directories.Delete_File ("diaries/inbox.txt");
            Ada.Directories.Rename ("diaries/inbox.tmp", "diaries/inbox.txt");
      end;
   exception
      when others => Con.Put_Line (Msg ("debug.failed"));
   end Write_Inbox;

   --  petitions.txt: a view of the petitions the replay filed (the last propose.file_cap lines;
   --  the oldest drop out of the file, never out of the diaries).  Rewritten atomically.
   procedure Write_Petitions is
      Cap : constant Natural := Natural (Int'Max (1, Limit ("propose.file_cap", 40)));
      Total : constant Natural := Petition_Total;
      First : constant Natural := (if Total > Cap then Total - Cap + 1 else 1);
      F : TIO.File_Type;
   begin
      if Preview then return; end if;
      Write_Inbox;
      TIO.Create (F, TIO.Out_File, "petitions.tmp");
      TIO.Put_Line (F, Sim_World.Show (Msg ("pet.head", Img (Seed), Img (Integer (Total) - First + 1), Img (Total))));
      for N in First .. Total loop TIO.Put_Line (F, Sim_World.Show (Petition_Line (N))); end loop;
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
      when others => Con.Put_Line (Msg ("debug.failed"));
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
      Dharma : Boolean := False;        --  dharma=1: started by a build with the Buddhism layer (rebirth moves allowed)
      World : Boolean := False;         --  world=1: the treadmill world (Sim_Things) runs in this session
      Rest : Boolean := False;          --  rest=1: recovery rates, rest trade-off and cool-downs
      Grant : Boolean := False;         --  grant=1: grants of petitions (diaries/grants.txt) change recovery rates
      Chess : Boolean := False;         --  chess=1: chess games as a rest activity, Elo ratings (Sim_Games, diaries/chess.txt)
      Screen : Boolean := False;        --  screen=1: the wesen own small text screens (Sim_Screen, diaries/screens.txt)
   end record;
   package Session_Vectors is new Ada.Containers.Vectors (Positive, Session_Rec);
   Sessions : Session_Vectors.Vector;
   Sessions_Path : constant String := "diaries/sessions.txt";
   Says_Path : constant String := "diaries/says.txt";
   Dharma_Stored : Str_Vectors.Vector;   --  D / C / Y lines of sessions.txt

   --  The ledger's last session = the ticks after the start of the newest session record.
   procedure Set_Ledger_From is
   begin
      Ledger_From := (if Sessions.Is_Empty then 0 else Sessions.Last_Element.Start);
   end Set_Ledger_From;

   function Votes_Text (V : Kalpa_Votes) return String is
     (Img (V (1)) & "/" & Img (V (2)) & "/" & Img (V (3)) & "/" & Img (V (4)));
   function Session_Line (R : Session_Rec) return String is
     ("S" & Img (R.N) & " start=" & Img (R.Start) & " votes=" & Votes_Text (R.Votes) & " len=" & Img (R.Len)
      & " src=" & (if R.By_Vote then "vote" else "explicit") & (if R.Dharma then " dharma=1" else "")
      & (if R.World then " world=1" else "") & (if R.Rest then " rest=1" else "") & (if R.Grant then " grant=1" else "")
      & (if R.Screen then " screen=1" else "") & (if R.Chess then " chess=1" else ""));
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
      R.Dharma := Token (L, "dharma") = "1";
      R.World := Token (L, "world") = "1";
      R.Rest := Token (L, "rest") = "1";
      R.Grant := Token (L, "grant") = "1";
      R.Screen := Token (L, "screen") = "1";
      R.Chess := Token (L, "chess") = "1";
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

   --  ---- the word vote (favourite words at the end of a session) --------------------------
   type Tok_Array is array (Entity_Id) of Unbounded_String;   --  word/origin, spaces as '-'
   type Word_Vote is record
      N    : Positive := 1;
      Tick : Int := 0;
      Tok  : Tok_Array;
   end record;
   package Word_Vote_Vectors is new Ada.Containers.Vectors (Positive, Word_Vote);
   Word_Votes : Word_Vote_Vectors.Vector;

   function Dashed (S : String) return String is
      R : String := S;
   begin
      for C of R loop if C = ' ' then C := '-'; end if; end loop;
      return R;
   end Dashed;

   --  What each wesen would name now (state of the replay at this tick).
   function Words_Now (Tick : Int) return Tok_Array is
      T : Tok_Array;
   begin
      for E in Entity_Id loop
         declare
            W : constant Natural := Favourite (Seed, E, Tick, St (E).Mood);
         begin
            T (E) := To_Unbounded_String (if W = 0 then "-" else Word (W) & "/" & Dashed (Origin (E, W)));
         end;
      end loop;
      return T;
   end Words_Now;

   function Tok_Text (T : Tok_Array) return String is
      R : Unbounded_String;
   begin
      for E in Entity_Id loop Append (R, (if E = 1 then "" else " ") & Name (E) & "=" & To_String (T (E))); end loop;
      return To_String (R);
   end Tok_Text;

   --  "ada water | gemini handphone | ..." for the console (the origin is in sessions.txt).
   function Words_Short (T : Tok_Array) return String is
      R : Unbounded_String;
   begin
      for E in Entity_Id loop
         declare
            V : constant String := To_String (T (E));
            Sl : constant Natural := Fx.Index (V, "/");
         begin
            Append (R, (if E = 1 then "" else " | ") & Name (E) & " " & (if Sl > 0 then V (V'First .. Sl - 1) else V));
         end;
      end loop;
      return To_String (R);
   end Words_Short;

   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (parsing of a W record of sessions.txt)
   procedure Parse_Word_Vote (L : String; R : out Word_Vote; OK : out Boolean) is
      Sp : constant Natural := Fx.Index (L, " ");
   begin
      R := (others => <>);
      OK := L'Length > 2 and then L (L'First) = 'W' and then Sp > 2;
      if not OK then return; end if;
      OK := To_Num (L (L'First + 1 .. Sp - 1)) > 0 and then To_Num (Token (L, "tick")) >= 0;
      if not OK then return; end if;
      R.N := Positive (To_Num (L (L'First + 1 .. Sp - 1)));
      R.Tick := To_Num (Token (L, "tick"));
      for E in Entity_Id loop
         R.Tok (E) := To_Unbounded_String (Token (L, Name (E)));
         OK := OK and then Length (R.Tok (E)) > 0;
      end loop;
   end Parse_Word_Vote;

   procedure Load_Sessions is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Mark  : constant String := "# seed ";
      Bmark : constant String := "# build v";
      R     : Session_Rec;
      OK    : Boolean;
   begin
      Sessions.Clear;
      Word_Votes.Clear;
      Dharma_Stored.Clear;
      World_Active := False;
      Rest_Active := False;
      Grant_Active := False;
      Screen_Active := False;
      Chess_Active := False;
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
            elsif L'Length > Bmark'Length and then L (L'First .. L'First + Bmark'Length - 1) = Bmark then
               Disk_Build := To_Unbounded_String (L (L'First + Bmark'Length .. L'Last));
            elsif L'Length > 0 and then L (L'First) in 'D' | 'C' | 'Y' | 'L' | 'R' then
               Dharma_Stored.Append (L);
            elsif L'Length > 0 and then L (L'First) = 'W' then
               declare
                  V : Word_Vote;
               begin
                  Parse_Word_Vote (L, V, OK);
                  if OK then Word_Votes.Append (V); else Warn (Msg ("warn.session_bad", Img (I))); end if;
               end;
            elsif L'Length > 0 and then L (L'First) = 'S' then
               Parse_Session (L, R, OK);
               if OK then Sessions.Append (R); else Warn (Msg ("warn.session_bad", Img (I))); end if;
            elsif L'Length > 0 and then L (L'First) /= '#' then
               Warn (Msg ("warn.session_bad", Img (I)));
            end if;
         end;
      end loop;
   end Load_Sessions;

   --  A liberated wesen of a new session moves to the location its own dice name (record + effect).
   procedure Start_Life (R : Session_Rec) is
   begin
      Sim_Dharma.Begin_Life (Seed, R.Start, R.N, L_Max + 1, R.Dharma);
      World_Active := R.World;
      if R.Rest and then not Rest_Active then Rest_Begin (Seed); end if;   --  the state runs on from session to session
      Rest_Active := R.Rest;
      Grant_Active := R.Grant;
      Screen_Active := R.Screen;
      Chess_Active := R.Chess;
      for E in Entity_Id loop
         if Sim_Dharma.Rebirth_Location (E) >= 0 then St (E).Location := Clamp (Sim_Dharma.Rebirth_Location (E), 0, L_Max); end if;
      end loop;
   end Start_Life;

   --  The world line of a session end (world sessions only): "L3 tick=2131 words=300 edits=12
   --  ada=225/2/5/1@3,-4 ..." = known / learned from the world / taught / coined @ position.
   function World_Line (N : Positive; Tick : Int) return String is
      R : Unbounded_String := To_Unbounded_String ("L" & Img (N) & " tick=" & Img (Tick) & " words=" & Img (Count)
                                                   & " edits=" & Img (Sim_Things.Edit_Count));
   begin
      for E in Entity_Id loop
         Append (R, " " & Name (E) & "=" & Img (Known_Count (E)) & "/" & Img (World_Learned (E)) & "/" & Img (Taught_Count (E))
                 & "/" & Img (Coined_Count_By (E)) & "@" & Img (Sim_Things.X (E)) & "," & Img (Sim_Things.Y (E)));
      end loop;
      return To_String (R);
   end World_Line;

   --  The rest line of a session end (rest=1 sessions): "R3 tick=2300 ada=100/5/2/9 ..." = recovery rate percent /
   --  cool-downs taken / rests cut short / quick rests, this session.
   function Rest_Line (N : Positive; Tick : Int) return String is
      R : Unbounded_String := To_Unbounded_String ("R" & Img (N) & " tick=" & Img (Tick));
   begin
      for E in Entity_Id loop
         Append (R, " " & Name (E) & "=" & Img (Rate_Pct (E)) & "/" & Img (Cool_N (E)) & "/" & Img (Cut_N (E)) & "/" & Img (Quick_N (E)));
      end loop;
      return To_String (R);
   end Rest_Line;

   --  The key of a D / C / Y / L line: its first two (C, L) or three (D, Y) words.
   function Key_Of (L : String) return String is
      Sp : Natural := 0;
      Need : constant Positive := (if L'Length > 0 and then L (L'First) in 'C' | 'L' | 'R' then 2 else 3);
   begin
      for I in L'Range loop
         if L (I) = ' ' then
            Sp := Sp + 1;
            if Sp = Need then return L (L'First .. I - 1); end if;
         end if;
      end loop;
      return L;
   end Key_Of;

   --  The stored D / C / Y lines of a session end must equal what the replay regenerates.
   procedure Check_Dharma_At (T : Int) is
      Stored : Str_Vectors.Vector;
      Votes : Kalpa_Votes := [others => 0];
      En : Sim_Dharma.Energies;
      N : Int := 0;
   begin
      for L of Dharma_Stored loop
         if Token (L, "tick") = Img (T) then
            Stored.Append (L);
            if N = 0 then N := To_Num (L (L'First + 1 .. Fx.Index (L, " ") - 1)); end if;
         end if;
      end loop;
      if Stored.Is_Empty or else N < 1 then return; end if;
      for R of Sessions loop if Int (R.N) = N then Votes := R.Votes; end if; end loop;
      for E in Entity_Id loop En (E) := St (E).Energy; end loop;
      declare
         Gen : Str_Vectors.Vector := Sim_Dharma.End_Life (Seed, T, Positive (N), Votes, En);
      begin
         if World_Active then Gen.Append (World_Line (Positive (N), T)); end if;
         if Rest_Active then Gen.Append (Rest_Line (Positive (N), T)); end if;
         for G of Gen loop
            if not Stored.Contains (G) then
               declare
                  Other : Unbounded_String := To_Unbounded_String ("(missing)");
               begin
                  for L of Stored loop if Key_Of (L) = Key_Of (G) then Other := To_Unbounded_String (L); end if; end loop;
                  raise Drift_Error with Msg ("err.dharma", Img (N), Img (T), Diff_At (To_String (Other), G));
               end;
            end if;
         end loop;
         for L of Stored loop
            if not Gen.Contains (L) then
               raise Drift_Error with Msg ("err.dharma", Img (N), Img (T), Diff_At (L, "(not in the replay)"));
            end if;
         end loop;
      end;
   end Check_Dharma_At;

   --  A stored session must reproduce its votes when the replay reaches its start tick.
   procedure Check_Sessions_At (T : Int) is
   begin
      Check_Dharma_At (T);
      for R of Word_Votes loop
         if R.Tick = T then
            declare
               Now : constant Tok_Array := Words_Now (T);
            begin
               if Now /= R.Tok then
                  raise Drift_Error with Msg ("err.words", Img (R.N), Img (R.Tick), Tok_Text (R.Tok), Tok_Text (Now));
               end if;
            end;
         end if;
      end loop;
      for R of Sessions loop
         if R.Start = T then
            declare
               V : constant Kalpa_Votes := Votes_At (T);
            begin
               if V /= R.Votes then
                  raise Drift_Error with Msg ("err.session", Img (R.N), Img (R.Start), "votes " & Votes_Text (R.Votes),
                                              "votes " & Votes_Text (V));
               end if;
               Start_Life (R);
            end;
         end if;
      end loop;
   end Check_Sessions_At;


   procedure Append_Text (Line : String) is
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
         TIO.Put_Line (F, "# build v" & Build);
         TIO.Put_Line (F, Msg ("hdr.sessions"));
         TIO.Put_Line (F, Msg ("words.hdr"));
         TIO.Put_Line (F, Msg ("hdr.dharma"));
      end if;
      TIO.Put_Line (F, Line);
      TIO.Flush (F);
      TIO.Close (F);
   end Append_Text;

   procedure Append_Session (R : Session_Rec) is
   begin
      Append_Text (Session_Line (R));
      Sessions.Append (R);
   end Append_Session;

   --  The end of a session: every wesen names a favourite word; the vote goes to sessions.txt.
   procedure Record_Word_Vote (Tick : Int) is
      R : Word_Vote;
      Votes : Kalpa_Votes := [others => 0];
      En : Sim_Dharma.Energies;
      Text : Unbounded_String;
   begin
      R.N := Positive'Max (1, Session_N);
      R.Tick := Tick;
      R.Tok := Words_Now (Tick);
      Text := To_Unbounded_String ("W" & Img (R.N) & " tick=" & Img (Tick) & " " & Tok_Text (R.Tok));
      for S of Sessions loop if S.N = R.N then Votes := S.Votes; end if; end loop;
      for E in Entity_Id loop En (E) := St (E).Energy; end loop;
      for L of Sim_Dharma.End_Life (Seed, Tick, R.N, Votes, En) loop Append (Text, ASCII.LF & L); end loop;
      if World_Active then Append (Text, ASCII.LF & World_Line (R.N, Tick)); end if;
      if Rest_Active then Append (Text, ASCII.LF & Rest_Line (R.N, Tick)); end if;
      Append_Text (To_String (Text));   --  W, D x4, C, Y x3 (and L in a world session) in one write
      Word_Votes.Append (R);
      Words_Text := To_Unbounded_String (Msg ("words.line", Img (R.N), Words_Short (R.Tok)));
   end Record_Word_Vote;

   --  New sessions carry world=1 unless data/limits.txt says world.enabled = 0 (or data/things.txt is missing).
   function World_Wanted return Boolean is (Limit ("world.enabled", 1) /= 0 and then Sim_Things.Loaded);
   function Rest_Wanted return Boolean is (World_Wanted and then Limit ("rest.enabled", 1) /= 0);   --  rest=1 needs the world
   function Grant_Wanted return Boolean is (Rest_Wanted and then Limit ("grant.enabled", 1) /= 0);   --  grant=1 needs rest=1
   function Chess_Wanted return Boolean is (World_Wanted and then Limit ("chess.enabled", 1) /= 0);   --  chess=1 needs the world
   function Screen_Wanted return Boolean is (World_Wanted and then Limit ("screen.enabled", 1) /= 0);   --  screen=1 needs the world

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
      Session_N := (if Sessions.Is_Empty then 0 else Sessions.Last_Element.N);
      if Explicit then
         R := (N => Next_N, Start => Int (Common), Len => Int'Max (0, Ticks - Int (Common)), Votes => V, By_Vote => False,
               Dharma => True, World => World_Wanted, Rest => Rest_Wanted, Grant => Grant_Wanted, Screen => Screen_Wanted, Chess => Chess_Wanted);
         if R.Len > 0 then
            Append_Session (R);
            Start_Life (R);
            Session_N := Next_N;
         end if;
         Kalpa_Line := To_Unbounded_String
           ((if R.Len > 0 then Msg ("kalpa.explicit", Img (Next_N), Yuga (Next_N), Img (R.Len), Votes_Text (V))
             else Msg ("kalpa.none", Votes_Text (V))));
      elsif Last_Ok > 0 and then Sessions (Last_Ok).Start + Sessions (Last_Ok).Len > Int (Common) then
         R := Sessions (Last_Ok);   --  an unfinished session (crash, quit): same target as decided
         Session_N := R.N;
         Ticks := R.Start + R.Len;
         Kalpa_Line := To_Unbounded_String (Msg ("kalpa.resume", Img (R.N), Yuga (R.N), Votes_Text (R.Votes), Img (R.Len), Img (Ticks)));
      else
         R := (N => Next_N, Start => Int (Common), Len => Decided (V), Votes => V, By_Vote => True, Dharma => True,
               World => World_Wanted, Rest => Rest_Wanted, Grant => Grant_Wanted, Screen => Screen_Wanted, Chess => Chess_Wanted);
         Ticks := Int (Common) + R.Len;
         Append_Session (R);
         Start_Life (R);
         Session_N := Next_N;
         Kalpa_Line := To_Unbounded_String (Msg ("kalpa.vote", Img (Next_N), Yuga (Next_N), Votes_Text (V), Img (R.Len)));
      end if;
   end Decide_Session;


   --  ---- Robert's words (diaries/says.txt) and the inbox -------------------------------------------
   --  Control characters, braces and backslashes would break the wording templates: replaced.
   function Clean (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         if C < ' ' or else C = ASCII.DEL then C := ' ';
         elsif C = '{' then C := '(';
         elsif C = '}' then C := ')';
         elsif C = '\' then C := '/';
         end if;
      end loop;
      declare
         T : constant String := Fx.Trim (R, Ada.Strings.Both);
      begin
         return (if T'Length > 200 then T (T'First .. T'First + 199) else T);
      end;
   end Clean;

   function Short (S : String) return String is (if S'Length > 70 then S (S'First .. S'First + 66) & "..." else S);

   --  Reads diaries/says.txt (A lines) and hands them to Sim_Dharma; must follow Sim_Dharma.Init.
   procedure Load_Says is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      if not Ada.Directories.Exists (Says_Path) then return; end if;
      Read_Lines (Says_Path, Lines, Found);
      for I in 1 .. Natural (Lines.Length) loop
         declare
            L : constant String := Lines (I);
            Tp : constant Natural := Fx.Index (L, " text=");
            Kind : constant String := Token (L, "kind");
            To : constant String := Token (L, "to");
            Tick : constant Int := To_Num (Token (L, "tick"));
            OK : Boolean := Tp > 0 and then Tick >= 0;
         begin
            if L'Length > 7 and then L (L'First .. L'First + 6) = "# seed " then
               if L /= "# seed " & Img (Seed) then raise Diary_Error with Msg ("err.session_seed", L (L'First + 7 .. L'Last)); end if;
            elsif L'Length > 0 and then L (L'First) = 'A' then
               if OK then
                  if Kind = "say" and then Sim_Dharma.Find_Wesen (To) > 0 then
                     Sim_Dharma.Add_Address (Tick, Sim_Dharma.Say, Sim_Dharma.Find_Wesen (To), Clean (L (Tp + 6 .. L'Last)));
                  elsif Kind = "all" then
                     Sim_Dharma.Add_Address (Tick, Sim_Dharma.Say_All, 0, Clean (L (Tp + 6 .. L'Last)));
                  elsif Kind = "relay" and then Sim_Dharma.Find_Player (To) > 0 then
                     Sim_Dharma.Add_Address (Tick, Sim_Dharma.Relay, Sim_Dharma.Find_Player (To), Clean (L (Tp + 6 .. L'Last)));
                  elsif Kind = "answer" then
                     Sim_Dharma.Add_Address (Tick, Sim_Dharma.Answer, 0, Clean (L (Tp + 6 .. L'Last)));
                  else
                     OK := False;
                  end if;
               end if;
               if not OK then Warn (Msg ("warn.says_bad", Img (I))); end if;
            end if;
         end;
      end loop;
   end Load_Says;

   --  The stored inbox.txt lines up to tick Upto must be exactly what the replay wrote (any difference
   --  is DRIFT); lines of later ticks are not checked yet.
   procedure Verify_Inbox (Upto : Int) is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      if not Ada.Directories.Exists ("diaries/inbox.txt") then return; end if;
      Read_Lines ("diaries/inbox.txt", Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'I' then
            declare
               Sp : constant Natural := Fx.Index (L, " ");
               Id : constant Int := (if Sp > 2 then To_Num (L (L'First + 1 .. Sp - 1)) else -1);
               Tk : constant Natural := Fx.Index (L, " t", Fx.Index (L, " s", Fx.Index (L, "from=") + 1) + 1);   --  " t<tick>"
               Stop : constant Natural := (if Tk > 0 then Fx.Index (L, " ", Tk + 1) else 0);
               Line_Tick : constant Int := (if Tk > 0 and then Stop > Tk + 2 then To_Num (L (Tk + 2 .. Stop - 1)) else -1);
            begin
               if Line_Tick > Upto then
                  null;   --  written after the point the replay has reached
               elsif Id < 1 or else Id > Int (Sim_Dharma.Inbox_Count) then
                  Inbox_Bad := True;
                  raise Drift_Error with Msg ("err.inbox", Short (L), "(not in the replay)");
               elsif Sim_Dharma.Inbox_Line (Positive (Id)) /= L then
               Inbox_Bad := True;
                  raise Drift_Error with Msg ("err.inbox", "I" & Img (Id), Diff_At (L, Sim_Dharma.Inbox_Line (Positive (Id))));
               end if;
            end;
         end if;
      end loop;
   end Verify_Inbox;

   --  The inbox file as lines (empty when there is none).
   function Inbox_File_Lines return Str_Vectors.Vector is
      Lines, Res : Str_Vectors.Vector;
      Found : Boolean;
   begin
      if Ada.Directories.Exists ("diaries/inbox.txt") then
         Read_Lines ("diaries/inbox.txt", Lines, Found);
         for L of Lines loop if L'Length > 1 and then L (L'First) = 'I' then Res.Append (L); end if; end loop;
      end if;
      return Res;
   end Inbox_File_Lines;

   function Inbox_Page return String is
      V : constant Str_Vectors.Vector := Inbox_File_Lines;
      R : Unbounded_String;
   begin
      if V.Is_Empty then return Msg ("inbox.none") & ASCII.LF & Msg ("inbox.answer") & ASCII.LF; end if;
      Append (R, Msg ("inbox.page", Img (Integer (V.Length))) & ASCII.LF);
      for P in Sim_Dharma.Player_Id loop Append (R, "  " & Msg ("inbox.players", Sim_Dharma.Player_Info (P)) & ASCII.LF); end loop;
      for L of V loop Append (R, L & ASCII.LF); end loop;
      Append (R, Msg ("inbox.answer") & ASCII.LF);
      return To_String (R);
   end Inbox_Page;

   --  Who speaks (--as): letters, digits, _ and -, at most 16, default "player".
   function By_Name (S : String) return String is
      R : String := Fx.Trim (S, Ada.Strings.Both);
   begin
      for C of R loop if C not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' then C := '_'; end if; end loop;
      return (if R = "" then "player" elsif R'Length > 16 then R (R'First .. R'First + 15) else R);
   end By_Name;

   --  make grant PETITION=P<n>: one G line in diaries/grants.txt at the lowest common tick (record-first, no replay);
   --  the next run applies it from the following tick (a grant=1 session; see README).
   procedure Do_Grant is
      Common_T : Natural := Natural'Max (0, 0);
      Seed_D : Int := -1;
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Want : constant String := Fx.Trim (To_String (Grant_Opt), Ada.Strings.Both);
      Num : constant Int := (if Want'Length > 1 and then Ada.Characters.Handling.To_Upper (Want (Want'First)) = 'P' then To_Num_Safe (Want (Want'First + 1 .. Want'Last))
                             elsif Want'Length > 0 then To_Num_Safe (Want) else -1);
      Who : Natural := 0;
      Tick_P : Natural := 0;
      Topic_S : Unbounded_String;
      N_G : Natural := 0;
      F : TIO.File_Type;
   begin
      if not Has_Diaries then raise Usage_Error with Msg ("say.nogame", To_String (Home_Path)); end if;
      if Num <= 0 then raise Usage_Error with Msg ("grant.nowho"); end if;
      Common_T := Natural'Last;
      for E in Entity_Id loop
         declare
            Cnt : Natural := 0;
            Key : constant String := " petition P" & Img (Num) & " (";
         begin
            Lines.Clear;
            Read_Lines (Path (E), Lines, Found);
            for L of Lines loop
               if Complete (L) then
                  Cnt := Cnt + 1;
                  if Seed_D < 0 then Seed_D := Field (L, "seed"); end if;
                  declare
                     K : constant Natural := Fx.Index (L, Key);
                     Close : constant Natural := (if K > 0 then Fx.Index (L, ")", K + Key'Length) else 0);
                  begin
                     if K > 0 and then Close > 0 and then Who = 0 then
                        Who := Positive (E);
                        Tick_P := Cnt;
                        Topic_S := To_Unbounded_String (L (K + Key'Length .. Close - 1));
                     end if;
                  end;
               end if;
            end loop;
            Common_T := Natural'Min (Common_T, Cnt);
         end;
      end loop;
      if Who = 0 or else Tick_P > Common_T then raise Usage_Error with Msg ("grant.nopetition", "P" & Img (Num), Img (Common_T)); end if;
      Seed := Seed_D;
      Seed_Shown := True;
      if Ada.Directories.Exists (Grants_Path) then
         Lines.Clear;
         Read_Lines (Grants_Path, Lines, Found);
         for L of Lines loop
            if L'Length > 1 and then L (L'First) = 'G' then
               N_G := N_G + 1;
               if Token (L, "petition") = "P" & Img (Num) then raise Usage_Error with Msg ("grant.already", "P" & Img (Num), L (L'First .. Fx.Index (L, " ") - 1)); end if;
            end if;
         end loop;
         declare
            Needs_Lf : constant Boolean := not Ends_With_Lf (Grants_Path);
         begin
            TIO.Open (F, TIO.Append_File, Grants_Path);
            if Needs_Lf then TIO.New_Line (F); end if;
         end;
      else
         TIO.Create (F, TIO.Out_File, Grants_Path);
         TIO.Put_Line (F, "# seed " & Img (Seed));
         TIO.Put_Line (F, Msg ("hdr.grants"));
      end if;
      TIO.Put_Line (F, "G" & Img (N_G + 1) & " tick=" & Img (Common_T) & " petition=P" & Img (Num) & " wesen=" & Name (Entity_Id (Who))
                    & " topic=" & To_String (Topic_S) & " by=" & By_Name (To_String (Say_By)));
      TIO.Flush (F);
      TIO.Close (F);
      Con.Put_Line (Msg ("grant.ok", "G" & Img (N_G + 1), "P" & Img (Num), Name (Entity_Id (Who)), To_String (Topic_S), Img (Common_T + 1)));
   exception
      when E : Usage_Error =>   --  nothing is written
         TIO.Put_Line (TIO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (2);
   end Do_Grant;

   --  make say / make answer: one A line in diaries/says.txt at the lowest common tick.  No replay,
   --  nothing else is touched; the next run applies it from the following tick.
   procedure Do_Say is
      Common_T : Natural := Natural'Last;
      Seed_D : Int := -1;
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      To_T : constant String := Internal_Id (Ada.Characters.Handling.To_Lower (Fx.Trim (To_String (Say_To), Ada.Strings.Both)));
      Text : constant String := Clean (To_String (Say_Text));
      By : constant String := By_Name (To_String (Say_By));
      Kind, To_Name, Re : Unbounded_String;
      N_A : Natural := 0;
      Last_S, Last_C : Natural := 0;
      F : TIO.File_Type;
      Players, Wesen : Unbounded_String;
   begin
      if not Has_Diaries then raise Usage_Error with Msg ("say.nogame", To_String (Home_Path)); end if;
      if Text = "" then raise Usage_Error with Msg ("say.empty"); end if;
      for E in Entity_Id loop
         declare
            Cnt : Natural := 0;
         begin
            Lines.Clear;
            Read_Lines (Path (E), Lines, Found);
            for L of Lines loop
               if Complete (L) then
                  Cnt := Cnt + 1;
                  if Seed_D < 0 then Seed_D := Field (L, "seed"); end if;
               end if;
            end loop;
            Common_T := Natural'Min (Common_T, Cnt);
         end;
      end loop;
      Seed := Seed_D;
      Seed_Shown := True;
      Sim_World.Init (Vocab, Seed, Start_Pct);   --  the player names come from data/ (Sim_Dharma.Init)
      Sim_Dharma.Init (Seed);
      for P in Sim_Dharma.Player_Id loop Append (Players, (if Natural (P) = 1 then "" else ", ") & Sim_Dharma.Player_Name (P)); end loop;
      for E in Entity_Id loop Append (Wesen, (if E = 1 then "" else ", ") & Name (E)); end loop;
      Lines.Clear;
      if Ada.Directories.Exists (Sessions_Path) then
         Read_Lines (Sessions_Path, Lines, Found);
         for L of Lines loop
            if L'Length > 1 and then L (L'First) = 'S' and then Fx.Index (L, " ") > 2 then
               Last_S := Natural (Int'Max (0, To_Num (L (L'First + 1 .. Fx.Index (L, " ") - 1))));
            elsif L'Length > 1 and then L (L'First) = 'C' and then Fx.Index (L, " ") > 2 then
               Last_C := Natural (Int'Max (0, To_Num (L (L'First + 1 .. Fx.Index (L, " ") - 1))));
            end if;
         end loop;
      end if;
      if Answer_Mode then
         if Last_C = 0 then raise Usage_Error with Msg ("say.nopetition"); end if;
         Kind := To_Unbounded_String ("answer");
         To_Name := To_Unbounded_String ("all");
         Re := To_Unbounded_String ("C" & Img (Last_C));
      elsif To_T = "" then
         raise Usage_Error with Msg ("say.nowho", To_String (Players), To_String (Wesen));
      elsif To_T = "all" then
         Kind := To_Unbounded_String ("all");
         To_Name := To_Unbounded_String ("all");
         Re := To_Unbounded_String ("-");
      elsif Sim_Dharma.Find_Player (To_T) > 0 then
         Kind := To_Unbounded_String ("relay");
         To_Name := To_Unbounded_String (Sim_Dharma.Player_Name (Sim_Dharma.Player_Id (Sim_Dharma.Find_Player (To_T))));
         Re := To_Unbounded_String ("-");
      elsif Sim_Dharma.Find_Wesen (To_T) > 0 then
         Kind := To_Unbounded_String ("say");
         To_Name := To_Unbounded_String (Name (Entity_Id (Sim_Dharma.Find_Wesen (To_T))));
         Re := To_Unbounded_String ("-");
      else
         raise Usage_Error with Msg ("say.unknown", To_String (Say_To), To_String (Players), To_String (Wesen));
      end if;
      if Ada.Directories.Exists (Says_Path) then
         Lines.Clear;
         Read_Lines (Says_Path, Lines, Found);
         for L of Lines loop if L'Length > 1 and then L (L'First) = 'A' then N_A := N_A + 1; end if; end loop;
         declare
            Needs_Lf : constant Boolean := not Ends_With_Lf (Says_Path);
         begin
            TIO.Open (F, TIO.Append_File, Says_Path);
            if Needs_Lf then TIO.New_Line (F); end if;
         end;
      else
         TIO.Create (F, TIO.Out_File, Says_Path);
         TIO.Put_Line (F, "# seed " & Img (Seed));
         TIO.Put_Line (F, Msg ("hdr.says"));
      end if;
      TIO.Put_Line (F, "A" & Img (N_A + 1) & " tick=" & Img (Common_T) & " session=" & Img (Last_S) & " to=" & To_String (To_Name)
                    & " kind=" & To_String (Kind) & " by=" & By & " re=" & To_String (Re) & " text=" & Text);
      TIO.Flush (F);
      TIO.Close (F);
      Con.Put_Line (Msg ("say.ok", "A" & Img (N_A + 1), To_String (To_Name), To_String (Kind) & (if To_String (Re) /= "-" then " re " & To_String (Re) else ""),
                         Img (Common_T + 1)));
   exception
      when E : Usage_Error =>   --  nothing is written, debug.txt is left alone
         TIO.Put_Line (TIO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (2);
   end Do_Say;

   --  An expected stop (drift at import, bad diary): a few plain lines, debug.txt DRIFT, exit 1.
   --  No traceback and no last_error.txt: this is not a crash.
   procedure Validation_Stop (Message : String; Drift : Boolean) is
      Built : constant String :=
        (if Length (Disk_Build) > 0 and then To_String (Disk_Build) /= Build
         then Msg ("drift.build", To_String (Disk_Build), Build) else "");
   begin
      if not Import_Done then Con.Put_Line (Msg ("import.failed", Message)); else Con.Put_Line (Message); end if;
      if Drift then
         Con.Put_Line (Msg ("drift.cause", Built));
         Con.Put_Line (Msg ("drift.fix"));
      end if;
      if Import_Done then Write_Petitions; end if;
      Write_Debug ("DRIFT", "error: " & Message & (if Built'Length > 0 then ASCII.LF & Msg ("drift.cause", Built) else ""));
      Con.Put_Line (Msg ("debug.attach"));
      Put_Saved;
      Ada.Command_Line.Set_Exit_Status (1);
   end Validation_Stop;


   --  The block after a session: what changed since the loaded diaries (the session start).
   function Since_Text return String is
      New_Ticks : constant Int := Int'Max (0, Ticks - Int (Common));
      Res : Unbounded_String;
   begin
      if New_Ticks = 0 then return Msg ("since.none", Img (Session_N), Img (Ticks)) & ASCII.LF; end if;
      Res := To_Unbounded_String (Msg ("since.head", Img (Session_N), Yuga (Positive'Max (1, Session_N)), Img (Common),
                                       Img (Ticks), Img (New_Ticks)) & ASCII.LF);
      for E in Entity_Id loop
         declare
            Coined_All, Best_Loc : Natural := 0;
            Best : Int := Int'First;
         begin
            for W in Base_Count + 1 .. Count loop
               if Coined_By (W) = Name (E) then Coined_All := Coined_All + 1; end if;
            end loop;
            for L in 0 .. 3 loop   --  favourite place of this session: vote of the new ticks only
               declare
                  A : Loc_Stats renames Votes_Of (E) (L);
                  B : Loc_Stats renames Snap_Votes (E) (L);
                  D : constant Loc_Stats := (A.N - B.N, A.Mood - B.Mood, A.Energy - B.Energy, A.Learned - B.Learned,
                                             A.Coined - B.Coined, A.Benches - B.Benches);
               begin
                  if D.N > 0 and then Vote (D) > Best then Best := Vote (D); Best_Loc := L; end if;
               end;
            end loop;
            Append (Res, Fx.Head (Name (E), 9)
                    & Msg ("since.words", Img (Known_Count (E)), Img (Known_Count (E) - Start_Known (E)), Img (Run_Learn (E)),
                           Img (Act_Count (E, Learn)), Img (Run_Coin (E)), Img (Coined_All))
                    & (if World_Active then " | " & Msg ("since.world", Img (World_Learned (E) - Start_World (E)), Img (World_Learned (E))) else "")
                    & " | " & Msg ("since.pet", Img (Petitions_Of (E) - Snap_Pet (E)), Img (Petitions_Of (E)))
                    & " | " & Msg ("since.state", Sgn (Int (Snap_Mood (E))), Sgn (Int (St (E).Mood)), Img (Snap_Energy (E)),
                                   Img (St (E).Energy), Msg ("loc." & Img (Best_Loc))) & ASCII.LF);
         end;
      end loop;
      return To_String (Res);
   end Since_Text;

   --  --preview (make demo): 200 ticks of a new world in memory, a few excerpts on screen,
   --  nothing on disk (no diaries/, entities/, debug.txt, reports, petitions.txt).
   procedure Run_Preview is
      Total : constant Int := (if Ticks >= 0 then Ticks else 200);
      Console, Text, Json : Unbounded_String;
      Shown : Natural;
      function Teacher (E : Entity_Id; W : Positive) return String is
         O : constant String := Origin (E, W);
      begin
         return (if O'Length > 10 and then O (O'First .. O'First + 9) = "taught by " then O (O'First + 10 .. O'Last) else "");
      end Teacher;
      function Cut (S : String; N : Positive) return String is
        (if S'Length > N then S (S'First .. S'First + N - 4) & "..." else S);
      --  "t":"talk","text":"..." of a diary line, as: tick action: text
      function Brief (E : Entity_Id; T : Int) return String is
         L : constant String := Sample (E).Element (Positive (T));
         Ta : constant Natural := Fx.Index (L, """t"":""");
         Tx : constant Natural := Fx.Index (L, """text"":""");
         Te : constant Natural := Fx.Index (L, """,""state""");
      begin
         if Ta = 0 or else Tx = 0 or else Te < Tx + 8 then return Cut (L, 90); end if;
         return Fx.Head (Name (E), 8) & Fx.Tail (Img (T), 4) & " "
           & L (Ta + 5 .. Fx.Index (L, """", Ta + 5) - 1) & ": " & Cut (L (Tx + 8 .. Te - 1), 80);
      end Brief;
   begin
      Ticks := Total;
      Seed := (if Seed_Opt >= 0 then Seed_Opt else 42);
      Seed_Shown := True;
      Sim_World.Init (Vocab, Seed, Start_Pct);
      Sim_Dharma.Init (Seed);
      Sim_Things.Init (Seed);
      Sim_Screen.Init (Seed, Coin_Cap);
      Sim_Games.Init (Seed);
      World_Active := World_Wanted;
      Rest_Active := Rest_Wanted;
      Grant_Active := Grant_Wanted;
      Screen_Active := Screen_Wanted;
      Chess_Active := Chess_Wanted;
      if Rest_Active then Rest_Begin (Seed); end if;
      Con.Put (To_String (Pending));
      Con.Put_Line (Msg ("preview.head", Img (Seed), Img (Total)));
      declare
         V : constant Kalpa_Votes := Votes_At (0);   --  what a bare first session would be
      begin
         Con.Put_Line (Msg ("preview.kalpa", Msg ("kalpa.vote", "1", Yuga (1), Votes_Text (V), Img (Decided (V)))));
      end;
      for Tick in Int range 1 .. Total loop Do_Tick (Tick); end loop;
      for E in Entity_Id loop
         for K in 1 .. 2 loop
            declare
               T : constant Int := (if K = 1 then Int'Max (1, Total / 2) else Total);
            begin
               if T >= 1 and then T <= Total and then (K = 2 or else T < Total) then Con.Put_Line (Brief (E, T)); end if;
            end;
         end loop;
      end loop;
      for N in 1 .. Integer'Min (2, Petition_Total) loop Con.Put_Line (Cut (Petition_Line (N), 110)); end loop;
      declare
         Known_Text, Coined_Text, Taught_Text : Unbounded_String;
      begin
         for E in Entity_Id loop
            Append (Known_Text, (if E = 1 then "" else " | ") & Name (E) & " " & Img (Known_Count (E)));
         end loop;
         Shown := 0;
         for W in Base_Count + 1 .. Count loop
            exit when Shown = 3;
            if Coined_By (W) /= "" then
               Append (Coined_Text, (if Shown = 0 then "" else " | ") & Word (W) & " (" & Parents (W) & ", " & Coined_By (W) & ")");
               Shown := Shown + 1;
            end if;
         end loop;
         Shown := 0;
         for E in Entity_Id loop
            for W in 1 .. Count loop
               if Knows (E, W) and then Teacher (E, W) /= "" and then Shown < 3 then
                  Append (Taught_Text, (if Shown = 0 then "" else " | ") & Word (W) & " " & Teacher (E, W) & ">" & Name (E));
                  Shown := Shown + 1;
                  exit;
               end if;
            end loop;
         end loop;
         Con.Put_Line (Msg ("preview.words", To_String (Known_Text), To_String (Coined_Text), To_String (Taught_Text)));
         if World_Active then
            for L of Sim_Things.Treadmill_Now loop Con.Put_Line (L); end loop;
         end if;
      end;
      Summarize (Seed, Total, Votes_Of, Console, Text, Json);
      Con.Put (To_String (Console));
      Con.Put_Line (Msg ("preview.foot"));
      Write_Digest ("OK", "");   --  only with --debug: the one file a preview ever writes
      if Length (Digest_Note) > 0 then Con.Put_Line (To_String (Digest_Note)); end if;
   end Run_Preview;


   --  Sessions on disk and the lowest common tick (what "continuing" starts from); read-only.
   procedure Save_Counts (Sessions_N, Ticks : out Natural) is
      Lines, Ent : Str_Vectors.Vector;
      Found : Boolean;
      R : Session_Rec;
      OK : Boolean;
   begin
      Sessions_N := 0;
      Ticks := 0;
      if not Has_Diaries then return; end if;
      Read_Lines (Sessions_Path, Lines, Found);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) = 'S' then
            Parse_Session (L, R, OK);
            if OK then Sessions_N := Sessions_N + 1; end if;
         end if;
      end loop;
      for E in Entity_Id loop
         Ent.Clear;
         Read_Lines (Path (E), Ent, Found);
         Ticks := (if E = 1 then Natural (Ent.Length) else Natural'Min (Ticks, Natural (Ent.Length)));
      end loop;
   end Save_Counts;

   --  The second line of the run header (the first one is "Save folder: ..."): what is there.
   function Start_Line return String is
      N, T : Natural;
   begin
      Save_Counts (N, T);
      if Fresh and then Has_Diaries then return Msg ("start.fresh", Img (N), Img (T)); end if;
      if Has_Diaries then return Msg ((if N = 1 then "start.found1" else "start.found"), Img (N), Img (T)); end if;
      if Yes or else Fresh then return Msg ("start.none"); end if;
      if Is_Tty (0) and then Is_Tty (1) then return Msg ("start.none.ask"); end if;
      return Msg ((if Explicit then "start.none" else "start.none.stop"));
   end Start_Line;

   --  ---- make map / --map: the treadmill windows of the last saved session end (read-only) -----------
   --  Seed and the last L line come from diaries/sessions.txt, the edits (up to that tick) from
   --  diaries/world.txt; nothing is replayed and nothing is written.
   Map_Mode : Boolean := False;

   --  "3,-4" after the '@' of an L-line token; False when it is not of that form.
   procedure Parse_At (Tok : String; X, Y : out Integer; OK : out Boolean) is
      At_P : constant Natural := Fx.Index (Tok, "@");
      Cm : constant Natural := Fx.Index (Tok, ",");
   begin
      X := 0;
      Y := 0;
      OK := At_P > 0 and then Cm > At_P + 1 and then Cm < Tok'Last;
      if OK then
         X := Integer'Value (Tok (At_P + 1 .. Cm - 1));
         Y := Integer'Value (Tok (Cm + 1 .. Tok'Last));
      end if;
   exception
      when Constraint_Error => OK := False;
   end Parse_At;

   procedure Do_Map is
      Lines : Str_Vectors.Vector;
      Found, OK : Boolean;
      Map_Seed : Int := 42;
      Last_L : Unbounded_String;
      PXs, PYs : Sim_Things.Pos_Array := [others => 0];
      Pres : Sim_Things.Placed_Array := [others => False];
      L_Tick : Int := 0;
   begin
      if Ada.Directories.Exists (Sessions_Path) then
         Read_Lines (Sessions_Path, Lines, Found);
         for L of Lines loop
            if L'Length > 7 and then L (L'First .. L'First + 6) = "# seed " then
               Map_Seed := To_Num (L (L'First + 7 .. L'Last));
            elsif L'Length > 1 and then L (L'First) = 'L' and then To_Num (Token (L, "tick")) >= 0 then
               Last_L := To_Unbounded_String (L);
            end if;
         end loop;
      end if;
      if Length (Last_L) = 0 then
         Con.Put_Line (Msg ("map.none"));
         return;
      end if;
      Sim_Things.Init (Int'Max (0, Map_Seed));
      L_Tick := To_Num (Token (To_String (Last_L), "tick"));
      if Ada.Directories.Exists (World_Path) then
         Lines.Clear;
         Read_Lines (World_Path, Lines, Found);
         for L of Lines loop
            if L'Length > 0 and then L (L'First) = 'X' and then To_Num (Token (L, "t")) in 0 .. L_Tick then
               Sim_Things.Apply_Line (L, OK);
            end if;
         end loop;
      end if;
      for E in Entity_Id loop
         Parse_At (Token (To_String (Last_L), Name (E)), PXs (E), PYs (E), OK);
         Pres (E) := OK;
      end loop;
      Con.Put_Line (Msg ("map.head", Img (L_Tick)));
      for L of Sim_Things.Treadmill (PXs, PYs, Pres) loop Con.Put_Line (L); end loop;
   end Do_Map;

   --  ---- the main menu (terminal only) -------------------------------------------------------
   --  What the menu shows under the tagline (at most six short lines, so that the large title fits
   --  into 80x24): the save folder; sessions, ticks and the last favourite-word vote with who
   --  taught or coined each word; karma; the last petition and the inbox.  Read-only.
   function Game_Info_Raw return Str_Vectors.Vector is
      Res, Lines : Str_Vectors.Vector;
      Found : Boolean;
      Last : Word_Vote;
      Have : Boolean := False;
      V : Word_Vote;
      OK : Boolean;
      Karma_Of : array (Entity_Id) of Unbounded_String;
      Have_D : Boolean := False;
      Pet, World_L : Unbounded_String;
      Sessions_N, Ticks : Natural;
      function Shown (E : Entity_Id) return String is
         T  : constant String := To_String (Last.Tok (E));
         Sl : constant Natural := Fx.Index (T, "/");
         Origin_Text : String := (if Sl > 0 then T (Sl + 1 .. T'Last) else "start");
      begin
         for C of Origin_Text loop if C = '-' then C := ' '; end if; end loop;
         return Fx.Head (Name (E), 8) & (if Sl > 0 then T (T'First .. Sl - 1) else T)
           & (if Origin_Text = "start" or else Sl = 0 then "" else " (" & Origin_Text & ")");
      end Shown;
   begin
      Res.Append (Msg ("menu.save", To_String (Home_Path)));
      if not Has_Diaries then
         Res.Append (Msg ("menu.nogame"));
         return Res;
      end if;
      Save_Counts (Sessions_N, Ticks);
      Read_Lines (Sessions_Path, Lines, Found);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) = 'W' then
            Parse_Word_Vote (L, V, OK);
            if OK then Last := V; Have := True; end if;
         elsif L'Length > 0 and then L (L'First) = 'D' and then Sim_Dharma.Find_Wesen (Token (L, "wesen")) > 0 then
            Karma_Of (Entity_Id (Sim_Dharma.Find_Wesen (Token (L, "wesen")))) := To_Unbounded_String (Token (L, "karma"));
            Have_D := True;
         elsif L'Length > 0 and then L (L'First) = 'L' and then To_Num (Token (L, "tick")) >= 0 then
            World_L := To_Unbounded_String (L);
         elsif L'Length > 0 and then L (L'First) = 'C' then
            Pet := To_Unbounded_String (L (L'First .. Fx.Index (L, " ") - 1) & " " & Token (L, "win"));
         end if;
      end loop;
      if Have then
         Res.Append (Msg ("menu.game.vote", Img (Sessions_N), Img (Ticks), Img (Last.N), Img (Last.Tick)));
         Res.Append (Fx.Head (Shown (1), 38) & Shown (2));
         Res.Append (Fx.Head (Shown (3), 38) & Shown (4));
      else
         Res.Append (Msg ("menu.game.novote", Img (Sessions_N), Img (Ticks)));
      end if;
      if Have_D then
         declare
            K : Unbounded_String;
         begin
            for E in Entity_Id loop Append (K, (if E = 1 then "" else " | ") & Name (E) & " " & To_String (Karma_Of (E))); end loop;
            Res.Append (Msg ("menu.dharma", To_String (K)));
         end;
      end if;
      if Ada.Directories.Exists (Chess_Path) then   --  chess: the newest rating of every competitor in diaries/chess.txt, best four
         declare
            CL : Str_Vectors.Vector;
            Cf : Boolean;
            Rate : array (Sim_Games.Comp_Id) of Natural := [others => 0];
            Line_E : Unbounded_String;
            Shown_N : Natural := 0;
         begin
            Read_Lines (Chess_Path, CL, Cf);
            for L of CL loop
               declare
                  P : constant Natural := Fx.Index (L, " elo ");
               begin
                  if P > 0 and then Fx.Index (L, " end ") > 0 then
                     for C in Sim_Games.Comp_Id loop
                        declare
                           Key : constant String := " " & Sim_Games.Comp_Name (C) & "=";
                           Q : constant Natural := Fx.Index (L (P .. L'Last), Key);
                           G : constant Natural := (if Q > 0 then Fx.Index (L (Q .. L'Last), ">") else 0);
                           Z : Natural := G + 1;
                        begin
                           while G > 0 and then Z <= L'Last and then L (Z) in '0' .. '9' loop Z := Z + 1; end loop;
                           if G > 0 and then Z > G + 1 then Rate (C) := Natural (Int'Max (0, To_Num_Safe (L (G + 1 .. Z - 1)))); end if;
                        end;
                     end loop;
                  end if;
               end;
            end loop;
            for Place in 1 .. 4 loop
               declare
                  Best : Natural := 0;
               begin
                  for C in Sim_Games.Comp_Id loop
                     if Rate (C) > 0 and then (Best = 0 or else Rate (C) > Rate (Best)) then Best := C; end if;
                  end loop;
                  if Best > 0 then
                     Append (Line_E, (if Shown_N = 0 then "" else " | ") & Sim_Games.Comp_Name (Best) & " " & Img (Rate (Best)));
                     Shown_N := Shown_N + 1;
                     Rate (Best) := 0;
                  end if;
               end;
            end loop;
            if Shown_N > 0 then Res.Append (Msg ("menu.elo", To_String (Line_E))); end if;
         end;
      end if;
      if Length (World_L) > 0 then   --  words learned in the world and where the wesen stood at the last session end
         declare
            Learned, Places : Unbounded_String;
            X, Y : Integer;
            Good : Boolean;
         begin
            Sim_Things.Init (0);   --  only the landmarks are needed
            for E in Entity_Id loop
               declare
                  T : constant String := Token (To_String (World_L), Name (E));
                  S1 : constant Natural := Fx.Index (T, "/");
                  S2 : constant Natural := (if S1 > 0 then Fx.Index (T, "/", S1 + 1) else 0);
               begin
                  Append (Learned, (if E = 1 then "" else " | ") & Name (E) & " " & (if S2 > S1 then T (S1 + 1 .. S2 - 1) else "?"));
                  Parse_At (T, X, Y, Good);
                  Append (Places, (if E = 1 then "" else " | ") & Name (E) & " " & (if Good then Msg ("loc." & Img (Sim_Things.Region (X, Y))) else "?"));
               end;
            end loop;
            Res.Append (Msg ("menu.world", To_String (Learned)));
            Res.Append (Msg ("menu.places", To_String (Places)));
         end;
      end if;
      declare
         Box : constant Str_Vectors.Vector := Inbox_File_Lines;
      begin
         if Length (Pet) > 0 or else not Box.Is_Empty then
            Res.Append (Msg ("menu.last", (if Length (Pet) > 0 then To_String (Pet) else "-"), Img (Integer (Box.Length))));
         end if;
      end;
      return Res;
   end Game_Info_Raw;

   function Game_Info return Str_Vectors.Vector is   --  the same lines with display names
      Res : Str_Vectors.Vector;
   begin
      for L of Game_Info_Raw loop Res.Append (Sim_World.Show (L)); end loop;
      return Res;
   end Game_Info;

   --  Intro, menu loop.  New Game on an existing game asks before it is moved aside (--fresh
   --  does that, never a delete); Load Game goes on with the normal load / vote flow.
   procedure Menu_Loop (Quit_Now : out Boolean) is
      Seed_V : Int := Seed_Opt;
      Every_V : Int := Every;
   begin
      Quit_Now := False;
      Sim_Menu.Intro (Natural (if Seed_Opt >= 0 then Seed_Opt else 42), Game_Info);
      loop
         case Sim_Menu.Ask (Game_Info, (if Has_Diaries then Sim_Menu.Load_Game else Sim_Menu.New_Game)) is
            when Sim_Menu.Quit =>
               Quit_Now := True;
               exit;
            when Sim_Menu.Load_Game =>
               exit;
            when Sim_Menu.New_Game =>
               if not Has_Diaries then
                  Yes := True;
                  exit;
               elsif Ask_Yes (Msg ("menu.confirm_move", Ada.Directories.Full_Name ("diaries"))) then
                  Fresh := True;
                  Con.Put_Line (Msg ("menu.moved"));
                  exit;
               end if;
            when Sim_Menu.Inbox =>
               Con.Put (Inbox_Page & Msg ("menu.inbox.back") & " ");
               TIO.Flush;
               begin
                  TIO.Skip_Line;
               exception
                  when TIO.End_Error => null;
               end;
            when Sim_Menu.Settings =>
               Sim_Menu.Edit_Settings (Seed_V, Every_V);
         end case;
      end loop;
      Seed_Opt := Seed_V;
      Every := Every_V;
      Read_Limits;   --  the Settings menu may have changed them
   end Menu_Loop;

begin
   Load_Data;
   while I <= Ada.Command_Line.Argument_Count loop
      declare
         A   : constant String := Ada.Command_Line.Argument (I);
         Eq  : constant Natural := Fx.Index (A, "=");
         Opt : constant String := (if Eq > 0 then A (A'First .. Eq - 1) else A);
         Num : constant Boolean := Opt in "--ticks" | "--seed" | "--every" | "--crash-at" | "--more";
         Sep : constant Boolean := (Num or else Opt in "--home" | "--say" | "--text" | "--as" | "--grant" | "--debug-section") and then Eq = 0 and then I < Ada.Command_Line.Argument_Count;   --  --ticks 200
         Val : constant String := (if Eq > 0 then A (Eq + 1 .. A'Last) elsif Sep then Ada.Command_Line.Argument (I + 1) else "");
         Help  : Str_Vectors.Vector;
         Found : Boolean;
      begin
         if Sep then I := I + 1; end if;
         if Opt = "--help" or else Opt = "-h" then
            Read_Lines (Data_Path ("help.txt"), Help, Found);
            for L of Help loop Con.Put_Line (L); end loop;
            if not Found then Con.Put_Line ("diary_sim: data/help.txt not found (--ticks --seed --every --fresh --crash-at)"); end if;
            return;
         elsif Opt = "--fresh" then Fresh := True;
         elsif Opt = "--yes" then Yes := True;
         elsif Opt = "--home" then Home_Opt := To_Unbounded_String (Val);
         elsif Opt = "--preview" then Preview := True;
         elsif Opt = "--say" then Say_Mode := True; Say_To := To_Unbounded_String (Val);
         elsif Opt = "--text" then Say_Text := To_Unbounded_String (Val);
         elsif Opt = "--as" then Say_By := To_Unbounded_String (Val);
         elsif Opt = "--answer" then Answer_Mode := True;
         elsif Opt = "--inbox" then Inbox_Mode := True;
         elsif Opt = "--map" then Map_Mode := True;
         elsif Opt = "--grant" then Grant_Mode := True; Grant_Opt := To_Unbounded_String (Val);
         elsif Opt = "--perft" then Perft_Mode := True;
         elsif Opt = "--elo" then Ledger_Mode := True; Elo_View := True;
         elsif Opt = "--screens" then Ledger_Mode := True; Screens_View := True;
         elsif Opt = "--ledger" then
            Ledger_Mode := True;
            Ledger_Full := Val = "full";
            if Val /= "" and then Val /= "full" then raise Usage_Error with Msg ("err.option", A); end if;
         elsif Opt = "--menu" then Menu_Opt := True;
         elsif Opt = "--debug" then Debug_On := True;
         elsif Opt = "--debug-section" then
            Section_Opt := To_Unbounded_String (Val);
            Debug_On := True;
            if Fx.Index (" " & Sections & " ", " " & Val & " ") = 0 then raise Usage_Error with Msg ("digest.nosection", Val, Sections); end if;
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
   if Preview and then (Fresh or else Yes or else More >= 0 or else Crash_At >= 0) then
      raise Usage_Error with Msg ("err.preview");
   end if;
   if Perft_Mode then
      Do_Perft;
      return;
   end if;
   if Preview then
      Run_Preview;
      return;
   end if;
   Menu_Wanted := Menu_Opt or else (Ada.Command_Line.Argument_Count = 0 and then Is_Tty (0) and then Is_Tty (1));
   if Menu_Opt and then not (Is_Tty (0) and then Is_Tty (1)) then raise Usage_Error with Msg ("err.menu_tty"); end if;
   Resolve_Home (Header => not (Menu_Wanted or else Inbox_Mode or else Map_Mode or else Ledger_Mode or else Grant_Mode or else Say_Mode or else Answer_Mode or else (Length (Section_Opt) > 0 and then not Preview)));
   Saved_Line := To_Unbounded_String (Msg ("saved", To_String (Home_Path)));
   if Map_Mode then
      Do_Map;
      Con.Put_Line (To_String (Saved_Line));
      return;
   elsif Inbox_Mode then
      Con.Put (Inbox_Page);
      Con.Put_Line (To_String (Saved_Line));
      return;
   elsif Grant_Mode then
      Do_Grant;
      Con.Put_Line (To_String (Saved_Line));
      return;
   elsif Say_Mode or else Answer_Mode then
      Do_Say;
      Con.Put_Line (To_String (Saved_Line));
      return;
   elsif Length (Section_Opt) > 0 then
      Print_Section (To_String (Section_Opt));
      return;
   end if;
   if Menu_Wanted then
      declare
         Quit_Now : Boolean;
      begin
         Menu_Loop (Quit_Now);
         if Quit_Now then
            Con.Put_Line (To_String (Saved_Line));
            return;   --  exit 0
         end if;
      end;
   end if;

   if not Ledger_Mode then Con.Put_Line (Start_Line); end if;   --  header line 2 (line 1 is Save folder:, printed first; the menu shows it itself)
   TIO.Flush;
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
   if Ledger_Mode and then not Has_Diaries then
      Con.Put_Line (Msg ("ledger.nosave", To_String (Home_Path)));
      return;
   end if;
   if not Fresh and then not Yes and then not Has_Diaries then
      if Is_Tty (0) and then Is_Tty (1) then
         if Confirm_New then
            Con.Put_Line (Msg ("ask.yes", Img (if Seed_Opt >= 0 then Seed_Opt else 42)));
         else
            Con.Put_Line (Msg ("ask.hint"));
            Con.Put_Line (Msg ("ask.cancelled"));
            return;   --  exit 0, nothing written
         end if;
      elsif not Explicit then   --  no terminal to ask (script, pipe): an explicit length means go on, else stop
         Con.Put_Line (Msg ("ask.noterminal", Ada.Directories.Full_Name ("diaries")));
         Ada.Command_Line.Set_Exit_Status (2);
         return;
      end if;
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
   if More >= 0 then Ticks := Int (Common) + More; end if;   --  --more N: N new ticks after the lowest common tick

   Seed := (if Disk_Seed >= 0 then Disk_Seed elsif Seed_Opt >= 0 then Seed_Opt else 42);
   if not Ledger_Mode then
      Con.Put_Line (Msg ("seed", Img (Seed), Msg (if Disk_Seed >= 0 then "seed.disk" elsif Seed_Opt >= 0 then "seed.option"
                                                   else "seed.default")));
   end if;
   Seed_Shown := True;
   Con.Put (To_String (Pending));
   if Disk_Seed >= 0 and then Seed_Opt >= 0 and then Seed_Opt /= Disk_Seed then
      Warn (Msg ("warn.seed_ignored", Img (Seed_Opt), Img (Disk_Seed)));
   end if;
   if not Ledger_Mode then Con.Put_Line (Msg ("entities", To_String (Names))); end if;
   for E in Entity_Id loop
      if Natural (Disk (E).Length) < Longest then
         Warn (Msg ("warn.behind", Name (E), Img (Integer (Disk (E).Length)), Img (Longest), Img (Common)));
      end if;
   end loop;

   --  Every run starts from the vocabulary and replays from tick 1.
   Sim_World.Init (Vocab, Seed, Start_Pct);
   Sim_Dharma.Init (Seed);
   Sim_Things.Init (Seed);
   Sim_Screen.Init (Seed, Coin_Cap);
   Sim_Games.Init (Seed);
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
   Load_Says;
   Load_World_File;
   Load_Grants;
   Sim_Store.Open (Screen_Store, Screens_Path, "# seed " & Img (Seed));
   Screen_N := 0;
   Sim_Store.Open (Chess_Store, Chess_Path, "# seed " & Img (Seed));
   Chess_N := 0;
   Set_Ledger_From;
   if not Ledger_Mode then Write_Debug ("RUN", ""); end if;   --  stub: a kill -9 still leaves a file

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
         if not Ledger_Mode then Con.Put_Line (To_String (Import_Block)); end if;
      end;
      if Ledger_Mode then   --  replayed and verified, nothing decided, nothing written: print the ledger
         for F of Out_File loop TIO.Close (F); end loop;
         for F of Side_Out loop TIO.Close (F); end loop;
         if Elo_View then Con.Put (Elo_Text); elsif Screens_View then Con.Put (Screens_Text); else Con.Put_Line (Sim_Ledger.Report (Seed, Ledger_From, Ledger_Full)); end if;
         return;
      end if;
      for E in Entity_Id loop
         Start_Known (E) := Known_Count (E);
         Start_World (E) := World_Learned (E);
         Snap_Mood (E) := St (E).Mood;
         Snap_Energy (E) := St (E).Energy;
         Snap_Pet (E) := Petitions_Of (E);
      end loop;
      Snap_Votes := Votes_Of;
      Sim_Dharma.Mark_Start;
      Verify_Inbox (Int (Verify_To));
      Verify_Edits (Int (Verify_To));
      Decide_Session;
      Set_Ledger_From;
      Con.Put_Line (To_String (Kalpa_Line));
   end if;

   --  Phase 2: the rest of the run (ticks beyond the common tick are appended where missing).
   if not Quit_Seen then
      for Tick in Int range Int (Verify_To) + 1 .. Ticks loop
         Do_Tick (Tick);
         Check_Dharma_At (Tick);   --  a stored session end beyond the common tick (a diary was behind)
         if Tick > Int (Common) and then Tick mod Every = 0 then
            Con.Put_Line (Msg ("progress", Img (Tick), Img (Ticks), Img (Integer (Entity_Id'Last)), Img (Events)));
            Write_Debug ("RUN", "");   --  refresh the stub
         end if;
         Quit_Seen := Sim_Quit.Requested;
         exit when Quit_Seen;
      end loop;
   end if;
   if not Quit_Seen and then Ticks > Int (Common)
     and then not (for some R of Word_Votes => R.Tick = Ticks)
   then
      Record_Word_Vote (Ticks);
   end if;
   for F of Out_File loop TIO.Close (F); end loop;
   for F of Side_Out loop TIO.Close (F); end loop;
   if not Quit_Seen then
      Verify_Inbox (Last_Done);
      Verify_Edits (Last_Done);
      Verify_Grants (Last_Done);
      Verify_Screens (Last_Done);
      Verify_Chess (Last_Done);
   end if;
   if Quit_Seen then   --  Ctrl-C / SIGTERM: everything written so far is flushed; a rerun resumes
      Con.Put_Line (Msg ("quit", Sim_Quit.Which, Img (Last_Done)));
      Write_Petitions;
      Write_Debug ("QUIT", Msg ("debug.quit", Sim_Quit.Which, Img (Last_Done)));
      Con.Put_Line (Msg ("debug.attach"));
      Put_Saved;
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
         TIO.Put (F, Sim_World.Show (To_String (Content)));
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
      Since_Head := To_Unbounded_String (Since_Text);
      Append (Rep, Since_Head);
      if World_Active then   --  the treadmill: where the wesen are and what lies around them
         Append (Rep, Msg ("map.head", Img (Ticks)) & ASCII.LF);
         for L of Sim_Things.Treadmill_Now loop Append (Rep, L & ASCII.LF); end loop;
      end if;
      if Rest_Active then   --  recovery: rate, cool-downs taken, rests cut short
         Append (Rep, Msg ("rest.head") & ASCII.LF);
         for E in Entity_Id loop Append (Rep, Rest_Text (E) & ASCII.LF); end loop;
      end if;
      if Screen_Active then   --  the screens: shown / left / read, and the words they taught and coined
         Append (Rep, Msg ("screen.rep") & ASCII.LF);
         for E in Entity_Id loop Append (Rep, Sim_Screen.Summary (E) & ASCII.LF); end loop;
      end if;
      if Chess_Active then   --  chess: ratings and results per competitor, then every game with its moves
         Append (Rep, Msg ("chess.rep") & ASCII.LF);
         for C in Sim_Games.Comp_Id loop Append (Rep, Sim_Games.Summary (C) & ASCII.LF); end loop;
         Append (Rep, Msg ("chess.head") & ASCII.LF);
         for L of Sim_Games.Report (True) loop Append (Rep, L & ASCII.LF); end loop;
      end if;
      if not Grant_Report.Is_Empty then   --  granted petitions and the recovery rates they changed
         Append (Rep, Msg ("grant.head") & ASCII.LF);
         for L of Grant_Report loop Append (Rep, L & ASCII.LF); end loop;
      end if;
      if Length (Words_Text) > 0 then Append (Rep, To_String (Words_Text) & ASCII.LF); end if;
      for L of Sim_Dharma.Table_Lines loop Append (Rep, L & ASCII.LF); end loop;
      for L of Sim_Dharma.Since_Lines loop Append (Rep, L & ASCII.LF); end loop;
      if not Sim_Dharma.Table_Lines.Is_Empty then
         Append (Rep, Msg ("since.players", Sim_Dharma.Address_Counts (Int (Common))) & ASCII.LF);
      end if;
      if not Sim_Dharma.Latest_Report.Is_Empty then
         Append (Rep, Msg ("inbox.head", Img (Integer (Sim_Dharma.Latest_Report.Length)), Img (Sim_Dharma.Inbox_Count)) & ASCII.LF);
         for L of Sim_Dharma.Latest_Report loop Append (Rep, L & ASCII.LF); end loop;
         Append (Rep, Msg ("inbox.answer") & ASCII.LF);
      end if;
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
      Save ("run_report.txt", Import_Block & ASCII.LF & Kalpa_Line & ASCII.LF & Rep & Console & Sim_Ledger.Report (Seed, Ledger_From, True) & ASCII.LF);
      if not Ada.Directories.Exists ("run_report.txt") or else Ada.Directories.Size ("run_report.txt") = 0 then
         Append (Rep, Msg ("export.failed", "run_report.txt not written") & ASCII.LF);
         Ada.Command_Line.Set_Exit_Status (1);
      end if;
      Write_Petitions;
      Write_Debug ((if Length (Fails) = 0 then "OK" else "DRIFT"), (if Length (Fails) = 0 then "" else "error: " & To_String (Export_Line)));
      Con.Put (To_String (Rep));
      Con.Put (To_String (Console));
      Con.Put_Line (Msg ("debug.attach"));
      Con.Put_Line (Msg ("pet.file", Img (Integer'Min (Petition_Total, Integer (Limit ("propose.file_cap", 40)))),
                         Img (Petition_Total), Ada.Directories.Full_Name ("petitions.txt")));
      Con.Put_Line (Msg ("pet.attach"));
      Put_Saved;
   end;
exception
   when E : Usage_Error =>
      TIO.Put_Line (TIO.Standard_Error, Ada.Exceptions.Exception_Message (E));
      Write_Debug ("USAGE", "error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (2);
   when E : Drift_Error =>   --  stored lines differ from the replay: an expected stop, no traceback
      Validation_Stop (Ada.Exceptions.Exception_Message (E), True);
   when E : Diary_Error =>   --  bad diary, seed mismatch, misplaced folder: also an expected stop
      Validation_Stop (Ada.Exceptions.Exception_Message (E), False);
   when E : others =>
      if not Import_Done then Con.Put_Line (Msg ("import.failed", Ada.Exceptions.Exception_Message (E))); end if;
      if Import_Done then Write_Petitions; end if;
      Write_Debug ("CRASH", Error_Brief (E));
      Report (E);
      Write_Digest ("CRASH", Error_Brief (E));   --  again: last_error.txt exists now
      if Length (Digest_Note) > 0 then Con.Put_Line (To_String (Digest_Note)); end if;
      Ada.Command_Line.Set_Exit_Status (1);
end Diary_Sim;
