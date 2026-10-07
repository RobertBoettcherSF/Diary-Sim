--  Version: 0.064
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

with Ada.Calendar, Ada.Calendar.Formatting, Ada.Characters.Handling, Ada.Numerics.Elementary_Functions, Ada.Command_Line, Ada.Containers.Indefinite_Hashed_Maps, Ada.Containers.Ordered_Maps, Ada.Containers.Indefinite_Hashed_Sets, Ada.Containers.Vectors, Ada.Directories, Ada.Environment_Variables,
     Ada.Exceptions, Ada.Finalization, Ada.Strings.Fixed, Ada.Streams.Stream_IO, Ada.Strings.Hash, Ada.Strings.Unbounded, Ada.Text_IO,
     GNAT.OS_Lib, GNAT.Traceback.Symbolic, Sim_Albanian, Sim_Carry, Sim_Ckpt, Sim_Dharma, Sim_Govern, Sim_Ledger, Sim_Next, Sim_Chat, Sim_Chess, Sim_Games, Sim_Menu, Sim_Preport, Sim_Quit, Sim_Records, Sim_Robot, Sim_Screen, Sim_Store, Sim_Things, Sim_Trial, Sim_Util, Sim_Visit, Sim_Voice, Sim_Wordstat, Sim_Evolve, Sim_Active, Sim_World;
use Ada.Strings.Unbounded, Sim_Util, Sim_World;

procedure Diary_Sim is
   package TIO renames Ada.Text_IO;
   package Fx renames Ada.Strings.Fixed;
   use type Ada.Directories.File_Size;
   use type Ada.Calendar.Time;

   --  Everything printed for people goes through Con: internal ids become display names (data/names.txt).
   --  Files that are replay-verified or hashed (diaries, sessions.txt, inbox.txt, world.txt) never do.
   package Con is
      procedure Put_Line (S : String);
      procedure Put (S : String);
      procedure Put_Line_Now (S : String);   --  also while the console is held
      procedure Put_Now (S : String);
      procedure Hold (On : Boolean);         --  night run: what a session says is kept (Held) instead of printed
      function Held return String;
      procedure Clear_Held;
      function Is_Dead return Boolean;
   end Con;
   package body Con is
      Dead : Boolean := False;   --  stdout is a closed pipe (| head): the rest of the output is dropped, the files are still written
      Holding : Boolean := False;
      Kept : Unbounded_String;
      procedure Hold (On : Boolean) is
      begin
         Holding := On;
      end Hold;
      function Held return String is (To_String (Kept));
      procedure Clear_Held is
      begin
         Kept := Null_Unbounded_String;
      end Clear_Held;
      procedure Put_Line_Now (S : String) is
      begin
         if not Dead then TIO.Put_Line (Sim_World.Show (S)); end if;
      exception
         when others => Dead := True;   --  EPIPE: Device_Error
      end Put_Line_Now;
      procedure Put_Line (S : String) is
      begin
         if Holding then Append (Kept, Sim_World.Show (S) & ASCII.LF); else Put_Line_Now (S); end if;
      end Put_Line;
      --  A text ending in a line feed is written as Put + New_Line: the runtime would otherwise think the line is unfinished and
      --  write one more line feed when it closes stdout (a write to a closed pipe at exit).
      procedure Put_Raw (S : String) is
         Shown : constant String := Sim_World.Show (S);
      begin
         if Dead then return; end if;
         if Shown'Length > 0 and then Shown (Shown'Last) = ASCII.LF then
            TIO.Put (Shown (Shown'First .. Shown'Last - 1));
            TIO.New_Line;
         else
            TIO.Put (Shown);
         end if;
      exception
         when others => Dead := True;
      end Put_Raw;
      procedure Put_Now (S : String) is
      begin
         Put_Raw (S);
      end Put_Now;
      procedure Put (S : String) is
      begin
         if Holding then Append (Kept, Sim_World.Show (S)); else Put_Raw (S); end if;
      end Put;
      function Is_Dead return Boolean is (Dead);
   end Con;

   --  A closed pipe (| head, a view command): leave quietly, without the traceback the runtime raises while it flushes and closes
   --  a dead stdout.  The last statement of the program (this object is finalized first) flushes; if that fails, nobody reads.
   type Pipe_Guard is new Ada.Finalization.Limited_Controlled with null record;
   overriding procedure Finalize (G : in out Pipe_Guard);
   procedure Finalize (G : in out Pipe_Guard) is
      pragma Unreferenced (G);
   begin
      if not Con.Is_Dead then TIO.Flush; end if;
      if Con.Is_Dead then GNAT.OS_Lib.OS_Exit (0); end if;
   exception
      when others => GNAT.OS_Lib.OS_Exit (0);
   end Finalize;
   Guard : Pipe_Guard;
   pragma Unreferenced (Guard);

   type State is record
      Energy, Mood, Location : Integer;   --  ranges: data/limits.txt; location: office lab cafe home
   end record;
   --  Rest Work Explore Talk Wander Bench Propose Learn.  Propose and Learn keep the location (Home -1).
   Energy_D : constant array (Action) of Integer := [14, -8, -10, -2, -3, -4, -1, -1];
   Mood_D   : constant array (Action) of Integer := [1, -4, 3, 2, -1, -1, 2, 1];
   Home     : constant array (Action) of Integer := [3, 0, 1, 2, 0, 1, -1, -1];   --  wander: rolled

   Build : constant String := "0.064";   --  = the Version header of this file (make version-check)
   Usage_Error, Diary_Error : exception;
   Drift_Error : exception;   --  stored lines or sessions differ from the replay: expected, no traceback
   Seed, Ticks, Every, Seed_Opt, Crash_At, More : Int := -1;   --  More: --more N = N new ticks on top of the disk
   Fresh, Seed_Shown : Boolean := False;
   T_Run : Ada.Calendar.Time := Ada.Calendar.Clock;   --  the start of this run (trend.txt: how long the session took)
   Self_Exe : constant String := Exe_Path;       --  this executable, absolute, fixed before any cd (make night starts it once per session)
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
   Disk_Base : array (Entity_Id) of Natural := [others => 0];   --  0.058: lines before Disk (E) (a start from state.ckpt reads only the
                                                                --  lines after the checkpoint): line N of the diary is Disk (E) (N - Disk_Base (E))
   --  0.058, the state checkpoint (state.ckpt in the save folder, see Ckpt_Write): written at the end of every run that wrote ticks
   --  and at a clean stop; a start whose files still fit it loads it instead of replaying ticks 1 .. Ckpt_Tick.
   Ckpt_Path : constant String := "state.ckpt";
   --  0.059: the checkpoint belongs to a STATE FORMAT, not to a build: Ckpt_Format is the number of the layout of the payload (the
   --  State_IO of the modules, in tagged sections since format 2).  A start accepts the formats Ckpt_Layout_Since .. Ckpt_Format: format 1
   --  (build 0.058, untagged, its section offsets in the header) has the same state layout as format 2.  A change of any State_IO or of
   --  a streamed type needs Ckpt_Format + 1 AND Ckpt_Layout_Since := that number (older checkpoints are refused: full replay), then the
   --  new line "ckpt_layout: <format> <hash>" in docs/CHECKPOINT.md (scripts/ckpt_layout.sh prints it; make check fails without it).
   Ckpt_Magic : constant String := "diary-sim-ckpt ";
   --  0.061, format 3: a section "carry" (Sim_Carry) after "main"; every other section is as in formats 1 and 2, so those still load
   --  (their carry state reads as zero; refused when a carry=1 session began before their tick: Ckpt_Fits).
   --  0.064, format 4: a section "albanian" (Sim_Albanian) after "carry"; formats 1 .. 3 still load (their Albanian state reads as
   --  zero; refused when an alb=1 session began before their tick: Ckpt_Fits).
   Ckpt_Format : constant := 4;
   Ckpt_Layout_Since : constant := 1;
   Replay_Opt : Boolean := False;                    --  --replay: never load the checkpoint (make verify replays anyway)
   Ckpt_Used : Boolean := False;                     --  this run started from the checkpoint
   Ckpt_Tick : Natural := 0;                         --  its tick (when used)
   Ckpt_Seed : Int := -1;
   Ckpt_Off : array (Entity_Id) of Long_Long_Integer := [others => 0];   --  the diary bytes up to the checkpoint's tick
   Ckpt_Why : Unbounded_String;                      --  why it was not used ("missing", "stale (...)")
   Ckpt_Start_Line : Unbounded_String;               --  the start line (Ckpt_Start_Text): console, the night's status lines and box
   Ckpt_Load_Secs : Duration := 0.0;
   Ckpt_Last_Write : Ada.Calendar.Time := Ada.Calendar.Clock;   --  a night writes it at most every night.ckpt_seconds (and at its end)
   Ckpt_Written : Natural := 0;                      --  checkpoints written by this run
   Ckpt_Write_Secs : Duration := 0.0;                --  the last one: seconds and bytes
   Ckpt_Bytes : Long_Long_Integer := 0;
   Data_Hash : Unbounded_String;                     --  the rule files of data/ as the program started (0.059: information, never a refusal)
   Data_Lines : Str_Vectors.Vector;                  --  "name hash" per rule file (Sim_Ckpt.Data_Prints)
   Start_Keys : Str_Vectors.Vector;                  --  0.059: "key text" of every number this start read before the restore point
   Data_Note : Unbounded_String;                     --  0.059: "data changed since the checkpoint ..." (a start that loaded one)
   Ckpt_Fmt_Used : Integer := 0;                     --  the format of the checkpoint this start loaded
   Ckpt_Verify_Diff : Boolean := False;              --  --verify: the checkpoint differed from the replay
   Ckpt_Test_Extra : Unbounded_String;               --  DIARY_TEST_CKPT_EXTRA=<section> (tests only): that section streams one Integer more
   Replay_Progress : Natural := 0;                   --  0.060: DIARY_REPLAY_PROGRESS=<n>: a stderr line every n replayed ticks (tick, seconds, ticks/s)
   Prog_T0 : constant Ada.Calendar.Time := Ada.Calendar.Clock;   --  0.060: the start of the program
   Replay_Wait_Ms : Natural := 0;                    --  DIARY_TEST_REPLAY_MS (tests only): a pause per replayed tick
   Tick_Wait_Ms : Natural := 0;                      --  DIARY_TEST_TICK_MS (tests only): a pause per new tick (a signal inside a session)
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
   Verbose : Boolean := False;                             --  --verbose / DIARY_VERBOSE=1 / make run VERBOSE=1: the whole report on the console as before
   Trend_Mode, Folder_Mode : Boolean := False;             --  --trend / make trend: the last lines of trend.txt; --folder: print the save folder (make share)
   Tty_Out : Boolean := False;                             --  a terminal: the night header is repainted in place (ANSI cursor home); else plain lines
   Night_On : Boolean := False;                            --  the night run is going (keys are read, the console is held)
   Night_Mode : Boolean := False;                          --  --continuous / make night: back-to-back sessions until q, a limit, or DRIFT
   Night_Ticks, Night_Sessions : Int := -1;                --  --session-ticks / --max-sessions (-1: data/limits.txt night.*)
   Night_Hours : Unbounded_String;                         --  --max-hours (text, may have decimals)
   End_Check_Max : Int := -1;                               --  --end-check-ticks N (0.057): the night's end check (a full replay) only up to
                                                            --  N ticks in the save (0 = never; -1 = no cap: night.verify_end decides)
   Runlog_Mode : Boolean := False;                         --  --runlog / make runlog: the last lines of run_log.txt
   Report_Mode : Boolean := False;                         --  --report / make report: print the last run_report.txt of the save folder
   Menu_Opt : Boolean := False;                            --  --menu: show the main menu (make menu)
   Say_Mode, Answer_Mode, Inbox_Mode : Boolean := False;   --  --say / --answer / --inbox
   Say_To, Say_Text, Say_By, Grant_Opt : Unbounded_String;
   Grant_Mode : Boolean := False;   --  --grant P<n>
   Act_Count : array (Entity_Id, Action) of Natural := [others => [others => 0]];   --  all ticks replayed
   Last_Act : Action := Rest;
   Voice_Act : array (Entity_Id) of List_Id := [others => Rest];   --  the latest verb and the newest learned or coined word of each wesen (display only: the voices)
   Voice_Hist : array (Entity_Id, 1 .. 5) of Natural := [others => [others => 0]];   --  the newest words, [1] the newest
   Voice_On : Boolean := True;                  --  voices are shown (voice.enabled, /voices on|off)

   procedure Voice_Note (E : Entity_Id; W : Positive) is
   begin
      for K in reverse 2 .. 5 loop Voice_Hist (E, K) := Voice_Hist (E, K - 1); end loop;
      Voice_Hist (E, 1) := W;
   end Voice_Note;
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
   --  robot=1 sessions (Sim_Robot): Q lines in diaries/robot.txt (commands, executions, shared screens), replay-verified.
   Robot_Active : Boolean := False;
   Robot_Path : constant String := "diaries/robot.txt";
   Robot_Store : Sim_Store.Store;
   Robot_N : Natural := 0;
   Robot_Lines : Str_Vectors.Vector;
   Robot_View : Boolean := False;                --  --robot: replay, then show the robot
   --  govern=1 sessions (Sim_Govern): the players decide petitions; D lines in diaries/govern.txt (Sim_Store, replay-verified);
   --  Robert's veto / approval inputs are V lines in diaries/vetoes.txt.
   Govern_Active : Boolean := False;
   Scoin_Active : Boolean := False;   --  scoin=1 sessions: screen blends have their own per-session cap
   Govern_Path : constant String := "diaries/govern.txt";
   Vetoes_Path : constant String := "diaries/vetoes.txt";
   Govern_Store : Sim_Store.Store;
   Govern_Lines : Str_Vectors.Vector;
   Govern_View, Veto_Mode, Veto_Approve : Boolean := False;   --  --govern / --veto D<n> / --approve D<n>
   Veto_Opt : Unbounded_String;
   Gov_Since : Int := 0;                                       --  the tick of the previous session end (the report window)
   --  preport=1 sessions (Sim_Preport): the players' claims to Robert, P lines in diaries/preports.txt (Sim_Store, replay-verified), a round at
   --  the last tick of each session; Robert's challenges are Q lines in diaries/challenges.txt; the boxes: player_reports.txt and the console end.
   Preport_Active : Boolean := False;
   Preport_End : Int := -1;                      --  the last tick of the preport=1 session being replayed (the tick of its round)
   Preport_Path : constant String := "diaries/preports.txt";
   Challenges_Path : constant String := "diaries/challenges.txt";
   Preport_Store : Sim_Store.Store;
   Preport_Lines : Str_Vectors.Vector;
   --  nextticks=1 sessions (Sim_Next): the advice for the next run, an N line in diaries/nextticks.txt per session end (Sim_Store, replay-verified)
   Next_Active : Boolean := False;
   Next_End : Int := -1;                         --  the last tick of the nextticks=1 session being replayed (the tick of its round)
   Next_Path : constant String := "diaries/nextticks.txt";
   Next_Store : Sim_Store.Store;
   Next_Lines : Str_Vectors.Vector;
   Next_View, Next_Ticks_Mode : Boolean := False;   --  --next / --next-ticks
   --  visit=1 sessions (Sim_Visit): Robert stands next to one wesen; his inputs are V lines and the answers A lines in diaries/visit.txt
   --  (Sim_Store, replay-verified).  --visit WHO / --visit-script FILE.
   Visit_Mode : Boolean := False;                --  --visit given (this run starts a visit)
   Visit_Opt, Visit_Script : Unbounded_String;
   Visit_Who : Natural := 0;                     --  the wesen of --visit
   Visit_Active : Boolean := False;              --  the session being replayed is a visit=1 session
   Visit_E : Entity_Id := 1;
   Visit_Start, Visit_End : Int := -1;           --  the ticks Visit_Start + 1 .. Visit_End are the visit
   --  trial=1 sessions (Sim_Trial): disputes settled over the board; T lines in diaries/trials.txt (Sim_Store, replay-verified); --trials
   Trial_Active : Boolean := False;
   Trial_Path : constant String := "diaries/trials.txt";
   Trial_Store : Sim_Store.Store;
   Trial_Lines : Str_Vectors.Vector;
   Trial_View : Boolean := False;
   --  records=1 sessions (Sim_Records): votes, petitions, dictionary and announcements as record files (Sim_Store, replay-verified)
   Votes_Path : constant String := "diaries/votes.txt";
   Pets_Path : constant String := "diaries/petitions.txt";
   Dict_Path : constant String := "diaries/dictionary.txt";
   Anns_Path : constant String := "diaries/announcements.txt";
   Bals_Path : constant String := "diaries/ballots.txt";   --  records=2: the secret ballots, read by the Ground only (make ballots)
   Votes_Store, Pets_Store, Dict_Store, Anns_Store, Bals_Store : Sim_Store.Store;
   Rec_View, Dict_View, Bal_View : Boolean := False;
   Visit_Path : constant String := "diaries/visit.txt";
   Visit_Store : Sim_Store.Store;
   type Visit_In is record
      N : Positive := 1;
      Tick : Int := 0;
      C : Sim_Visit.Command;
      Done : Boolean := False;
   end record;
   package Visit_Vectors is new Ada.Containers.Vectors (Positive, Visit_In);
   Visit_Inputs : Visit_Vectors.Vector;
   --  chat=1 sessions (Sim_Chat): Robert's typed lines and every answer are C lines of diaries/chat.txt (record-first, replay-verified)
   Chat_Mode : Boolean := False;                 --  --chat / make chat: one session with the input line, paced
   Chat_Script_Opt : Unbounded_String;           --  --chat-script FILE: lines "<ticks into the session> <text>" typed by a script (tests)
   Frust_Mode : Boolean := False;                --  --frustration / make frustration: the MiniMax report (read-only; data/frustration.txt)
   Evolve_Mode : Boolean := False;               --  --evolve / make evolve: the evolution preview (read-only; Sim_Evolve, docs/EVOLVE.md)
   Active_Mode : Boolean := False;               --  --active / make active: the active-vocabulary preview with a cap (read-only)
   Wordstat_Mode : Boolean := False;             --  --wordstat / make wordstat: the vocabulary report (read-only)
   Since_Session : Natural := 0;                 --  --since-session N (0.057, report-only): make frustration counts sessions N and later
                                                 --  (the diaries are entered by a binary search on the tick, not read from the start)
   Chatlog_Mode : Boolean := False;              --  --chatlog / make chatlog: the last chat lines
   Chat_Active : Boolean := False;               --  the session being replayed is a chat=1 session
   Symbols_Active : Boolean := False;            --  the session being replayed is a symbols=1 session: chess strings are symbols, not words (docs/EVOLVE.md 9)
   --  active=1 sessions (Sim_Active, docs/EVOLVE.md 13): dormant and woken words, the state of each wesen at a session end: A lines of diaries/active.txt
   Active_Path : constant String := "diaries/active.txt";
   Active_Store : Sim_Store.Store;
   Active_N : Natural := 0;
   Chat_Path : constant String := "diaries/chat.txt";
   Chat_Store : Sim_Store.Store;
   type Chat_In is record
      N : Positive := 1;
      Tick : Int := 0;
      Text : Unbounded_String;
      Done : Boolean := False;
   end record;
   package Chat_Vectors is new Ada.Containers.Vectors (Positive, Chat_In);
   Chat_Inputs : Chat_Vectors.Vector;
   Chat_N : Natural := 0;                        --  C lines so far (the next one is Chat_N + 1)
   Chat_Paused : Boolean := False;               --  /pause: the ticks wait (live only)
   Chat_Live : Boolean := False;                 --  the line being handled was typed now (effects and screen), not replayed
   Chat_Shown : Str_Vectors.Vector;              --  the chat lines on the screen (live ones)
   Chat_Version : Natural := 0;                  --  counts changes of Chat_Shown (the screen is drawn again)
   Chat_Start_Mood : array (Entity_Id) of Integer := [others => 0];   --  the moods at the start of the session (replay-stable, for "since the session began")
   Chat_Samples : Sim_Chat.Sample_Vectors.Vector;
   Chat_Script : Str_Vectors.Vector;
   Chat_Script_Next : Positive := 1;
   Chat_Session_Count : Natural := 0;            --  sessions started so far (Start_Life), replay-stable
   Visit_Left : Boolean := False;                --  the human left: no more frames
   Visit_Wait : Int := 0;                        --  no prompt before this tick
   Script_File : TIO.File_Type;
   Script_On : Boolean := False;
   Last_Diary : array (Entity_Id) of Unbounded_String;   --  the diary line of the latest tick of each wesen (the frame shows it)
   Audit_View, Challenge_Mode : Boolean := False;   --  --audit / --challenge <player>
   Challenge_Opt : Unbounded_String;
   Verify_View : Boolean := False;               --  --verify (make verify): replay everything from the files, compare, print one line
   Verify_Incr : Boolean := False;               --  0.060: --verify replays from the last VERIFIED checkpoint (state.verified.ckpt); --verify-full from tick 1
   Verified_Path : constant String := "state.verified.ckpt";   --  0.060: the checkpoint a passed verify wrote (incremental verify starts there)
   Verify_From : Natural := 0;                   --  0.060: the tick an incremental verify started after (0: tick 1, a full verify)
   Sim_Print_Opt : Unbounded_String;             --  0.060: --sim-print <hash> (make verify-full): the fingerprint of the simulation sources, kept in verify_stamp.txt
   Deadline_Opt : Int := 0;                      --  0.060: --deadline <unix seconds>: when the whole job (make slice / night-ship) is due
   Run_Label : Unbounded_String := To_Unbounded_String ("night");   --  0.060: --run-label slice|ship|night: the name of the run on the screen and in the box (display only)
   Reserve_Opt : Int := 0;                       --  0.060: --reserve <seconds>: what the job needs after the night (the reports)
   Voices_View : Boolean := False;                 --  --voices / make voices: the four wesen messages at the last tick
   Elo_View, Perft_Mode : Boolean := False;      --  --elo (replay, then the ranking) / --perft (the move generator checks)
   Screens_View : Boolean := False;              --  --screens: replay, then show the screens (a view like --ledger)
   Rate_Pct, Load, Hist, Cool, Streak, Since_Work, Cool_N, Cut_N, Quick_N : array (Entity_Id) of Natural := [others => 0];
   function RL (Key : String; Default : Integer) return Integer is (Integer (Limit (Key, Int (Default))));
   --  "G7 ada-iris 1-0 ..." of the chess report: the two ids of the pairing shown as display names ('-' keeps Show from doing it).
   function Game_Names (L : String) return String is
      A : constant Natural := Fx.Index (L, " ");
      B : constant Natural := (if A = 0 then 0 else Fx.Index (L, " ", A + 1));
      D : constant Natural := (if B = 0 then 0 else Fx.Index (L (A + 1 .. B - 1), "-"));
   begin
      if D = 0 then return L; end if;
      return L (L'First .. A) & Sim_World.Show (L (A + 1 .. D - 1)) & "-" & Sim_World.Show (L (D + 1 .. B - 1)) & L (B .. L'Last);
   end Game_Names;

   function Rate_Now (E : Entity_Id) return Natural is   --  the recovery rate, with the governed offset (govern=1)
     (Natural'Max (1, Integer (Rate_Pct (E)) + Sim_Govern.Off (E, Sim_Govern.Rate)));
   function Cool_Len (E : Entity_Id) return Positive is
     (Positive'Max (1, RL ("rest.cool", 16) * 100 / Rate_Now (E) + Sim_Govern.Off (E, Sim_Govern.Cool)));   --  slow recoverers cool longer
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
         Phase := Integer'Min (100, Integer'Max (1, RL ("rest.quick.energy_pct", 60) + Sim_Govern.Off (E, Sim_Govern.Quick)));
         Mo := Mo + RL ("rest.quick.mood", -1);
         Last_Phase := -1;
         Quick_N (E) := Quick_N (E) + 1;
      elsif Since_Work (E) >= Natural (RL ("rest.calm", 8)) then
         Phase := RL ("rest.calm.energy_pct", 120);
         Mo := Mo + RL ("rest.calm.mood", 2);
         Last_Phase := 1;
      end if;
      En := En * Integer (Rate_Now (E)) * Phase / 10_000;
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
     (Msg ("rest.line", Name (E), Img (Rate_Now (E)), Img (Cool_Len (E)), Img (Cool_N (E)), Img (Cut_N (E)), Img (Quick_N (E))));

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
      for F of Str_Vectors.Vector'(["karma.txt", "dharma.txt", "players.txt", "things.txt", "ledger.txt", "screens.txt", "chess.txt", "robot.txt", "govern.txt", "preport.txt", "ticks.txt", "visit.txt", "voices.txt", "wordstat.txt", "evolve.txt", "frustration.txt", "chat.txt", "trial.txt", "records.txt"]) loop   --  the Buddhism layer: numbers, wording, players
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

   procedure Emit_Active_Lines;   --  below: the new lines of Sim_Active as A lines of diaries/active.txt (a lesson wake in Step)

   --  Advance entity E by one tick; returns its diary line.  Teaching, coining and
   --  bench happen here; their working-folder lines are ensured as they occur.
   --  0.061, carry=1 sessions (Sim_Carry): the action of E after the word carrying rules, from the rolled one (Base).
   --  Relief: below the relief energy a wesen rests instead of talking (teaching).  Pull: a wesen with spare energy and a low mood
   --  teaches the target (the wesen missing the most words all the others know) one of those words: Carry_To (E) and Carry_W (E)
   --  name the lesson for Teach in the same step.  Its own dice (salts 23101, 23102); older sessions return Base untouched.
   package Exchange_Words is new Ada.Containers.Vectors (Positive, Positive);   --  0.062: the words of an exchange
   Carry_To : array (Entity_Id) of Natural := [others => 0];
   Carry_R : array (Entity_Id) of Positive := [others => 1];   --  0.062: the index of the planned word among the carriable ones

   --  0.062, moodrest=1 sessions (Robert: reaching a good mood is the goal; staying above it all the time is unnatural): every wesen
   --  has a resting mood inside the band moodrest.band_lo .. band_hi (60 .. 80), derived from its birth row (Core_Percent, the
   --  constant Rule 30 personality: moodrest.core_lo .. core_hi maps onto the band), so every wesen, a new one too, gets its own;
   --  moodrest.<id> sets one by hand.  Each tick a gain shrinks with the distance to the upper bound (above the middle of the
   --  range), a loss with the distance to the lower bound (below it); then the mood drifts moodrest.pull_pct percent of the way
   --  back to the resting mood, moodrest.pull_high_pct above the band (adaptation).  Set by Start_Life, derived from the sessions
   --  after a checkpoint load (no state of its own).
   Moodrest_Active : Boolean := False;
   --  0.063 moodrest=2: the same resting moods, but the drift is a one-point step taken with the probability rate x gap (a die
   --  of 10000: moodrest.pull_bp basis points per point of gap, pull_high_bp above the band), and the soft bounds round by a
   --  die too; so the expected drift is rate x gap with no rounding dead zone and no state of its own
   Moodrest_Level : Positive := 1;
   Rest_Mood_Known : Boolean := False;
   Rest_Mood_Of : array (Entity_Id) of Integer := [others => 0];
   function Rest_Mood (E : Entity_Id) return Integer is
   begin
      if not Rest_Mood_Known then
         declare
            Lo : constant Integer := Integer (Limit ("moodrest.band_lo", 60));
            Hi : constant Integer := Integer'Max (Lo, Integer (Limit ("moodrest.band_hi", 80)));
            C_Lo : constant Integer := Integer (Limit ("moodrest.core_lo", 30));
            C_Hi : constant Integer := Integer'Max (C_Lo + 1, Integer (Limit ("moodrest.core_hi", 70)));
         begin
            for X in Entity_Id loop
               declare
                  P : constant Integer := Clamp (Integer (Core_Percent (Seed, X)), C_Lo, C_Hi);
               begin
                  Rest_Mood_Of (X) := Clamp (Integer (Limit ("moodrest." & Name (X), Int (Lo + (Hi - Lo) * (P - C_Lo) / (C_Hi - C_Lo)))), M_Min, M_Max);
               end;
            end loop;
         end;
         Rest_Mood_Known := True;
      end if;
      return Rest_Mood_Of (E);
   end Rest_Mood;
   --  the mood after one tick of moodrest=1: From the mood before the tick, To after it (bounds M_Min .. M_Max)
   function Mood_Rest_Step (E : Entity_Id; From, To : Integer) return Integer is
      Mid : constant Integer := (M_Max + M_Min) / 2;
      D : constant Integer := To - From;
      Soft : constant Boolean := Limit ("moodrest.soft", 1) /= 0;
      M : Integer := From + D;
   begin
      if Soft and then D > 0 and then From > Mid and then M_Max > Mid then M := From + D * (M_Max - From) / (M_Max - Mid);
      elsif Soft and then D < 0 and then From < Mid and then Mid > M_Min then M := From + D * (From - M_Min) / (Mid - M_Min);
      end if;
      declare
         Diff : constant Integer := Rest_Mood (E) - M;
         Pct : constant Integer := Integer (Int'Max (0, Int'Min (100,
           (if M > Integer (Limit ("moodrest.band_hi", 80)) then Limit ("moodrest.pull_high_pct", 15) else Limit ("moodrest.pull_pct", 5)))));
      begin
         M := M + (Diff * Pct + (if Diff >= 0 then 50 else -50)) / 100;
      end;
      return Clamp (M, M_Min, M_Max);
   end Mood_Rest_Step;
   function Mood_Rest_Step2 (E : Entity_Id; From, To : Integer; Tick : Int) return Integer is
      Mid : constant Integer := (M_Max + M_Min) / 2;
      D : constant Integer := To - From;
      Soft : constant Boolean := Limit ("moodrest.soft", 1) /= 0;
      M : Integer := From + D;
      --  N / Den rounded by a die: the remainder becomes one more point with the probability |remainder| / Den
      function Div_Die (N, Den : Integer; Salt : Natural) return Integer is
         Q : constant Integer := N / Den;
         R : constant Integer := abs (N rem Den);
      begin
         if R > 0 and then Roll (Seed, Positive (E), Tick, Salt, Den) <= R then return Q + (if N > 0 then 1 else -1); end if;
         return Q;
      end Div_Die;
   begin
      if Soft and then D > 0 and then From > Mid and then M_Max > Mid then M := From + Div_Die (D * (M_Max - From), M_Max - Mid, 23105);
      elsif Soft and then D < 0 and then From < Mid and then Mid > M_Min then M := From + Div_Die (D * (From - M_Min), Mid - M_Min, 23105);
      end if;
      declare
         Gap : constant Integer := Rest_Mood (E) - M;
         Bp : constant Int := Int'Max (0, (if M > Integer (Limit ("moodrest.band_hi", 80)) then Limit ("moodrest.pull_high_bp", 45)
                                           else Limit ("moodrest.pull_bp", 15)));
         P : constant Int := Int'Min (10_000, Bp * Int (abs Gap));
      begin
         if Gap /= 0 and then P > 0 and then Int (Roll (Seed, Positive (E), Tick, 23106, 10_000)) <= P then
            M := M + (if Gap > 0 then 1 else -1);
         end if;
      end;
      return Clamp (M, M_Min, M_Max);
   end Mood_Rest_Step2;
   Carry_W : array (Entity_Id) of Positive := [others => 1];
   function Carry_Choice (E : Entity_Id; Tick : Int; Base : Action) return Action is
      Eid : constant Positive := Positive (E);
   begin
      Carry_To (E) := 0;
      if not Sim_Carry.Active or else Base = Learn then return Base; end if;
      if St (E).Energy < Sim_Carry.Relief_Energy then
         return (if Base = Talk then Rest else Base);
      end if;
      --  0.062: in a moodrest=1 session the moods rest at 60..80, so "mood <= carry.teacher_mood" would stop all teaching: there a
      --  wesen at or below its own resting mood (+ carry.teacher_rest_margin) may teach
      if St (E).Energy >= Sim_Carry.Teacher_Energy
        and then St (E).Mood <= (if Moodrest_Active then Rest_Mood (E) + Integer (Limit ("carry.teacher_rest_margin", 0))
                                 else Sim_Carry.Teacher_Mood)
        and then Sim_Carry.Lessons < Sim_Carry.Session_Cap
        and then Roll (Seed, Eid, Tick, 23101, 100) <= Sim_Carry.Pull_Pct
      then
         declare
            T : constant Natural := Sim_Carry.Target;
         begin
            if T /= 0 and then T /= Natural (E) and then Pending_Word (Entity_Id (T)) = 0
              and then St (Entity_Id (T)).Energy >= Sim_Carry.Relief_Energy
              and then Slow_Pass (Seed, Entity_Id (T), Tick, Slow_Lesson)   --  active=2 mint-slow: the same die as a lesson in Teach
            then
               declare
                  N : constant Natural := Carry_Count (E, Entity_Id (T));
               begin
                  if N > 0 then
                     Carry_To (E) := T;
                     Carry_R (E) := Roll (Seed, Eid, Tick, 23102, N);
                     Carry_W (E) := Nth_Carry (E, Entity_Id (T), Carry_R (E));
                     return Talk;
                  end if;
               end;
            end if;
         end;
      end if;
      return Base;
   end Carry_Choice;

   --  0.064, the mood causes of a session (report only, docs/EVOLVE.md 18): every tick's mood change of a wesen split by cause, as
   --  it happens; no die, nothing the replay reads or the checkpoint holds.  Start_Life zeroes them, Record_Word_Vote (the end of a
   --  NEW session) appends one line per session to moodcause.txt in the save folder (part=1: this run began inside the session).
   type Cause_Kind is (C_Refusal, C_Lesson, C_Work, C_Rest, C_Talk, C_Game, C_Other);
   Cause_Net : array (Entity_Id, Cause_Kind) of Integer := [others => [others => 0]];
   Cause_Refusals : array (Entity_Id) of Natural := [others => 0];
   Cause_Session : Natural := 0;   --  the session Start_Life began in this run (0: none)
   procedure Note_Cause (E : Entity_Id; K : Cause_Kind; D : Integer) is
   begin
      Cause_Net (E, K) := Cause_Net (E, K) + D;
   end Note_Cause;

   function Step (E : Entity_Id; Tick : Int) return String is
      A   : constant Action := Carry_Choice
        (E, Tick, (if Pending_Word (E) /= 0 then Learn else Choose (Seed, E, Tick, St (E).Energy, St (E).Mood, Work_Keep (E))));
      Carry_Mo : constant Integer := (if Carry_To (E) /= 0 then Sim_Carry.Mood_Gain else 0);   --  being useful lifts the mood a little
      Pre_En : constant Integer := St (E).Energy;     --  state before this action
      Pre_Mo : constant Integer := St (E).Mood;
      S   : State renames St (E);
      Detail, Learned : Unbounded_String;
      Eid : constant Positive := Positive (E);
      World_Mode : constant Boolean := World_Active;
      Verb : List_Id := A;
      Eff_En : Integer := Energy_D (A);   --  a rest=1 rest changes these (Rest_Effect)
      Eff_Mo : Integer := Mood_D (A) + Carry_Mo;
      --  the mood ledger (report only, Sim_Ledger): where this tick's mood change came from
      Was_Cool : constant Boolean := Rest_Active and then Cool (E) > 0;
      Led_Phase, Push_Nom : Integer := 0;
      Push_Feel : Integer := -1;
      Chess_Fx, Chess_Nom : Integer := 0;   --  mood of finished chess games, taken at this step
      Gov_Fx, Gov_Nom : Integer := 0;       --  mood of governance decisions, taken at this step
      M_Base, M_After_Base : Integer;
      --  0.064, the mood causes (report only, Note_Causes): the refused part of Gov_Fx, and what the favour / the work lever
      --  changed of the action's own mood
      Ref_Fx, Fav_Adj, Lever_Adj : Integer := 0;
      Refused : Boolean := False;

      procedure Add (Text : String) is
      begin
         Append (Detail, (if Length (Detail) > 0 then "; " else "") & Text);
      end Add;

      --  ---- the treadmill world (world=1 sessions): things are met, named and learned ----------
      procedure Meet (W : Positive) is
      begin
         if not Knows (E, W) then
            Learn_From_World (E, W);
            if Knows (E, W) then Ensure (E, Words_File, Words_Line (W, "world", Tick, Meaning_Of (W))); end if;   --  a blocked symbol is not learned: no words.txt line
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
         if Carry_To (E) /= 0 then   --  carry=1: the lesson Carry_Choice planned (no adjacency needed, no dialect drift)
            declare
               L : constant Entity_Id := Entity_Id (Carry_To (E));
               W : constant Positive := Carry_W (E);
            begin
               Pending_Word (L) := W;
               Pending_From (L) := E;
               Did_Teach := True;
               Use_Word (E, W);
               Sim_Carry.Carried (E, L);
               if Sim_Carry.Level < 2 then
                  Add (Msg ("detail.carried", Name (L), Word (W)));
               else   --  0.062 carry=2: an exchange; more words by the learner's energy, words back by the teacher's
                  declare
                     K1 : constant Natural := Sim_Carry.Words_For (St (L).Energy);   --  with W (learned at the learner's next step)
                     K2 : constant Natural := Sim_Carry.Words_For (Pre_En);
                     N1 : constant Natural := Carry_Count (E, L);
                     Outs : Unbounded_String := To_Unbounded_String ("'" & Word (W) & "'");
                     Backs : Unbounded_String;
                     Got : Natural := 1;
                     Back_N : Natural := 0;
                     Ws : Exchange_Words.Vector;
                  begin
                     for J in 0 .. N1 - 1 loop   --  the next carriable words after W in table order (wrapping)
                        exit when Got >= K1;
                        declare
                           X : constant Positive := Nth_Carry (E, L, (Carry_R (E) - 1 + J) mod N1 + 1);
                        begin
                           if X /= W then Ws.Append (X); Got := Got + 1; end if;
                        end;
                     end loop;
                     for X of Ws loop
                        Learn_Word (L, X, Natural (E));
                        if Knows (L, X) then Ensure (L, Words_File, Words_Line (X, "taught", Tick, Name (E))); end if;
                        Use_Word (E, X);
                        Append (Outs, " '" & Word (X) & "'");
                     end loop;
                     Ws.Clear;
                     declare
                        N2 : constant Natural := Carry_Count (L, E);   --  what the learner can give back: missing by one at E
                        R2 : constant Positive := Roll (Seed, Eid, Tick, 23104, Natural'Max (1, N2));
                     begin
                        for J in 0 .. Natural'Min (K2, N2) - 1 loop Ws.Append (Nth_Carry (L, E, (R2 - 1 + J) mod N2 + 1)); end loop;
                     end;
                     for X of Ws loop
                        Learn_Word (E, X, Natural (L));
                        if Knows (E, X) then Ensure (E, Words_File, Words_Line (X, "taught", Tick, Name (L))); end if;
                        Use_Word (L, X);
                        Append (Backs, (if Back_N > 0 then " '" else "'") & Word (X) & "'");
                        Back_N := Back_N + 1;
                     end loop;
                     if Back_N > 0 then
                        Sim_Carry.Settled (L, E);
                        Add (Msg ("detail.exchanged", Name (L), To_String (Outs), To_String (Backs)));
                     else
                        Add (Msg ("detail.exchanged0", Name (L), To_String (Outs)));
                     end if;
                  end;
               end if;
            end;
            return;
         end if;
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
         if Int (Roll (Seed, Eid, Tick, 2, 100)) <= Teach_Pct and then Pending_Word (P) = 0 then
            declare
               N : constant Natural := Teachable_Count (E, P);   --  0.057: counted once (it walks the whole word table; was twice)
            begin
               if N > 0 then
                  declare
                     W0 : constant Positive := Nth_Teachable (E, P, Roll (Seed, Eid, Tick, 4, N));
                     W : constant Positive := (if World_Mode then Sim_Things.Mutate (W0, E, Tick) else W0);
                  begin
                     --  active=2 mint-slow: a pupil at the cap gets a NEW word only when the die lets it through (a word it has asleep is no new word)
                     if not Asleep (P, W) and then not Slow_Pass (Seed, P, Tick, Slow_Lesson) then return; end if;
                     Pending_Word (P) := W;
                     Pending_From (P) := E;
                     Did_Teach := True;
                     Use_Word (E, W0);   --  the teacher mentions it too
                     Add (Msg ("detail.taught", Name (P), Word (W)));
                  end;
               end if;
            end;
         end if;
      end Teach;

      procedure Coin is
         K : constant Natural := Usable_Count (E);   --  = Known_Count unless active=1 (dormant words are not coined from)
      begin
         if Int (Roll (Seed, Eid, Tick, 5, 100)) <= Coin_Pct and then K >= 2
           and then Int (Coined_Total) - (if Scoin_Active then Int (Sim_Screen.Coined_All) else 0) < Coin_Cap   --  scoin=1: blends from screens do not use up the cap
           and then Slow_Pass (Seed, E, Tick, Slow_Coin)   --  active=2 mint-slow (salt 20871)
         then
            declare
               Ia : constant Positive := Roll (Seed, Eid, Tick, 6, K);
               Ib0 : constant Positive := Roll (Seed, Eid, Tick, 7, K - 1);
               Ib : constant Positive := (if Ib0 >= Ia then Ib0 + 1 else Ib0);
               Pa : constant Positive := Nth_Usable (E, Ia);
               Pb : constant Positive := Nth_Usable (E, Ib);
               Text : constant String := Word (Pa) & Word (Pb);
            begin
               if Text'Length <= 24 and then Find (Text) = 0 and then not Blocked (Pa) and then not Blocked (Pb) and then not Blocked_Text (Text)
                 and then (not Is_Clean or else (Plain (Pa) and then Plain (Pb) and then not Overlaps (Pa, Pb)))   --  records=1: no chess moves, no part twice
               then
                  declare
                     W : constant Positive := Add_Coined (Text, Pa, Pb, E);
                  begin
                     Use_Word (E, Pa);
                     Use_Word (E, Pb);
                     Learn_Word (E, W);
                     Voice_Note (E, W);
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
      if Govern_Active and then A = Work and then Eff_Mo < 0 then   --  a governed lever: work costs less mood (never turns it positive)
         Lever_Adj := Eff_Mo;
         Eff_Mo := Integer'Min (0, Eff_Mo + Sim_Govern.Off (E, Sim_Govern.Work));
         Lever_Adj := Eff_Mo - Lever_Adj;
      end if;
      --  carry=1: a learner who owes E a favour helps with the work: it costs E no mood and half the energy that tick
      if Sim_Carry.Active and then A = Work and then (Eff_Mo < 0 or else Eff_En < 0) then
         declare
            D : constant Natural := Sim_Carry.Debtor (E);
         begin
            if D /= 0 and then St (Entity_Id (D)).Energy >= Sim_Carry.Relief_Energy + Sim_Carry.Help_Energy
              and then Roll (Seed, Eid, Tick, 23103, 100) <= Sim_Carry.Spend_Pct
            then
               Fav_Adj := Integer'Max (0, Eff_Mo) - Eff_Mo;
               Eff_Mo := Integer'Max (0, Eff_Mo);
               Eff_En := Eff_En / 2;
               St (Entity_Id (D)).Energy := Clamp (St (Entity_Id (D)).Energy - Sim_Carry.Help_Energy, E_Min, E_Max);
               Sim_Carry.Spend (Entity_Id (D), E);
               Add (Msg ("detail.favour", Name (Entity_Id (D))));
            end if;
         end;
      end if;
      M_Base := Clamp (Pre_Mo + Mood_D (A) + Carry_Mo, M_Min, M_Max) - Pre_Mo;   --  ledger: the action's own part, after the bounds
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
      Voice_Act (E) := Verb;
      S.Location := Clamp (S.Location, 0, L_Max);
      case A is
         when Talk => Teach;
         when Explore | Wander => Coin;
         when Learn =>
            declare
               W : constant Positive := Pending_Word (E);
               Woke : Boolean;
            begin
               Sim_Active.Wake (Positive (E), W, Tick, Name (Pending_From (E)), Woke);   --  active=2: a lesson of a dormant word wakes it
               if Woke then
                  Emit_Active_Lines;
                  Use_Word (E, W);
                  Add (Msg ("detail.woke", Word (W), Name (Pending_From (E))));
                  Pending_Word (E) := 0;
                  Did_Learn := True;
               else
                  Learn_Word (E, W, Natural (Pending_From (E)));
                  Voice_Note (E, W);
                  if Knows (E, W) then   --  a lesson chosen before the word became a symbol (symbols=1 / symstrict=1): not learned, no words.txt line
                     Ensure (E, Words_File, Words_Line (W, "taught", Tick, Name (Pending_From (E))));
                  end if;
                  Add (Msg ("detail.learned", Word (W), Name (Pending_From (E))));
                  Pending_Word (E) := 0;
                  Did_Learn := True;
                  if Screen_Active then Sim_Screen.Note (E, W, "taught"); end if;
               end if;
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
               if Govern_Active then Sim_Govern.Filed (N, E, Tick, Pre_Mo); end if;
               if Trial_Active then Sim_Trial.Note_Petition (E, Tick, N, Petition_Topic (N)); end if;
               if Sim_Records.Active and then Govern_Active then
                  Sim_Records.Note_Petition (E, Tick, Petition_Topic (N), Pre_Mo);
                  declare
                     Cost : constant Natural := Sim_Records.Take_Cost (E);   --  announcing exposes the speaker: a little standing
                  begin
                     if Cost > 0 then Sim_Govern.Adjust (E, 0, -Integer (Cost)); end if;
                  end;
               end if;
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
                  --  symbols=1: the move and its numeric string stay symbols of the board (diaries/chess.txt, the diary line); they are not minted as words
                  if not Symbols_Active then
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
            for Rd of Sim_Screen.Take_Reads loop   --  whoever read the screen of a steering wesen may steer too
               if Robot_Active then Sim_Robot.Share (Rd.Viewer, Rd.Owner, Tick, Robot_Lines); end if;
            end loop;
         end;
         if Robot_Active then   --  the robot: learn a command word beside it, pin and send a command, read its answer
            declare
               Learned_R : Str_Vectors.Vector;
               Said_R : Unbounded_String;
            begin
               Sim_Robot.Control (E, Tick, Robot_Lines, Learned_R, Said_R);
               for Id of Learned_R loop
                  declare
                     W : constant Positive := Positive'Value (Id);
                  begin
                     Ensure (E, Words_File, Words_Line (W, "world", Tick, Meaning_Of (W)));
                  end;
               end loop;
               declare
                  Reply : constant String := Sim_Robot.Take_Reply (E);
               begin
                  if Length (Said_R) > 0 then Add (To_String (Said_R)); end if;
                  if Reply /= "" then Add (Reply); end if;
               end;
            end;
         end if;
      end if;
      if Govern_Active then   --  the answer of the player to a petition: a little mood (granted up, refused down)
         declare
            Gov : constant Integer := Sim_Govern.Take_Mood (E);
            Heard : constant Integer := (if Sim_Records.Active then Sim_Records.Take_Mood (E) else 0);   --  records=1: what the others announced
            Want : constant Integer := Gov + Heard;
            Got : constant Integer := Clamp (S.Mood + Want, M_Min, M_Max) - S.Mood;
         begin
            if Gov /= 0 then Add (Msg (if Gov > 0 then "detail.gov.up" else "detail.gov.down")); end if;
            if Heard /= 0 then Add (Msg (if Heard > 0 then "detail.rec.up" else "detail.rec.down")); end if;
            S.Mood := S.Mood + Got;
            Gov_Fx := Got;
            Gov_Nom := Want;
            if Gov < 0 then Ref_Fx := Integer'Max (Gov, Got - Heard); Refused := True; end if;   --  0.064 mood causes: the refusal's part
         end;
      end if;
      if Moodrest_Active then   --  0.062 moodrest=1: soft bounds and the drift to the resting mood (ledger: in the rest-model part)
         declare
            M : constant Integer := (if Moodrest_Level >= 2 then Mood_Rest_Step2 (E, Pre_Mo, S.Mood, Tick) else Mood_Rest_Step (E, Pre_Mo, S.Mood));
         begin
            M_After_Base := M_After_Base + (M - S.Mood);
            S.Mood := M;
         end;
      end if;
      Sim_Ledger.Add (E, Tick, A, Verb, S.Location, M_Base, M_After_Base - Pre_Mo - M_Base, S.Mood - M_After_Base - Chess_Fx - Gov_Fx,
                      Eff_Mo + Push_Nom + Chess_Nom + Gov_Nom, Led_Phase, Was_Cool, Push_Feel, Chess_Fx, Gov_Fx);
      declare   --  0.064 mood causes (report only: no die, no stored state; moodcause.txt at the session end)
         Rest_Fx : constant Integer := M_After_Base - Pre_Mo - M_Base;   --  rest model, moodrest pull, favour, lever, bounds
         Own : constant Cause_Kind :=
           (if Carry_To (E) /= 0 or else A = Learn then C_Lesson elsif A = Work then C_Work elsif A = Rest then C_Rest
            elsif A = Talk then C_Talk else C_Other);
      begin
         Note_Cause (E, Own, M_Base);
         Note_Cause (E, C_Lesson, Fav_Adj);
         Note_Cause (E, C_Other, Lever_Adj);
         Note_Cause (E, C_Rest, Rest_Fx - Fav_Adj - Lever_Adj);
         Note_Cause (E, C_Other, S.Mood - M_After_Base - Chess_Fx - Gov_Fx);   --  the pushed things
         Note_Cause (E, C_Game, Chess_Fx);
         Note_Cause (E, C_Refusal, Ref_Fx);
         Note_Cause (E, C_Other, Gov_Fx - Ref_Fx);   --  grants and heard announcements
         if Refused then Cause_Refusals (E) := Cause_Refusals (E) + 1; end if;
      end;
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
   pragma No_Inline (Forced);   --  the symbolic trace of a forced crash names it, also in an optimized build

   function Disk_Len (E : Entity_Id) return Natural is (Disk_Base (E) + Natural (Disk (E).Length));

   procedure Load_Diary (E : Entity_Id; Disk_Seed : in out Int) is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      Read_Lines (Path (E), Lines, Found);
      for I in 1 .. Natural (Lines.Length) loop
         declare
            L : constant String := Lines (I);
            N : constant Int := Int (Disk_Len (E)) + 1;
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

   --  0.058, a start from the checkpoint: the diary from byte Offset on (the first Base lines are the checkpoint's); the same checks.
   procedure Load_Diary_From (E : Entity_Id; Offset : Long_Long_Integer; Base : Natural; Disk_Seed : Int) is
      package SIO renames Ada.Streams.Stream_IO;
      use type Ada.Streams.Stream_Element_Offset;
      F : SIO.File_Type;
      Line_No : Natural := 0;
      Part : Unbounded_String;   --  a line across two blocks
      B : Ada.Streams.Stream_Element_Array (1 .. 262_144);
      N : Ada.Streams.Stream_Element_Offset;
      procedure One (L : String) is
         Want : constant Int := Int (Disk_Len (E)) + 1;
      begin
         Line_No := Line_No + 1;
         if Complete (L) then
            if Field (L, "tick") /= Want then
               raise Diary_Error with Msg ("err.gap", Name (E), Img (Base + Line_No), Img (Field (L, "tick")), Img (Want));
            elsif Disk_Seed >= 0 and then Field (L, "seed") /= Disk_Seed then
               raise Diary_Error with Msg ("err.seed", Name (E), Img (Base + Line_No), Img (Field (L, "seed")), Img (Disk_Seed));
            end if;
            Disk (E).Append (L);
         elsif L'Length > 0 then
            Warn (Msg ("warn.bad_line", Name (E), Img (Base + Line_No)));
         end if;
      end One;
   begin
      Disk (E).Clear;
      Disk_Base (E) := Base;
      SIO.Open (F, SIO.In_File, Path (E));
      if Long_Long_Integer (SIO.Size (F)) > Offset then
         SIO.Set_Index (F, SIO.Positive_Count (Offset + 1));
         loop
            SIO.Read (F, B, N);
            exit when N < 1;
            declare
               T : String (1 .. Natural (N));
               From : Positive := 1;
            begin
               for I in T'Range loop T (I) := Character'Val (B (Ada.Streams.Stream_Element_Offset (I))); end loop;
               for I in T'Range loop
                  if T (I) = ASCII.LF then
                     if Length (Part) > 0 then
                        Append (Part, T (From .. I - 1));
                        One (To_String (Part));
                        Part := Null_Unbounded_String;
                     else
                        One (T (From .. I - 1));
                     end if;
                     From := I + 1;
                  end if;
               end loop;
               if From <= T'Last then Append (Part, T (From .. T'Last)); end if;
            end;
            exit when N < B'Last;
         end loop;
         if Length (Part) > 0 then One (To_String (Part)); end if;
      end if;
      SIO.Close (F);
   exception
      when others =>
         if SIO.Is_Open (F) then SIO.Close (F); end if;
         raise;
   end Load_Diary_From;

   --  0.057: the last line of a diary without reading the whole file (a night run checks its own diaries after every session; reading
   --  them whole cost more than the session itself on a big save).  True: the file ends with a line break and its last line is complete
   --  with "tick":Want.  Anything else (or an error) is False: the caller reads the whole file as before.
   function Diary_Tail_Ok (P : String; Want : Natural) return Boolean is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count, Ada.Streams.Stream_Element_Offset;
      F : SIO.File_Type;
      Size : SIO.Count;
      B : Ada.Streams.Stream_Element_Array (1 .. 16_384);
      N : Ada.Streams.Stream_Element_Offset;
   begin
      if not Ada.Directories.Exists (P) then return False; end if;
      SIO.Open (F, SIO.In_File, P);
      Size := SIO.Size (F);
      if Size < 2 then SIO.Close (F); return Want = 0; end if;
      SIO.Set_Index (F, (if Size > B'Length then Size - B'Length + 1 else 1));
      SIO.Read (F, B, N);
      SIO.Close (F);
      declare
         T : String (1 .. Integer (N));
         From : Natural := 0;
      begin
         for I in T'Range loop T (I) := Character'Val (B (Ada.Streams.Stream_Element_Offset (I))); end loop;
         if T (T'Last) /= ASCII.LF then return False; end if;
         for I in reverse T'First .. T'Last - 1 loop
            if T (I) = ASCII.LF then From := I + 1; exit; end if;
         end loop;
         if From = 0 then
            if Size > B'Length then return False; end if;   --  a last line longer than the window: read it all
            From := 1;
         end if;
         declare
            L : constant String := T (From .. T'Last - 1);
         begin
            return Complete (L) and then Field (L, "tick") = Int (Want);
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (F) then SIO.Close (F); end if;
         return False;
   end Diary_Tail_Ok;

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
   Sections : constant String := "status drift trace players inbox run ledger preport";
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
      if Govern_Active then Dg_Add (V, "run", "govern", Msg ("govern.digest", Sim_Govern.Totals_Line), 5); end if;
      if Sim_Preport.Round_Count > 0 then Dg_Add (V, "preport", "preport", Sim_Preport.Digest_Line, 6); end if;
      if Sim_Next.Rounds > 0 then Dg_Add (V, "preport", "next", Sim_Next.Digest_Line, 6); end if;
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
                  if To_String (Name) /= "status" and then (To_String (Name) /= "preport" or else (for some E of V => To_String (E.Sec) = "preport")) then   --  [preport] only when players reported
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

   --  run_log.txt (save folder): technical metadata of the runs, kept OFF the console.  One entry per run (and per DRIFT stop), appended,
   --  each starting with a LOCAL time stamp "YYYY-MM-DD HH:MM:SS LABEL" (Ada.Calendar).  The stamp lives only here: no replay-verified file,
   --  no diary and no summary ever has a clock in it.  Only the last report.log_keep entries stay.  The log is a nicety: no error stops a run.
   function Local_Stamp return String is
      Y : Ada.Calendar.Year_Number;
      Mo : Ada.Calendar.Month_Number;
      D : Ada.Calendar.Day_Number;
      Sec : Ada.Calendar.Day_Duration;
      function P2 (N : Natural) return String is (Fx.Tail (Img (N), 2, '0'));
   begin
      Ada.Calendar.Split (Ada.Calendar.Clock, Y, Mo, D, Sec);
      declare
         T : constant Natural := Natural'Min (86_399, Natural (Integer'Max (0, Integer (Sec - 0.5))));
      begin
         return Img (Natural (Y)) & "-" & P2 (Natural (Mo)) & "-" & P2 (Natural (D)) & " " & P2 (T / 3600) & ":" & P2 (T mod 3600 / 60) & ":" & P2 (T mod 60);
      end;
   end Local_Stamp;

   function Is_Stamp (L : String) return Boolean is
      function Dig (I : Positive) return Boolean is (L (L'First + I - 1) in '0' .. '9');
   begin
      return L'Length >= 20 and then L (L'First + 4) = '-' and then L (L'First + 7) = '-' and then L (L'First + 10) = ' '
        and then L (L'First + 13) = ':' and then L (L'First + 16) = ':' and then Dig (1) and then Dig (4) and then Dig (6) and then Dig (9)
        and then Dig (12) and then Dig (15) and then Dig (18) and then Dig (19) and then L (L'First + 19) = ' ';
   end Is_Stamp;

   --  The bytes of all files below Dir (trend.txt, the timer of make night).  A file that vanishes while counting is skipped.
   function Folder_Bytes (Dir : String) return Int is
      Total : Int := 0;
      S : Ada.Directories.Search_Type;
      E : Ada.Directories.Directory_Entry_Type;
   begin
      Ada.Directories.Start_Search (S, Dir, "", [Ada.Directories.Directory | Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (S) loop
         Ada.Directories.Get_Next_Entry (S, E);
         begin
            if Ada.Directories.Simple_Name (E) /= "." and then Ada.Directories.Simple_Name (E) /= ".." then
               if Ada.Directories.Kind (E) in Ada.Directories.Directory then
                  Total := Total + Folder_Bytes (Ada.Directories.Full_Name (E));
               else
                  Total := Total + Int (Ada.Directories.Size (E));
               end if;
            end if;
         exception
            when others => null;   --  an entry that vanished (a .tmp renamed) is skipped
         end;
      end loop;
      Ada.Directories.End_Search (S);
      return Total;
   exception
      when others => return Total;
   end Folder_Bytes;

   function Tenths_Text (D : Duration) return String is   --  "8.1"
      T : constant Natural := Natural (Duration'Max (0.0, D) * 10);
   begin
      return Img (T / 10) & "." & Img (T mod 10);
   end Tenths_Text;

   function Secs_Text (D : Duration) return String is   --  "0.42"
      H : constant Natural := Natural (Duration'Max (0.0, D) * 100);
   begin
      return Img (H / 100) & "." & (if H mod 100 < 10 then "0" else "") & Img (H mod 100);
   end Secs_Text;

   procedure Append_Log (Label, Text : String) is
      Old : Str_Vectors.Vector;
      Found : Boolean;
      Entries, Seen : Natural := 0;
      Keep : constant Natural := Natural (Int'Max (1, Limit ("report.log_keep", 500)));
      F : TIO.File_Type;
   begin
      Read_Lines ("run_log.txt", Old, Found);
      for L of Old loop if Is_Stamp (L) then Entries := Entries + 1; end if; end loop;
      TIO.Create (F, TIO.Out_File, "run_log.txt.tmp");
      for L of Old loop
         if Is_Stamp (L) then Seen := Seen + 1; end if;
         if Seen > 0 and then Seen + Keep - 1 > Entries then TIO.Put_Line (F, L); end if;   --  the last Keep - 1 entries stay
      end loop;
      TIO.Put (F, Local_Stamp & " " & Label & ASCII.LF & (if Text'Length > 0 and then Text (Text'Last) = ASCII.LF then Text (Text'First .. Text'Last - 1) else Text));
      TIO.Close (F);   --  Text_IO ends the last line itself
      if Ada.Directories.Exists ("run_log.txt") then Ada.Directories.Delete_File ("run_log.txt"); end if;
      Ada.Directories.Rename ("run_log.txt.tmp", "run_log.txt");
   exception
      when others => null;
   end Append_Log;

   --  trend.txt (save folder): ONE line per finished session (a run that added ticks), appended by every run, also by make night.  The first
   --  line is a '#' legend.  Only the last report.trend_keep lines stay.  The time stamp is only here, not in any replay-verified file.
   procedure Append_Trend (Line : String) is
      Old : Str_Vectors.Vector;
      Found : Boolean;
      Rows : Natural := 0;
      Seen : Natural := 0;
      Keep : constant Natural := Natural (Int'Max (2, Limit ("report.trend_keep", 2000)));
      Order : Unbounded_String;
      F : TIO.File_Type;
   begin
      for E in Entity_Id loop Append (Order, (if E = Entity_Id'First then "" else ",") & Sim_World.Show (Name (E))); end loop;
      Read_Lines ("trend.txt", Old, Found);
      for L of Old loop if L'Length > 0 and then L (L'First) = 'T' then Rows := Rows + 1; end if; end loop;
      TIO.Create (F, TIO.Out_File, "trend.txt.tmp");
      TIO.Put_Line (F, Msg ("trend.head", To_String (Order)));
      for L of Old loop
         if L'Length > 0 and then L (L'First) = 'T' then
            Seen := Seen + 1;
            if Seen + Keep - 1 > Rows then TIO.Put_Line (F, L); end if;   --  the last Keep - 1 lines stay
         end if;
      end loop;
      TIO.Put_Line (F, Line);
      TIO.Close (F);
      if Ada.Directories.Exists ("trend.txt") then Ada.Directories.Delete_File ("trend.txt"); end if;
      Ada.Directories.Rename ("trend.txt.tmp", "trend.txt");
   exception
      when others => null;
   end Append_Trend;

   --  --runlog / --trend: the last lines (limit key Tail_Key) of a file of the save folder
   procedure Print_Tail (File, Tail_Key, None_Key : String) is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Tail : constant Natural := Natural (Int'Max (1, Limit (Tail_Key, 40)));
   begin
      Read_Lines (File, Lines, Found);
      if not Found or else Lines.Is_Empty then
         TIO.Put_Line (TIO.Standard_Error, Msg (None_Key, Ada.Directories.Full_Name (File)));
         Ada.Command_Line.Set_Exit_Status (2);
         return;
      end if;
      begin
         for I in Natural'Max (1, Natural (Lines.Length) - Tail + 1) .. Natural (Lines.Length) loop TIO.Put_Line (Lines (I)); end loop;
      exception
         when others => null;   --  stdout is a closed pipe (| head)
      end;
   end Print_Tail;

   --  --chatlog: the last chat.log_tail lines of diaries/chat.txt as "t6001 you -> Eve: hello"; nothing is simulated.
   procedure Print_Chatlog is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Tail : constant Natural := Natural (Int'Max (1, Limit ("chat.log_tail", 30)));
      First : Natural := 0;
      Count : Natural := 0;
   begin
      Read_Lines (Chat_Path, Lines, Found);
      if Found and then Natural (Lines.Length) > 0 and then Lines.First_Element'Length > 7 and then Lines.First_Element (1 .. 7) = "# seed " then
         Sim_Chat.Init (Int'Value (Lines.First_Element (8 .. Lines.First_Element'Last)));   --  the check number h= depends on the seed
      end if;
      for I in reverse 1 .. Natural (Lines.Length) loop
         exit when Count >= Tail;
         if Lines.Element (I)'Length > 0 and then Lines.Element (I) (1) = 'C' then Count := Count + 1; First := I; end if;
      end loop;
      if not Found or else Count = 0 then
         TIO.Put_Line (TIO.Standard_Error, Msg ("chatlog.none", Ada.Directories.Full_Name (Chat_Path)));
         Ada.Command_Line.Set_Exit_Status (2);
         return;
      end if;
      begin
         for I in First .. Natural (Lines.Length) loop
            declare
               P : Sim_Chat.Parsed;
               OK : Boolean;
            begin
               Sim_Chat.Parse_Line (Lines (I), P, OK);
               if OK then
                  TIO.Put_Line (Msg ("chatlog.line", Img (P.Tick), Sim_World.Show (To_String (P.Who)), Sim_World.Show (To_String (P.To_Id)), To_String (P.Text)));
               end if;
            end;
         end loop;
      exception
         when others => null;   --  stdout is a closed pipe (| head)
      end;
   end Print_Chatlog;

   --  --frustration: the MiniMax report (data/frustration.txt); READ-ONLY, nothing is simulated or written.
   --  Sources: diaries/petitions.txt (P lines: s=, wesen=, player=, out=grant|partial|refuse), diaries/sessions.txt (S start= len=,
   --  W tick=: the session ranges) and diaries/<id>.jsonl ("tick", state "mood").  The score of a wesen in a session is
   --  frustration.refuse_weight (10) x its refused petitions + the depth of its lowest mood below 0; the worst wesen holds the
   --  largest such score, the MiniMax line names the wesen whose worst case is the smallest.  The player load is the number of
   --  petitions a player decided in one session.  Nothing changes the grant rate: this is a report only.
   procedure Print_Frustration is
      type Nat_Array is array (Positive range <>) of Natural;
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Max_S : constant := 5_000;   --  sessions counted: the newest ones (0.057: was the first ones), or the window of --since-session
      W_Ref : constant Natural := Natural (Int'Max (0, Limit ("frustration.refuse_weight", 10)));
      N_S : Natural := 0;   --  sessions in the window
      N_All : Natural := 0;   --  sessions found
      Base : Natural := 0;   --  session Base + k is index k
      Name_W : constant := 12;
      Cell_W : constant := 9;

      function Field (L, Key : String) return String is   --  value of " key=" (or "key=" at the start), "" if none
         K : constant String := Key & "=";
      begin
         for I in L'First .. L'Last - K'Length + 1 loop
            if L (I .. I + K'Length - 1) = K and then (I = L'First or else L (I - 1) = ' ') then
               declare
                  J : Natural := I + K'Length;
               begin
                  while J <= L'Last and then L (J) /= ' ' loop J := J + 1; end loop;
                  return L (I + K'Length .. J - 1);
               end;
            end if;
         end loop;
         return "";
      end Field;

      function Num (S : String) return Natural is
        (if S'Length in 1 .. 9 and then (for all C of S => C in '0' .. '9') then Natural'Value (S) else 0);

      function Pad_L (S : String; W : Positive) return String is
        (Fx."*" (Natural'Max (0, W - S'Length), ' ') & S);
      function Pad_R (S : String; W : Positive) return String is
        (if S'Length >= W then S (S'First .. S'First + W - 1) else S & Fx."*" (W - S'Length, ' '));
      function Cell (S : String) return String is (Pad_L (S, Cell_W));
      function Pct (A, B : Natural) return Natural is (if B = 0 then 0 else Natural (Int (A) * 100 / Int (B)));
      procedure Put (S : String) is begin TIO.Put_Line (S); end Put;
      procedure Para (S : String) is
      begin
         for L of Sim_Voice.Wrap (S, 79) loop Put (L); end loop;
      end Para;
   begin
      Read_Lines ("diaries/sessions.txt", Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'S' and then L (L'First + 1) in '0' .. '9' then N_All := N_All + 1; end if;
      end loop;
      if Since_Session > 1 then Base := Natural'Min (Since_Session - 1, Natural'Max (1, N_All) - 1); end if;
      if N_All - Base > Max_S then Base := N_All - Max_S; end if;
      N_S := N_All - Base;
      if N_S = 0 then
         TIO.Put_Line (TIO.Standard_Error, Msg ("frust.none", Ada.Directories.Full_Name ("diaries/sessions.txt")));
         Ada.Command_Line.Set_Exit_Status (2);
         return;
      end if;
      declare
         First, Last : Nat_Array (1 .. N_S) := [others => 0];   --  ticks First .. Last belong to session n
         type Wesen_Session is array (Entity_Id, 1 .. N_S) of Natural;
         Refused : Wesen_Session := [others => [others => 0]];
         Low : array (Entity_Id, 1 .. N_S) of Int := [others => [others => 0]];
         Seen : array (Entity_Id, 1 .. N_S) of Boolean := [others => [others => False]];
         Tot_Pet, Tot_Grant, Tot_Part, Tot_Ref : array (Entity_Id) of Natural := [others => 0];
         Low_All : array (Entity_Id) of Int := [others => 0];
         Worst, Worst_S : array (Entity_Id) of Natural := [others => 0];
         Players : Str_Vectors.Vector;   --  internal player ids in order of first appearance
         Max_P : constant := 16;
         P_Load : array (1 .. Max_P, 1 .. N_S) of Natural := [others => [others => 0]];
         P_Tot, P_Ref : array (1 .. Max_P) of Natural := [others => 0];
         All_Pet, All_Ref : Natural := 0;
         K : Natural := 0;

         function Session_Of (T : Natural) return Natural is
         begin
            for S in 1 .. N_S loop
               if T >= First (S) and then T <= Last (S) then return S; end if;
            end loop;
            return 0;
         end Session_Of;

         function Player_Index (P : String) return Natural is
         begin
            for I in 1 .. Natural (Players.Length) loop
               if Players (I) = P then return I; end if;
            end loop;
            if Natural (Players.Length) >= Max_P then return 0; end if;
            Players.Append (P);
            return Natural (Players.Length);
         end Player_Index;

         function Score (E : Entity_Id; S : Positive) return Natural is
           (W_Ref * Refused (E, S) + Natural (Int'Max (0, -Low (E, S))));
      begin
         for L of Lines loop   --  S<n> start=<t> ... len=<ticks>, then W<n> tick=<end>
            if L'Length > 1 and then L (L'First) in 'S' | 'W' and then L (L'First + 1) in '0' .. '9' then
               declare
                  Sp : Natural := L'First + 1;
               begin
                  while Sp <= L'Last and then L (Sp) /= ' ' loop Sp := Sp + 1; end loop;
                  K := Num (L (L'First + 1 .. Sp - 1));
                  K := (if K > Base then K - Base else 0);
                  if K in 1 .. N_S then
                     if L (L'First) = 'S' then
                        First (K) := Num (Field (L, "start")) + 1;
                        Last (K) := Num (Field (L, "start")) + Num (Field (L, "len"));
                     elsif Num (Field (L, "tick")) > 0 then
                        Last (K) := Num (Field (L, "tick"));
                     end if;
                  end if;
               end;
            end if;
         end loop;
         Lines.Clear;
         Read_Lines ("diaries/petitions.txt", Lines, Found);
         for L of Lines loop   --  P<n> t=<tick> s=<session> ... wesen=<id> ... player=<id> out=grant|partial|refuse
            if L'Length > 1 and then L (L'First) = 'P' and then L (L'First + 1) in '0' .. '9' then
               declare
                  Out_V : constant String := Field (L, "out");
                  S : Natural := Num (Field (L, "s"));
                  E : Natural := 0;
                  P : Natural := 0;
               begin
                  S := (if S > Base then S - Base else 0);
                  if S not in 1 .. N_S then S := Session_Of (Num (Field (L, "t"))); end if;
                  if Base > 0 and then S = 0 then goto Next_Petition; end if;   --  before the window
                  P := Player_Index (Field (L, "player"));
                  for X in Entity_Id loop
                     if Name (X) = Field (L, "wesen") then E := Natural (X); end if;
                  end loop;
                  if Out_V'Length > 0 then
                     All_Pet := All_Pet + 1;
                     if Out_V = "refuse" then All_Ref := All_Ref + 1; end if;
                     if E > 0 then
                        Tot_Pet (Entity_Id (E)) := Tot_Pet (Entity_Id (E)) + 1;
                        if Out_V = "grant" then Tot_Grant (Entity_Id (E)) := Tot_Grant (Entity_Id (E)) + 1;
                        elsif Out_V = "partial" then Tot_Part (Entity_Id (E)) := Tot_Part (Entity_Id (E)) + 1;
                        elsif Out_V = "refuse" then
                           Tot_Ref (Entity_Id (E)) := Tot_Ref (Entity_Id (E)) + 1;
                           if S > 0 then Refused (Entity_Id (E), S) := Refused (Entity_Id (E), S) + 1; end if;
                        end if;
                     end if;
                     if P > 0 then
                        P_Tot (P) := P_Tot (P) + 1;
                        if Out_V = "refuse" then P_Ref (P) := P_Ref (P) + 1; end if;
                        if S > 0 then P_Load (P, S) := P_Load (P, S) + 1; end if;
                     end if;
                  end if;
                  <<Next_Petition>> null;
               end;
            end if;
         end loop;
         Lines.Clear;
         for E in Entity_Id loop   --  the lowest mood of each session, streamed: {"tick":N, ... "mood":M, ...}
            if Ada.Directories.Exists (Path (E)) then
               declare
                  package SIO renames Ada.Streams.Stream_IO;
                  F : SIO.File_Type;
                  S : Natural := 1;
                  Size : SIO.Count;
                  Buf : Ada.Streams.Stream_Element_Array (1 .. 65_536);
                  Got : Ada.Streams.Stream_Element_Offset;
                  Part : Unbounded_String;   --  a line cut by the end of a buffer
                  Key_T : constant String := '"' & "tick" & '"' & ":";

                  function Tick_Of (L : String) return Natural is   --  the tick of a diary line, 0 if none
                     At_T : constant Natural := Fx.Index (L, Key_T);
                     T : Natural := 0;
                     J : Natural;
                  begin
                     if At_T = 0 then return 0; end if;
                     J := At_T + Key_T'Length;
                     while J <= L'Last and then L (J) in '0' .. '9' loop
                        if T < 100_000_000 then T := T * 10 + Character'Pos (L (J)) - Character'Pos ('0'); end if;
                        J := J + 1;
                     end loop;
                     return T;
                  end Tick_Of;

                  --  The tick of the first whole line that starts after byte Pos (0: none in the next 4 KB).
                  function Tick_After (Pos : SIO.Positive_Count) return Natural is
                     B : Ada.Streams.Stream_Element_Array (1 .. 4_096);
                     N : Ada.Streams.Stream_Element_Offset;
                     Txt : String (1 .. 4_096);
                     From : Natural := 0;
                  begin
                     SIO.Set_Index (F, Pos);
                     SIO.Read (F, B, N);
                     for I in 1 .. Integer (N) loop Txt (I) := Character'Val (B (Ada.Streams.Stream_Element_Offset (I))); end loop;
                     for I in 1 .. Integer (N) loop
                        if Txt (I) = ASCII.LF then From := I + 1; exit; end if;
                     end loop;
                     if From = 0 or else From > Integer (N) then return 0; end if;
                     for I in From .. Integer (N) loop
                        if Txt (I) = ASCII.LF then return Tick_Of (Txt (From .. I - 1)); end if;
                     end loop;
                     return 0;
                  end Tick_After;

                  procedure One_Line (L : String);

                  procedure Feed (Chunk : String) is   --  split into lines; the rest waits in Part
                     From : Positive := Chunk'First;
                  begin
                     for I in Chunk'Range loop
                        if Chunk (I) = ASCII.LF then
                           if Length (Part) > 0 then
                              Append (Part, Chunk (From .. I - 1));
                              One_Line (To_String (Part));
                              Part := Null_Unbounded_String;
                           else
                              One_Line (Chunk (From .. I - 1));
                           end if;
                           From := I + 1;
                        end if;
                     end loop;
                     if From <= Chunk'Last then Append (Part, Chunk (From .. Chunk'Last)); end if;
                  end Feed;

                  procedure One_Line (L : String) is
                  begin
                     declare
                        T_At : constant Natural := Fx.Index (L, """tick"":");
                        M_At : constant Natural := Fx.Index (L, """mood"":");
                        T : Natural := 0;
                        M : Int := 0;
                        Neg : Boolean := False;
                        J : Natural;
                     begin
                        if T_At > 0 and then M_At > 0 then
                           J := T_At + 7;
                           while J <= L'Last and then L (J) in '0' .. '9' loop
                              if T < 100_000_000 then T := T * 10 + Character'Pos (L (J)) - Character'Pos ('0'); end if;
                              J := J + 1;
                           end loop;
                           J := M_At + 7;
                           if J <= L'Last and then L (J) = '-' then Neg := True; J := J + 1; end if;
                           while J <= L'Last and then L (J) in '0' .. '9' loop
                              if M < 100_000 then M := M * 10 + Int (Character'Pos (L (J)) - Character'Pos ('0')); end if;
                              J := J + 1;
                           end loop;
                           if Neg then M := -M; end if;
                           if S > N_S or else T < First (S) or else T > Last (S) then S := Natural'Max (1, Session_Of (T)); end if;
                           if T >= First (S) and then T <= Last (S) then
                              if not Seen (E, S) or else M < Low (E, S) then Low (E, S) := M; end if;
                              Seen (E, S) := True;
                           end if;
                        end if;
                     end;
                  end One_Line;

                  Lo, Hi, Mid : SIO.Positive_Count;
                  Skip_Part : Boolean;
                  use type SIO.Count, Ada.Streams.Stream_Element_Offset;
               begin
                  SIO.Open (F, SIO.In_File, Path (E));
                  Size := SIO.Size (F);
                  Lo := 1;   --  a byte whose next whole line is still before the window (or the start of the file)
                  if Base > 0 and then First (1) > 1 and then Size > 8_192 then   --  a binary search on the tick: the window, not the whole diary
                     Hi := Size;
                     while Hi - Lo > 4_096 loop
                        Mid := Lo + (Hi - Lo) / 2;
                        declare
                           T : constant Natural := Tick_After (Mid);
                        begin
                           if T /= 0 and then T < First (1) then Lo := Mid; else Hi := Mid; end if;
                        end;
                     end loop;
                  end if;
                  SIO.Set_Index (F, Lo);
                  Skip_Part := Lo > 1;   --  the cut line before the first whole one is left out
                  loop
                     SIO.Read (F, Buf, Got);
                     exit when Got = 0;
                     declare
                        C : String (1 .. Integer (Got));
                        Start : Positive := 1;
                     begin
                        for I in C'Range loop C (I) := Character'Val (Buf (Ada.Streams.Stream_Element_Offset (I))); end loop;
                        if Skip_Part then
                           Start := C'Last + 1;
                           for I in C'Range loop
                              if C (I) = ASCII.LF then Start := I + 1; Skip_Part := False; exit; end if;
                           end loop;
                        end if;
                        if Start <= C'Last then Feed (C (Start .. C'Last)); end if;
                     end;
                     exit when Got < Buf'Last;
                  end loop;
                  if Length (Part) > 0 then One_Line (To_String (Part)); end if;
                  SIO.Close (F);
               exception
                  when others => if SIO.Is_Open (F) then SIO.Close (F); end if;
               end;
            end if;
         end loop;
         for E in Entity_Id loop
            for S in 1 .. N_S loop
               if Seen (E, S) and then Low (E, S) < Low_All (E) then Low_All (E) := Low (E, S); end if;
               if Worst_S (E) = 0 or else Score (E, S) > Worst (E) then Worst (E) := Score (E, S); Worst_S (E) := S; end if;
            end loop;
         end loop;
         begin
            Put (Msg ("frust.title", Img (N_S), Img (All_Pet)));
            if Base > 0 then Put (Msg ("frust.window", Img (Base + 1), Img (Base + N_S), Img (N_All))); end if;
            Put ("");
            Para (Msg ("frust.wesen.head", Img (W_Ref)));
            Put (Pad_R ("", Name_W) & Cell (Msg ("frust.col.pet")) & Cell (Msg ("frust.col.grant")) & Cell (Msg ("frust.col.part"))
                 & Cell (Msg ("frust.col.ref")) & Cell (Msg ("frust.col.low")) & Cell (Msg ("frust.col.worst")) & Cell (Msg ("frust.col.in")));
            for E in Entity_Id loop
               Put (Pad_R (Display (E), Name_W) & Cell (Img (Tot_Pet (E))) & Cell (Img (Tot_Grant (E))) & Cell (Img (Tot_Part (E)))
                    & Cell (Img (Tot_Ref (E))) & Cell (Img (Low_All (E))) & Cell (Img (Worst (E))) & Cell ("s" & Img (Worst_S (E) + Base)));
            end loop;
            declare
               Hi, Lo : Entity_Id := Entity_Id'First;
            begin
               for E in Entity_Id loop
                  if Worst (E) > Worst (Hi) then Hi := E; end if;
                  if Worst (E) < Worst (Lo) then Lo := E; end if;
               end loop;
               Put ("");
               Para (Msg ("frust.worst", Display (Hi), Img (Worst (Hi)), Img (Worst_S (Hi) + Base), Img (Refused (Hi, Worst_S (Hi))),
                          Img (Low (Hi, Worst_S (Hi)))));
               Para (Msg ("frust.minimax", Display (Lo), Img (Worst (Lo)), Img (Worst_S (Lo) + Base), Img (Worst (Hi) - Worst (Lo))));
            end;
            Put ("");
            Para (Msg ("frust.player.head"));
            Put (Pad_R ("", Name_W) & Cell (Msg ("frust.col.dec")) & Cell (Msg ("frust.col.ref")) & Cell (Msg ("frust.col.share"))
                 & Cell (Msg ("frust.col.max")) & Cell (Msg ("frust.col.in")) & Cell (Msg ("frust.col.mean")));
            declare
               Hi : Natural := 0;
               Hi_Max, Hi_S : Natural := 0;
            begin
               for P in 1 .. Natural (Players.Length) loop
                  declare
                     Mx, Ms, Busy : Natural := 0;
                  begin
                     for S in 1 .. N_S loop
                        if P_Load (P, S) > Mx then Mx := P_Load (P, S); Ms := S; end if;
                        if P_Load (P, S) > 0 then Busy := Busy + 1; end if;
                     end loop;
                     Put (Pad_R (Sim_World.Show (Players (P)), Name_W) & Cell (Img (P_Tot (P))) & Cell (Img (P_Ref (P)))
                          & Cell (Img (Pct (P_Ref (P), P_Tot (P))) & "%") & Cell (Img (Mx)) & Cell ("s" & Img (Ms + (if Ms > 0 then Base else 0)))
                          & Cell (Img (P_Tot (P) / Natural'Max (1, N_S)) & "." & Img ((P_Tot (P) * 10 / Natural'Max (1, N_S)) mod 10)));
                     if Hi = 0 or else Mx > Hi_Max or else (Mx = Hi_Max and then P_Tot (P) > P_Tot (Hi)) then
                        Hi := P; Hi_Max := Mx; Hi_S := Ms;
                     end if;
                  end;
               end loop;
               Put ("");
               if Hi > 0 then
                  Para (Msg ("frust.load", Sim_World.Show (Players (Hi)), Img (Hi_Max), Img (Hi_S + (if Hi_S > 0 then Base else 0)), Img (P_Tot (Hi)), Img (Pct (P_Ref (Hi), P_Tot (Hi)))));
               else
                  Para (Msg ("frust.load.none"));
               end if;
            end;
            Put ("");
            Put (Msg ("frust.concl.head"));
            Para (Msg ("frust.concl", Img (All_Ref), Img (All_Pet), Img (Pct (All_Ref, All_Pet))));
         exception
            when others => null;   --  stdout is a closed pipe (| head)
         end;
      end;
   end Print_Frustration;

   --  --wordstat: the vocabulary report (Sim_Wordstat, data/wordstat.txt); READ-ONLY, nothing is simulated or written.
   --  Sources: entities/<id>/words.txt (what is known, how, when), and the later use of a word: diaries/screens.txt (show, read, pin, cmd,
   --  leave, blend by the wesen), diaries/dictionary.txt (word= and mean= of its proposals; st=A is the agreed meaning), diaries/votes.txt
   --  (kind=favourite choices), diaries/petitions.txt (the words of req=), entities/<id>/notebook.txt (if there is one).
   --  PROOF-LATER: Importance 2/10, Urgency 1/10, SPARK2 (percent arithmetic on counts, bounded slices)
   procedure Print_Wordstat (Evolve, Active : Boolean := False) is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Name_W : constant := 36;   --  label column
      Cell_W : constant := 7;
      Total_W : constant := 8;


      function Nth (L : String; N : Positive) return String is   --  N-th blank-separated field, "" if none
         Pos : Natural := L'First;
         Count : Natural := 0;
      begin
         while Pos <= L'Last loop
            while Pos <= L'Last and then L (Pos) = ' ' loop Pos := Pos + 1; end loop;
            exit when Pos > L'Last;
            declare
               Start : constant Positive := Pos;
            begin
               while Pos <= L'Last and then L (Pos) /= ' ' loop Pos := Pos + 1; end loop;
               Count := Count + 1;
               if Count = N then return L (Start .. Pos - 1); end if;
            end;
         end loop;
         return "";
      end Nth;

      function Num (S : String) return Natural is
        (if S'Length in 1 .. 9 and then (for all C of S => C in '0' .. '9') then Natural'Value (S) else 0);

      function Ent_Of (S : String) return Natural is
      begin
         for E in Entity_Id loop
            if Name (E) = S then return Natural (E); end if;
         end loop;
         return 0;
      end Ent_Of;

      procedure Ids (E : Natural; List : String; Tick : Natural) is   --  "*12,5,40": every number is a word id
         Acc : Natural := 0;
         Have : Boolean := False;
      begin
         if E = 0 then return; end if;
         for I in List'First .. List'Last + 1 loop
            if I <= List'Last and then List (I) in '0' .. '9' then
               if Acc < 100_000_000 then Acc := Acc * 10 + Character'Pos (List (I)) - Character'Pos ('0'); end if;
               Have := True;
            else
               if Have and then Acc > 0 then Sim_Wordstat.Seen_Id (E, Acc, Tick); end if;
               Acc := 0;
               Have := False;
            end if;
         end loop;
      end Ids;

      procedure Texts (E : Natural; List : String; Tick : Natural; Why : Sim_Evolve.Event_Kind := Sim_Evolve.Mention) is   --  letters and digits make a word, anything else separates
         From : Natural := 0;
      begin
         if E = 0 then return; end if;
         for I in List'First .. List'Last + 1 loop
            if I <= List'Last and then List (I) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | Character'Val (128) .. Character'Val (255) then
               if From = 0 then From := I; end if;
            else
               if From /= 0 then Sim_Wordstat.Seen_Text (E, Ada.Characters.Handling.To_Lower (List (From .. I - 1)), Tick, Why); end if;
               From := 0;
            end if;
         end loop;
      end Texts;

      function Pad_L (S : String; W : Positive) return String is
        (Fx."*" (Natural'Max (0, W - S'Length), ' ') & S);
      function Pad_R (S : String; W : Positive) return String is
        (if S'Length >= W then S (S'First .. S'First + W - 1) else S & Fx."*" (W - S'Length, ' '));
      function Pct (A, B : Natural) return Natural is (if B = 0 then 0 else Natural (Int (A) * 100 / Int (B)));
      function Cell (N : Natural) return String is (Pad_L (Img (N), Cell_W));

      Per : array (0 .. Integer (Entity_Id'Last)) of Sim_Wordstat.Stat;
      Head : Unbounded_String;

      procedure Put (S : String) is begin TIO.Put_Line (S); end Put;

      --  active=1/2 saves (diaries/active.txt): the live active words only, by kind, the most used ones and the shared beginnings
      --  (themes); a word counts as dormant from its dormant line until a wake line.  Nothing is printed on an older save.
      procedure Active_Only is
         package Count_Maps is new Ada.Containers.Indefinite_Hashed_Maps (String, Natural, Ada.Strings.Hash, "=");
         AL : Str_Vectors.Vector;
         AF : Boolean;
         Any_State : Boolean := False;
         Dorm : Str_Sets.Set;
         type Kind_List is array (Positive range <>) of Sim_Wordstat.Kind;
         Kinds : constant Kind_List := [Sim_Wordstat.Start, Sim_Wordstat.World, Sim_Wordstat.Taught, Sim_Wordstat.Screen, Sim_Wordstat.Coined, Sim_Wordstat.Other];
         Cnt : array (Entity_Id, Kinds'Range) of Natural := [others => [others => 0]];
         Act, Used_A : array (Entity_Id) of Natural := [others => 0];
         Fam : Count_Maps.Map;
         use type Sim_Wordstat.Kind;
         function Field (L : String; N : Positive) return String is
            P : Natural := L'First;
            K : Natural := 0;
         begin
            while P <= L'Last loop
               declare
                  Stop : Natural := P;
               begin
                  while Stop <= L'Last and then L (Stop) /= ' ' loop Stop := Stop + 1; end loop;
                  K := K + 1;
                  if K = N then return L (P .. Stop - 1); end if;
                  P := Stop + 1;
               end;
            end loop;
            return "";
         end Field;
         procedure Row (Label : String; V : access function (E : Entity_Id) return Natural) is
            Line : Unbounded_String := To_Unbounded_String (Pad_R (Label, Name_W));
            Sum : Natural := 0;
         begin
            for E in Entity_Id loop
               Append (Line, Pad_L (Img (V (E)), Cell_W));
               Sum := Sum + V (E);
            end loop;
            Append (Line, Pad_L (Img (Sum), Total_W));
            Put (To_String (Line));
         end Row;
         function Act_Of (E : Entity_Id) return Natural is (Act (E));
         function Used_Of (E : Entity_Id) return Natural is (Used_A (E));
      begin
         if not Ada.Directories.Exists ("diaries/active.txt") then return; end if;
         Read_Lines ("diaries/active.txt", AL, AF);
         for L of AL loop
            if L'Length > 2 and then L (L'First) = 'A' then
               declare
                  Op : constant String := Field (L, 5);
                  Key : constant String := Field (L, 4) & ":" & Token (L, "word");
               begin
                  if Op = "dormant" then Dorm.Include (Key);
                  elsif Op = "wake" then Dorm.Exclude (Key);
                  elsif Op = "state" then Any_State := True;
                  end if;
               end;
            end if;
         end loop;
         if not Any_State then return; end if;
         declare
            package Nat_V is new Ada.Containers.Vectors (Positive, Natural);
            Uses : array (Entity_Id) of Nat_V.Vector;
         begin
            for E in Entity_Id loop Uses (E) := Nat_V.To_Vector (0, Ada.Containers.Count_Type (Natural'Max (1, Sim_Wordstat.Word_Count (Positive (E))))); end loop;
            for J in 1 .. Sim_Wordstat.Event_Count loop
               declare
                  Ev : constant Sim_Wordstat.Log_Event := Sim_Wordstat.Event_At (J);
               begin
                  if Ev.E in 1 .. 4 and then Ev.Index in 1 .. Natural (Uses (Entity_Id (Ev.E)).Length) then
                     Uses (Entity_Id (Ev.E)).Replace_Element (Ev.Index, Uses (Entity_Id (Ev.E)).Element (Ev.Index) + 1);
                  end if;
               end;
            end loop;
            TIO.New_Line;
            for L of Sim_Voice.Wrap (Msg ("wordstat.act.title"), 79) loop Put (L); end loop;
            Put (Pad_R ("", Name_W) & Pad_L (Sim_World.Show (Name (1)), Cell_W) & Pad_L (Sim_World.Show (Name (2)), Cell_W)
                 & Pad_L (Sim_World.Show (Name (3)), Cell_W) & Pad_L (Sim_World.Show (Name (4)), Cell_W) & Pad_L (Msg ("wordstat.col.total"), Total_W));
            for E in Entity_Id loop
               for I in 1 .. Sim_Wordstat.Word_Count (Positive (E)) loop
                  declare
                     K : constant Sim_Wordstat.Kind := Sim_Wordstat.Word_Kind (Positive (E), I);
                     T : constant String := Sim_Wordstat.Word_Text (Positive (E), I);
                  begin
                     if K not in Sim_Wordstat.Chess | Sim_Wordstat.Number and then not Dorm.Contains (Name (E) & ":" & T) then
                        Act (E) := Act (E) + 1;
                        if Uses (E) (I) > 0 then Used_A (E) := Used_A (E) + 1; end if;
                        for J in Kinds'Range loop
                           if Kinds (J) = K then Cnt (E, J) := Cnt (E, J) + 1; end if;
                        end loop;
                        if T'Length >= 4 and then (for all C of T (T'First .. T'First + 2) => C in 'a' .. 'z') then
                           declare
                              F : constant String := T (T'First .. T'First + 2);
                           begin
                              if Fam.Contains (F) then Fam.Replace (F, Fam.Element (F) + 1); else Fam.Insert (F, 1); end if;
                           end;
                        end if;
                     end if;
                  end;
               end loop;
            end loop;
            Row ("  " & Msg ("wordstat.act.active"), Act_Of'Access);
            for J in Kinds'Range loop
               declare
                  function Of_K (E : Entity_Id) return Natural is (Cnt (E, J));
               begin
                  Row ("    " & Msg ("wordstat.k." & Ada.Characters.Handling.To_Lower (Sim_Wordstat.Kind'Image (Kinds (J)))), Of_K'Access);
               end;
            end loop;
            Row ("  " & Msg ("wordstat.act.used"), Used_Of'Access);
            TIO.New_Line;
            Put (Msg ("wordstat.act.top"));
            for E in Entity_Id loop
               declare
                  Line : Unbounded_String;
                  Taken : array (1 .. Natural'Max (1, Sim_Wordstat.Word_Count (Positive (E)))) of Boolean := [others => False];
               begin
                  for R in 1 .. Natural (Limit ("wordstat.act_top", 6)) loop
                     declare
                        Best, Best_U : Natural := 0;
                     begin
                        for I in 1 .. Sim_Wordstat.Word_Count (Positive (E)) loop
                           if not Taken (I) and then Uses (E) (I) > Best_U
                             and then Sim_Wordstat.Word_Kind (Positive (E), I) not in Sim_Wordstat.Chess | Sim_Wordstat.Number
                             and then not Dorm.Contains (Name (E) & ":" & Sim_Wordstat.Word_Text (Positive (E), I))
                           then
                              Best := I;
                              Best_U := Uses (E) (I);
                           end if;
                        end loop;
                        exit when Best = 0;
                        Taken (Best) := True;
                        Append (Line, (if R = 1 then "" else ", ") & Sim_Wordstat.Word_Text (Positive (E), Best) & " " & Img (Best_U));
                     end;
                  end loop;
                  for L of Sim_Voice.Wrap ("  " & Sim_World.Show (Name (E)) & ": " & (if Length (Line) = 0 then "-" else To_String (Line)), 79) loop Put (L); end loop;
               end;
            end loop;
            declare
               Line : Unbounded_String;
               Done : Str_Sets.Set;
            begin
               for R in 1 .. Natural (Limit ("wordstat.act_themes", 10)) loop
                  declare
                     Best : Unbounded_String;
                     Best_N : Natural := 0;
                  begin
                     for C in Fam.Iterate loop
                        declare
                           K : constant String := Count_Maps.Key (C);
                           N : constant Natural := Count_Maps.Element (C);
                        begin
                           if not Done.Contains (K) and then (N > Best_N or else (N = Best_N and then N > 0 and then K < To_String (Best))) then
                              Best := To_Unbounded_String (K);
                              Best_N := N;
                           end if;
                        end;
                     end loop;
                     exit when Best_N < 2;
                     Done.Include (To_String (Best));
                     Append (Line, (if R = 1 then "" else ", ") & To_String (Best) & "- " & Img (Best_N));
                  end;
               end loop;
               TIO.New_Line;
               for L of Sim_Voice.Wrap (Msg ("wordstat.act.themes", (if Length (Line) = 0 then "-" else To_String (Line))), 79) loop Put (L); end loop;
               for L of Sim_Voice.Wrap (Msg ("wordstat.act.concl", Img (Act (1) + Act (2) + Act (3) + Act (4)), Img (Natural (Dorm.Length)),
                                             Img (Used_A (1) + Used_A (2) + Used_A (3) + Used_A (4))), 79) loop Put (L); end loop;
            end;
         end;
      end Active_Only;

      --  One row: the label and the value of every wesen, then the total.
      generic
         with function Pick (S : Sim_Wordstat.Stat) return Natural;
      procedure Row (Label : String);
      procedure Row (Label : String) is
         R : Unbounded_String := To_Unbounded_String (Pad_R (Label, Name_W));
      begin
         for E in 1 .. Integer (Entity_Id'Last) loop Append (R, Cell (Pick (Per (E)))); end loop;
         Append (R, Pad_L (Img (Pick (Per (0))), Total_W));
         Put (To_String (R));
      end Row;

      function Total_Of (S : Sim_Wordstat.Stat) return Natural is (S.Total);
      function Distinct_Of (S : Sim_Wordstat.Stat) return Natural is (S.Distinct);
      function Agreed_Of (S : Sim_Wordstat.Stat) return Natural is (S.Agreed);
      function Described_Of (S : Sim_Wordstat.Stat) return Natural is (S.Described);
      function Used_Of (S : Sim_Wordstat.Stat) return Natural is (S.Used);
      function Unused_Of (S : Sim_Wordstat.Stat) return Natural is (S.Total - S.Used);
      function Unused_Pct_Of (S : Sim_Wordstat.Stat) return Natural is (Pct (S.Total - S.Used, S.Total));
      function Chess_D_Of (S : Sim_Wordstat.Stat) return Natural is (S.Chess_Dist);
      function Number_D_Of (S : Sim_Wordstat.Stat) return Natural is (S.Number_Dist);
      function Prefix_Of (S : Sim_Wordstat.Stat) return Natural is (S.Prefix_Var);
      function Suffix_Of (S : Sim_Wordstat.Stat) return Natural is (S.Suffix_Var);
      function Any_Of (S : Sim_Wordstat.Stat) return Natural is (S.Any_Var);
      procedure Row_Total is new Row (Total_Of);
      procedure Row_Distinct is new Row (Distinct_Of);
      function Since_Of (S : Sim_Wordstat.Stat) return Natural is (S.Since);
      function Since_Token_Of (S : Sim_Wordstat.Stat) return Natural is (S.Since_Token);
      procedure Row_Since is new Row (Since_Of);
      procedure Row_Since_Token is new Row (Since_Token_Of);
      function Strict_Token_Of (S : Sim_Wordstat.Stat) return Natural is (S.Strict_Token);
      procedure Row_Strict_Token is new Row (Strict_Token_Of);
      function Agreed_After_Of (S : Sim_Wordstat.Stat) return Natural is (S.Agreed_After);
      procedure Row_Agreed is new Row (Agreed_Of);
      procedure Row_Agreed_After is new Row (Agreed_After_Of);
      procedure Row_Described is new Row (Described_Of);
      procedure Row_Used is new Row (Used_Of);
      procedure Row_Unused is new Row (Unused_Of);
      procedure Row_Unused_Pct is new Row (Unused_Pct_Of);
      procedure Row_Chess_D is new Row (Chess_D_Of);
      procedure Row_Number_D is new Row (Number_D_Of);
      procedure Row_Prefix is new Row (Prefix_Of);
      procedure Row_Suffix is new Row (Suffix_Of);
      procedure Row_Any is new Row (Any_Of);

      --  ---- --evolve / --active: the evolution preview (Sim_Evolve, data/evolve.txt); READ-ONLY ---------------------------------
      procedure Evolve_Report (Active_View : Boolean) is
         function Lm (Key : String; D : Natural) return Natural is (Natural (Int'Max (0, Limit (Key, Int (D)))));
         Starts : Sim_Evolve.Int_Vectors.Vector;
         Pw : Sim_Evolve.Word_Params;
         Pc : Sim_Evolve.Chess_Params;
         Tw : array (Entity_Id) of Sim_Evolve.Word_Totals;
         use type Sim_Wordstat.Kind;
         Cap_N : constant Natural := Lm ("evolve.cap", 500);
         Top_N : constant Natural := Lm ("evolve.top", 15);
         List_N : constant Natural := Lm ("evolve.list", 15);
         Curve_N : constant Natural := Lm ("evolve.curve", 30);

         type Sel is (S_Known, S_Symbols, S_Plain, S_Base, S_Active, S_Held, S_Dormant, S_Woken, S_Avg, S_Cap);
         function Pick (T : Sim_Evolve.Word_Totals; S : Sel) return Natural is
           (case S is
               when S_Known => T.Known, when S_Symbols => T.Symbols, when S_Plain => T.Known - T.Symbols, when S_Base => T.Base,
               when S_Active => T.Active, when S_Held => T.Held, when S_Dormant => T.Dormant, when S_Woken => T.Woken_Later,
               when S_Avg => (if T.Active = 0 then 0 else T.Fit10_Sum / T.Active), when S_Cap => T.Cap_Reached);

         procedure Erow (Label : String; S : Sel) is
            Line : Unbounded_String := To_Unbounded_String (Pad_R (Label, Name_W));
            Sum, Fit, Act : Natural := 0;
         begin
            for E in Entity_Id loop
               Append (Line, Pad_L ((if S = S_Cap and then Pick (Tw (E), S) = 0 then "-" else Img (Pick (Tw (E), S))), Cell_W));
               Sum := Sum + Pick (Tw (E), S);
               Fit := Fit + Tw (E).Fit10_Sum;
               Act := Act + Tw (E).Active;
            end loop;
            Append (Line, Pad_L ((if S = S_Cap then "" elsif S = S_Avg then Img (Integer (if Act = 0 then 0 else Fit / Act)) else Img (Integer (Sum))), Total_W));
            Put (To_String (Line));
         end Erow;

         function Cname (C : Sim_Games.Comp_Id) return String is   --  the id of a chess competitor as the record writes it (wesen 1 .. 4, players 5 .. 7)
           (if C <= 4 then Name (Entity_Id (C)) else Msg ("evolve.comp." & Img (C)));
         function Sgn (N : Integer) return String is
           (if N > 0 then "+" & Img (Int (N)) elsif N < 0 then "-" & Img (Int (-N)) else ".");
         function Fit_Img (N : Natural) return String is (Img (N / 10) & "." & Img (N mod 10));

         type Pair is record E : Natural := 0; I : Natural := 0; end record;
         package Pair_Vectors is new Ada.Containers.Vectors (Positive, Pair);

         function Chosen (V : Pair_Vectors.Vector; E, I : Natural) return Boolean is
         begin
            for P of V loop if P.E = E and then P.I = I then return True; end if; end loop;
            return False;
         end Chosen;

         procedure Head_Line is
            H : Unbounded_String := To_Unbounded_String (Pad_R ("", Name_W));
         begin
            for E in Entity_Id loop Append (H, Pad_L (Sim_World.Show (Name (E)), Cell_W)); end loop;
            Append (H, Pad_L (Msg ("evolve.col.total"), Total_W));
            Put (To_String (H));
         end Head_Line;

         procedure Load_And_Run is
         begin
            Lines.Clear;
            Read_Lines ("diaries/sessions.txt", Lines, Found);
            for L of Lines loop
               if L'Length > 1 and then L (L'First) = 'S' and then Token (L, "start") /= "" then
                  Starts.Append (Integer (Num (Token (L, "start"))));
               end if;
            end loop;
            if Starts.Is_Empty or else Starts.First_Element > 0 then Starts.Prepend (0); end if;
            Pw := (Use_Pts => Lm ("evolve.use_pts", 1), Use_Cap => Lm ("evolve.word_use_cap", 5), Grant_Pts => Lm ("evolve.grant_pts", 3),
                   Agree_Pts => Lm ("evolve.agree_pts", 5), Line10 => Lm ("evolve.line10", 3), Fit_Cap => Lm ("evolve.fit_cap", 200),
                   Probation => Lm ("evolve.probation", 3), Idle => Lm ("evolve.idle_sessions", 6), Retire_Max => Lm ("evolve.retire_max", 40),
                   Min_Active => (if Active_View then Cap_N else Lm ("evolve.min_active", 300)), Cap => (if Active_View then Cap_N else 0));
            Sim_Evolve.Words_Reset (Pw, Starts);
            for E in Entity_Id loop
               for I in 1 .. Sim_Wordstat.Word_Count (Positive (E)) loop
                  declare
                     K : constant Sim_Wordstat.Kind := Sim_Wordstat.Word_Kind (Positive (E), I);
                  begin
                     Sim_Evolve.Add_Word (Positive (E), Sim_Wordstat.Word_Tick (Positive (E), I), K = Sim_Wordstat.Start, K in Sim_Wordstat.Chess | Sim_Wordstat.Number);
                  end;
               end loop;
            end loop;
            for J in 1 .. Sim_Wordstat.Event_Count loop
               declare
                  Ev : constant Sim_Wordstat.Log_Event := Sim_Wordstat.Event_At (J);
               begin
                  Sim_Evolve.Add_Event (Ev.E, Ev.Index, Ev.Tick, Ev.Why);
               end;
            end loop;
            Sim_Evolve.Words_Run;
            for E in Entity_Id loop Tw (E) := Sim_Evolve.Totals (Positive (E)); end loop;
         end Load_And_Run;

         Sum_Known, Sum_Sym, Sum_Dorm, Sum_Woken, Sum_Active : Natural := 0;
         Best_E, Best_I : Natural := 0;
         Chess_Found : Boolean := False;
         Big_W : Integer := 0;
         Big_C, Big_F : Natural := 0;
         Elo_Lo, Elo_Hi : Natural := 0;
         Games_Total : Natural := 0;
      begin
         Load_And_Run;
         for E in Entity_Id loop
            Sum_Known := Sum_Known + Tw (E).Known;
            Sum_Sym := Sum_Sym + Tw (E).Symbols;
            Sum_Dorm := Sum_Dorm + Tw (E).Dormant;
            Sum_Woken := Sum_Woken + Tw (E).Woken_Later;
            Sum_Active := Sum_Active + Tw (E).Active;
         end loop;
         if Active_View then
            declare
               Act_Lines : Str_Vectors.Vector;
               Act_Found : Boolean;
               Last_State : array (Entity_Id) of Unbounded_String := [others => Null_Unbounded_String];
               Param_Line, Param_Line2 : Unbounded_String;   --  the params lines of active=1 and active=2
               Has_Real : Boolean := False;
               Sum_K, Sum_S, Sum_A, Sum_D, Sum_B : Natural := 0;
               function Tok (L, Key : String) return String is
                  P : Natural := L'First;
               begin
                  while P <= L'Last loop
                     declare
                        Stop : Natural := P;
                     begin
                        while Stop <= L'Last and then L (Stop) /= ' ' loop Stop := Stop + 1; end loop;
                        if Stop - P > Key'Length and then L (P .. P + Key'Length - 1) = Key and then L (P + Key'Length) = '=' then
                           return L (P + Key'Length + 1 .. Stop - 1);
                        end if;
                        P := Stop + 1;
                     end;
                  end loop;
                  return "";
               end Tok;
               function Num (X : String) return Natural is (if X'Length in 1 .. 9 and then (for all C of X => C in '0' .. '9') then Natural'Value (X) else 0);
               function Level2 return Boolean is (Tok (To_String (Last_State (Entity_Id'First)), "slow") /= "");   --  the last closed window was active=2
               function At_Floor return Boolean is (Tok (To_String (Last_State (Entity_Id'First)), "slowat") = "floor");   --  slowfloor=1: mint-slow from the floor up
            begin
               if Ada.Directories.Exists ("diaries/active.txt") then
                  Read_Lines ("diaries/active.txt", Act_Lines, Act_Found);
                  for L of Act_Lines loop
                     if Fx.Index (L, " params level=2 ") > 0 then Param_Line2 := To_Unbounded_String (L);
                     elsif Fx.Index (L, " params ") > 0 then Param_Line := To_Unbounded_String (L);
                     elsif L'Length > 4 and then L (L'First) = 'A' then
                        for E in Entity_Id loop
                           if Fx.Index (L, " " & Name (E) & " state ") > 0 then Last_State (E) := To_Unbounded_String (L); Has_Real := True; end if;
                        end loop;
                     end if;
                  end loop;
               end if;
               if Has_Real then
                  for L of Sim_Voice.Wrap (Msg ("evolve.a.real", Tok (To_String (Last_State (Entity_Id'First)), "s"), Tok (To_String (Last_State (Entity_Id'First)), "t"),
                                                (if Level2 then "2" else "1")), 79) loop Put (L); end loop;
                  TIO.New_Line;
                  if Length (Param_Line) > 0 then
                     declare
                        PL : constant String := To_String (Param_Line);
                        At_P : constant Natural := Fx.Index (PL, " params ");
                     begin
                        for L of Sim_Voice.Wrap (Msg ("evolve.a.params", PL (At_P + 8 .. PL'Last)), 79) loop Put (L); end loop;
                     end;
                     TIO.New_Line;
                  end if;
                  if Length (Param_Line2) > 0 then
                     declare
                        PL : constant String := To_String (Param_Line2);
                        At_P : constant Natural := Fx.Index (PL, " params level=2 ");
                     begin
                        for L of Sim_Voice.Wrap (Msg ("evolve.a.params2", Tok (PL, "floor"), Tok (PL, "cap"), PL (At_P + 16 .. PL'Last)), 79) loop Put (L); end loop;
                     end;
                     TIO.New_Line;
                  end if;
                  Put (Msg ("evolve.a.sec"));
                  Head_Line;
                  declare
                     procedure Rrow (Label, Key : String) is
                        Line : Unbounded_String := To_Unbounded_String (Pad_R (Label, Name_W));
                        Sum : Natural := 0;
                     begin
                        for E in Entity_Id loop
                           declare
                              V : constant Natural := Num (Tok (To_String (Last_State (E)), Key));
                           begin
                              Append (Line, Pad_L (Img (V), Cell_W));
                              Sum := Sum + V;
                           end;
                        end loop;
                        Append (Line, Pad_L (Img (Sum), Total_W));
                        Put (To_String (Line));
                     end Rrow;
                  begin
                     Rrow ("  " & Msg ("evolve.l.known"), "known");
                     Rrow ("  " & Msg ("evolve.l.symbols"), "symbols");
                     Rrow ("  " & Msg ("evolve.l.active_real"), "active");
                     Rrow ("  " & Msg ("evolve.l.dormant_real"), "dormant");
                     Rrow ("  " & Msg ("evolve.l.base_real"), "base");
                     Rrow ("  " & Msg ("evolve.l.woke_real"), "woke");
                     if Level2 then Rrow ("  " & Msg (if At_Floor then "evolve.l.slow_floor" else "evolve.l.slow_real"), "slow"); end if;
                  end;
                  TIO.New_Line;
                  for E in Entity_Id loop
                     Sum_K := Sum_K + Num (Tok (To_String (Last_State (E)), "known"));
                     Sum_S := Sum_S + Num (Tok (To_String (Last_State (E)), "symbols"));
                     Sum_A := Sum_A + Num (Tok (To_String (Last_State (E)), "active"));
                     Sum_D := Sum_D + Num (Tok (To_String (Last_State (E)), "dormant"));
                     Sum_B := Sum_B + Num (Tok (To_String (Last_State (E)), "base"));
                  end loop;
                  Put (Msg ("evolve.concl.head"));
                  for L of Sim_Voice.Wrap (Msg ("evolve.a.concl.real", Img (Sum_A), Img (Sum_D), Img (Sum_S), Img (Sum_B)), 79) loop Put (L); end loop;
                  if Level2 then
                     declare
                        PL : constant String := To_String (Param_Line2);
                        N_Slow : Natural := 0;
                     begin
                        for E in Entity_Id loop N_Slow := N_Slow + Num (Tok (To_String (Last_State (E)), "slow")); end loop;
                        for L of Sim_Voice.Wrap (Msg ((if At_Floor then "evolve.a.concl.level2f" else "evolve.a.concl.level2"), Tok (PL, "floor"), Tok (PL, "cap"), Img (N_Slow)), 79) loop Put (L); end loop;
                     end;
                  end if;
                  return;
               end if;
            end;
            for L of Sim_Voice.Wrap (Msg ("evolve.a.title", Img (Cap_N), Img (Per (0).Last_Tick), Img (Sim_Evolve.Sessions)), 79) loop Put (L); end loop;
            TIO.New_Line;
            for L of Sim_Voice.Wrap (Msg ("evolve.a.rules", Img (Cap_N), Img (Lm ("evolve.retire_max", 40))), 79) loop Put (L); end loop;
            TIO.New_Line;
            Put (Msg ("evolve.a.sec"));
            Head_Line;
            Erow ("  " & Msg ("evolve.l.known"), S_Known);
            Erow ("  " & Msg ("evolve.l.symbols"), S_Symbols);
            Erow ("  " & Msg ("evolve.l.plain"), S_Plain);
            Erow ("  " & Msg ("evolve.l.base"), S_Base);
            Erow ("  " & Msg ("evolve.l.active"), S_Active);
            Erow ("  " & Msg ("evolve.l.held"), S_Held);
            Erow ("  " & Msg ("evolve.l.dormant"), S_Dormant);
            Erow ("  " & Msg ("evolve.l.woken"), S_Woken);
            Erow ("  " & Msg ("evolve.l.cap"), S_Cap);
            TIO.New_Line;
            Put (Msg ("evolve.a.sec.kind"));
            Put (Msg ("evolve.a.kind.head"));
            for K in Sim_Wordstat.Start .. Sim_Wordstat.Coined loop
               declare
                  A, D : Natural := 0;
               begin
                  for E in Entity_Id loop
                     for I in 1 .. Sim_Wordstat.Word_Count (Positive (E)) loop
                        if Sim_Wordstat.Word_Kind (Positive (E), I) = K then
                           if Sim_Evolve.Result (Positive (E), I).Dormant_In = 0 then A := A + 1; else D := D + 1; end if;
                        end if;
                     end loop;
                  end loop;
                  Put (Pad_R ("  " & Msg ("wordstat.k." & Ada.Characters.Handling.To_Lower (Sim_Wordstat.Kind'Image (K))), Name_W + 3) & Pad_L (Img (A), 7) & Pad_L (Img (D), 9));
               end;
            end loop;
            TIO.New_Line;
            declare
               Cap_Max : Natural := 0;
               Per_E : constant Natural := Sum_Active / Entity_Id'Pos (Entity_Id'Last);
            begin
               for E in Entity_Id loop Cap_Max := Natural'Max (Cap_Max, Tw (E).Cap_Reached); end loop;
               Put (Msg ("evolve.concl.head"));
               for L of Sim_Voice.Wrap ((if Cap_Max > 0 then Msg ("evolve.a.concl", Img (Cap_N), Img (Per_E), Img (Sum_Active), Img (Sum_Dorm), Img (Cap_Max), Img (Sum_Woken), Img (Tw (Entity_Id'First).Base))
                                         else Msg ("evolve.a.concl.never", Img (Cap_N), Img (Per_E), Img (Sum_Active), Img (Sum_Dorm), Img (Sum_Woken))), 79) loop
                  Put (L);
               end loop;
            end;
            return;
         end if;
         --  ---- the words
         for L of Sim_Voice.Wrap (Msg ("evolve.title", Img (Per (0).Last_Tick), Img (Sim_Evolve.Sessions)), 79) loop Put (L); end loop;
         TIO.New_Line;
         for L of Sim_Voice.Wrap (Msg ("evolve.rules", Fit_Img (Pw.Line10), Img (Pw.Idle), Img (Pw.Probation), Img (Pw.Retire_Max), Img (Pw.Min_Active)), 79) loop Put (L); end loop;
         TIO.New_Line;
         Put (Msg ("evolve.sec.words"));
         Head_Line;
         Erow ("  " & Msg ("evolve.l.known"), S_Known);
         Erow ("  " & Msg ("evolve.l.symbols"), S_Symbols);
         Erow ("  " & Msg ("evolve.l.plain"), S_Plain);
         Erow ("  " & Msg ("evolve.l.base"), S_Base);
         Erow ("  " & Msg ("evolve.l.active"), S_Active);
         Erow ("  " & Msg ("evolve.l.held"), S_Held);
         Erow ("  " & Msg ("evolve.l.dormant"), S_Dormant);
         Erow ("  " & Msg ("evolve.l.woken"), S_Woken);
         Erow ("  " & Msg ("evolve.l.avg"), S_Avg);
         TIO.New_Line;
         Put (Msg ("evolve.sec.top", Img (Top_N)));
         Put (Msg ("evolve.top.head"));
         declare
            Done : Pair_Vectors.Vector;
         begin
            for N in 1 .. Top_N loop
               declare
                  B : Pair := (0, 0);
                  Bf : Integer := -1;
               begin
                  for E in Entity_Id loop
                     for I in 1 .. Sim_Wordstat.Word_Count (Positive (E)) loop
                        declare
                           R : constant Sim_Evolve.Word_Result := Sim_Evolve.Result (Positive (E), I);
                        begin
                           if not Sim_Evolve.Is_Symbol (Positive (E), I) and then R.Dormant_In = 0 and then Integer (R.Fit10) > Bf
                             and then not Chosen (Done, Natural (E), I)
                           then
                              Bf := Integer (R.Fit10);
                              B := (Natural (E), I);
                           end if;
                        end;
                     end loop;
                  end loop;
                  exit when B.E = 0;
                  Done.Append (B);
                  if Best_E = 0 then Best_E := B.E; Best_I := B.I; end if;
                  declare
                     R : constant Sim_Evolve.Word_Result := Sim_Evolve.Result (B.E, B.I);
                  begin
                     Put ("  " & Pad_R (Sim_Wordstat.Word_Text (B.E, B.I), 20) & Pad_R (Sim_World.Show (Name (Entity_Id (B.E))), 8) & Pad_L (Fit_Img (R.Fit10), 8)
                          & Pad_L (Img (R.Uses), 7) & Pad_L (Img (R.Sessions), 9));
                  end;
               end;
            end loop;
            if Done.Is_Empty then Put (Msg ("evolve.none")); end if;
         end;
         TIO.New_Line;
         Put (Msg ("evolve.sec.dorm", Img (List_N)));
         Put (Msg ("evolve.dorm.head"));
         declare
            Done : Pair_Vectors.Vector;
         begin
            for N in 1 .. List_N loop
               declare
                  B : Pair := (0, 0);
                  Bf : Integer := Integer'Last;
               begin
                  for E in Entity_Id loop
                     for I in 1 .. Sim_Wordstat.Word_Count (Positive (E)) loop
                        declare
                           R : constant Sim_Evolve.Word_Result := Sim_Evolve.Result (Positive (E), I);
                        begin
                           if R.Dormant_In > 0 and then Integer (R.Fit_Then) < Bf and then not Chosen (Done, Natural (E), I) then
                              Bf := Integer (R.Fit_Then);
                              B := (Natural (E), I);
                           end if;
                        end;
                     end loop;
                  end loop;
                  exit when B.E = 0;
                  Done.Append (B);
                  declare
                     R : constant Sim_Evolve.Word_Result := Sim_Evolve.Result (B.E, B.I);
                  begin
                     Put ("  " & Pad_R (Sim_Wordstat.Word_Text (B.E, B.I), 20) & Pad_R (Sim_World.Show (Name (Entity_Id (B.E))), 8) & Pad_L (Fit_Img (R.Fit_Then), 8)
                          & Pad_L (Img (R.Uses), 7) & Pad_L (Img (R.Dormant_In), 17));
                  end;
               end;
            end loop;
            if Done.Is_Empty then Put (Msg ("evolve.none")); end if;
         end;
         TIO.New_Line;
         --  ---- chess
         Pc := (Use_Cap => Lm ("evolve.use_cap", 3), Step => Lm ("evolve.step", 1), Big_Elo => Lm ("evolve.big_elo", 16), W_Max => Lm ("evolve.w_max", 8),
                Sess_Max => Lm ("evolve.sess_max", 3), Sess_Total => Lm ("evolve.sess_total", 12), Elo_Start => Lm ("elo.start", 1200));
         Sim_Evolve.Chess_Reset (Pc, Starts);
         Lines.Clear;
         Read_Lines ("diaries/chess.txt", Lines, Found);
         for L of Lines loop
            if L'Length > 1 and then L (L'First) = 'C' then
               declare
                  Op : constant String := Nth (L, 4);
                  G : constant Natural := Num (Token (L, "g"));
                  T : constant Natural := Num (Token (L, "t"));

                  function Comp_Of (S : String) return Natural is
                  begin
                     for C in Sim_Games.Comp_Id loop
                        if Cname (C) = S then return C; end if;
                     end loop;
                     return 0;
                  end Comp_Of;
               begin
                  if G > 0 and then Op = "start" then
                     Chess_Found := True;
                     if Comp_Of (Token (L, "white")) > 0 and then Comp_Of (Token (L, "black")) > 0 then
                        Sim_Evolve.Chess_Start (G, Comp_Of (Token (L, "white")), Comp_Of (Token (L, "black")));
                     end if;
                  elsif G > 0 and then Op = "move" then
                     Sim_Evolve.Chess_Move (G, Nth (L, 7));
                  elsif G > 0 and then Op = "end" then
                     declare
                        Elo_At_Pos : constant Natural := Fx.Index (L, " elo ");
                        White_Name : constant String := "";
                        Res : constant String := Nth (L, 5);
                        Delta_W : Integer := 0;
                        Rest : constant String := (if Elo_At_Pos = 0 then "" else L (Elo_At_Pos + 5 .. L'Last));
                        Pos : Natural := Rest'First;
                        pragma Unreferenced (White_Name);
                     begin
                        --  "name=before>after name=before>after": the rating after the game, and the change of the first one named
                        while Pos <= Rest'Last loop
                           declare
                              Stop : constant Natural := (if Fx.Index (Rest, " ", Pos) = 0 then Rest'Last + 1 else Fx.Index (Rest, " ", Pos));
                              Tok : constant String := Rest (Pos .. Stop - 1);
                              Eq : constant Natural := Fx.Index (Tok, "=");
                              Gt : constant Natural := Fx.Index (Tok, ">");
                           begin
                              if Eq > 0 and then Gt > Eq then
                                 declare
                                    C : constant Natural := Comp_Of (Tok (Tok'First .. Eq - 1));
                                    After : constant Natural := Num (Tok (Gt + 1 .. Tok'Last));
                                    Before : constant Natural := Num (Tok (Eq + 1 .. Gt - 1));
                                 begin
                                    if C > 0 and then After > 0 then Sim_Evolve.Elo_Point (C, T, After); end if;
                                    if Pos = Rest'First then Delta_W := Integer (After) - Integer (Before); end if;   --  white is named first
                                 end;
                              end if;
                              Pos := Stop + 1;
                           end;
                        end loop;
                        Sim_Evolve.Chess_End (G, T, (if Res = "1-0" then 1 elsif Res = "0-1" then -1 else 0), Delta_W);
                     end;
                  end if;
               end;
            end if;
         end loop;
         Sim_Evolve.Chess_Finish;
         for L of Sim_Voice.Wrap (Msg ("evolve.sec.chess"), 79) loop Put (L); end loop;
         if not Chess_Found then
            Put (Msg ("evolve.chess.none"));
         else
            for L of Sim_Voice.Wrap (Msg ("evolve.chess.cap", Img (Pc.W_Max), Img (Pc.Sess_Max), Img (Pc.Sess_Total), Img (Pc.Big_Elo)), 77) loop Put ("  " & L); end loop;
            declare
               H : Unbounded_String := To_Unbounded_String (Pad_R ("", 22));
            begin
               for C in Sim_Games.Comp_Id loop Append (H, Pad_L (Sim_World.Show (Cname (C)), 8)); end loop;
               Put (To_String (H));
            end;
            for F in Sim_Evolve.Feature loop
               declare
                  Line : Unbounded_String := To_Unbounded_String (Pad_R ("  " & Msg ("evolve.f." & Img (F)), 22));
               begin
                  for C in Sim_Games.Comp_Id loop
                     Append (Line, Pad_L (Sgn (Sim_Evolve.Weight (C, F)), 8));
                     if abs Sim_Evolve.Weight (C, F) > abs Big_W then
                        Big_W := Sim_Evolve.Weight (C, F);
                        Big_C := C;
                        Big_F := F;
                     end if;
                  end loop;
                  Put (To_String (Line));
               end;
            end loop;
            declare
               Gm, Wn, Eo : Unbounded_String;
            begin
               Gm := To_Unbounded_String (Pad_R ("  " & Msg ("evolve.chess.games"), 22));
               Wn := To_Unbounded_String (Pad_R ("  " & Msg ("evolve.chess.wins"), 22));
               Eo := To_Unbounded_String (Pad_R ("  " & Msg ("evolve.chess.elo"), 22));
               for C in Sim_Games.Comp_Id loop
                  declare
                     N : constant Natural := Sim_Evolve.Games_Of (C);
                     R : constant Natural := Sim_Evolve.Elo_At (C, Sim_Evolve.Elo_Sessions);
                  begin
                     Games_Total := Games_Total + N;
                     Append (Gm, Pad_L (Img (N), 8));
                     Append (Wn, Pad_L (Img (Pct (Sim_Evolve.Wins_Of (C), N)), 8));
                     Append (Eo, Pad_L (Img (R), 8));
                     Elo_Lo := (if Elo_Lo = 0 then R else Natural'Min (Elo_Lo, R));
                     Elo_Hi := Natural'Max (Elo_Hi, R);
                  end;
               end loop;
               Put (To_String (Gm));
               Put (To_String (Wn));
               Put (To_String (Eo));
            end;
            TIO.New_Line;
            for L of Sim_Voice.Wrap (Msg ("evolve.sec.elo", Img (Curve_N)), 79) loop Put (L); end loop;
            Put (Msg ("evolve.elo.head"));
            declare
               S_N : constant Natural := Sim_Evolve.Elo_Sessions;
               First : constant Positive := Positive'Max (1, S_N - Natural'Min (S_N, Curve_N) + 1);
               G_Lo : Natural := 0;
               G_Hi : Natural := 0;
               Bars : constant String := " .:-=+*#%@";
            begin
               for C in Sim_Games.Comp_Id loop
                  for S in First .. Positive'Max (First, S_N) loop
                     declare
                        R : constant Natural := Sim_Evolve.Elo_At (C, S);
                     begin
                        G_Lo := (if G_Lo = 0 then R else Natural'Min (G_Lo, R));
                        G_Hi := Natural'Max (G_Hi, R);
                     end;
                  end loop;
               end loop;
               for C in Sim_Games.Comp_Id loop
                  declare
                     Lo, Hi : Natural := 0;
                     Bar : Unbounded_String;
                  begin
                     for S in 1 .. S_N loop
                        declare
                           R : constant Natural := Sim_Evolve.Elo_At (C, S);
                        begin
                           Lo := (if Lo = 0 then R else Natural'Min (Lo, R));
                           Hi := Natural'Max (Hi, R);
                        end;
                     end loop;
                     for S in First .. Positive'Max (First, S_N) loop
                        Append (Bar, Bars (Bars'First + (Sim_Evolve.Elo_At (C, S) - G_Lo) * 9 / Natural'Max (1, G_Hi - G_Lo)));
                     end loop;
                     Put ("  " & Pad_R (Sim_World.Show (Cname (C)), 11) & Pad_L (Img (Sim_Evolve.Elo_At (C, 1)), 8)
                          & Pad_L (Img (Sim_Evolve.Elo_At (C, S_N)), 6) & Pad_L (Img (Lo), 6) & Pad_L (Img (Hi), 6) & "  " & To_String (Bar));
                  end;
               end loop;
            end;
         end if;
         TIO.New_Line;
         Put (Msg ("evolve.concl.head"));
         for L of Sim_Voice.Wrap
           (Msg ("evolve.concl.1", Img (Sum_Dorm), Img (Sum_Known - Sum_Sym), Img (Pct (Sum_Dorm, Sum_Known - Sum_Sym)), Img (Sum_Sym), Img (Sum_Woken),
                 (if Best_E = 0 then "-" else Sim_Wordstat.Word_Text (Best_E, Best_I)), (if Best_E = 0 then "0" else Fit_Img (Sim_Evolve.Result (Best_E, Best_I).Fit10))), 79)
         loop
            Put (L);
         end loop;
         if Chess_Found then
            for L of Sim_Voice.Wrap
              (Msg ("evolve.concl.2", Img (Sim_Evolve.Moves_Seen), Img (Games_Total / 2), Sgn (Big_W),
                    (if Big_F = 0 then "-" else Msg ("evolve.f." & Img (Big_F))), (if Big_C = 0 then "-" else Sim_World.Show (Cname (Sim_Games.Comp_Id (Big_C)))),
                    Img (Elo_Lo), Img (Elo_Hi)) & " " & Msg ("evolve.concl.3", Img (Sim_Evolve.Bounded_Hits)), 79)
            loop
               Put (L);
            end loop;
         else
            Put (Msg ("evolve.concl.nochess"));
         end if;
      end Evolve_Report;

      Edges : Sim_Wordstat.Edge_Array;
      Any_Words : Boolean := False;
      Sym_Tick : Integer := -1;
      Sym_Sess : Natural := 0;
      Str_Tick : Integer := -1;   --  the first symstrict=1 session (coined chess strings are symbols too)
      Str_Sess : Natural := 0;
      Dict_Decided, Dict_Agreed, Dict_Rejected, Dict_Name, Dict_Coined, Dict_Ann, Ann_File : Natural := 0;
      Dict_Means : Str_Vectors.Vector;
   begin
      for I in Edges'Range loop
         Edges (I) := Num (Msg ("wordstat.edge." & Img (I)));
         if Edges (I) = 0 then Edges (I) := (if I = 1 then 2 else Edges (I - 1) + 1); end if;
      end loop;
      Sim_Wordstat.Reset (Natural (Int'Max (1, Limit ("wordstat.stem_min", 3))), Edges);
      --  1. what each wesen knows
      for E in Entity_Id loop
         Lines.Clear;
         Read_Lines ("entities/" & Name (E) & "/words.txt", Lines, Found);
         if Found then
            for L of Lines loop
               if L'Length > 0 and then L (L'First) /= '#' and then Num (Nth (L, 1)) > 0 and then Nth (L, 2) /= "" then
                  Sim_Wordstat.Add_Word (Positive (E), Num (Nth (L, 1)), Nth (L, 2), Nth (L, 3), Num (Nth (L, 4)), Nth (L, 5));
                  Any_Words := True;
               end if;
            end loop;
         end if;
      end loop;
      if not Any_Words then
         TIO.Put_Line (TIO.Standard_Error, Msg ("wordstat.none"));
         Ada.Command_Line.Set_Exit_Status (2);
         return;
      end if;
      --  2. the later use of a word
      Lines.Clear;
      Read_Lines ("diaries/screens.txt", Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'K' then
            declare
               Op : constant String := Nth (L, 4);
               E : constant Natural := Ent_Of (Nth (L, 3));
               T : constant Natural := Num (Token (L, "t"));
            begin
               if Op in "show" | "read" | "pin" | "cmd" | "leave" | "blend" then
                  Ids (E, Token (L, "w"), T);
                  if Op = "blend" then Ids (E, Token (L, "a"), T); Ids (E, Token (L, "b"), T); end if;
               end if;
            end;
         end if;
      end loop;
      Lines.Clear;
      Read_Lines ("diaries/sessions.txt", Lines, Found);   --  the first symbols=1 session: from its start on chess strings are not minted as words
      for L of Lines loop
         if Sym_Tick < 0 and then L'Length > 1 and then L (L'First) = 'S' and then Token (L, "symbols") = "1" then
            Sym_Tick := Num (Token (L, "start"));
            Sym_Sess := Num (L (L'First + 1 .. Fx.Index (L, " ") - 1));
         end if;
         if Str_Tick < 0 and then L'Length > 1 and then L (L'First) = 'S' and then Token (L, "symstrict") = "1" then
            Str_Tick := Num (Token (L, "start"));
            Str_Sess := Num (L (L'First + 1 .. Fx.Index (L, " ") - 1));
         end if;
      end loop;
      Sim_Wordstat.Set_Strict (Str_Tick);
      Sim_Wordstat.Set_Symbols (Sym_Tick);
      Lines.Clear;
      Read_Lines ("diaries/dictionary.txt", Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'L' then
            declare
               W : constant String := Token (L, "word");
               E : constant Natural := Ent_Of (Token (L, "by"));
               T : constant Natural := Num (Token (L, "t"));
               St : constant String := Token (L, "st");
            begin
               Dict_Decided := Dict_Decided + 1;
               if St = "A" then
                  Dict_Agreed := Dict_Agreed + 1;
                  if Token (L, "slot") = "coined" then Dict_Coined := Dict_Coined + 1; else Dict_Name := Dict_Name + 1; end if;
                  if not Dict_Means.Contains (Token (L, "mean")) then Dict_Means.Append (Token (L, "mean")); end if;
                  Sim_Wordstat.Agree (W, T);
               elsif St = "R" then
                  Dict_Rejected := Dict_Rejected + 1;
               end if;
               if Token (L, "ann") = "1" then Dict_Ann := Dict_Ann + 1; end if;
               --  the proposed text of a new name is not a word of any word list: only the meaning (a base word) counts as used
               if E /= 0 then Texts (E, Token (L, "mean"), T, (if St = "A" then Sim_Evolve.Agreed else Sim_Evolve.Mention)); end if;
            end;
         end if;
      end loop;
      Lines.Clear;
      Read_Lines ("diaries/announcements.txt", Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'A' then Ann_File := Ann_File + 1; end if;
      end loop;
      Lines.Clear;
      Read_Lines ("diaries/votes.txt", Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'V' and then Token (L, "kind") = "favourite" then
            Texts (Ent_Of (Token (L, "voter")), Token (L, "choice"), Num (Token (L, "t")));
         end if;
      end loop;
      Lines.Clear;
      Read_Lines ("diaries/petitions.txt", Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'P' then
            Texts (Ent_Of (Token (L, "wesen")), Token (L, "req"), Num (Token (L, "t")),
                   (if Token (L, "out") = "grant" then Sim_Evolve.Granted else Sim_Evolve.Mention));
         end if;
      end loop;
      for E in Entity_Id loop   --  the notebooks of docs/LEARN.md, if a later build keeps them
         Lines.Clear;
         Read_Lines ("entities/" & Name (E) & "/notebook.txt", Lines, Found);
         if Found then
            for L of Lines loop
               if L'Length > 0 and then L (L'First) /= '#' then Texts (Natural (E), L, Num (Token (L, "t"))); end if;
            end loop;
         end if;
      end loop;
      for E in 0 .. Integer (Entity_Id'Last) loop Per (E) := Sim_Wordstat.Result (E); end loop;
      if Evolve or else Active then
         Evolve_Report (Active);
         return;
      end if;
      --  3. the report
      Put (Msg ("wordstat.title", Img (Per (0).Last_Tick)));
      TIO.New_Line;
      Head := To_Unbounded_String (Pad_R ("", Name_W));
      for E in Entity_Id loop Append (Head, Pad_L (Sim_World.Show (Name (E)), Cell_W)); end loop;
      Append (Head, Pad_L (Msg ("wordstat.col.total"), Total_W));
      Put (To_String (Head));
      Row_Total (Msg ("wordstat.l.known"));
      Row_Distinct (Msg ("wordstat.l.distinct"));
      TIO.New_Line;
      Put (Msg ("wordstat.sec.kind"));
      for K in Sim_Wordstat.Kind loop
         declare
            function Pick (S : Sim_Wordstat.Stat) return Natural is (S.Known (K));
            procedure Row_K is new Row (Pick);
         begin
            Row_K ("  " & Msg ("wordstat.k." & Ada.Characters.Handling.To_Lower (Sim_Wordstat.Kind'Image (K))));
         end;
      end loop;
      TIO.New_Line;
      Put (Msg ("wordstat.sec.sym"));
      if Sym_Tick < 0 then
         for L of Sim_Voice.Wrap (Msg ("wordstat.sym.none"), 77) loop Put ("  " & L); end loop;
      else
         for L of Sim_Voice.Wrap (Msg ("wordstat.sym.first", Img (Sym_Sess), Img (Sym_Tick)), 77) loop Put ("  " & L); end loop;
         Row_Since ("  " & Msg ("wordstat.l.since"));
         Row_Since_Token ("  " & Msg ("wordstat.l.since_tok"));
         if Str_Tick >= 0 then
            for L of Sim_Voice.Wrap (Msg ("wordstat.sym.strict", Img (Str_Sess), Img (Str_Tick)), 77) loop Put ("  " & L); end loop;
            Row_Strict_Token ("  " & Msg ("wordstat.l.strict_tok"));
         else
            for L of Sim_Voice.Wrap (Msg ("wordstat.sym.nostrict"), 77) loop Put ("  " & L); end loop;
         end if;
      end if;
      TIO.New_Line;
      Put (Msg ("wordstat.sec.use"));
      Row_Described ("  " & Msg ("wordstat.l.described"));
      Row_Used ("  " & Msg ("wordstat.l.used"));
      Row_Unused ("  " & Msg ("wordstat.l.unused"));
      Row_Unused_Pct ("  " & Msg ("wordstat.l.unused_pct"));
      TIO.New_Line;
      Put (Msg ("wordstat.sec.dict"));
      for Item of Str_Vectors.Vector'(
        [Msg ("wordstat.d.decided") & "|" & Img (Dict_Decided), Msg ("wordstat.d.agreed") & "|" & Img (Dict_Agreed),
         Msg ("wordstat.d.name") & "|" & Img (Dict_Name), Msg ("wordstat.d.coined") & "|" & Img (Dict_Coined),
         Msg ("wordstat.d.means") & "|" & Img (Natural (Dict_Means.Length)), Msg ("wordstat.d.rejected") & "|" & Img (Dict_Rejected),
         Msg ("wordstat.d.ann") & "|" & Img (Dict_Ann), Msg ("wordstat.d.annfile") & "|" & Img (Ann_File)])
      loop
         declare
            Bar : constant Natural := Fx.Index (Item, "|");
         begin
            Put ("  " & Pad_R (Item (Item'First .. Bar - 1), Name_W - 2 + Cell_W * Natural (Entity_Id'Last)) & Pad_L (Item (Bar + 1 .. Item'Last), Total_W));
         end;
      end loop;
      Put (Msg ("wordstat.d.vocab"));
      Row_Agreed ("  " & Msg ("wordstat.l.agreed"));
      Row_Agreed_After ("  " & Msg ("wordstat.l.agreed_after"));
      for L of Sim_Voice.Wrap (Msg ("wordstat.d.note"), 77) loop Put ("  " & L); end loop;
      TIO.New_Line;
      Put (Msg ("wordstat.sec.kinduse"));
      Put (Msg ("wordstat.kinduse.head"));
      for K in Sim_Wordstat.Kind loop
         declare
            Known : constant Natural := Per (0).Known (K);
            Used : constant Natural := Per (0).Used_Kind (K);
         begin
            Put (Msg ("wordstat.kinduse.row", Pad_R ("  " & Msg ("wordstat.k." & Ada.Characters.Handling.To_Lower (Sim_Wordstat.Kind'Image (K))), Name_W),
                      Pad_L (Img (Known), 8), Pad_L (Img (Used), 7), Pad_L (Img (Known - Used), 7), Pad_L (Img (Pct (Known - Used, Known)), 9)));
         end;
      end loop;
      TIO.New_Line;
      for Plain in Boolean loop
         Put (Msg (if Plain then "wordstat.sec.len_plain" else "wordstat.sec.len"));
         for B in 1 .. Sim_Wordstat.Buckets loop
            declare
               Lo : constant Natural := (if B = 1 then 1 else Edges (B - 1) + 1);
               Label : constant String :=
                 (if B = Sim_Wordstat.Buckets then Msg ("wordstat.len.open", Img (Lo))
                  elsif Lo = Edges (B) then Msg ("wordstat.len.one", Img (Lo))
                  else Msg ("wordstat.len.range", Img (Lo), Img (Edges (B))));
               function Pick (S : Sim_Wordstat.Stat) return Natural is (if Plain then S.Len_Plain (B) else S.Len (B));
               procedure Row_B is new Row (Pick);
            begin
               Row_B ("  " & Label);
            end;
         end loop;
         TIO.New_Line;
      end loop;
      Put (Msg ("wordstat.sec.var"));
      Row_Chess_D ("  " & Msg ("wordstat.l.chess_dist"));
      Row_Number_D ("  " & Msg ("wordstat.l.number_dist"));
      Row_Prefix ("  " & Msg ("wordstat.l.prefix"));
      Row_Suffix ("  " & Msg ("wordstat.l.suffix"));
      Row_Any ("  " & Msg ("wordstat.l.anyvar"));
      TIO.New_Line;
      Put (Msg ("wordstat.sec.origin"));
      for K in Sim_Wordstat.Kind loop
         if Per (0).Token_From (K) > 0 then
            Put (Pad_R ("  " & Msg ("wordstat.o." & Ada.Characters.Handling.To_Lower (Sim_Wordstat.Kind'Image (K))), Name_W) & Pad_L (Img (Per (0).Token_From (K)), Total_W));
         end if;
      end loop;
      TIO.New_Line;
      --  4. the conclusion: one paragraph, wrapped to 79 columns
      declare
         T : Sim_Wordstat.Stat renames Per (0);
         package SW renames Sim_Wordstat;
         Tokens : constant Natural := T.Known (SW.Chess) + T.Known (SW.Number);
         type Group is (G_Start, G_World, G_Taught, G_Screen, G_Coined, G_Chess, G_Other);
         function Size (G : Group) return Natural is
           (case G is
               when G_Start => T.Known (SW.Start), when G_World => T.Known (SW.World), when G_Taught => T.Known (SW.Taught),
               when G_Screen => T.Known (SW.Screen), when G_Coined => T.Known (SW.Coined), when G_Chess => Tokens, when G_Other => T.Known (SW.Other));
         function Key (G : Group) return String is
           (case G is when G_Start => "start", when G_World => "world", when G_Taught => "taught", when G_Screen => "screen",
               when G_Coined => "coined", when G_Chess => "chess", when G_Other => "other");
         Big : Group := G_Start;
         Route : SW.Kind := SW.Other;
         Rest_Words : constant Natural := T.Total - Tokens;
         Avg_Rest : constant Natural := Rest_Words / Entity_Id'Pos (Entity_Id'Last);
         Avg_Fold : constant Natural := Natural'Max (0, Rest_Words - T.Any_Var) / Entity_Id'Pos (Entity_Id'Last);
         Para : Unbounded_String;
      begin
         for G in Group loop
            if Size (G) > Size (Big) then Big := G; end if;
         end loop;
         for K in SW.Start .. SW.Other loop
            if K not in SW.Chess | SW.Number and then T.Token_From (K) > T.Token_From (Route) then Route := K; end if;
         end loop;
         Para := To_Unbounded_String
           (Msg ("wordstat.concl.1", Msg ("wordstat.g." & Key (Big)), Img (Size (Big)), Img (T.Total), Img (Pct (Size (Big), T.Total)))
            & " " & Msg ("wordstat.concl.2", Img (Tokens), Img (Pct (Tokens, T.Total)), Msg ("wordstat.route." & Ada.Characters.Handling.To_Lower (SW.Kind'Image (Route))), Img (Pct (T.Total - T.Used, T.Total)))
            & " " & Msg ("wordstat.concl.3", Img (Avg_Rest), Img (Avg_Fold))
            & " " & Msg ("wordstat.concl.4", Img (T.Distinct), Img (T.Chess_Dist + T.Number_Dist)));
         Put (Msg ("wordstat.concl.head"));
         for L of Sim_Voice.Wrap (To_String (Para), 79) loop Put (L); end loop;
         Active_Only;
      end;
   exception
      when TIO.Layout_Error | TIO.Device_Error | TIO.Status_Error => null;   --  stdout is a closed pipe (| head)
   end Print_Wordstat;

   --  --report: print run_report.txt of the save folder (the complete report of the last run); nothing is simulated.
   procedure Print_Report is
      F : Ada.Streams.Stream_IO.File_Type;
   begin
      if not Ada.Directories.Exists ("run_report.txt") then
         TIO.Put_Line (TIO.Standard_Error, Msg ("report.none", Ada.Directories.Full_Name ("run_report.txt")));
         Ada.Command_Line.Set_Exit_Status (2);
         return;
      end if;
      Ada.Streams.Stream_IO.Open (F, Ada.Streams.Stream_IO.In_File, "run_report.txt");
      declare
         Text : String (1 .. Natural (Ada.Streams.Stream_IO.Size (F)));
      begin
         String'Read (Ada.Streams.Stream_IO.Stream (F), Text);
         Ada.Streams.Stream_IO.Close (F);
         if Text'Length > 0 then
            begin
               --  a text ending in a line feed is written as Put + New_Line (see Con.Put)
               if Text (Text'Last) = ASCII.LF then
                  TIO.Put (Text (Text'First .. Text'Last - 1)); TIO.New_Line;
               else
                  TIO.Put (Text);
               end if;
            exception
               when others => null;   --  stdout is a closed pipe (| head)
            end;
         end if;
      end;
   end Print_Report;

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
      if Preview or else Ledger_Mode then return; end if;   --  preview writes nothing; the read-only replays (make verify, the night's end check
      --  child, elo, ledger ...) leave debug.txt of the run alone (0.057: the end check child and the night wrote debug.tmp at the same
      --  time after a SIGHUP, the rename of one failed: "debug.txt could not be written")
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
            if Ada.Directories.Exists ("debug.txt") then Ada.Directories.Delete_File ("debug.txt"); end if;
            Ada.Directories.Rename ("debug.tmp", "debug.txt");
      end;
      Write_Digest (Status, Err);   --  only with --debug, and only for a final status
   exception
      when E : others =>   --  say why (the folder, the exception): the console may be gone (a closed terminal), so this never raises
         begin
            if TIO.Is_Open (F) then TIO.Close (F); end if;
            Con.Put_Line (Msg ("debug.failed") & " (" & Ada.Exceptions.Exception_Name (E) & ": " & Ada.Exceptions.Exception_Message (E)
                          & " in " & Ada.Directories.Current_Directory & ")");
         exception
            when others => null;
         end;
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

   --  active=1: every decision of Sim_Active (the params, a dormant word, a woken word, the state of a wesen) is an A line of
   --  diaries/active.txt: "A12 t=3300 s=11 ada dormant w=345 word=gentle fit=0 why=idle".  Replay-verified like the screens.
   procedure Emit_Active_Lines is
      New_Lines : Str_Vectors.Vector;
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      Sim_Active.Drain (New_Lines);
      for T of New_Lines loop
         Active_N := Active_N + 1;
         declare
            Line : constant String := "A" & Img (Active_N) & " " & T;
         begin
            Sim_Store.Emit (Active_Store, Line, not Preview and then not Ledger_Mode, Result, Old);
            if Sim_Store."=" (Result, Sim_Store.Differs) then
               raise Drift_Error with Msg ("err.active", "A" & Img (Active_N), Diff_At (To_String (Old), Line));
            elsif Sim_Store."=" (Result, Sim_Store.Skipped) and then Ledger_Mode and then not Preview then   --  make verify: a stored line went missing
               raise Drift_Error with Msg ("err.active", "A" & Img (Active_N), Diff_At ("(missing)", Line));
            end if;
         end;
      end loop;
   end Emit_Active_Lines;

   --  A record line that was just emitted: its uses count for the open active=1 window (a dormant word that is used wakes).
   procedure Active_Feed (Line : String) is
   begin
      if Sim_Active.Is_Open then
         Sim_Active.Note_Line (Line);
         Emit_Active_Lines;
      end if;
   end Active_Feed;

   procedure Verify_Active (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Active_Store, Upto);
   begin
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.active", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Active;

   --  The numbers of active=1: the params line of diaries/active.txt (a save keeps the numbers it started with), else data/limits.txt
   --  evolve.* with evolve.cap as floor and cap (the rule of make active).
   procedure Load_Active_Params is
      Lines : Str_Vectors.Vector;
      Found, OK : Boolean;
      Cap : constant Natural := Natural (Int'Max (0, Limit ("evolve.cap", 500)));
      function Lm (K : String; D : Int) return Natural is (Natural (Int'Max (0, Int'Min (100_000, Limit (K, D)))));
      Pr : Sim_Evolve.Word_Params :=
        (Use_Pts => Lm ("evolve.use_pts", 1), Use_Cap => Lm ("evolve.word_use_cap", 5), Grant_Pts => Lm ("evolve.grant_pts", 3),
         Agree_Pts => Lm ("evolve.agree_pts", 5), Line10 => Lm ("evolve.line10", 3), Fit_Cap => Lm ("evolve.fit_cap", 200),
         Probation => Lm ("evolve.probation", 3), Idle => Lm ("evolve.idle_sessions", 6), Retire_Max => Lm ("evolve.retire_max", 40),
         Min_Active => Cap, Cap => Cap);
      --  active=2 (docs/EVOLVE.md 14): the same points with its own floor and cap, and the mint-slow percents
      Pr2 : Sim_Evolve.Word_Params := (Pr with delta Min_Active => Lm ("active.floor", 300), Cap => Lm ("active.cap", 500));
      Slow : Sim_Active.Slow_Pcts := (Lesson => Lm ("active.slow_lesson_pct", 25), Coin => Lm ("active.slow_coin_pct", 50),
                                      Screen => Lm ("active.slow_screen_pct", 50));
      Have : array (1 .. 2) of Boolean := [others => False];
   begin
      if Ada.Directories.Exists (Active_Path) then
         Read_Lines (Active_Path, Lines, Found);
         for L of Lines loop   --  the params line of the first session of each level (a save keeps its numbers)
            if Fx.Index (L, " params ") > 0 then
               declare
                  Lv : constant Positive := Sim_Active.Params_Level (L);
               begin
                  if not Have (Lv) then
                     if Lv = 2 then
                        Sim_Active.Parse_Params (L, Pr2, OK);
                        Sim_Active.Parse_Slow (L, Slow);
                     else
                        Sim_Active.Parse_Params (L, Pr, OK);
                     end if;
                     Have (Lv) := True;
                  end if;
               end;
               exit when Have (1) and then Have (2);
            end if;
         end loop;
      end if;
      Sim_Active.Reset (Pr, Pr2, Slow);
   end Load_Active_Params;

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
            Active_Feed (Line);
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

   --  Every robot record (command, execution with the camera view, shared screen, learned word) is a Q line in diaries/robot.txt.
   procedure Emit_Robot_Lines (Tick : Int) is
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      for T of Robot_Lines loop
         Robot_N := Robot_N + 1;
         declare
            Line : constant String := "Q" & Img (Robot_N) & " t=" & Img (Tick) & " " & T;
         begin
            Sim_Store.Emit (Robot_Store, Line, not Preview and then not Ledger_Mode, Result, Old);
            if Sim_Store."=" (Result, Sim_Store.Differs) then
               raise Drift_Error with Msg ("err.robot", "Q" & Img (Robot_N), Diff_At (To_String (Old), Line));
            end if;
         end;
      end loop;
      Robot_Lines.Clear;
   end Emit_Robot_Lines;

   procedure Verify_Robot (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Robot_Store, Upto);
   begin
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.robot", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Robot;

   --  records=1: the new lines of Sim_Records are compared with the record files (appended where they are new: Write).
   procedure Flush_Records (Write : Boolean) is
      Vs, Ps, Ds, Ns, Bs : Str_Vectors.Vector;
      Can : constant Boolean := Write and then not Preview and then not Ledger_Mode;
      procedure One (S : in out Sim_Store.Store; Lines : Str_Vectors.Vector; File : String) is
         Result : Sim_Store.Status;
         Old : Unbounded_String;
      begin
         for T of Lines loop
            Sim_Store.Emit (S, T, Can, Result, Old);
            if Sim_Store."=" (Result, Sim_Store.Differs) then
               raise Drift_Error with Msg ("err.records", File & " " & Sim_Store.Key_Of (T), Diff_At (To_String (Old), T));
            elsif Sim_Store."=" (Result, Sim_Store.Skipped) and then not Preview and then not Ledger_Mode then   --  a stored file lost a line
               raise Drift_Error with Msg ("err.records", File & " " & Sim_Store.Key_Of (T), Diff_At ("(missing)", T));
            end if;
            if File = "votes.txt" or else File = "petitions.txt" or else File = "dictionary.txt" then Active_Feed (T); end if;
         end loop;
      end One;
   begin
      Sim_Records.Drain (Vs, Ps, Ds, Ns, Bs);
      One (Votes_Store, Vs, "votes.txt");
      One (Pets_Store, Ps, "petitions.txt");
      One (Dict_Store, Ds, "dictionary.txt");
      One (Anns_Store, Ns, "announcements.txt");
      One (Bals_Store, Bs, "ballots.txt");
   end Flush_Records;

   procedure Verify_Records (Upto : Int) is
      procedure One (S : Sim_Store.Store; File : String) is
         Orphan : constant String := Sim_Store.Orphan (S, Upto);
      begin
         if Orphan /= "" then
            raise Drift_Error with Msg ("err.records", File & " " & Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
         end if;
      end One;
   begin
      One (Votes_Store, "votes.txt");
      One (Pets_Store, "petitions.txt");
      One (Dict_Store, "dictionary.txt");
      One (Anns_Store, "announcements.txt");
      One (Bals_Store, "ballots.txt");
   end Verify_Records;

   --  Every decision of a player (also a refusal), veto and approval is a D line in diaries/govern.txt: replay-verified.
   procedure Emit_Govern_Lines is
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      for T of Govern_Lines loop
         Sim_Store.Emit (Govern_Store, T, not Preview and then not Ledger_Mode, Result, Old);
         if Sim_Store."=" (Result, Sim_Store.Differs) then
            raise Drift_Error with Msg ("err.govern", Sim_Store.Key_Of (T), Diff_At (To_String (Old), T));
         end if;
         if Sim_Records.Active then Sim_Records.From_Decision (T); end if;   --  records=1: the vote and the answer of the petition
      end loop;
      Govern_Lines.Clear;
      if Sim_Records.Active then Flush_Records (Cur_Tick > Int (Common)); end if;
   end Emit_Govern_Lines;

   procedure Verify_Govern (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Govern_Store, Upto);
   begin
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.govern", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Govern;

   --  The claims of the players (Sim_Preport) at the end of a preport=1 session: P lines, compared with diaries/preports.txt.  A line that is
   --  missing for a tick that is already on disk is DRIFT as well (tamper or removal); new ticks append.
   function Mood_Now return Sim_Preport.Ints is
      R : Sim_Preport.Ints;
   begin
      for E in Entity_Id loop R (E) := St (E).Mood; end loop;
      return R;
   end Mood_Now;

   function Pets_Now return Sim_Preport.Ints is
      R : Sim_Preport.Ints;
   begin
      for E in Entity_Id loop R (E) := Petitions_Of (E); end loop;
      return R;
   end Pets_Now;

   procedure Preport_Round (Tick : Int) is
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      Preport_Lines.Clear;
      Sim_Preport.Round (Tick, Mood_Now, Pets_Now, Preport_Lines);
      for T of Preport_Lines loop
         Sim_Store.Emit (Preport_Store, T, Tick > Int (Common) and then not Preview and then not Ledger_Mode, Result, Old);
         if Sim_Store."=" (Result, Sim_Store.Differs) then
            raise Drift_Error with Msg ("err.preport", Sim_Store.Key_Of (T), Diff_At (To_String (Old), T));
         elsif Sim_Store."=" (Result, Sim_Store.Skipped) and then not Preview then
            raise Drift_Error with Msg ("err.preport", Sim_Store.Key_Of (T), Diff_At ("(missing)", T));
         end if;
      end loop;
   end Preport_Round;

   procedure Verify_Preport (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Preport_Store, Upto);
   begin
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.preport", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Preport;

   --  The advice for the next run (Sim_Next) at the end of a nextticks=1 session: an N line, compared with diaries/nextticks.txt (same rules as
   --  the P lines: a differing or missing line is DRIFT, new ticks append).
   function Next_Inputs return Sim_Next.Inputs is
      R : Sim_Next.Inputs;
   begin
      for E in Entity_Id loop
         R.Mood (E) := St (E).Mood;
         R.Energy (E) := St (E).Energy;
         R.Unrest (E) := Sim_Dharma.Unrest_Of (E);
         R.Open (E) := Sim_Govern.Open_Of (E);
         R.Defer (E) := Sim_Govern.Deferred_Of (E);
      end loop;
      return R;
   end Next_Inputs;

   procedure Next_Round (Tick : Int) is
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      Next_Lines.Clear;
      Sim_Next.Round (Tick, Next_Inputs, Next_Lines);
      for T of Next_Lines loop
         Sim_Store.Emit (Next_Store, T, Tick > Int (Common) and then not Preview and then not Ledger_Mode, Result, Old);
         if Sim_Store."=" (Result, Sim_Store.Differs) then
            raise Drift_Error with Msg ("err.nextticks", Sim_Store.Key_Of (T), Diff_At (To_String (Old), T));
         elsif Sim_Store."=" (Result, Sim_Store.Skipped) and then not Preview then
            raise Drift_Error with Msg ("err.nextticks", Sim_Store.Key_Of (T), Diff_At ("(missing)", T));
         end if;
         if Sim_Records.Active then Sim_Records.From_Advice (T); end if;
      end loop;
      if Sim_Records.Active then Flush_Records (Tick > Int (Common)); end if;
   end Next_Round;

   procedure Verify_Next (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Next_Store, Upto);
   begin
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.nextticks", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Next;

   --  The advice lines of the end box (display names are applied by the box / the console layer).
   function Next_Extra (Tick : Int) return Str_Vectors.Vector is
      V : Str_Vectors.Vector;
   begin
      if Next_Active or else Sim_Next.Rounds > 0 then V := Sim_Next.Box_Lines (Tick, Next_Inputs); end if;
      declare
         Visit_Line : constant String := Sim_Visit.Comment (Session_N, Natural (Sim_Dharma.Last_Player));   --  a player on Robert's visit (visit=1)
         Trial_Line : constant String := (if Trial_Active then Sim_Trial.Box_Line (Natural (Sim_Dharma.Last_Player)) else "");   --  a trial of this session
         Rec_Line : constant String := Sim_Records.Box_Line (Natural (Sim_Dharma.Last_Player));   --  records=1: words and announcements of this session
      begin
         if Trial_Line /= "" then V.Append (Trial_Line); end if;
         if Rec_Line /= "" then V.Append (Rec_Line); end if;
         if Visit_Line /= "" then V.Append (Visit_Line); end if;
      end;
      return V;
   end Next_Extra;

   --  Robert's challenge inputs: Q<n> tick=<T> player=<id> by=<who> (read before the replay).
   procedure Load_Challenges is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      if not Ada.Directories.Exists (Challenges_Path) then return; end if;
      Read_Lines (Challenges_Path, Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'Q' and then Fx.Index (L, " ") > 2 then
            declare
               Sp : constant Natural := Fx.Index (L, " ");
               N : constant Int := To_Num_Safe (L (L'First + 1 .. Sp - 1));
               Tk : constant Int := To_Num_Safe (Token (L, "tick"));
               Pl : constant Natural := Sim_Dharma.Find_Player (Token (L, "player"));
            begin
               if N > 0 and then Tk >= 0 and then Pl > 0 then
                  Sim_Preport.Add_Challenge (Positive (N), Tk, Sim_Dharma.Player_Id (Pl));
               else
                  Warn (Msg ("warn.grants_bad", L));
               end if;
            end;
         end if;
      end loop;
   end Load_Challenges;

   --  Robert's veto / approval inputs: V<n> tick=<T> decision=D<k> act=veto|approve by=<who> (read before the replay).
   procedure Load_Vetoes is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      if not Ada.Directories.Exists (Vetoes_Path) then return; end if;
      Read_Lines (Vetoes_Path, Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'V' and then Fx.Index (L, " ") > 2 then
            declare
               Sp : constant Natural := Fx.Index (L, " ");
               N : constant Int := To_Num_Safe (L (L'First + 1 .. Sp - 1));
               Tk : constant Int := To_Num_Safe (Token (L, "tick"));
               Dc : constant String := Token (L, "decision");
               Dn : constant Int := (if Dc'Length > 1 and then Dc (Dc'First) = 'D' then To_Num_Safe (Dc (Dc'First + 1 .. Dc'Last)) else -1);
               Act : constant String := Token (L, "act");
            begin
               if N > 0 and then Tk >= 0 and then Dn > 0 and then Act in "veto" | "approve" then
                  Sim_Govern.Add_Input (Positive (N), Tk, Positive (Dn), Act = "approve");
               else
                  Warn (Msg ("warn.grants_bad", L));
               end if;
            end;
         end if;
      end loop;
   end Load_Vetoes;

   --  ---- the visit (Sim_Visit): Robert next to one wesen; every input is a V line, every answer an A line of diaries/visit.txt ----------
   --  The recorded inputs (V lines) are read before the replay and applied at the end of their tick, in this code path live and on replay.
   --  A V line that is not exactly what the program writes (its check number h= included), a V line outside a visit=1 session, a missing,
   --  changed or invented V / A line is DRIFT.
   procedure Load_Visit is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      Visit_Inputs.Clear;
      if not Ada.Directories.Exists (Visit_Path) then return; end if;
      Read_Lines (Visit_Path, Lines, Found);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) = 'V' then
            declare
               N : Natural;
               Tk : Int;
               C : Sim_Visit.Command;
               OK : Boolean;
            begin
               Sim_Visit.Parse_Input (L, N, Tk, C, OK);
               if not OK then raise Drift_Error with Msg ("err.visit_in", Sim_Store.Key_Of (L)); end if;
               Visit_Inputs.Append (Visit_In'(N => Positive (N), Tick => Tk, C => C, Done => False));
            end;
         end if;
      end loop;
   end Load_Visit;

   procedure Emit_Visit (Line : String; Tick : Int) is
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      Sim_Store.Emit (Visit_Store, Line, Tick > Int (Common) and then not Preview and then not Ledger_Mode, Result, Old);
      if Sim_Store."=" (Result, Sim_Store.Differs) then
         raise Drift_Error with Msg ("err.visit", Sim_Store.Key_Of (Line), Diff_At (To_String (Old), Line));
      elsif Sim_Store."=" (Result, Sim_Store.Skipped) then
         raise Drift_Error with Msg ("err.visit", Sim_Store.Key_Of (Line), Diff_At ("(missing)", Line));
      end if;
   end Emit_Visit;

   --  One command at the end of Tick: its V line, the effect (answer, words learned), its A line.
   procedure Visit_Apply (N : Positive; C : Sim_Visit.Command; Tick : Int) is
      Answer : Unbounded_String;
      Learned : Sim_Visit.Word_Vectors.Vector;
   begin
      Emit_Visit (Sim_Visit.Input_Line (N, Tick, C), Tick);
      Sim_Visit.Apply (C, Visit_E, Tick, N, St (Visit_E).Mood, St (Visit_E).Energy,
                       (if Govern_Active then Sim_Govern.Open_Of (Visit_E) else 0), Answer, Learned);
      for W of Learned loop
         if Knows (Visit_E, W) then Ensure (Visit_E, Words_File, Words_Line (W, "visit", Tick, "")); end if;   --  a blocked symbol is not learned
         if Screen_Active then Sim_Screen.Note (Visit_E, W, "taught"); end if;
      end loop;
      if Length (Answer) > 0 then Emit_Visit (To_String (Answer), Tick); end if;
   end Visit_Apply;

   --  A new command of the live visit: numbered after the last V line, remembered, applied.
   procedure Visit_Record (C : Sim_Visit.Command; Tick : Int) is
      N : Positive := 1;
   begin
      for X of Visit_Inputs loop N := Positive'Max (N, X.N + 1); end loop;
      Visit_Inputs.Append (Visit_In'(N => N, Tick => Tick, C => C, Done => True));
      Visit_Apply (N, C, Tick);
   end Visit_Record;

   --  The next command line of the human (stdin) or of the script (blank lines and # lines skipped); Got False at the end of the input.
   procedure Visit_Read (Line : out Unbounded_String; Got : out Boolean) is
   begin
      Line := Null_Unbounded_String;
      Got := False;
      TIO.Flush;
      if Script_On then
         while not TIO.End_Of_File (Script_File) loop
            declare
               L : constant String := Fx.Trim (TIO.Get_Line (Script_File), Ada.Strings.Both);
            begin
               if L'Length > 0 and then L (L'First) /= '#' then
                  Line := To_Unbounded_String (L);
                  Got := True;
                  return;
               end if;
            end;
         end loop;
      else
         Line := To_Unbounded_String (TIO.Get_Line);
         Got := True;
      end if;
   exception
      when others => Got := False;   --  end of the input, or a closed one
   end Visit_Read;

   --  The frame of this tick; then (every visit.every ticks) the commands of the human until a wait or leave.
   procedure Visit_Live (Tick : Int) is
      Sc : Sim_Visit.Scene;
      Note : Unbounded_String;
      Line : Unbounded_String;
      Got : Boolean;
      procedure Leave_Now is
      begin
         Visit_Record ((Kind => Sim_Visit.Leave, others => <>), Tick);
         Visit_Left := True;
         Con.Put_Line (Sim_Visit.Leave_Text (Visit_E));
      end Leave_Now;
   begin
      Sc := (E => Visit_E, Tick => Tick, Index => Natural (Tick - Visit_Start), Total => Natural (Visit_End - Visit_Start),
             Mood => St (Visit_E).Mood, Energy => St (Visit_E).Energy, Location => St (Visit_E).Location,
             Pets => (if Govern_Active then Sim_Govern.Open_Of (Visit_E) else 0), Diary => Last_Diary (Visit_E),
             World => World_Active, Screen => Screen_Active, Prompt => False, Note => Null_Unbounded_String);
      if Natural (Tick - Visit_Start) mod Sim_Visit.Every /= 0 or else Tick < Visit_Wait then
         Con.Put (Sim_Visit.Frame (Sc));
         return;
      end if;
      Sc.Prompt := True;
      loop
         Sc.Note := Note;
         Note := Null_Unbounded_String;
         Con.Put (Sim_Visit.Frame (Sc));
         if Con.Is_Dead or else Sim_Quit.Requested then
            Visit_Left := True;   --  nobody reads: the session runs on quietly
            return;
         end if;
         Visit_Read (Line, Got);
         if not Got then
            Con.Put ("" & ASCII.LF);
            Leave_Now;
            return;
         end if;
         if not Is_Tty (0) then Con.Put_Line (To_String (Line)); end if;
         declare
            C : constant Sim_Visit.Command := Sim_Visit.Parse (To_String (Line));
         begin
            case C.Kind is
               when Sim_Visit.Bad =>
                  Note := To_Unbounded_String (Msg ("visit.help.unknown", To_String (C.Text)) & " | " & Sim_Visit.Help_Text);
               when Sim_Visit.Say | Sim_Visit.Teach | Sim_Visit.Show_Cmd =>
                  Visit_Record (C, Tick);
               when Sim_Visit.Wait =>
                  Visit_Record (C, Tick);
                  Visit_Wait := Tick + Int (C.N);
                  return;
               when Sim_Visit.Leave =>
                  Leave_Now;
                  return;
            end case;
         end;
      end loop;
   end Visit_Live;

   procedure Visit_Step (Tick : Int) is
   begin
      for I in 1 .. Natural (Visit_Inputs.Length) loop
         if not Visit_Inputs (I).Done and then Visit_Inputs (I).Tick = Tick then
            Visit_Inputs.Reference (I).Done := True;
            Visit_Apply (Visit_Inputs (I).N, Visit_Inputs (I).C, Tick);
         end if;
      end loop;
      if Visit_Mode and then not Visit_Left and then Tick > Int (Common) and then not Ledger_Mode and then not Preview then
         Visit_Live (Tick);
      end if;
   end Visit_Step;

   procedure Verify_Visit (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Visit_Store, Upto);
   begin
      for X of Visit_Inputs loop
         if not X.Done and then X.Tick <= Upto then
            raise Drift_Error with Msg ("err.visit_out", "V" & Img (X.N), Img (X.Tick));
         end if;
      end loop;
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.visit", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Visit;

   --  The facts one wesen can say about itself, from the real records of the replayed state.
   function Voice_Facts (E : Entity_Id; Change : Integer) return Sim_Voice.Facts is
      F : Sim_Voice.Facts;
      Fav : Natural := 0;
      Fav_N : Int := 0;
      Latest : Natural := 0;
      Dec : constant String := (if Govern_Active then Sim_Govern.Last_Line_Of (E) else "");
   begin
      F.Id := To_Unbounded_String (Name (E));
      F.Name := To_Unbounded_String (Sim_World.Display (E));
      F.Act := To_Unbounded_String (Low (Voice_Act (E)));
      F.Mood := St (E).Mood;
      F.Energy := St (E).Energy;
      F.Words := Known_Count (E);
      F.Change := Change;
      for L in 0 .. 3 loop
         if Votes_Of (E) (L).N > Fav_N then Fav_N := Votes_Of (E) (L).N; Fav := L; end if;
      end loop;
      if Fav_N > 0 then F.Place := To_Unbounded_String (Msg ("loc." & Img (Fav))); end if;
      if Voice_Hist (E, 1) > 0 then F.Word := To_Unbounded_String (Word (Voice_Hist (E, 1))); end if;
      for N in reverse 1 .. Petition_Total loop
         if Petition_From (N) = E then Latest := N; exit; end if;
      end loop;
      F.Open := (if Govern_Active then Sim_Govern.Open_Of (E) else Petitions_Of (E));
      F.Outcome := To_Unbounded_String (Token (Dec, "kind"));
      if Dec /= "" and then F.Open = 0 and then Topic_Id (Token (Dec, "topic")) > 0 then
         F.Topic := To_Unbounded_String (Topic_Phrase (Topic_Id (Token (Dec, "topic"))));
      elsif Latest > 0 then
         F.Topic := To_Unbounded_String (Topic_Phrase (Topic_Id (Petition_Topic (Latest))));
      end if;
      F.Trials := (if Trial_Active then Sim_Trial.Count else 0);
      return F;
   exception
      when Constraint_Error => return F;
   end Voice_Facts;

   function Voice_Text (E : Entity_Id; Tick : Int; Change : Integer) return String is
     (Sim_Voice.Message (Voice_Facts (E, Change), Seed, Tick, Integer (E)));

   --  ---- the chat (Sim_Chat): every typed line and every answer is a C line of diaries/chat.txt ----------------------------------------
   --  A line is handled at the very end of its tick (state: the replayed state of that tick, in this code path live and on replay).  The
   --  typed lines (who = the human) are read before the replay; the answers are computed again and compared: a line that is not exactly
   --  what the program writes (its check number h= included), a missing, changed or invented line is DRIFT.  Nothing here changes the
   --  simulation: the chat reads the state and writes diaries/chat.txt only.
   procedure Load_Chat is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      Chat_Inputs.Clear;
      Chat_N := 0;
      if not Ada.Directories.Exists (Chat_Path) then return; end if;
      Read_Lines (Chat_Path, Lines, Found);
      for L of Lines loop
         if L'Length > 0 and then L (L'First) = 'C' then
            declare
               P : Sim_Chat.Parsed;
               OK : Boolean;
            begin
               Sim_Chat.Parse_Line (L, P, OK);
               if not OK then raise Drift_Error with Msg ("err.chat_in", Sim_Store.Key_Of (L)); end if;
               if To_String (P.Who) = Sim_Chat.Me then
                  Chat_Inputs.Append (Chat_In'(N => Positive (P.N), Tick => P.Tick, Text => P.Text, Done => False));
               end if;
            end;
         end if;
      end loop;
   end Load_Chat;

   procedure Chat_Sample (Tick : Int) is
      Step : constant Int := Int'Max (1, Limit ("chat.trend_step", 100));
      S : Sim_Chat.Sample;
   begin
      if Tick mod Step /= 0 then return; end if;
      S.Tick := Tick;
      for E in Entity_Id loop
         S.Mood (Integer (E)) := St (E).Mood;
         S.Energy (Integer (E)) := St (E).Energy;
      end loop;
      Chat_Samples.Append (S);
      if Natural (Chat_Samples.Length) > 200 then Chat_Samples.Delete_First; end if;
   end Chat_Sample;

   function Chat_World (Tick : Int) return Sim_Chat.World is
      W : Sim_Chat.World;
      Seen : Natural := 0;
   begin
      W.Tick := Tick;
      Seen := Chat_Session_Count;
      W.Session := Seen;
      W.Sessions := Seen;
      W.Samples := Chat_Samples;
      for E in Entity_Id loop
         declare
            P : Sim_Chat.Person;
         begin
            P.Kind := Sim_Chat.Wesen;
            P.Id := To_Unbounded_String (Name (E));
            P.Name := To_Unbounded_String (Sim_World.Display (E));
            P.Facts := Voice_Facts (E, St (E).Mood - Chat_Start_Mood (E));
            for K in 1 .. 5 loop
               if Voice_Hist (E, K) > 0 then Append (P.Word_List, (if Length (P.Word_List) > 0 then ", " else "") & Word (Voice_Hist (E, K))); end if;
            end loop;
            W.People.Append (P);
         end;
      end loop;
      for Pl in 1 .. 4 loop
         declare
            Pid : constant Sim_Dharma.Player_Id := Sim_Dharma.Player_Id (Pl);
            P : Sim_Chat.Person;
         begin
            P.Kind := Sim_Chat.Player;
            P.Id := To_Unbounded_String (Sim_Dharma.Player_Name (Pid));
            P.Name := To_Unbounded_String (Sim_World.Show (Sim_Dharma.Player_Name (Pid)));
            P.Present := Pl <= Integer (Sim_Dharma.Last_Player);
            if P.Present then
               for E in Entity_Id loop
                  if Natural (Sim_Dharma.Watcher (E)) = Pl then
                     P.Watches := To_Unbounded_String (Sim_World.Display (E));
                     P.Watch_Mood := St (E).Mood;
                     P.Watch_Energy := St (E).Energy;
                     P.Open := P.Open + (if Govern_Active then Sim_Govern.Open_Of (E) else 0);
                  end if;
               end loop;
               declare
                  C : constant Sim_Govern.Counts_T := Sim_Govern.Counts_Of (Pid);
               begin
                  P.Seen := C (1);
                  P.Granted := C (2);
                  P.Refused := C (5);
               end;
               P.Stance := Sim_Dharma.Warm_Of (Pid);
            end if;
            W.People.Append (P);
         end;
      end loop;
      declare
         P : Sim_Chat.Person;
      begin
         P.Kind := Sim_Chat.Observer;
         P.Id := To_Unbounded_String (Msg ("chat.id.observer"));
         P.Name := To_Unbounded_String (Msg ("chat.name.observer"));
         W.People.Append (P);
      end;
      return W;
   end Chat_World;

   procedure Chat_Emit (Line : String; Tick : Int) is
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      Sim_Store.Emit (Chat_Store, Line, Tick > Int (Common) and then not Preview and then not Ledger_Mode, Result, Old);
      if Sim_Store."=" (Result, Sim_Store.Differs) then
         raise Drift_Error with Msg ("err.chat", Sim_Store.Key_Of (Line), Diff_At (To_String (Old), Line));
      elsif Sim_Store."=" (Result, Sim_Store.Skipped) then
         raise Drift_Error with Msg ("err.chat", Sim_Store.Key_Of (Line), Diff_At ("(missing)", Line));
      end if;
   end Chat_Emit;

   --  The chat window on the screen: what was said, newest last (only lines typed now; a replay does not fill the screen).
   procedure Chat_Show (Who, Text : String) is
      Shown : constant String := Msg ("chat.fmt.line", Sim_World.Show (Who), Text);
   begin
      Chat_Shown.Append (Shown);
      while Natural (Chat_Shown.Length) > Natural (Int'Max (4, Limit ("chat.keep", 200))) loop Chat_Shown.Delete_First; end loop;
      Chat_Version := Chat_Version + 1;
      if Night_On and then not Tty_Out then Con.Put_Line_Now (Shown); end if;   --  no terminal: the lines go to the plain console
   end Chat_Show;

   procedure Chat_Line (Who, To_Id, Text : String; Tick : Int) is
   begin
      Chat_N := Chat_N + 1;
      Chat_Emit (Sim_Chat.Line_Of (Chat_N, Tick, Who, To_Id, Text), Tick);
      if Chat_Live then Chat_Show (Who, Text); end if;
   end Chat_Line;

   --  One typed line at the end of Tick: Robert's C line, the answers, and (typed now only) what an order does to the run.
   procedure Chat_Apply (Text : String; Tick : Int) is
      Res : constant Sim_Chat.Result := Sim_Chat.Handle (Chat_World (Tick), Chat_N + 1, Text);
   begin
      Chat_Line (Sim_Chat.Me, To_String (Res.To), Text, Tick);
      for R of Res.Replies loop Chat_Line (To_String (R.Who), To_String (R.To_Id), To_String (R.Text), Tick); end loop;
      if Chat_Live then
         case Res.Effect is
            when Sim_Chat.None => null;
            when Sim_Chat.Pause => Chat_Paused := Tty_Out and then Length (Chat_Script_Opt) = 0;   --  a script runs on ticks: it cannot wait
            when Sim_Chat.Resume => Chat_Paused := False;
            when Sim_Chat.Quit => Sim_Quit.Ask_Quit;
            when Sim_Chat.Clear =>
               declare
                  Last : constant String := (if Chat_Shown.Is_Empty then "" else Chat_Shown.Last_Element);
               begin
                  Chat_Shown.Clear;
                  if Last /= "" then Chat_Shown.Append (Last); end if;
                  Chat_Version := Chat_Version + 1;
               end;
            when Sim_Chat.Voices_On => Voice_On := True;
            when Sim_Chat.Voices_Off => Voice_On := False;
         end case;
      end if;
   end Chat_Apply;

   --  The first number of a script line "<ticks> <text>" (ticks into the live part of the run); -1: not a script line.
   function Script_At (L : String) return Int is
      Sp : constant Natural := Fx.Index (L, " ");
   begin
      return (if Sp > L'First and then (for all C of L (L'First .. Sp - 1) => C in '0' .. '9') then Int'Value (L (L'First .. Sp - 1)) else -1);
   end Script_At;

   --  The lines typed now (the terminal's, or the script's) are handled in tick order, at the end of Tick.
   procedure Chat_Live_Lines (Tick : Int) is
   begin
      Chat_Live := True;
      loop
         if Chat_Script_Next <= Natural (Chat_Script.Length) and then Script_At (Chat_Script.Element (Chat_Script_Next)) <= Tick - Int (Common) then
            declare
               L : constant String := Chat_Script.Element (Chat_Script_Next);
            begin
               Chat_Script_Next := Chat_Script_Next + 1;
               Chat_Inputs.Append (Chat_In'(N => Chat_N + 1, Tick => Tick, Text => To_Unbounded_String (Fx.Trim (L (Fx.Index (L, " ") + 1 .. L'Last), Ada.Strings.Both)), Done => True));
               Chat_Apply (Fx.Trim (L (Fx.Index (L, " ") + 1 .. L'Last), Ada.Strings.Both), Tick);
            end;
         elsif Sim_Quit.Pending then
            declare
               L : constant String := Sim_Quit.Take;
            begin
               Chat_Inputs.Append (Chat_In'(N => Chat_N + 1, Tick => Tick, Text => To_Unbounded_String (L), Done => True));
               Chat_Apply (L, Tick);
            end;
         else
            exit;
         end if;
      end loop;
      Chat_Live := False;
   exception
      when others => Chat_Live := False; raise;
   end Chat_Live_Lines;

   procedure Chat_Step (Tick : Int) is
   begin
      for I in 1 .. Natural (Chat_Inputs.Length) loop
         if not Chat_Inputs (I).Done and then Chat_Inputs (I).Tick = Tick then
            Chat_Inputs.Reference (I).Done := True;
            Chat_Apply (To_String (Chat_Inputs (I).Text), Tick);
         end if;
      end loop;
      if Tick > Int (Common) and then not Ledger_Mode and then not Preview and then (Night_On or else Chat_Mode) then
         Chat_Live_Lines (Tick);
      end if;
   end Chat_Step;

   procedure Verify_Chat (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Chat_Store, Upto);
   begin
      for X of Chat_Inputs loop
         if not X.Done and then X.Tick <= Upto then
            raise Drift_Error with Msg ("err.chat_out", "C" & Img (X.N), Img (X.Tick));
         end if;
      end loop;
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.chat", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Chat;


   --  trial=1: at most one dispute per tick is settled (Sim_Trial); its games are g=N lines of diaries/chess.txt, the trial a T line.
   procedure Trial_Step (Tick : Int) is
      Moods : Sim_Games.Mood_Array;
      Result : Sim_Store.Status;
      Old : Unbounded_String;
   begin
      for X in Entity_Id loop Moods (X) := St (X).Mood; end loop;
      Trial_Lines.Clear;
      Sim_Trial.Step (Tick, Moods, Trial_Lines, Chess_Lines);
      Emit_Chess_Lines (Tick);
      for T of Trial_Lines loop
         declare
            Line : constant String := T;
         begin
            Sim_Store.Emit (Trial_Store, Line, Tick > Int (Common) and then not Preview and then not Ledger_Mode, Result, Old);
            if Sim_Store."=" (Result, Sim_Store.Differs) then
               raise Drift_Error with Msg ("err.trial", Sim_Store.Key_Of (Line), Diff_At (To_String (Old), Line));
            elsif Sim_Store."=" (Result, Sim_Store.Skipped) and then not Preview and then not Ledger_Mode then   --  a stored session lost a line
               raise Drift_Error with Msg ("err.trial", Sim_Store.Key_Of (Line), Diff_At ("(missing)", Line));
            end if;
            if Sim_Records.Active then Sim_Records.From_Trial (Line); end if;
         end;
      end loop;
      if Sim_Records.Active then Flush_Records (Tick > Int (Common)); end if;
   end Trial_Step;

   procedure Verify_Trial (Upto : Int) is
      Orphan : constant String := Sim_Store.Orphan (Trial_Store, Upto);
   begin
      if Orphan /= "" then
         raise Drift_Error with Msg ("err.trial", Sim_Store.Key_Of (Orphan), Diff_At (Orphan, "(not in the replay)"));
      end if;
   end Verify_Trial;

   procedure Do_Tick (Tick : Int) is
   begin
      Cur_Tick := Tick;
      Sim_Dharma.Tick_Begin (Tick);
      Apply_Grants (Tick);
      if Chess_Active then   --  the clocks of the running games (a timeout ends one)
         Sim_Games.Clock (Tick, Chess_Lines);
         Emit_Chess_Lines (Tick);
      end if;
      if Govern_Active then   --  the players decide the petitions that are due; Robert's vetoes and approvals take effect
         declare
            Bad : Natural;
         begin
            Sim_Govern.Tick_Begin (Tick, Govern_Lines, Bad);
            if Bad > 0 then raise Drift_Error with Msg ("err.govern_in", "V" & Img (Bad)); end if;
            Emit_Govern_Lines;
         end;
      end if;
      if Preport_Active then   --  Robert's challenges of a lying player take effect
         declare
            Bad : Natural;
         begin
            Sim_Preport.Tick_Begin (Tick, Bad);
            if Bad > 0 then raise Drift_Error with Msg ("err.preport_in", "Q" & Img (Bad)); end if;
         end;
      end if;
      if Robot_Active then   --  the robot acts when its delay is over
         Sim_Robot.Tick_Begin (Tick, Robot_Lines);
         Emit_Robot_Lines (Tick);
      end if;
      for E in Entity_Id loop
         Cur_Name := To_Unbounded_String (Name (E));
         if Tick = Crash_At and then Tick > Int (Common) and then E = 1 then Events := Forced (Tick); end if;
         declare
            Line : constant String := Step (E, Tick);
         begin
            Emit_Screen_Lines (Tick);
            Emit_Chess_Lines (Tick);
            Emit_Robot_Lines (Tick);
            if Tick <= Int (Disk_Len (E)) then   --  already on disk: compare, do not write
               if No_Ts (Line) /= No_Ts (Disk (E) (Positive (Tick - Int (Disk_Base (E))))) then
                  raise Drift_Error with Msg ("err.drift", Name (E), Img (Tick),
                                              Diff_At (No_Ts (Disk (E) (Positive (Tick - Int (Disk_Base (E))))), No_Ts (Line)));
               end if;
               Verified := Verified + 1;
            else
               if Preview then
                  Sample (E).Append (Line);
               else
                  TIO.Put_Line (Out_File (E), Line);
                  TIO.Flush (Out_File (E));
                  if Night_Mode then Disk (E).Append (Line); end if;   --  0.057: the next session of a night needs no reread of the diary
                  --  (0.058: a start from state.ckpt holds only the lines after the checkpoint, Disk_Base counts the others)
               end if;
               Written := Written + 1;
            end if;
            Events := Written + Verified;
            Last_Diary (E) := To_Unbounded_String (Line);
            Act_Count (E, Last_Act) := Act_Count (E, Last_Act) + 1;
            if Last_Verb in World_Verb then Verb_Count (E, Last_Verb) := Verb_Count (E, Last_Verb) + 1; end if;
            Sim_Dharma.Deed (E, Last_Act, Pre_Energy_G, Did_Teach, Did_Coin);
            Record_Tick (Votes_Of (E), St (E).Location, St (E).Mood, St (E).Energy, Did_Learn, Did_Coin, Did_Bench);
            if Trial_Active then Sim_Trial.Note_Step (E, Tick, St (E).Location, Last_Act = Sim_World.Work, Did_Coin, Rest_Active and then Cool (E) > 0); end if;
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
      if Visit_Active and then Tick > Visit_Start and then Tick <= Visit_End then Visit_Step (Tick); end if;   --  the visitor's turn
      if Preport_Active and then Tick = Preport_End then Preport_Round (Tick); end if;   --  the claims of the players at the end of the session
      if Next_Active and then Tick = Next_End then Next_Round (Tick); end if;   --  the advice for the next run
      if Trial_Active then Trial_Step (Tick); end if;   --  disputes settled over the board
      if Sim_Records.Active then   --  records=1: new coined words are proposals; what was announced this tick
         Sim_Records.Scan_Coined (Tick);
         Flush_Records (Tick > Int (Common));
      end if;
      Chat_Sample (Tick);
      if Chat_Active then Chat_Step (Tick); end if;   --  the typed lines of this tick and their answers (chat=1), after everything else
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
      for N in 1 .. 99 loop   --  perft.rule.N = insufficient|enough FEN (chessrules=2: no mate possible)
         declare
            T : constant String := Msg ("perft.rule." & Img (N));
         begin
            exit when T (T'First) = '[';
            declare
               Want : constant String := Word_At (T, 1);
               Got : constant String := (if Sim_Chess.Insufficient (Pos_Of (After (T, 1))) then "insufficient" else "enough");
            begin
               Check (Got = Want, "rule " & Want & " " & After (T, 1), Want, Got);
            end;
         end;
      end loop;
      for N in 1 .. 99 loop   --  perft.key.N = same|diff FEN | FEN (the repetition key: board, side to move, castling rights, en passant)
         declare
            T : constant String := Msg ("perft.key." & Img (N));
            Bar : constant Natural := Fx.Index (T, " | ");
         begin
            exit when T (T'First) = '[';
            declare
               Want : constant String := Word_At (T, 1);
               A : constant Sim_Chess.Position := Pos_Of (T (T'First + Want'Length + 1 .. Bar - 1));
               B : constant Sim_Chess.Position := Pos_Of (T (Bar + 3 .. T'Last));
               Got : constant String := (if Sim_Chess.Same_Key (A, B) then "same" else "diff");
            begin
               Check (Got = Want, "key " & T, Want, Got);
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

   --  The box block of the players, last on the console: whole boxes in frames of at most preport.page_lines lines (80x24 terminal), ONE
   --  write per frame; on a terminal (and preport.pause = 1) a frame waits for Enter, otherwise (pipe, file) the frames follow each other.
   procedure Put_Frames (Block : String) is
      Max : constant Natural := Natural (Int'Max (8, Limit ("preport.page_lines", 23)));
      Frame : Unbounded_String;
      N : Natural := 0;       --  lines in the frame
      Box : Unbounded_String;
      Box_N : Natural := 0;   --  lines of the box being read (the blank line after it ends it)
      Ask : constant Boolean := Limit ("preport.pause", 1) /= 0 and then Is_Tty (0) and then Is_Tty (1) and then not Night_On;
      Frames : Natural := 0;
      procedure Flush is
      begin
         if N = 0 then return; end if;
         if Frames > 0 and then Ask then
            Con.Put_Line (Msg ("preport.more"));
            begin
               TIO.Skip_Line;
            exception
               when TIO.End_Error => null;
            end;
         end if;
         Con.Put (To_String (Frame));
         Frames := Frames + 1;
         Frame := Null_Unbounded_String; N := 0;
      end Flush;
      procedure Take_Box is
      begin
         if Box_N = 0 then return; end if;
         if N + Box_N > Max then Flush; end if;
         Append (Frame, To_String (Box)); N := N + Box_N;
         Box := Null_Unbounded_String; Box_N := 0;
      end Take_Box;
      From : Natural := Block'First;
   begin
      for I in Block'Range loop
         if Block (I) = ASCII.LF then
            declare
               Ln : constant String := Block (From .. I - 1);
            begin
               if Ln = "" then
                  Append (Box, ASCII.LF); Box_N := Box_N + 1; Take_Box;   --  a box and the blank line after it
               else
                  Append (Box, Ln & ASCII.LF); Box_N := Box_N + 1;
               end if;
            end;
            From := I + 1;
         end if;
      end loop;
      Take_Box;
      Flush;
   end Put_Frames;

   --  The audit after the replay (--audit / make audit): what the players claimed against what was true.
   function Audit_Text return String is
      R : Unbounded_String;
   begin
      if not Preport_Active and then Sim_Preport.Round_Count = 0 then return Msg ("audit.none") & ASCII.LF; end if;
      for L of Sim_Preport.Audit loop Append (R, L & ASCII.LF); end loop;
      return To_String (R);
   end Audit_Text;

   function Lines_Text (V : Str_Vectors.Vector) return String is
      R : Unbounded_String;
   begin
      for L of V loop Append (R, L & ASCII.LF); end loop;
      return To_String (R);
   end Lines_Text;

   --  The trials after the replay (--trials / make trials).
   function Trials_Text return String is
      R : Unbounded_String;
   begin
      for L of Sim_Trial.View loop Append (R, L & ASCII.LF); end loop;
      return To_String (R);
   end Trials_Text;

   --  The advice for the next run after the replay (--next / make next).
   function Next_Text return String is
      R : Unbounded_String;
   begin
      if Sim_Next.Rounds = 0 then return Msg ("next.none") & ASCII.LF; end if;
      for L of Sim_Next.View (Sim_Next.Last_Tick, Next_Inputs) loop Append (R, L & ASCII.LF); end loop;
      return To_String (R);
   end Next_Text;

   --  --next-ticks (make run without TICKS): the last recorded advice as a bare number on the LAST line, only with nextticks.use = 1; reads the
   --  record file, replays nothing (a tampered file is caught by the next replay).
   procedure Do_Next_Ticks is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Best : Natural := 0;
   begin
      if Limit ("nextticks.use", 0) = 0 or else not Ada.Directories.Exists (Next_Path) then return; end if;
      Read_Lines (Next_Path, Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) = 'N' and then Token (L, "next") /= "" then
            declare
               V : constant Integer := Integer (To_Num_Safe (Token (L, "next")));
            begin
               if V > 0 then Best := V; end if;
            end;
         end if;
      end loop;
      if Best > 0 then TIO.Put_Line (Img (Best)); end if;
   end Do_Next_Ticks;

   --  The governance after the replay (--govern / make govern).
   function Govern_Text return String is
      R : Unbounded_String;
   begin
      if not Govern_Active then return Msg ("govern.none") & ASCII.LF; end if;
      for L of Sim_Govern.View loop Append (R, L & ASCII.LF); end loop;
      return To_String (R);
   end Govern_Text;

   --  The robot after the replay (--robot / make robot).
   function Robot_Text return String is
      R : Unbounded_String;
   begin
      if not Robot_Active then return Msg ("robot.none") & ASCII.LF; end if;
      for L of Sim_Robot.View (Last_Done) loop Append (R, L & ASCII.LF); end loop;
      return To_String (R);
   end Robot_Text;

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
      if Kind = 'd' and then (Night_Mode or else Ckpt_Used) and then Expect > 0 and then Diary_Tail_Ok (P, Natural (Expect)) then   --  0.057: a night checks the end
         Lines := Expect;   --  of its own diary (it wrote every line of this run; the older ones were read and compared at its start)
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
         if Disk_Len (E) > 0 then Have := Have + 1; end if;
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
      Chessrules : Boolean := False;    --  chessrules=2: all the rules of chess (insufficient material, fivefold, 75 moves, claims; needs chess=1)
      Screen : Boolean := False;        --  screen=1: the wesen own small text screens (Sim_Screen, diaries/screens.txt)
      Robot : Boolean := False;         --  robot=1: the robot steered through the screens (Sim_Robot, diaries/robot.txt)
      Govern : Boolean := False;        --  govern=1: the players decide petitions (Sim_Govern, diaries/govern.txt)
      Scoin : Boolean := False;         --  scoin=1: screen blends have their own per-session cap and rate (not the global coin_cap)
      Players4 : Boolean := False;      --  players4=1: a fourth player (Sim_Dharma) takes over a wesen from this session on
      Trial : Boolean := False;         --  trial=1: disputes are settled with chess games (Sim_Trial, diaries/trials.txt; needs chess=1 and govern=1)
      Nextticks : Boolean := False;     --  nextticks=1: wesen propose and players decide the ticks of the next run (Sim_Next, diaries/nextticks.txt)
      Preport : Boolean := False;       --  preport=1: the players report to Robert in text boxes; their claims are recorded (Sim_Preport, diaries/preports.txt)
      Rec2 : Boolean := False;          --  records=2: records=1 plus the quality rules for word proposals (meaning is a base word, no repeated meanings; Sim_Records)
      Records : Boolean := False;       --  records=1: votes, petitions, dictionary and announcements as record files; a clean word vote (Sim_Records; needs govern=1)
      Visit : Boolean := False;         --  visit=1: Robert stands next to one wesen (vwho=<id>) and talks to it (Sim_Visit, diaries/visit.txt)
      Visit_Who : Natural := 0;
      Active : Boolean := False;        --  active=1: an active vocabulary per wesen, dormant words, wake on use (needs screen=1; Sim_Active, docs/EVOLVE.md 13)
      Active_Level : Natural := 1;      --  1 or 2 (active=2: floor and cap, mint-slow, wider wake; docs/EVOLVE.md 14), when Active
      Symbols : Boolean := False;       --  symbols=1: chess moves and their numeric strings are symbols, never minted as words (needs chess=1; docs/EVOLVE.md 9)
      Symstrict : Boolean := False;     --  symstrict=1 (with symbols=1): a COINED chess or number string (a blend 53+36 = 5336) is a symbol too
      Slowfloor : Boolean := False;     --  slowfloor=1 (with active=2): mint-slow already from the floor up, the same percents (docs/EVOLVE.md 14)
      Chat : Boolean := False;          --  chat=1: Robert types lines (@name text, /order) and the answers are recorded (Sim_Chat, diaries/chat.txt)
      Carry : Boolean := False;         --  carry=1 (0.061): word carrying among the wesen: target, teacher pull, relief, favours (Sim_Carry)
      Carry2 : Boolean := False;        --  carry=2 (0.062, with Carry): a lesson is an exchange of several words both ways
      Moodrest : Boolean := False;      --  moodrest=1 (0.062): resting moods, soft bounds (Mood_Rest_Step)
      Moodrest2 : Boolean := False;     --  moodrest=2 (0.063): the drift as a one-point step by a die (Mood_Rest_Step2)
      Alb : Boolean := False;           --  alb=1 (0.064): the Albanian book, hearing and saying at the session start (Sim_Albanian)
      Alb_G : String (1 .. 4) := "uuuu";   --  albg= (with Alb): the wesen genders of data/wesen_gender.txt when the session began (m f n u)
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
      & (if R.Symstrict then " symstrict=1" else "") & (if R.Slowfloor then " slowfloor=1" else "")   --  build 0.054, before screen=1: older checks anchor the end
      & (if R.Carry then (if R.Carry2 then " carry=2" else " carry=1") else "") & (if R.Moodrest then (if R.Moodrest2 then " moodrest=2" else " moodrest=1") else "")   --  0.061 / 0.062, before screen=1
      & (if R.Alb then " alb=1 albg=" & R.Alb_G else "")   --  0.064
      & (if R.Screen then " screen=1" else "") & (if R.Chess then " chess=1" else "") & (if R.Chessrules then " chessrules=2" else "")
      & (if R.Robot then " robot=1" else "") & (if R.Govern then " govern=1" else "") & (if R.Scoin then " scoin=1" else "")
      & (if R.Preport then " preport=1" else "") & (if R.Players4 then " players4=1" else "") & (if R.Nextticks then " nextticks=1" else "") & (if R.Trial then " trial=1" else "") & (if R.Rec2 and then R.Records then " records=2" elsif R.Records then " records=1" else "")
      & (if R.Visit then " visit=1 vwho=" & Name (Entity_Id (R.Visit_Who)) else "")
      & (if R.Symbols then " symbols=1" else "")
      & (if R.Active then " active=" & Img (R.Active_Level) else "")
      & (if R.Chat then " chat=1" else ""));
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
      R.Chessrules := R.Chess and then Token (L, "chessrules") = "2";
      R.Robot := Token (L, "robot") = "1";
      R.Govern := Token (L, "govern") = "1";
      R.Scoin := Token (L, "scoin") = "1";
      R.Preport := Token (L, "preport") = "1";
      R.Players4 := Token (L, "players4") = "1";
      R.Nextticks := Token (L, "nextticks") = "1";
      R.Trial := R.Chess and then R.Govern and then Token (L, "trial") = "1";
      R.Records := R.Govern and then (Token (L, "records") = "1" or else Token (L, "records") = "2");
      R.Rec2 := R.Records and then Token (L, "records") = "2";
      R.Visit := Token (L, "visit") = "1";
      R.Visit_Who := (if R.Visit then Sim_Dharma.Find_Wesen (Token (L, "vwho")) else 0);
      R.Symbols := R.Chess and then Token (L, "symbols") = "1";
      R.Active := R.Screen and then (Token (L, "active") = "1" or else Token (L, "active") = "2");
      R.Active_Level := (if Token (L, "active") = "2" then 2 else 1);
      R.Symstrict := R.Symbols and then Token (L, "symstrict") = "1";
      R.Slowfloor := R.Active and then R.Active_Level = 2 and then Token (L, "slowfloor") = "1";
      R.Chat := Token (L, "chat") = "1";
      R.Carry := Token (L, "carry") = "1" or else Token (L, "carry") = "2";
      R.Carry2 := Token (L, "carry") = "2";
      R.Moodrest := Token (L, "moodrest") = "1" or else Token (L, "moodrest") = "2";
      R.Moodrest2 := Token (L, "moodrest") = "2";
      R.Alb := Token (L, "alb") = "1";
      if R.Alb and then Token (L, "albg")'Length = 4 then R.Alb_G := Token (L, "albg"); end if;
      OK := To_Num (L (L'First + 1 .. Sp - 1)) > 0 and then R.Start >= 0 and then R.Len > 0
        and then Token (L, "src") in "vote" | "explicit" and then V'Length > 0 and then (R.Visit_Who > 0 or else not R.Visit);
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

   --  0.060: indices by tick of the stored session records.  The replay asked at EVERY tick which D / C / Y / L / R lines, W votes and
   --  S records belong to that tick, by scanning the whole history (Token + Img per stored line): O(history) per tick, so a replay and
   --  a live session got slower with every session (40 ticks/s on a 777000-tick save).  The lists keep the order of sessions.txt, so
   --  every check sees the same lines in the same order as the scans did.
   package Idx_Vectors is new Ada.Containers.Vectors (Positive, Positive);
   package Idx_By_Text is new Ada.Containers.Indefinite_Hashed_Maps (String, Idx_Vectors.Vector, Ada.Strings.Hash, "=", Idx_Vectors."=");
   package Idx_By_Tick is new Ada.Containers.Ordered_Maps (Int, Idx_Vectors.Vector, "<", Idx_Vectors."=");
   Dharma_By_Tick : Idx_By_Text.Map;   --  the text of the tick= token (as Token gives it) -> lines of Dharma_Stored
   Votes_By_Tick : Idx_By_Tick.Map;    --  W record tick -> Word_Votes
   Sessions_By_Start : Idx_By_Tick.Map;   --  S record start -> Sessions

   procedure Idx_Add (M : in out Idx_By_Tick.Map; Key : Int; I : Positive) is
      C : constant Idx_By_Tick.Cursor := M.Find (Key);
   begin
      if Idx_By_Tick.Has_Element (C) then
         M.Reference (C).Append (I);
      else
         M.Insert (Key, Idx_Vectors.To_Vector (I, 1));
      end if;
   end Idx_Add;

   procedure Dharma_Add (L : String) is
      K : constant String := Token (L, "tick");
      C : constant Idx_By_Text.Cursor := Dharma_By_Tick.Find (K);
   begin
      Dharma_Stored.Append (L);
      if Idx_By_Text.Has_Element (C) then
         Dharma_By_Tick.Reference (C).Append (Natural (Dharma_Stored.Length));
      else
         Dharma_By_Tick.Insert (K, Idx_Vectors.To_Vector (Natural (Dharma_Stored.Length), 1));
      end if;
   end Dharma_Add;

   procedure Session_Add (R : Session_Rec) is
   begin
      Sessions.Append (R);
      Idx_Add (Sessions_By_Start, R.Start, Natural (Sessions.Length));
   end Session_Add;

   procedure Vote_Add (R : Word_Vote) is
   begin
      Word_Votes.Append (R);
      Idx_Add (Votes_By_Tick, R.Tick, Natural (Word_Votes.Length));
   end Vote_Add;

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
      Dharma_By_Tick.Clear;
      Votes_By_Tick.Clear;
      Sessions_By_Start.Clear;
      World_Active := False;
      Rest_Active := False;
      Grant_Active := False;
      Screen_Active := False;
      Chess_Active := False;
      Robot_Active := False;
      Govern_Active := False;
      Scoin_Active := False;
      Preport_Active := False;
      Sim_Carry.Reset;
      Moodrest_Active := False;
      Moodrest_Level := 1;
      Preport_End := -1;
      Next_Active := False;
      Next_End := -1;
      Visit_Active := False;
      Chat_Active := False;
      Symbols_Active := False;
      Sim_World.Hide_Symbols (False);
      Trial_Active := False;
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
               Dharma_Add (L);
            elsif L'Length > 0 and then L (L'First) = 'W' then
               declare
                  V : Word_Vote;
               begin
                  Parse_Word_Vote (L, V, OK);
                  if OK then Vote_Add (V); else Warn (Msg ("warn.session_bad", Img (I))); end if;
               end;
            elsif L'Length > 0 and then L (L'First) = 'S' then
               Parse_Session (L, R, OK);
               if OK then Session_Add (R); else Warn (Msg ("warn.session_bad", Img (I))); end if;
            elsif L'Length > 0 and then L (L'First) /= '#' then
               Warn (Msg ("warn.session_bad", Img (I)));
            end if;
         end;
      end loop;
   end Load_Sessions;

   --  0.064 alb=1: the Albanian of a session (Sim_Albanian) and its lines of diaries/albanian.txt.  The file is a record written
   --  once per session (the first run that reaches the session writes it; a replay of an older session recomputes the state but
   --  leaves the file alone), never read by the simulation; scripts/alb_report.sh scores it for checkin.txt.
   Alb_Path : constant String := "diaries/albanian.txt";
   Alb_Disk_Last : Integer := -1;   --  the newest session of the file (-1: not read yet)
   procedure Alb_Session (R : Session_Rec) is
      Lines : Str_Vectors.Vector;
      F : TIO.File_Type;
   begin
      Sim_Albanian.Session (Seed, R.N, R.Start, R.Alb_G, Lines);
      if Preview or else Ledger_Mode then return; end if;
      if Alb_Disk_Last < 0 then
         declare
            Old : Str_Vectors.Vector;
            Found : Boolean;
         begin
            Alb_Disk_Last := 0;
            Read_Lines (Alb_Path, Old, Found);
            for L of Old loop
               if L'Length > 3 and then L (L'First + 1) = ' ' and then L (L'First + 2) = 'S' then
                  declare
                     Sp : constant Natural := Fx.Index (L (L'First + 3 .. L'Last), " ");
                     N : constant Int := To_Num (L (L'First + 3 .. (if Sp = 0 then L'Last else Sp - 1)));
                  begin
                     if N > Int (Alb_Disk_Last) then Alb_Disk_Last := Integer (N); end if;
                  end;
               end if;
            end loop;
         end;
      end if;
      if R.N <= Alb_Disk_Last then return; end if;
      if Ada.Directories.Exists (Alb_Path) then TIO.Open (F, TIO.Append_File, Alb_Path);
      else
         TIO.Create (F, TIO.Out_File, Alb_Path);
         TIO.Put_Line (F, "# diary-sim 0.064 alb=1: B = the book found, H = sentences heard (Tatoeba ids), U = a sentence said "
                       & "(noun article adjective; src=mem|end2|end1|def; held=1: a held-back noun), J = first person (g = gender)");
      end if;
      for L of Lines loop TIO.Put_Line (F, L); end loop;
      TIO.Close (F);
      Alb_Disk_Last := R.N;
   end Alb_Session;

   --  A liberated wesen of a new session moves to the location its own dice name (record + effect).
   procedure Start_Life (R : Session_Rec) is
   begin
      Cause_Net := [others => [others => 0]];   --  0.064 mood causes: a new session
      Cause_Refusals := [others => 0];
      Cause_Session := R.N;
      Sim_Ledger.Keep_From (R.Start);   --  0.058: the ledger keeps the ticks of the newest session (and the sums of all)
      Sim_Active.Open (R.N, R.Start, (if R.Active and then R.Screen then R.Active_Level else 0), R.Slowfloor);   --  closes the window of the previous active session (dormancies), opens this one
      Emit_Active_Lines;
      Sim_Dharma.Begin_Life (Seed, R.Start, R.N, L_Max + 1, R.Dharma, R.Players4);
      World_Active := R.World;
      if R.Rest and then not Rest_Active then Rest_Begin (Seed); end if;   --  the state runs on from session to session
      Rest_Active := R.Rest;
      Grant_Active := R.Grant;
      Screen_Active := R.Screen;
      Chess_Active := R.Chess;
      Sim_Carry.Begin_Session (R.Carry, (if R.Carry2 then 2 else 1));
      if R.Alb then Alb_Session (R); end if;   --  0.064 alb=1: hearing and saying at the session start
      Moodrest_Active := R.Moodrest;
      Moodrest_Level := (if R.Moodrest2 then 2 else 1);
      Sim_Games.Set_Rules (if R.Chessrules then 2 else 0);
      Robot_Active := R.Robot;
      Govern_Active := R.Govern;
      Scoin_Active := R.Scoin and then R.Screen;
      Sim_Screen.Begin_Session (Scoin_Active);   --  a new count of screen blends per wesen
      if R.Govern then Sim_Govern.Begin_Life (R.Start); end if;   --  the players take over the petitions with the first govern=1 session
      Sim_Records.Begin_Session (R.N, R.Start, R.Records and then R.Govern, R.Rec2 and then R.Records and then R.Govern);   --  also sets the clean word vote
      if Sim_Records.Active then
         Sim_Records.Length_Votes (R.Start, R.Votes);
         Flush_Records (R.Start >= Int (Common));
      end if;
      Preport_Active := R.Preport and then R.Govern;
      Preport_End := (if Preport_Active then R.Start + R.Len else -1);   --  the players report at the last tick of the session
      if Preport_Active then Sim_Preport.Begin_Session (R.Start, Pets_Now); end if;
      Next_Active := R.Nextticks and then R.Govern;
      Next_End := (if Next_Active then R.Start + R.Len else -1);   --  wesen and players give their advice at the last tick of the session
      if R.Robot then Sim_Robot.Begin_Life (R.Start); end if;   --  the robot comes into the world with its first session
      Trial_Active := R.Trial and then R.Chess and then R.Govern;
      if Trial_Active then Sim_Trial.Begin_Session; end if;
      Chat_Active := R.Chat;
      Symbols_Active := R.Symbols and then R.Chess;
      Sim_World.Hide_Symbols (Symbols_Active, R.Symstrict);   --  old chess strings are not learned, taught or blended any more (symstrict=1: coined ones too)
      Chat_Session_Count := Chat_Session_Count + 1;
      for E in Entity_Id loop Chat_Start_Mood (E) := St (E).Mood; end loop;
      Visit_Active := R.Visit;
      if R.Visit then
         Visit_E := Entity_Id (R.Visit_Who);
         Visit_Start := R.Start;
         Visit_End := R.Start + R.Len;
         Sim_Visit.Begin_Session (R.N, Visit_E);
      end if;
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
         Append (R, " " & Name (E) & "=" & Img (Rate_Now (E)) & "/" & Img (Cool_N (E)) & "/" & Img (Cut_N (E)) & "/" & Img (Quick_N (E)));
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

   --  govern=1: each player's report to Robert is built from the D records only (counter line first, then every change); the
   --  window is the time since the previous session end.  The wording follows the player's tone; nothing is left out.
   procedure Hand_Govern_Report (Tick : Int) is
   begin
      if not Govern_Active then return; end if;
      for P in Sim_Dharma.Player_Id loop
         Sim_Dharma.Set_Govern_Report (P, Sim_Govern.Report (P, Gov_Since, Sim_Dharma.Variant_Of (P)));
      end loop;
      Gov_Since := Tick;
   end Hand_Govern_Report;

   --  records=1: the end of a session at T: the favourite words, the votes on the collective petition, the vote of the players on the
   --  proposed words, their announcements; the standing an announcement cost is paid.  The same call in the replay and in a new session end.
   procedure Rec_End (T : Int; C_Line : String) is
      Now : constant Tok_Array := Words_Now (T);
      Favs, Concern : Str_Vectors.Vector;
      Trust : Sim_Records.Trust_Array;
   begin
      if not Sim_Records.Active then return; end if;
      for E in Entity_Id loop
         declare
            V : constant String := To_String (Now (E));
            Sl : constant Natural := Fx.Index (V, "/");
         begin
            Favs.Append (if Sl > 0 then V (V'First .. Sl - 1) else V);
            Trust (E) := Sim_Govern.Trust_Of (E);
         end;
      end loop;
      for P in Sim_Dharma.Player_Id loop Concern.Append (Sim_Govern.Top_Concern (P)); end loop;
      Sim_Records.Session_End (T, Favs, C_Line, Trust, Concern);
      for E in Entity_Id loop
         declare
            C : constant Natural := Sim_Records.Take_Cost (E);
         begin
            if C > 0 then Sim_Govern.Adjust (E, 0, -Integer (C)); end if;
         end;
      end loop;
      Flush_Records (T > Int (Common));
   end Rec_End;

   --  The stored D / C / Y lines of a session end must equal what the replay regenerates.
   procedure Check_Dharma_At (T : Int) is
      Stored : Str_Vectors.Vector;
      Votes : Kalpa_Votes := [others => 0];
      En : Sim_Dharma.Energies;
      N : Int := 0;
      C : constant Idx_By_Text.Cursor := Dharma_By_Tick.Find (Img (T));   --  0.060: the lines of this tick (was a scan of all of them)
   begin
      if not Idx_By_Text.Has_Element (C) then return; end if;
      for I of Dharma_By_Tick.Constant_Reference (C) loop
         declare
            L : constant String := Dharma_Stored (I);
         begin
            Stored.Append (L);
            if N = 0 then N := To_Num (L (L'First + 1 .. Fx.Index (L, " ") - 1)); end if;
         end;
      end loop;
      if Stored.Is_Empty or else N < 1 then return; end if;
      for R of Sessions loop if Int (R.N) = N then Votes := R.Votes; end if; end loop;
      for E in Entity_Id loop En (E) := St (E).Energy; end loop;
      Hand_Govern_Report (T);
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
         if Sim_Records.Active then
            declare
               C : Unbounded_String;
            begin
               for G of Gen loop
                  if G'Length > 1 and then G (G'First) = 'C' and then G (G'First + 1) in '0' .. '9' then C := To_Unbounded_String (G); end if;
               end loop;
               Rec_End (T, To_String (C));
            end;
         end if;
      end;
   end Check_Dharma_At;

   --  A stored session must reproduce its votes when the replay reaches its start tick.
   procedure Start_Sessions_At (T : Int) is   --  0.058: alone after a start from the checkpoint (the session end at T is in it)
      C : constant Idx_By_Tick.Cursor := Sessions_By_Start.Find (T);   --  0.060: the sessions of this start tick, in file order
   begin
      if not Idx_By_Tick.Has_Element (C) then return; end if;
      for I of Sessions_By_Start.Constant_Reference (C) loop
         declare
            R : constant Session_Rec := Sessions (I);
            V : constant Kalpa_Votes := Votes_At (T);
         begin
            if V /= R.Votes then
               raise Drift_Error with Msg ("err.session", Img (R.N), Img (R.Start), "votes " & Votes_Text (R.Votes),
                                           "votes " & Votes_Text (V));
            end if;
            Start_Life (R);
         end;
      end loop;
   end Start_Sessions_At;

   procedure Check_Sessions_At (T : Int) is
      C : constant Idx_By_Tick.Cursor := Votes_By_Tick.Find (T);   --  0.060: the W records of this tick (was two scans of all of them)
      Has_Vote : constant Boolean := Idx_By_Tick.Has_Element (C);
      Now_T : constant Tok_Array := (if Has_Vote then Words_Now (T) else [others => Null_Unbounded_String]);   --  before the session end's records, as a new session end does (active=1: a record line can wake a word)
   begin
      Check_Dharma_At (T);
      if Has_Vote then
         for I of Votes_By_Tick.Constant_Reference (C) loop
            declare
               R : constant Word_Vote := Word_Votes (I);
               Now : constant Tok_Array := Now_T;
            begin
               if Now /= R.Tok then
                  raise Drift_Error with Msg ("err.words", Img (R.N), Img (R.Tick), Tok_Text (R.Tok), Tok_Text (Now));
               end if;
            end;
         end loop;
      end if;
      Start_Sessions_At (T);
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
      Session_Add (R);
   end Append_Session;

   --  The end of a session: every wesen names a favourite word; the vote goes to sessions.txt.
   procedure Record_Word_Vote (Tick : Int) is
      R : Word_Vote;
      Votes : Kalpa_Votes := [others => 0];
      En : Sim_Dharma.Energies;
      Text, C_Text : Unbounded_String;
   begin
      R.N := Positive'Max (1, Session_N);
      R.Tick := Tick;
      R.Tok := Words_Now (Tick);
      Text := To_Unbounded_String ("W" & Img (R.N) & " tick=" & Img (Tick) & " " & Tok_Text (R.Tok));
      for S of Sessions loop if S.N = R.N then Votes := S.Votes; end if; end loop;
      for E in Entity_Id loop En (E) := St (E).Energy; end loop;
      Hand_Govern_Report (Tick);
      for L of Sim_Dharma.End_Life (Seed, Tick, R.N, Votes, En) loop
         Append (Text, ASCII.LF & L);
         if L'Length > 1 and then L (L'First) = 'C' and then L (L'First + 1) in '0' .. '9' then C_Text := To_Unbounded_String (L); end if;
      end loop;
      if World_Active then Append (Text, ASCII.LF & World_Line (R.N, Tick)); end if;
      if Rest_Active then Append (Text, ASCII.LF & Rest_Line (R.N, Tick)); end if;
      Append_Text (To_String (Text));   --  W, D x4, C, Y x3 (and L in a world session) in one write
      if not Preview and then not Ledger_Mode then   --  0.064: the mood causes of this session (report only)
         declare
            F : TIO.File_Type;
            L : Unbounded_String := To_Unbounded_String ("M S" & Img (R.N) & " t=" & Img (Tick) & (if Cause_Session /= R.N then " part=1" else ""));
         begin
            for E in Entity_Id loop
               Append (L, " " & Name (E) & "=");
               for K in Cause_Kind loop Append (L, Img (Cause_Net (E, K)) & ","); end loop;
               Append (L, Img (Cause_Refusals (E)) & "," & Img (St (E).Mood));
            end loop;
            if Ada.Directories.Exists ("moodcause.txt") then TIO.Open (F, TIO.Append_File, "moodcause.txt");
            else
               TIO.Create (F, TIO.Out_File, "moodcause.txt");
               TIO.Put_Line (F, "# diary-sim 0.064 mood causes (report only): M S<session> t=<end tick> <wesen>=<refusal>,<lesson>,<work>,"
                             & "<rest>,<talk>,<game>,<other>,<refusals>,<mood at the end>; net mood points of the session by cause");
            end if;
            TIO.Put_Line (F, To_String (L));
            TIO.Close (F);
         exception
            when others => if TIO.Is_Open (F) then TIO.Close (F); end if;
         end;
      end if;
      Vote_Add (R);
      Rec_End (Tick, To_String (C_Text));   --  records=1: favourites, collective vote, words voted, announcements
      Words_Text := To_Unbounded_String (Msg ("words.line", Img (R.N), Words_Short (R.Tok)));
   end Record_Word_Vote;

   --  New sessions carry world=1 unless data/limits.txt says world.enabled = 0 (or data/things.txt is missing).
   function World_Wanted return Boolean is (Limit ("world.enabled", 1) /= 0 and then Sim_Things.Loaded);
   function Rest_Wanted return Boolean is (World_Wanted and then Limit ("rest.enabled", 1) /= 0);   --  rest=1 needs the world
   function Grant_Wanted return Boolean is (Rest_Wanted and then Limit ("grant.enabled", 1) /= 0);   --  grant=1 needs rest=1
   function Chess_Wanted return Boolean is (World_Wanted and then Limit ("chess.enabled", 1) /= 0);   --  chess=1 needs the world
   function Chessrules_Wanted return Boolean is (Chess_Wanted and then Limit ("chessrules.enabled", 1) /= 0);   --  chessrules=2 needs chess=1
   function Screen_Wanted return Boolean is (World_Wanted and then Limit ("screen.enabled", 1) /= 0);   --  screen=1 needs the world
   function Robot_Wanted return Boolean is (Screen_Wanted and then Limit ("robot.enabled", 1) /= 0);     --  robot=1 needs the screens
   function Scoin_Wanted return Boolean is (Screen_Wanted and then Limit ("screen.coin_enabled", 1) /= 0);   --  scoin=1 needs the screens
   function Govern_Wanted return Boolean is (Rest_Wanted and then Limit ("govern.enabled", 1) /= 0);     --  govern=1 needs the rest model (the levers)
   function Players4_Wanted return Boolean is (Limit ("players4.enabled", 1) /= 0);   --  players4=1: the fourth player (data/players.txt player.4.*)
   function Trial_Wanted return Boolean is (Chess_Wanted and then Govern_Wanted and then Limit ("trial.enabled", 1) /= 0);   --  trial=1 needs chess=1 and govern=1
   function Records_Wanted return Boolean is (Govern_Wanted and then Limit ("records.enabled", 1) /= 0);
   function Rec2_Wanted return Boolean is (Records_Wanted and then Limit ("rec.quality", 1) /= 0);   --  records=2: quality rules for word proposals   --  records=1 needs the governance (the D records)
   function Nextticks_Wanted return Boolean is (Govern_Wanted and then Limit ("nextticks.enabled", 1) /= 0);   --  nextticks=1 needs the governance (the open petitions)
   function Symbols_Wanted return Boolean is (Chess_Wanted and then Limit ("symbols.enabled", 1) /= 0);   --  symbols=1 needs chess=1 (docs/EVOLVE.md 9)
   function Active_Wanted return Boolean is (Screen_Wanted and then Limit ("active.enabled", 2) /= 0);   --  active=1/2 needs screen=1 (the uses are read on the screens)
   function Active_Level_Wanted return Natural is (if Limit ("active.enabled", 2) >= 2 then 2 else 1);   --  active.enabled = 2: new sessions carry active=2
   function Symstrict_Wanted return Boolean is (Symbols_Wanted and then Limit ("symbols.strict", 1) /= 0);   --  symstrict=1: coined chess strings are symbols too
   function Slowfloor_Wanted return Boolean is   --  slowfloor=1: active=2 mint-slow from the floor up
     (Active_Wanted and then Active_Level_Wanted = 2 and then Limit ("active.slow_floor", 1) /= 0);
   function Chat_Wanted return Boolean is   --  new sessions carry chat=1 when a line can be typed (a terminal in the foreground, or --chat)
     (Sim_Chat.Enabled and then not Preview and then (Chat_Mode or else Sim_Quit.Lines_On));

   function Carry_Wanted return Boolean is (Limit ("carry.enabled", 2) /= 0);   --  carry=1 (0.061): word carrying in new sessions
   function Carry2_Wanted return Boolean is (Limit ("carry.enabled", 2) >= 2);  --  carry=2 (0.062): exchanges (carry.enabled = 1: carry=1)
   function Moodrest_Wanted return Boolean is (Limit ("moodrest.enabled", 2) /= 0);   --  moodrest=1 (0.062) or 2 (0.063)
   function Moodrest2_Wanted return Boolean is (Limit ("moodrest.enabled", 2) >= 2);   --  moodrest=2 (0.063)
   function Alb_Wanted return Boolean is (Limit ("albanian.enabled", 1) /= 0);   --  alb=1 (0.064): the Albanian book
   function Alb_G_Now return String is (if Alb_Wanted then Sim_Albanian.Genders_Now else "uuuu");   --  stamped into the session line

   function Preport_Wanted return Boolean is (Govern_Wanted and then Limit ("preport.enabled", 1) /= 0);   --  preport=1 needs the governance (the D records)

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
               Dharma => True, World => World_Wanted, Rest => Rest_Wanted, Grant => Grant_Wanted, Screen => Screen_Wanted, Chess => Chess_Wanted, Robot => Robot_Wanted, Govern => Govern_Wanted, Scoin => Scoin_Wanted, Records => Records_Wanted, Rec2 => Rec2_Wanted, Preport => Preport_Wanted, Players4 => Players4_Wanted, Nextticks => Nextticks_Wanted, Chessrules => Chessrules_Wanted, Trial => Trial_Wanted,
               Visit => Visit_Mode, Visit_Who => Visit_Who, Chat => Chat_Wanted, Symbols => Symbols_Wanted, Symstrict => Symstrict_Wanted, Active => Active_Wanted, Active_Level => Active_Level_Wanted, Slowfloor => Slowfloor_Wanted, Carry => Carry_Wanted, Carry2 => Carry2_Wanted, Moodrest => Moodrest_Wanted, Moodrest2 => Moodrest2_Wanted, Alb => Alb_Wanted, Alb_G => Alb_G_Now);
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
               World => World_Wanted, Rest => Rest_Wanted, Grant => Grant_Wanted, Screen => Screen_Wanted, Chess => Chess_Wanted, Robot => Robot_Wanted, Govern => Govern_Wanted, Scoin => Scoin_Wanted, Records => Records_Wanted, Rec2 => Rec2_Wanted, Preport => Preport_Wanted, Players4 => Players4_Wanted, Nextticks => Nextticks_Wanted, Chessrules => Chessrules_Wanted, Trial => Trial_Wanted,
               Visit => False, Visit_Who => 0, Chat => Chat_Wanted, Symbols => Symbols_Wanted, Symstrict => Symstrict_Wanted, Active => Active_Wanted, Active_Level => Active_Level_Wanted, Slowfloor => Slowfloor_Wanted, Carry => Carry_Wanted, Carry2 => Carry2_Wanted, Moodrest => Moodrest_Wanted, Moodrest2 => Moodrest2_Wanted, Alb => Alb_Wanted, Alb_G => Alb_G_Now);
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

   --  How many players does the save have (the inbox view does not replay): 4 once a session carries players4=1.
   function Players_In_Save return Sim_Dharma.Player_Id is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      if Ada.Directories.Exists (Sessions_Path) then
         Read_Lines (Sessions_Path, Lines, Found);
         for L of Lines loop
            if L'Length > 1 and then L (L'First) = 'S' and then Token (L, "players4") = "1" then return 4; end if;
         end loop;
      end if;
      return 3;
   end Players_In_Save;

   function Inbox_Page return String is
      V : constant Str_Vectors.Vector := Inbox_File_Lines;
      R : Unbounded_String;
   begin
      if V.Is_Empty then return Msg ("inbox.none") & ASCII.LF & Msg ("inbox.answer") & ASCII.LF; end if;
      Append (R, Msg ("inbox.page", Img (Integer (V.Length))) & ASCII.LF);
      for P in Sim_Dharma.Player_Id range 1 .. Players_In_Save loop Append (R, "  " & Msg ("inbox.players", Sim_Dharma.Player_Info (P)) & ASCII.LF); end loop;
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

   --  make veto / make approve DECISION=D<n>: one V line in diaries/vetoes.txt at the lowest common tick (like make grant).
   procedure Do_Veto is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Want : constant String := Fx.Trim (To_String (Veto_Opt), Ada.Strings.Both);
      Num : constant Int := (if Want'Length > 1 and then Ada.Characters.Handling.To_Upper (Want (Want'First)) = 'D' then To_Num_Safe (Want (Want'First + 1 .. Want'Last))
                             elsif Want'Length > 0 then To_Num_Safe (Want) else -1);
      Dline : Unbounded_String;
      Common_T : Natural := Natural'Last;
      Seed_D : Int := -1;
      N_V : Natural := 0;
      F : TIO.File_Type;
      Act : constant String := (if Veto_Approve then "approve" else "veto");
   begin
      if not Has_Diaries then raise Usage_Error with Msg ("say.nogame", To_String (Home_Path)); end if;
      if Num <= 0 then raise Usage_Error with Msg ("veto.nodecision", Want); end if;
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
      if Ada.Directories.Exists (Govern_Path) then
         Lines.Clear;
         Read_Lines (Govern_Path, Lines, Found);
         for L of Lines loop
            if L'Length > 1 and then L (L'First) = 'D' and then Fx.Index (L, " ") > 2 then
               if L (L'First .. Fx.Index (L, " ") - 1) = "D" & Img (Num) then Dline := To_Unbounded_String (L); end if;
               if Token (L, "of") = "D" & Img (Num) then raise Usage_Error with Msg ("veto.already", "D" & Img (Num)); end if;
            end if;
         end loop;
      end if;
      if Length (Dline) = 0 then raise Usage_Error with Msg ("veto.nodecision", "D" & Img (Num)); end if;
      declare
         K : constant String := Token (To_String (Dline), "kind");
         T : constant Int := To_Num_Safe (Token (To_String (Dline), "t"));
      begin
         if (not Veto_Approve and then K not in "grant" | "partial") or else (Veto_Approve and then K not in "grant" | "partial" | "refuse") then
            raise Usage_Error with Msg ("veto.cant", "D" & Img (Num), K);
         end if;
         if T < 0 or else T > Int (Common_T) then raise Usage_Error with Msg ("veto.nodecision", "D" & Img (Num)); end if;
      end;
      if Ada.Directories.Exists (Vetoes_Path) then
         Lines.Clear;
         Read_Lines (Vetoes_Path, Lines, Found);
         for L of Lines loop
            if L'Length > 1 and then L (L'First) = 'V' then
               N_V := N_V + 1;
               if Token (L, "decision") = "D" & Img (Num) then raise Usage_Error with Msg ("veto.already", "D" & Img (Num)); end if;
            end if;
         end loop;
         declare
            Needs_Lf : constant Boolean := not Ends_With_Lf (Vetoes_Path);
         begin
            TIO.Open (F, TIO.Append_File, Vetoes_Path);
            if Needs_Lf then TIO.New_Line (F); end if;
         end;
      else
         TIO.Create (F, TIO.Out_File, Vetoes_Path);
         TIO.Put_Line (F, "# seed " & Img (Seed));
         TIO.Put_Line (F, Msg ("vetoes.header"));
      end if;
      TIO.Put_Line (F, "V" & Img (N_V + 1) & " tick=" & Img (Common_T) & " decision=D" & Img (Num) & " act=" & Act & " by=" & By_Name (To_String (Say_By)));
      TIO.Flush (F);
      TIO.Close (F);
      Con.Put_Line (Msg ("veto.ok", "V" & Img (N_V + 1), Act, "D" & Img (Num), Sim_Govern.Describe (To_String (Dline)), Img (Common_T + 1)));
   exception
      when E : Usage_Error =>   --  nothing is written
         TIO.Put_Line (TIO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (2);
   end Do_Veto;

   --  make challenge PLAYER=<name>: one Q line in diaries/challenges.txt at the lowest common tick (like make veto).  Only a player with a
   --  misreport (flag=lie in diaries/preports.txt, up to that tick) that was not challenged yet can be challenged; the next run lowers
   --  the standing of that player with its wesen a little.
   procedure Do_Challenge is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Want : constant String := Internal_Id (Ada.Characters.Handling.To_Lower (Fx.Trim (To_String (Challenge_Opt), Ada.Strings.Both)));
      Pl : Natural := 0;
      Common_T : Natural := Natural'Last;
      Seed_D : Int := -1;
      N_Q, Done_Q : Natural := 0;
      Lie_T : Str_Vectors.Vector;
      F : TIO.File_Type;
   begin
      if not Has_Diaries then raise Usage_Error with Msg ("say.nogame", To_String (Home_Path)); end if;
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
      Pl := Sim_Dharma.Find_Player (Want);
      if Pl = 0 then raise Usage_Error with Msg ("challenge.noplayer", Want); end if;
      declare
         Pn : constant String := Sim_Dharma.Player_Name (Sim_Dharma.Player_Id (Pl));
      begin
         if Ada.Directories.Exists (Preport_Path) then
            Lines.Clear;
            Read_Lines (Preport_Path, Lines, Found);
            for L of Lines loop
               if L'Length > 1 and then L (L'First) = 'P' and then Token (L, "player") = Pn and then Token (L, "flag") = "lie"
                 and then To_Num_Safe (Token (L, "t")) in 0 .. Int (Common_T) and then not Lie_T.Contains (Token (L, "t"))
               then
                  Lie_T.Append (Token (L, "t"));   --  one misreport round per tick
               end if;
            end loop;
         end if;
         if Ada.Directories.Exists (Challenges_Path) then
            Lines.Clear;
            Read_Lines (Challenges_Path, Lines, Found);
            for L of Lines loop
               if L'Length > 1 and then L (L'First) = 'Q' then
                  N_Q := N_Q + 1;
                  if Token (L, "player") = Pn then Done_Q := Done_Q + 1; end if;
               end if;
            end loop;
         end if;
         if Natural (Lie_T.Length) <= Done_Q then raise Usage_Error with Msg ("challenge.nolie", Sim_World.Show (Pn)); end if;
         if Ada.Directories.Exists (Challenges_Path) then
            declare
               Needs_Lf : constant Boolean := not Ends_With_Lf (Challenges_Path);
            begin
               TIO.Open (F, TIO.Append_File, Challenges_Path);
               if Needs_Lf then TIO.New_Line (F); end if;
            end;
         else
            TIO.Create (F, TIO.Out_File, Challenges_Path);
            TIO.Put_Line (F, "# seed " & Img (Seed));
            TIO.Put_Line (F, Msg ("challenges.header"));
         end if;
         TIO.Put_Line (F, "Q" & Img (N_Q + 1) & " tick=" & Img (Common_T) & " player=" & Pn & " by=" & By_Name (To_String (Say_By)));
         TIO.Flush (F);
         TIO.Close (F);
         Con.Put_Line (Msg ("challenge.ok", "Q" & Img (N_Q + 1), Pn, Img (Limit ("preport.challenge_cost", 3)), Img (Common_T + 1)));
      end;
   exception
      when E : Usage_Error =>   --  nothing is written
         TIO.Put_Line (TIO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         Ada.Command_Line.Set_Exit_Status (2);
   end Do_Challenge;

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
      if Drift then   --  a DRIFT stop writes no report: its time stamped entry in run_log.txt says why
         declare
            Flat : String := Message;
         begin
            for C of Flat loop if C = ASCII.LF then C := '|'; end if; end loop;
            Append_Log ("DRIFT", "@@TRACE build=" & Build & " seed=" & Img (Seed) & " result=DRIFT" & ASCII.LF & "reason: " & Flat & ASCII.LF
                        & (if Built'Length > 0 then "build: " & To_String (Disk_Build) & " on disk, " & Build & " now" & ASCII.LF else "")
                        & "debug: " & Ada.Directories.Full_Name ("debug.txt") & ASCII.LF);
         end;
      end if;
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
      Sim_Robot.Init (Seed);
      Sim_Govern.Init (Seed);
      Sim_Preport.Init (Seed);
      Sim_Next.Init (Seed);
      Sim_Trial.Init (Seed);
   Sim_Records.Init (Seed);
      World_Active := World_Wanted;
      Rest_Active := Rest_Wanted;
      Grant_Active := Grant_Wanted;
      Screen_Active := Screen_Wanted;
      Chess_Active := Chess_Wanted;
      Symbols_Active := Symbols_Wanted;
      Sim_World.Hide_Symbols (Symbols_Active, Symstrict_Wanted);
      Robot_Active := Robot_Wanted;
      Govern_Active := Govern_Wanted;
      Scoin_Active := Scoin_Wanted;
      Sim_Screen.Begin_Session (Scoin_Active);
      Sim_Carry.Begin_Session (Carry_Wanted, (if Carry2_Wanted then 2 else 1));
      Moodrest_Active := Moodrest_Wanted;
      Moodrest_Level := (if Moodrest2_Wanted then 2 else 1);
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

   --  make night / --continuous: normal sessions back to back, ALL IN THIS PROCESS.  The history is replayed once (the first session's
   --  Phase 1); then every session is the same code as a hand-made `--more N` run: the world simply goes on from the tick where the
   --  previous session ended instead of being rebuilt, and the files are written exactly as a run started by hand would write them
   --  (own session record, own markers, the same bytes; scripts/checks.sh compares both).  The console of a session is held and kept
   --  in night_console.txt.  At the end (and every night.verify_every sessions) a child process replays the WHOLE history from the
   --  files (`diary_sim --verify`, make verify) and compares it with what is stored.
   --  Keys: q is looked at between ticks (a fraction of a second at every stage).  During the very first replay nothing new exists:
   --  q stops at once.  Later the session in progress finishes (it is short), everything is written, then the run stops.
   --  Ctrl-C, SIGTERM and SIGHUP (the terminal was closed) stop at the next tick; the files are consistent and a rerun resumes.
   function Elapsed_Text (D : Duration) return String is
      T : constant Natural := Natural (Duration'Max (0.0, D));
   begin
      return Img (T / 3600) & "h" & Fx.Tail (Img (T mod 3600 / 60), 2, '0') & "m";
   end Elapsed_Text;

   procedure Flush_Out is   --  a closed terminal (SIGHUP) or pipe must not turn into an error
   begin
      TIO.Flush;
   exception
      when others => null;
   end Flush_Out;

   function Since (T : Ada.Calendar.Time) return Duration is (Ada.Calendar."-" (Ada.Calendar.Clock, T));

   Night_Per : Int := 300;                      --  ticks of a session
   Night_Max_S : Int := 0;                      --  0: no limit
   Night_Max_Secs : Duration := 0.0;            --  0: no limit
   Night_T0 : Ada.Calendar.Time := Ada.Calendar.Clock;
   Night_Why : Unbounded_String;
   Night_Done, Night_First_S, Night_Last_S, Night_Last_Tick : Natural := 0;
   Night_Replay_Line : Unbounded_String;   --  the history replay has finished, the new sessions begin (shown in the box; plain: at once)
   Base_S, Base_T : Natural := 0;               --  the sessions and ticks the save had at the start
   Night_Phase : Natural := 0;                  --  0 replaying the history, 1 a session, 2 verifying, 3 between sessions
   Night_Verified : Natural := 0;               --  full replays by the child process
   Q_Said : Boolean := False;
   Night_Check_Skipped : Boolean := False;      --  0.057: the end check was left out (--end-check-ticks, a big save)
   Night_Verify_Cut : Boolean := False;         --  the check at the end was cut short by q (the reason stays the limit)
   Q_Dropped : Boolean := False;                --  a q came when the limit was already reached: dropped, the reason is the limit
   Size0, Size_Now : Int := 0;
   Sess_Total, Last_Dur : Duration := 0.0;      --  wall time of the finished sessions / of the last one
   S_Start, Last_Paint, Last_Poll, Last_Size : Ada.Calendar.Time := Night_T0;
   Loop_End : Ada.Calendar.Time := Night_T0;   --  0.057: when the tick loop of the session ended (trend.txt secs= loop= tps=; the rest is the end report)
   Last_Line : Unbounded_String;
   Recent : Str_Vectors.Vector;                 --  the status lines of the sessions (shown below the header on a terminal)

   function Hms (D : Duration) return String is
      T : constant Natural := Natural (Duration'Max (0.0, D));
   begin
      return Img (T / 3600) & "h" & Fx.Tail (Img (T mod 3600 / 60), 2, '0') & "m" & Fx.Tail (Img (T mod 60), 2, '0') & "s";
   end Hms;

   function Size_Text (B : Int) return String is
     (if B < 1024 then Img (B) & " B" elsif B < 1_048_576 then Img (B / 1024) & " KB"
      else Img (B / 1_048_576) & "." & Img (B * 10 / 1_048_576 mod 10) & " MB");

   function Left_Text return String is   --  time to the nearest limit, from the average session so far
      Best : Duration := 0.0;
      Have : Boolean := False;
   begin
      if Night_Max_Secs > 0.0 then Best := Night_Max_Secs - Since (Night_T0); Have := True; end if;
      if Night_Max_S > 0 and then Night_Done > 0 then
         declare
            L : constant Duration := (Sess_Total / Night_Done) * Natural'Max (0, Natural (Night_Max_S) - Night_Done);
         begin
            if not Have or else L < Best then Best := L; end if;
            Have := True;
         end;
      end if;
      return (if Have then Hms (Best) else "-");
   end Left_Text;

   function Ticks_Per_Sec return String is
     (if Sess_Total > 0.0 and then Night_Done > 0 then Img (Natural (Float (Night_Done) * Float (Night_Per) / Float (Sess_Total))) else "-");

   function Avg_Text return String is (if Night_Done > 0 then Tenths_Text (Sess_Total / Night_Done) & " s" else "-");

   function Growth_Text return String is
     ((if Size_Now >= Size0 then "+" else "-") & Size_Text (abs (Size_Now - Size0)));

   function Limits_Text return String is
     (Msg ("night.lim", (if Night_Max_Secs = 0.0 then Msg ("night.none") else Hms (Night_Max_Secs)),
           (if Night_Max_S = 0 then Msg ("night.none") else Img (Night_Max_S))));

   --  "Adam -3/80 Eve 12/60 ..." from the mood= and energy= lists of a trend line
   function Compact (L : String) return String is
      Mo : constant String := Token (L, "mood");
      En : constant String := Token (L, "energy");
      R : Unbounded_String;
      Pm : Natural := Mo'First;
      Pe : Natural := En'First;
      procedure Next (T : String; P : in out Natural; Item : out Unbounded_String) is
         Q : constant Natural := Fx.Index (T, ",", P);
      begin
         Item := To_Unbounded_String (T (P .. (if Q = 0 then T'Last else Q - 1)));
         P := (if Q = 0 then T'Last + 1 else Q + 1);
      end Next;
   begin
      for E in Entity_Id loop
         declare
            M, N : Unbounded_String;
         begin
            exit when Pm > Mo'Last or else Pe > En'Last;
            Next (Mo, Pm, M); Next (En, Pe, N);
            Append (R, (if E = Entity_Id'First then "" else " ") & Sim_World.Show (Name (E)) & " " & To_String (M) & "/" & To_String (N));
         end;
      end loop;
      return To_String (R);
   end Compact;

   function Last_Trend return String is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      Read_Lines ("trend.txt", Lines, Found);
      for I in reverse 1 .. Natural (Lines.Length) loop
         declare
            Ln : constant String := Lines (I);
         begin
            if Ln'Length > 0 and then Ln (Ln'First) = 'T' then return Ln; end if;
         end;
      end loop;
      return "";
   end Last_Trend;

   --  The n-th item of "a,b,c,d" ("-" when there is none)
   function Nth (List : String; N : Positive) return String is
      From : Natural := List'First;
      K : Natural := 1;
   begin
      for I in List'Range loop
         if List (I) = ',' then
            if K = N then return List (From .. I - 1); end if;
            K := K + 1;
            From := I + 1;
         end if;
      end loop;
      return (if K = N and then From <= List'Last then List (From .. List'Last) else "-");
   end Nth;

   --  The live columns of the header: four wesen (mood, energy, words, petitions), then four players (the wesen they watch, the mood
   --  of those, petitions granted / refused, stance).  Columns of 12, labels of 13: at most 62 columns.
   --  ---- the voices of the wesen (Sim_Voice, data/voices.txt): display only, a pure function of the replayed state ---------------------
   --  Nothing here writes to a diary or changes the simulation; voice_log.txt of the save folder is a log of what was shown (not verified).
   Voice_Cache, Voice_Logged : array (Entity_Id) of Unbounded_String;
   Voice_Idx : Integer := -1;                   --  the rotation step of the cache (a new one every voice.refresh_seconds)
   Voice_Log_N : Natural := 0;                  --  lines of voice_log.txt
   Voice_Log_Path : constant String := "voice_log.txt";

   procedure Voice_Log_Add (Line : String) is
      F : TIO.File_Type;
      Keep : constant Natural := Natural (Int'Max (10, Limit ("voice.log_keep", 500)));
   begin
      if Limit ("voice.log", 1) = 0 then return; end if;
      begin
         TIO.Open (F, TIO.Append_File, Voice_Log_Path);
      exception
         when TIO.Name_Error => TIO.Create (F, TIO.Out_File, Voice_Log_Path);
      end;
      TIO.Put_Line (F, Line);
      TIO.Close (F);
      Voice_Log_N := Voice_Log_N + 1;
      if Voice_Log_N > 2 * Keep then   --  keep the newest voice.log_keep lines
         declare
            Lines : Str_Vectors.Vector;
            Found : Boolean;
         begin
            Read_Lines (Voice_Log_Path, Lines, Found);
            TIO.Create (F, TIO.Out_File, Voice_Log_Path);
            for I in Natural'Max (1, Natural (Lines.Length) - Keep + 1) .. Natural (Lines.Length) loop TIO.Put_Line (F, Lines (I)); end loop;
            TIO.Close (F);
            Voice_Log_N := Natural'Min (Keep, Natural (Lines.Length));
         end;
      end if;
   exception
      when others => if TIO.Is_Open (F) then TIO.Close (F); end if;   --  a log that cannot be written never stops the run
   end Voice_Log_Add;

   --  A new rotation step every voice.refresh_seconds: the four messages are made again for the tick now (so a text stays for its step).
   procedure Voice_Refresh (Elapsed : Duration) is
      Step : constant Integer := Integer (Elapsed / Duration (Int'Max (1, Limit ("voice.refresh_seconds", 4))));
      Shown : constant Natural := Natural (Int'Max (1, Int'Min (4, Limit ("voice.shown", 2))));
   begin
      if Step = Voice_Idx or else Cur_Tick = 0 then return; end if;
      Voice_Idx := Step;
      for E in Entity_Id loop
         Voice_Cache (E) := To_Unbounded_String (Voice_Text (E, Cur_Tick, (if Night_Phase = 0 then 0 else St (E).Mood - Snap_Mood (E))));
      end loop;
      for J in 0 .. Shown - 1 loop
         declare
            E : constant Entity_Id := Entity_Id ((Voice_Idx + J) mod Integer (Entity_Id'Last) + 1);
         begin
            if Voice_Cache (E) /= Voice_Logged (E) then
               Voice_Logged (E) := Voice_Cache (E);
               Voice_Log_Add ("t=" & Img (Cur_Tick) & " " & To_String (Voice_Cache (E)));
            end if;
         end;
      end loop;
   end Voice_Refresh;

   --  The voices region of the header: Shown messages of Rows lines each (padded, so the header keeps its height).
   function Voice_Region (Shown, Rows : Natural) return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
   begin
      for J in 0 .. Shown - 1 loop
         declare
            V : Str_Vectors.Vector;
         begin
            if Voice_Idx >= 0 then
               V := Sim_Voice.Fit (To_String (Voice_Cache (Entity_Id ((Voice_Idx + J) mod Integer (Entity_Id'Last) + 1))), 77, Positive'Max (1, Rows));
            end if;
            for K in 1 .. Rows loop R.Append (" " & (if K <= Natural (V.Length) then V (K) else "")); end loop;
         end;
      end loop;
      return R;
   end Voice_Region;

   function Voices_Text return String is   --  --voices / make voices: the four messages at the last tick of the history
      R : Unbounded_String;
   begin
      for E in Entity_Id loop Append (R, Voice_Text (E, Last_Done, 0) & ASCII.LF); end loop;
      return To_String (R);
   end Voices_Text;

   function Night_Table return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
      Line : Unbounded_String;
      function Lab (Key : String) return String is (Fx.Head (Msg (Key), 13));
      function Cl (S : String) return String is (Fx.Head (S, 11) & " ");
      procedure Add is
      begin
         R.Append (Fx.Trim (To_String (Line), Ada.Strings.Right));
         Line := Null_Unbounded_String;
      end Add;
   begin
      Append (Line, Lab ("night.l.wesen"));
      for E in Entity_Id loop Append (Line, Cl (Sim_World.Show (Name (E)))); end loop;
      Add;
      Append (Line, Lab ("night.l.mood"));
      for E in Entity_Id loop Append (Line, Cl (Sgn (Int (St (E).Mood)))); end loop;
      Add;
      Append (Line, Lab ("night.l.energy"));
      for E in Entity_Id loop Append (Line, Cl (Img (St (E).Energy))); end loop;
      Add;
      Append (Line, Lab ("night.l.words"));
      for E in Entity_Id loop Append (Line, Cl (Img (Known_Count (E)))); end loop;
      Add;
      Append (Line, Lab ("night.l.pets"));
      for E in Entity_Id loop Append (Line, Cl (Img (Petitions_Of (E)))); end loop;
      Add;
      declare
         Rec : constant String := Sim_Records.Trend;
         G : constant String := Token (Rec, "grant");
         Rf : constant String := Token (Rec, "refuse");
         Last : constant Natural := Natural (Sim_Dharma.Last_Player);
      begin
         Append (Line, Lab ("night.l.player"));
         for P in 1 .. 4 loop Append (Line, Cl (if P <= Last then Sim_World.Show (Sim_Dharma.Player_Name (Sim_Dharma.Player_Id (P))) else "-")); end loop;
         Add;
         Append (Line, Lab ("night.l.watches"));
         for P in 1 .. 4 loop
            declare
               W : Unbounded_String;
            begin
               if P <= Last then
                  for E in Entity_Id loop
                     if Natural (Sim_Dharma.Watcher (E)) = P then
                        Append (W, (if Length (W) > 0 then "+" else "") & Sim_World.Show (Name (E)));
                     end if;
                  end loop;
               end if;
               Append (Line, Cl (if Length (W) > 0 then To_String (W) else "-"));
            end;
         end loop;
         Add;
         Append (Line, Lab ("night.l.pmood"));
         for P in 1 .. 4 loop
            declare
               W : Unbounded_String;
            begin
               if P <= Last then
                  for E in Entity_Id loop
                     if Natural (Sim_Dharma.Watcher (E)) = P then
                        Append (W, (if Length (W) > 0 then "/" else "") & Img (St (E).Mood));
                     end if;
                  end loop;
               end if;
               Append (Line, Cl (if Length (W) > 0 then To_String (W) else "-"));
            end;
         end loop;
         Add;
         Append (Line, Lab ("night.l.votes"));
         for P in 1 .. 4 loop Append (Line, Cl (if P <= Last then Nth (G, P) & "/" & Nth (Rf, P) else "-")); end loop;
         Add;
         Append (Line, Lab ("night.l.stance"));
         for P in 1 .. 4 loop
            Append (Line, Cl (if P <= Last then Sgn (Int (Sim_Dharma.Warm_Of (Sim_Dharma.Player_Id (P)))) else "-"));
         end loop;
         Add;
      end;
      return R;
   exception
      when others => return R;   --  a state that is not complete yet: show what there is
   end Night_Table;

   --  The last Rows lines of the chat window (each entry wrapped to the screen width), padded to Rows lines.
   function Chat_Region (Rows : Natural) return Str_Vectors.Vector is
      All_Lines, R : Str_Vectors.Vector;
   begin
      for T of Chat_Shown loop
         declare
            V : constant Str_Vectors.Vector := Sim_Voice.Wrap (T, 74);
         begin
            for K in 1 .. Natural (V.Length) loop All_Lines.Append ((if K = 1 then " " else "   ") & V.Element (K)); end loop;
         end;
      end loop;
      for I in Natural'Max (1, Natural (All_Lines.Length) - Rows + 1) .. Natural (All_Lines.Length) loop R.Append (All_Lines (I)); end loop;
      while Natural (R.Length) < Rows loop R.Prepend (""); end loop;
      return R;
   end Chat_Region;

   --  The run ends at its limit after this session anyway (or it has ended and the check at the end runs): a q then changes nothing,
   --  the reason stays max_sessions / max_hours (a stray q byte of the terminal must not turn a full night into "you pressed q").
   function Limit_Ending return Boolean is
     (Night_Phase /= 0 and then not Chat_Mode   --  --chat: q stops the session at the next tick, it is never "the last session anyway"
      and then ((Night_Max_S > 0 and then Int (Night_Done) + (if Night_Phase = 1 then 1 else 0) >= Night_Max_S)
                or else (Night_Max_Secs > 0.0 and then Since (Night_T0) >= Night_Max_Secs)));

   function Q_Text return String is
     (Msg (if Night_Phase = 0 then "night.q.replay"
           elsif Limit_Ending then (if Night_Phase = 2 then "night.q.limit_verify" else "night.q.limit")
           elsif Chat_Mode then "night.q.chat" else "night.q"));

   --  One piece, written with one call: home, the lines (each cleared to its end), clear below.
   procedure Paint is
      R : Unbounded_String;
      Folder : constant String := To_String (Home_Path);
      procedure L (T : String) is begin Append (R, T & ASCII.ESC & "[K" & ASCII.LF); end L;
      Tab : constant Str_Vectors.Vector := Night_Table;
      Now_Text : constant String :=
        (case Night_Phase is
            when 0 => (if Verify_To = 0 and then Cur_Tick = 0 then Msg ("night.t.load", Img (Base_S + Night_Done + 1))
                       else Msg ("night.t.replay", Img (Base_S + Night_Done + 1), Img (Cur_Tick), Img (Verify_To),
                                 Img (Natural (Cur_Tick) * 100 / Natural'Max (1, Verify_To)))),
            when 1 => Msg ("night.t.run", Img (Base_S + Night_Done + 1), Img (Cur_Tick), Img (Ticks)),
            when 2 => Msg ("night.t.verify"),
            when others => Msg ("night.t.idle"));
   begin
      Append (R, ASCII.ESC & "[H");
      L (Msg ("night.t.1", Local_Stamp, Hms (Since (Night_T0)), To_String (Run_Label)));
      L (Msg ("night.t.2", Limits_Text, Left_Text));
      L (Msg ("night.t.3", Size_Text (Size_Now), Growth_Text));
      L (Msg ("night.t.path", Fx.Tail (Folder, Natural'Min (Folder'Length, 76))));
      L (Msg ("night.t.4", Now_Text));
      L (Msg ("night.t.5", Img (Night_Done), (if Night_Done > 0 then Tenths_Text (Last_Dur) & " s" else "-"), Avg_Text, Ticks_Per_Sec));
      for T of Tab loop L (" " & T); end loop;
      L (if Sim_Quit.Key_Q then Q_Text
         elsif Chat_Paused then Msg ("chat.hint.paused", Img (Last_Done))
         elsif Sim_Quit.Lines_On then Msg ("chat.hint")
         else Msg (if Sim_Quit.Watching then "night.keys" else "night.nokeys"));
      if Voice_On then
         for T of Voice_Region (Natural (Int'Max (1, Int'Min (4, Limit ((if Sim_Quit.Lines_On then "voice.shown_chat" else "voice.shown"), (if Sim_Quit.Lines_On then 1 else 2))))), 2) loop L (T); end loop;
      end if;
      for I in Natural'Max (1, Natural (Recent.Length) - Natural (Int'Max (0, Limit ((if Sim_Quit.Lines_On then "chat.recent" else "night.recent"), (if Sim_Quit.Lines_On then 1 else 2)))) + 1) .. Natural (Recent.Length) loop
         L (Recent (I));
      end loop;
      if Sim_Quit.Lines_On then
         for T of Chat_Region (Natural (Int'Max (1, Limit ("chat.rows", 3)))) loop L (T); end loop;
      end if;
      if Sim_Quit.Lines_On then   --  the input line is the last row but one; the cursor goes back up behind the typed text
         declare
            Typed : constant String := Msg ("chat.prompt") & Fx.Tail (Sim_Quit.Typing, 70);
         begin
            Append (R, Typed & ASCII.ESC & "[K" & ASCII.LF & ASCII.ESC & "[J" & ASCII.ESC & "[A" & ASCII.ESC & "[" & Img (Natural (Typed'Length + 1)) & "G");
         end;
      else
         Append (R, ASCII.ESC & "[J");
      end if;
      Con.Put_Now (To_String (R));
      Flush_Out;
   end Paint;

   --  Called every few ticks (both tick loops, the wait for the verify child): reads the keys, says at once that q was understood, and
   --  repaints the header about once a second.
   Typed_Seen, Chat_Seen : Natural := 0;        --  Sim_Quit.Changed / Chat_Version when the screen was drawn last
   Pace_At : Ada.Calendar.Time := Ada.Calendar.Clock;   --  --chat: when the next tick may run

   procedure Night_Tick is
      Now : Ada.Calendar.Time := Ada.Calendar.Clock;

      --  Draw again at once when the typed line or the chat window changed, else about once a second.
      procedure Refresh is
      begin
         Now := Ada.Calendar.Clock;
         if Voice_On then Voice_Refresh (Now - Night_T0); end if;
         if Tty_Out and then (Sim_Quit.Changed /= Typed_Seen or else Chat_Version /= Chat_Seen) then
            Typed_Seen := Sim_Quit.Changed;
            Chat_Seen := Chat_Version;
            Last_Paint := Now;
            Paint;
         elsif Tty_Out and then Now - Last_Paint >= 1.0 then
            Last_Paint := Now;
            if Now - Last_Size >= 3.0 then Last_Size := Now; Size_Now := Folder_Bytes ("."); end if;
            Paint;
         end if;
      end Refresh;

      --  A line typed while no chat session is running (an old session without chat=1): answered on the screen only, not recorded.
      procedure No_Session is
      begin
         while Sim_Quit.Pending and then Night_Phase = 1 and then not Chat_Active loop
            declare
               Dropped : constant String := Sim_Quit.Take;
               pragma Unreferenced (Dropped);
            begin
               Chat_Show (Msg ("chat.id.system"), Msg ("chat.nosession"));
            end;
         end loop;
      end No_Session;
   begin
      if not Night_On then return; end if;
      if Now - Last_Poll >= 0.05 then
         Last_Poll := Now;
         Sim_Quit.Poll;
      end if;
      No_Session;
      if (Sim_Quit.Key_Q or else Sim_Quit.Requested) and then not Q_Said then
         Q_Said := True;
         if Tty_Out then Paint; else Con.Put_Line_Now (if Sim_Quit.Key_Q then Q_Text else Msg ((if Night_Phase = 0 then "night.q.replay" elsif Chat_Mode then "night.q.chat" else "night.q"))); Flush_Out; end if;
      end if;
      Refresh;
      if Chat_Paused then   --  /pause: the ticks wait; the screen, the keys and the lines go on
         while Chat_Paused and then not Sim_Quit.Key_Q and then not Sim_Quit.Requested loop
            Sim_Quit.Poll;
            No_Session;
            if Chat_Active and then Last_Done > Int (Common) and then Sim_Quit.Pending then Chat_Live_Lines (Last_Done); end if;
            Refresh;
            delay 0.05;
         end loop;
         Chat_Paused := False;
         Pace_At := Ada.Calendar.Clock;
      end if;
      if Chat_Mode and then Night_Phase = 1 and then Tty_Out and then Last_Done > Int (Common) and then Length (Chat_Script_Opt) = 0 then   --  paced: chat.tps ticks a second
         Pace_At := Ada.Calendar."+" (Pace_At, 1.0 / Duration (Int'Max (1, Limit ("chat.tps", 20))));
         if Ada.Calendar.Clock - Pace_At > 1.0 then Pace_At := Ada.Calendar.Clock; end if;
         while Ada.Calendar.Clock < Pace_At and then not Sim_Quit.Key_Q and then not Sim_Quit.Requested loop
            delay Duration'Min (0.05, Pace_At - Ada.Calendar.Clock);
            Sim_Quit.Poll;
            Refresh;
         end loop;
      end if;
   end Night_Tick;

   procedure Night_Begin is
   begin
      Night_On := True;
      Night_Per := Int'Max (1, (if Night_Ticks >= 0 then Night_Ticks elsif Chat_Mode then Limit ("chat.session_ticks", 600) else Limit ("night.session_ticks", 300)));
      Night_Max_S := (if Night_Sessions >= 0 then Night_Sessions else Limit ("night.max_sessions", 0));
      Night_Max_Secs :=
        (if Length (Night_Hours) > 0 then Duration'Value (To_String (Night_Hours)) * 3600 else Duration (Limit ("night.max_hours", 12)) * 3600);
      Night_T0 := Ada.Calendar.Clock;
      S_Start := Night_T0; Last_Paint := Night_T0; Last_Poll := Night_T0; Last_Size := Night_T0;
      Tty_Out := Is_Tty (1);
      Size0 := Folder_Bytes (".");
      Size_Now := Size0;
      Save_Counts (Base_S, Base_T);
      declare
         L0 : constant String := Last_Trend;
      begin
         if L0 /= "" then Last_Line := To_Unbounded_String (Compact (L0)); end if;
      end;
      Sim_Quit.Watch_Keys (True);
      Voice_On := Limit ("voice.enabled", 1) /= 0;
      if Tty_Out and then Sim_Chat.Enabled then Sim_Quit.Set_Lines (True, Positive (Int'Max (20, Limit ("chat.max_input", 120)))); end if;   --  the input line (B2)
      if Voice_On and then Ada.Directories.Exists (Voice_Log_Path) then
         declare
            Lines : Str_Vectors.Vector;
            Found : Boolean;
         begin
            Read_Lines (Voice_Log_Path, Lines, Found);
            Voice_Log_N := Natural (Lines.Length);
         end;
      end if;
      if Tty_Out then
         Con.Put_Now (ASCII.ESC & "[2J");
         Paint;
      else
         Con.Put_Line_Now (Msg ("night.start", Img (Night_Per), (if Night_Max_S = 0 then Msg ("night.none") else Img (Night_Max_S)),
                                (if Night_Max_Secs = 0.0 then Msg ("night.none")
                                 else To_String (if Length (Night_Hours) > 0 then Night_Hours else To_Unbounded_String (Img (Limit ("night.max_hours", 12))))),
                                To_String (Run_Label)));
         Con.Put_Line_Now (Msg (if Sim_Quit.Watching then "night.keys" else "night.nokeys"));
      end if;
      Flush_Out;
      Append_Log ("NIGHT", "start: session_ticks=" & Img (Night_Per) & " max_sessions=" & Img (Night_Max_S) & " keys="
                  & (if Sim_Quit.Watching then "q" else "none") & ASCII.LF);
      Con.Hold (True);
   end Night_Begin;

   --  The held console of the session goes to night_console.txt (the last one stays for the box and for DRIFT texts).
   procedure Night_Keep_Console is
      F : TIO.File_Type;
   begin
      TIO.Create (F, TIO.Out_File, "night_console.txt");
      TIO.Put (F, Con.Held);
      TIO.Close (F);
      Con.Clear_Held;
   exception
      when others => Con.Clear_Held;
   end Night_Keep_Console;

   --  The console is visible again (an error text, the final box); the last lines of what the session said are shown first.
   procedure Night_Release (Tail : Boolean) is
      T : constant String := Con.Held;
      Cut : Natural := T'First;
      Seen : Natural := 0;
   begin
      Sim_Quit.Set_Lines (False);   --  the terminal as it was
      Con.Hold (False);
      if Tail and then T'Length > 0 then
         for I in reverse T'First .. T'Last - 1 loop
            if T (I) = ASCII.LF then
               Seen := Seen + 1;
               if Seen = 6 then Cut := I + 1; exit; end if;
            end if;
         end loop;
         Con.Put_Now (T (Cut .. T'Last));
      end if;
      Night_Keep_Console;
   end Night_Release;

   --  The whole history from the files in a child process: `diary_sim --verify`.  True: it passed (or was cut short by q / a signal).
   function Night_Verify return Boolean is
      Args : GNAT.OS_Lib.Argument_List (1 .. 8);
      Pid : GNAT.OS_Lib.Process_Id;
      OK : Boolean;
      RC : Integer := -1;
   begin
      Night_Phase := 2;
      Last_Paint := Ada.Calendar.Time_Of (1970, 1, 1);
      if Ada.Directories.Exists ("night_rc.txt") then Ada.Directories.Delete_File ("night_rc.txt"); end if;
      Args (1) := new String'("-c");
      Args (2) := new String'("""$0"" ""$@"" > night_verify.txt 2>&1; echo $? > night_rc.tmp; mv night_rc.tmp night_rc.txt");
      Args (3) := new String'(Self_Exe);
      Args (4) := new String'("--verify-full");   --  0.060: the end check replays the whole history (make verify is incremental)
      Args (5) := new String'("--home");
      Args (6) := new String'(To_String (Home_Path));
      Args (7) := new String'("--sim-print");
      Args (8) := new String'(if Length (Sim_Print_Opt) > 0 then To_String (Sim_Print_Opt) else "-");
      if not Tty_Out then Con.Put_Line_Now (Msg ("night.t.verify")); end if;
      Pid := GNAT.OS_Lib.Non_Blocking_Spawn ("/bin/sh", Args);
      if GNAT.OS_Lib.Pid_To_Integer (Pid) <= 0 then return False; end if;
      while not Ada.Directories.Exists ("night_rc.txt") loop
         Night_Tick;
         if Sim_Quit.Key_Q or else Sim_Quit.Requested then   --  q / Ctrl-C while the check runs: stop it (it is read-only), the run ends
            declare   --  the program of the check and its shell (pkill is part of every Linux; if it is missing the check just runs to its end)
               Ok_K : Boolean;
               Kill_Args : GNAT.OS_Lib.Argument_List (1 .. 2);
               Pat : String := "--verify --home " & To_String (Home_Path);
            begin
               for C of Pat loop
                  if C not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '/' | '_' | '-' | ' ' then C := '.'; end if;
               end loop;
               Kill_Args (1) := new String'("-c");
               Kill_Args (2) := new String'("pkill -9 -f '" & Pat & "' 2>/dev/null");
               GNAT.OS_Lib.Spawn ("/bin/sh", Kill_Args, Ok_K);
            end;
            GNAT.OS_Lib.Kill (Pid, Hard_Kill => True);
            GNAT.OS_Lib.Wait_Process (Pid, OK);
            Append_Log ("NIGHT", "verify: cut short" & ASCII.LF);
            Night_Verify_Cut := Sim_Quit.Key_Q;
            return True;
         end if;
         delay 0.2;
      end loop;
      declare
         Rc_Lines : Str_Vectors.Vector;
         Found : Boolean;
      begin
         Read_Lines ("night_rc.txt", Rc_Lines, Found);
         RC := (if Found and then not Rc_Lines.Is_Empty then Integer'Value (Fx.Trim (Rc_Lines.First_Element, Ada.Strings.Both)) else -1);
         GNAT.OS_Lib.Wait_Process (Pid, OK);
         Ada.Directories.Delete_File ("night_rc.txt");
      exception
         when others => RC := -1;
      end;
      if RC = 0 and then Ada.Directories.Exists ("night_verify.txt") then Ada.Directories.Delete_File ("night_verify.txt"); end if;
      Night_Verified := Night_Verified + 1;
      Append_Log ("NIGHT", "verify: " & (if RC = 0 then "ok" else "FAILED rc=" & Img (RC)) & " ticks=" & Img (Common) & ASCII.LF);
      if RC /= 0 then
         declare
            Cons : Str_Vectors.Vector;
            Found : Boolean;
         begin
            Read_Lines ("night_verify.txt", Cons, Found);
            for I in Natural'Max (1, Natural (Cons.Length) - 5) .. Natural (Cons.Length) loop Con.Put_Line_Now (Cons (I)); end loop;
         end;
      end if;
      Night_Phase := 3;
      return RC = 0;
   end Night_Verify;

   --  The final box, the log entry, the exit status.  Why: q, signal, max_sessions, max_hours, drift, error.
   procedure Night_End (Why : String) is
      Box : Str_Vectors.Vector;
      Wide : Natural := 0;
   begin
      if not Night_On then return; end if;
      Night_On := False;
      Sim_Quit.Set_Lines (False);
      Con.Hold (False);
      Night_Phase := 3;
      Size_Now := Folder_Bytes (".");
      if Tty_Out then Paint; end if;
      Append_Log ("NIGHT", "stop: reason=" & Why & " sessions=" & Img (Night_Done) & " last_session=" & Img (Night_Last_S) & " tick=" & Img (Night_Last_Tick)
                  & " elapsed=" & Elapsed_Text (Since (Night_T0)) & ASCII.LF);
      Box.Append (Msg ("night.box.why", Msg ("night.why." & Why)));
      if Night_Done = 0 then
         Box.Append (Msg ("night.box.nosession", Img (Last_Done)));
      else
         Box.Append (Msg ("night.box.sessions", Img (Night_Done), Img (Night_First_S), Img (Night_Last_S), Img (Night_Last_Tick)));
      end if;
      Box.Append (if Length (Night_Replay_Line) > 0 then To_String (Night_Replay_Line) else Msg ("night.box.replay_no"));
      if Length (Ckpt_Start_Line) > 0 then Box.Append (To_String (Ckpt_Start_Line)); end if;   --  0.058: checkpoint or replay, the start time
      if Length (Data_Note) > 0 then Box.Append (To_String (Data_Note)); end if;   --  0.059: the rule files differ from the checkpoint's
      Box.Append (Msg ("night.box.time", Elapsed_Text (Since (Night_T0))));
      Box.Append (Msg ("night.box.speed", Avg_Text, Ticks_Per_Sec, Size_Text (Size_Now), Growth_Text));
      if Night_Verified > 0 then Box.Append (Msg ("night.box.verified", Img (Night_Verified))); end if;
      if Night_Verify_Cut and then Why in "max_sessions" | "max_hours" then Box.Append (Msg ("night.box.verify_cut")); end if;
      if Night_Check_Skipped then Box.Append (Msg ("night.box.check_skipped", Img (Last_Done), Img (End_Check_Max))); end if;
      if Q_Dropped and then Why in "max_sessions" | "max_hours" then Box.Append (Msg ("night.box.q_dropped")); end if;
      if Length (Last_Line) > 0 then Box.Append (Msg ("night.box.last", To_String (Last_Line))); end if;
      Box.Append (Msg ("night.box.files"));
      for L of Box loop Wide := Natural'Max (Wide, L'Length); end loop;
      Con.Put_Line ("+-- " & Msg ("night.box.title", To_String (Run_Label)) & " "
                    & Fx."*" (Natural'Max (0, Wide - Msg ("night.box.title", To_String (Run_Label))'Length - 2), '-') & "+");
      for L of Box loop Con.Put_Line ("| " & Fx.Head (L, Wide) & " |"); end loop;
      Con.Put_Line ("+" & Fx."*" (Wide + 2, '-') & "+");
      declare   --  the same box at the end of night_console.txt (make ship copies it into checkin.txt: the night ran on the terminal)
         F : TIO.File_Type;
      begin
         if Ada.Directories.Exists ("night_console.txt") then TIO.Open (F, TIO.Append_File, "night_console.txt");
         else TIO.Create (F, TIO.Out_File, "night_console.txt");
         end if;
         TIO.Put_Line (F, "== night box == reason=" & Why);
         for L of Box loop TIO.Put_Line (F, L); end loop;
         TIO.Close (F);
      exception
         when others => if TIO.Is_Open (F) then TIO.Close (F); end if;
      end;
      Con.Put_Line (To_String (Saved_Line));
      Flush_Out;
      if Why = "signal" then Ada.Command_Line.Set_Exit_Status (130);
      elsif Why in "drift" | "error" then Ada.Command_Line.Set_Exit_Status (1);
      end if;
   end Night_End;

   --  After a session (its report is on the held console): the status line, the limits, the check of the whole history.  True: stop now.
   function Night_After_Session return Boolean is
      Every_N : constant Int := Limit ("night.verify_every", 0);
      End_Check : constant Boolean := Limit ("night.verify_end", 1) /= 0 and then not Chat_Mode;   --  --chat: one short session, no full check at its end
      Verified_Now : Boolean := False;
      Ok : Boolean := True;
      function Limit_Reached return Boolean is
        ((Night_Max_S > 0 and then Int (Night_Done) >= Night_Max_S) or else (Night_Max_Secs > 0.0 and then Since (Night_T0) >= Night_Max_Secs));
   begin
      Night_Done := Night_Done + 1;
      Last_Dur := Since (S_Start);
      Sess_Total := Sess_Total + Last_Dur;
      Night_Keep_Console;
      declare
         L : constant String := Last_Trend;
         Now : constant String := Local_Stamp;
      begin
         if L /= "" then
            if Night_First_S = 0 then Night_First_S := Natural'Value (Token (L, "session")); end if;
            Night_Last_S := Natural'Value (Token (L, "session"));
            Night_Last_Tick := Natural'Value (Token (L, "tick"));
            Last_Line := To_Unbounded_String (Compact (L));
            Recent.Append (Msg ("night.status", Token (L, "session"), Token (L, "tick"), Now (12 .. 19), Compact (L)));
         else
            Recent.Append (Msg ("night.nostatus", Img (Night_Done)));
         end if;
      end;
      Night_Phase := 3;
      Size_Now := Folder_Bytes (".");
      Sim_Quit.Poll;
      if Tty_Out then
         Paint;
      else   --  plain lines: the status line and, below it, the timer figures
         Con.Put_Line_Now (Recent.Last_Element);
         Con.Put_Line_Now (Msg ("night.plain", Hms (Since (Night_T0)), Size_Text (Size_Now), Growth_Text, Avg_Text, Ticks_Per_Sec, Left_Text));
         Flush_Out;
      end if;
      if Sim_Quit.Key_Q and then Limit_Reached then   --  a q in the last session (or a stray q byte of the terminal): the limit ends the run anyway
         Sim_Quit.Forget_Q;   --  dropped before the check at the end: a q pressed during that check still cuts it short
         Q_Said := False;
         Q_Dropped := True;
         Append_Log ("NIGHT", "q: came in the last session, dropped (the limit ends the run)" & ASCII.LF);
      end if;
      if Every_N > 0 and then Int (Night_Done) mod Every_N = 0 and then not Sim_Quit.Key_Q and then not Sim_Quit.Requested then
         Ok := Night_Verify;
         Verified_Now := True;
      end if;
      --  The order: drift, a signal, the limit (sessions, then hours), q.  The limit first: a full night is a full night even when a q
      --  (or a stray q byte, e.g. of an escape sequence) came in its last session; a q in any earlier session still stops with why=q.
      if not Ok then Night_Why := To_Unbounded_String ("drift");
      elsif Sim_Quit.Requested then Night_Why := To_Unbounded_String ("signal");
      elsif Night_Max_S > 0 and then Int (Night_Done) >= Night_Max_S then Night_Why := To_Unbounded_String ("max_sessions");
      elsif Night_Max_Secs > 0.0 and then Since (Night_T0) >= Night_Max_Secs then Night_Why := To_Unbounded_String ("max_hours");
      elsif Sim_Quit.Key_Q then Night_Why := To_Unbounded_String ("q");
      end if;
      if Length (Night_Why) = 0 then
         S_Start := Ada.Calendar.Clock;
         return False;
      end if;
      if Ok and then End_Check and then not Verified_Now and then To_String (Night_Why) in "max_sessions" | "max_hours"
        and then End_Check_Max >= 0 and then Last_Done > End_Check_Max
      then   --  make night-ship: a full replay of a big save takes many minutes after the night; make verify does it by hand
         Append_Log ("NIGHT", "verify: skipped ticks=" & Img (Last_Done) & " cap=" & Img (End_Check_Max) & ASCII.LF);
         Night_Check_Skipped := True;
      elsif Ok and then End_Check and then not Verified_Now and then To_String (Night_Why) in "max_sessions" | "max_hours" then   --  not after q / Ctrl-C: those end at once; make verify does it by hand
         if not Night_Verify then Night_Why := To_Unbounded_String ("drift");
         elsif Sim_Quit.Requested then Night_Why := To_Unbounded_String ("signal");
         end if;   --  cut short by q: the reason stays the limit, the box says the check was cut short (Night_Verify_Cut)
      end if;
      return True;
   end Night_After_Session;

   --  The next session of a night run: the diaries have Ticks lines each now (this process wrote them), the world in memory is at that tick.
   --  What a run started by hand would have built by replaying them is reset or reloaded here: the lines on disk, the files kept open, the
   --  counters of "this run".  The rest (session record, snapshots, import text) is redone by the loop body, as it does for any run.
   --  ---- 0.058: the state checkpoint (state.ckpt in the save folder) ---------------------------------------------------------
   --  The header is text, one "key value" per line up to the line "end": the format, the build, the data hash, the seed, the tick,
   --  the bytes of each diary up to that tick, the counts the files must still give at that tick (Ckpt_Counts, the record lines of
   --  each store), the sections and the length and hash of the payload, and the fingerprint of every record file (Sim_Ckpt.File_Print).
   --  The payload is the State_IO of every module and of this program, in sections with a marker.  What the files give (the
   --  diaries, sessions.txt, the record files, Robert's inputs) is not in it: every start reads them as before (Load_*), and the
   --  restore only sets what the replay of ticks 1 .. tick would have built from them.
   Layout_Error : exception;   --  0.059: a section that does not read back the way this build streams it (message: the section)
   Sect_Count : constant := 18;   --  the 17 sections of the modules and "end" (0.061: "carry" after "main"; formats 1 and 2 end after "main";
                                  --  0.064: "albanian" after "carry"; format 3 ends after "carry")
   Mod_Count : constant := 17;
   Sect_At : array (1 .. Sect_Count + 1) of Ada.Streams.Stream_Element_Offset := [others => 0];   --  where each section starts
   --  the bodies of the sections of a payload in memory (bytes From .. To of its stream), from the header (format 1) or the section heads
   type Sect_Bounds is array (1 .. Mod_Count) of Ada.Streams.Stream_Element_Offset;
   type Layout is record
      From, To : Sect_Bounds := [others => 0];
      Have : Natural := Mod_Count;   --  the module sections it holds: 15 (formats 1, 2: no "carry"), 16 (format 3: no "albanian"),
                                     --  17; a missing one reads as the Reset of its module (0.061 / 0.064)
   end record;
   Ckpt_L : Layout;   --  the bodies in Ckpt_Data (Ckpt_Probe)
   Ckpt_Data : aliased Sim_Ckpt.Mem_Stream;   --  the file read by Ckpt_Probe (header and payload)
   Ckpt_Pay_At : Ada.Streams.Stream_Element_Offset := 0;   --  the payload starts after this byte
   Ckpt_Head : Str_Vectors.Vector;
   Store_Count : constant := 15;

   --  ckpt_log.txt in the save folder: one time stamped line per load, write or refusal (the last 200 lines; run_log.txt keeps its
   --  one entry per run).  Not in views (they write nothing).
   procedure Ckpt_Log (Text : String) is
      Old : Str_Vectors.Vector;
      Found : Boolean;
      F : TIO.File_Type;
   begin
      if (Ledger_Mode and then not Verify_View) or else Preview then return; end if;   --  0.059: make verify writes the checkpoint
      Read_Lines ("ckpt_log.txt", Old, Found);
      TIO.Create (F, TIO.Out_File, "ckpt_log.txt.tmp");
      for I in Integer'Max (1, Natural (Old.Length) - 198) .. Natural (Old.Length) loop TIO.Put_Line (F, Old (I)); end loop;
      TIO.Put_Line (F, Local_Stamp & " " & Text);
      TIO.Close (F);
      if Ada.Directories.Exists ("ckpt_log.txt") then Ada.Directories.Delete_File ("ckpt_log.txt"); end if;
      Ada.Directories.Rename ("ckpt_log.txt.tmp", "ckpt_log.txt");
   exception
      when others => null;
   end Ckpt_Log;

   function Sect_Name (K : Positive) return String is
     (case K is when 1 => "world", when 2 => "dharma", when 3 => "things", when 4 => "screen", when 5 => "games", when 6 => "robot",
                when 7 => "govern", when 8 => "preport", when 9 => "next", when 10 => "trial", when 11 => "records", when 12 => "visit",
                when 13 => "active", when 14 => "ledger", when 15 => "main", when 16 => "carry", when 17 => "albanian", when others => "end");
   --  0.061: the sections of a checkpoint of format Fmt and the name of its K-th section (formats 1 and 2: no "carry", K = 16 is "end")
   --  0.064: format 3 has no "albanian", K = 17 is "end" there
   function Mods_Of (Fmt : Integer) return Natural is (if Fmt <= 2 then Mod_Count - 2 elsif Fmt = 3 then Mod_Count - 1 else Mod_Count);
   function Sect_Count_Of (Fmt : Integer) return Positive is (Mods_Of (Fmt) + 1);
   function Sect_Name_Of (Fmt : Integer; K : Positive) return String is (if K > Mods_Of (Fmt) then "end" else Sect_Name (K));

   procedure With_Store (K : Positive; Act : not null access procedure (S : in out Sim_Store.Store)) is
   begin
      case K is
         when 1 => Act (Screen_Store);
         when 2 => Act (Chess_Store);
         when 3 => Act (Robot_Store);
         when 4 => Act (Govern_Store);
         when 5 => Act (Preport_Store);
         when 6 => Act (Next_Store);
         when 7 => Act (Trial_Store);
         when 8 => Act (Votes_Store);
         when 9 => Act (Pets_Store);
         when 10 => Act (Dict_Store);
         when 11 => Act (Anns_Store);
         when 12 => Act (Bals_Store);
         when 13 => Act (Visit_Store);
         when 14 => Act (Chat_Store);
         when others => Act (Active_Store);
      end case;
   end With_Store;

   --  The variables of this program the replay builds (the input lists and the lines of the files are not among them).
   procedure Main_State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Integer);
      procedure IO is new Sim_Ckpt.IO (Int);
      procedure IO is new Sim_Ckpt.IO (Boolean);
      procedure IO is new Sim_Ckpt.IO (State);
      procedure IO is new Sim_Ckpt.IO (Entity_Id);
      procedure IO is new Sim_Ckpt.IO (List_Id);
      procedure IO is new Sim_Ckpt.IO (All_Stats);
      procedure IO is new Sim_Ckpt.IO (Str_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Sim_Chat.Sample_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Unbounded_String);
   begin
      IO (S, Save, Cur_Tick); IO (S, Save, Last_Done);
      IO (S, Save, Did_Learn); IO (S, Save, Did_Coin); IO (S, Save, Did_Bench); IO (S, Save, Did_Teach);
      IO (S, Save, Pre_Energy_G); IO (S, Save, Last_Act); IO (S, Save, Votes_Of); IO (S, Save, World_Active); IO (S, Save, Last_Verb);
      for E in Entity_Id loop
         IO (S, Save, St (E));
         IO (S, Save, Pending_Word (E)); IO (S, Save, Pending_From (E));
         for A in Action loop IO (S, Save, Act_Count (E, A)); end loop;
         IO (S, Save, Voice_Act (E));
         for K in 1 .. 5 loop IO (S, Save, Voice_Hist (E, K)); end loop;
         for V in World_Verb loop IO (S, Save, Verb_Count (E, V)); end loop;
         IO (S, Save, Rate_Pct (E)); IO (S, Save, Load (E)); IO (S, Save, Hist (E)); IO (S, Save, Cool (E)); IO (S, Save, Streak (E));
         IO (S, Save, Since_Work (E)); IO (S, Save, Cool_N (E)); IO (S, Save, Cut_N (E)); IO (S, Save, Quick_N (E));
         IO (S, Save, Chat_Start_Mood (E));
         declare   --  without its "ts" (a replay writes the time of now; the frame shows only "t" and "text")
            D : Unbounded_String := (if Save then To_Unbounded_String (No_Ts (To_String (Last_Diary (E)))) else Null_Unbounded_String);
         begin
            IO (S, Save, D);
            if not Save then Last_Diary (E) := D; end if;
         end;
      end loop;
      IO (S, Save, Last_Phase);
      IO (S, Save, Rest_Active); IO (S, Save, Grant_Active);
      IO (S, Save, Screen_Active); IO (S, Save, Screen_N); IO (S, Save, Scr_Lines);
      IO (S, Save, Chess_Active); IO (S, Save, Chess_N); IO (S, Save, Chess_Lines);
      IO (S, Save, Robot_Active); IO (S, Save, Robot_N); IO (S, Save, Robot_Lines);
      IO (S, Save, Govern_Active); IO (S, Save, Scoin_Active); IO (S, Save, Govern_Lines); IO (S, Save, Gov_Since);
      IO (S, Save, Preport_Active); IO (S, Save, Preport_End); IO (S, Save, Preport_Lines);
      IO (S, Save, Next_Active); IO (S, Save, Next_End); IO (S, Save, Next_Lines);
      IO (S, Save, Visit_Active); IO (S, Save, Visit_E); IO (S, Save, Visit_Start); IO (S, Save, Visit_End); IO (S, Save, Visit_Wait);
      IO (S, Save, Trial_Active); IO (S, Save, Trial_Lines);
      IO (S, Save, Chat_Active); IO (S, Save, Symbols_Active); IO (S, Save, Active_N); IO (S, Save, Chat_N);
      IO (S, Save, Chat_Samples); IO (S, Save, Chat_Session_Count);
      IO (S, Save, World_Flushed);
      for K in Eff_Hit'Range loop IO (S, Save, Eff_Hit (K)); end loop;
      IO (S, Save, Grant_Report);
   end Main_State_IO;

   --  One section of the payload: the State_IO of a module (K = 1 .. 14), of this program (15) or of the word carrying (16, 0.061).
   procedure Sect_IO (K : Positive; S : not null access Sim_Ckpt.Mem_Stream; Save : Boolean) is
   begin
      case K is
         when 1 => Sim_World.State_IO (S, Save);
         when 2 => Sim_Dharma.State_IO (S, Save);
         when 3 => Sim_Things.State_IO (S, Save);
         when 4 => Sim_Screen.State_IO (S, Save);
         when 5 => Sim_Games.State_IO (S, Save);
         when 6 => Sim_Robot.State_IO (S, Save);
         when 7 => Sim_Govern.State_IO (S, Save);
         when 8 => Sim_Preport.State_IO (S, Save);
         when 9 => Sim_Next.State_IO (S, Save);
         when 10 => Sim_Trial.State_IO (S, Save);
         when 11 => Sim_Records.State_IO (S, Save);
         when 12 => Sim_Visit.State_IO (S, Save);
         when 13 => Sim_Active.State_IO (S, Save);
         when 14 => Sim_Ledger.State_IO (S, Save);
         when 15 => Main_State_IO (S, Save);
         when 16 => Sim_Carry.State_IO (S, Save);
         when others => Sim_Albanian.State_IO (S, Save);
      end case;
      if Length (Ckpt_Test_Extra) > 0 and then To_String (Ckpt_Test_Extra) = Sect_Name (K) then   --  tests only: a build with a field more
         declare
            X : Integer := 4242;
         begin
            if Save then Integer'Write (S, X); else Integer'Read (S, X); end if;
         end;
      end if;
   end Sect_IO;

   --  0.059, format 2: everything, each section with its head (tag = the section name, byte length and hash of the body; Sim_Ckpt),
   --  the last one "end" with an empty body.
   procedure All_State_Write (S : not null access Sim_Ckpt.Mem_Stream) is
      At_B : Ada.Streams.Stream_Element_Offset;
   begin
      for K in 1 .. Sect_Count loop
         Sim_Ckpt.Section_Begin (S.all, Sect_Name (K), At_B);
         Sect_At (K) := At_B;
         if K <= Mod_Count then Sect_IO (K, S, True); end if;
         Sim_Ckpt.Section_End (S.all, At_B);
      end loop;
      Sect_At (Sect_Count + 1) := S.Last;
   end All_State_Write;

   --  Reads every section from its body only (the stream ends at the body's last byte while it is read): a section that wants more
   --  bytes, or leaves some, was written with another layout of that module: Layout_Error with its name.
   procedure All_State_Read (S : not null access Sim_Ckpt.Mem_Stream; L : Layout) is
      use type Ada.Streams.Stream_Element_Offset;
      Full : constant Ada.Streams.Stream_Element_Offset := S.Last;
   begin
      for K in 1 .. Mod_Count loop
         if K > L.Have then   --  0.061 / 0.064: an older checkpoint has no carry (formats 1, 2) or Albanian state: none was built yet
            if K = 16 then Sim_Carry.Reset; else Sim_Albanian.Reset; end if;
            goto Next_K;
         end if;
         S.Pos := L.From (K) - 1;
         S.Last := L.To (K);
         begin
            Sect_IO (K, S, False);
         exception
            when others =>
               S.Last := Full;
               raise Layout_Error with Sect_Name (K);
         end;
         S.Last := Full;
         if S.Pos /= L.To (K) then raise Layout_Error with Sect_Name (K); end if;
         <<Next_K>>
      end loop;
      S.Pos := Full;
   end All_State_Read;

   --  The section marker of format 1 (build 0.058): Integer 77000 + K before section K.
   function Marker_Bytes (K : Positive) return Ada.Streams.Stream_Element_Array is
      M : aliased Sim_Ckpt.Mem_Stream;
      X : constant Integer := 77_000 + K;
   begin
      Integer'Write (M'Access, X);
      declare
         R : constant Ada.Streams.Stream_Element_Array := M.Buf (1 .. M.Last);
      begin
         Sim_Ckpt.Clear (M);
         return R;
      end;
   end Marker_Bytes;

   --  What the files give at tick C: the sessions begun before C, the word votes up to C and Robert's inputs that have taken effect
   --  by then.  Equal at the write and at the load, or the files were changed behind the checkpoint (an old input added or removed).
   function Ckpt_Counts (C : Int) return String is
      Ses, Vot, Gr, Vi, Ch : Natural := 0;
   begin
      for R of Sessions loop if R.Start < C then Ses := Ses + 1; end if; end loop;
      for R of Word_Votes loop if R.Tick <= C then Vot := Vot + 1; end if; end loop;
      for G of Grants loop if G.Tick < C then Gr := Gr + 1; end if; end loop;
      for X of Visit_Inputs loop if X.Tick <= C then Vi := Vi + 1; end if; end loop;
      for X of Chat_Inputs loop if X.Tick <= C then Ch := Ch + 1; end if; end loop;
      return "sessions=" & Img (Ses) & " votes=" & Img (Vot) & " says=" & Img (Sim_Dharma.Addresses_Before (C)) & " grants=" & Img (Gr)
        & " vetoes=" & Img (Sim_Govern.Inputs_Before (C)) & " challenges=" & Img (Sim_Preport.Inputs_Before (C))
        & " visit=" & Img (Vi) & " chat=" & Img (Ch);
   end Ckpt_Counts;

   function Head_Get (Head : Str_Vectors.Vector; Key : String) return String is
   begin
      for L of Head loop
         if L'Length > Key'Length and then L (L'First .. L'First + Key'Length) = Key & " " then return L (L'First + Key'Length + 1 .. L'Last); end if;
      end loop;
      return "";
   end Head_Get;

   --  The format number of the first header line "diary-sim-ckpt N" (-1: no checkpoint header).
   function Head_Format (Head : Str_Vectors.Vector) return Integer is
   begin
      if Head.Is_Empty then return -1; end if;
      declare
         F : constant String := Head.First_Element;
      begin
         if F'Length <= Ckpt_Magic'Length or else F (F'First .. F'First + Ckpt_Magic'Length - 1) /= Ckpt_Magic then return -1; end if;
         return Integer'Value (F (F'First + Ckpt_Magic'Length .. F'Last));
      end;
   exception
      when others => return -1;
   end Head_Format;

   --  The bodies of the sections of the payload Data (after byte Pay_At), and "" or why they do not fit what this build streams.
   --  Format 1: the header lines "section<K> <name> <offset>" and the markers.  Format 2: the section heads, read in a row; a tag
   --  other than the name this build expects there, or sections after "end", is another state layout ('state layout changed: <name>').
   procedure Parse_Sections (Head : Str_Vectors.Vector; Data : Sim_Ckpt.Mem_Stream; Fmt : Integer; Pay_At : Ada.Streams.Stream_Element_Offset;
                             L : out Layout; Why : out Unbounded_String) is
      use type Ada.Streams.Stream_Element_Offset, Ada.Streams.Stream_Element_Array, Sim_Ckpt.Hash_T;
   begin
      L := (others => <>);
      Why := Null_Unbounded_String;
      if Fmt = 1 then
         declare
            NS : constant Positive := Sect_Count_Of (1);   --  0.061: format 1 has no section "carry"
            Off : array (1 .. NS) of Ada.Streams.Stream_Element_Offset := [others => 0];
         begin
            for K in 1 .. NS loop
               declare
                  V : constant String := Head_Get (Head, "section" & Img (K));
                  Sp : constant Natural := Fx.Index (V, " ");
               begin
                  if Sp = 0 then Why := To_Unbounded_String (Msg ("ckpt.why.corrupt", "section line")); return; end if;
                  if V (V'First .. Sp - 1) /= Sect_Name_Of (1, K) then Why := To_Unbounded_String (Msg ("ckpt.why.layout", Sect_Name_Of (1, K))); return; end if;
                  Off (K) := Ada.Streams.Stream_Element_Offset'Value (V (Sp + 1 .. V'Last));
               end;
            end loop;
            if Head_Get (Head, "section" & Img (Integer (NS + 1))) /= "" then
               Why := To_Unbounded_String (Msg ("ckpt.why.layout", "end"));
               return;
            end if;
            for K in 1 .. NS loop
               if Off (K) < 0 or else Pay_At + Off (K) + 4 > Data.Last or else (K > 1 and then Off (K) < Off (K - 1) + 4)
                 or else Data.Buf (Pay_At + Off (K) + 1 .. Pay_At + Off (K) + 4) /= Marker_Bytes (K)
               then
                  Why := To_Unbounded_String (Msg ("ckpt.why.corrupt", "section " & Sect_Name_Of (1, K)));
                  return;
               end if;
            end loop;
            if Pay_At + Off (NS) + 4 /= Data.Last then Why := To_Unbounded_String (Msg ("ckpt.why.layout", "end")); return; end if;
            for K in 1 .. NS - 1 loop
               L.From (K) := Pay_At + Off (K) + 5;
               L.To (K) := Pay_At + Off (K + 1);
            end loop;
            L.Have := NS - 1;
         end;
      else
         declare
            P : Ada.Streams.Stream_Element_Offset := Pay_At;
            Tag : String (1 .. Sim_Ckpt.Tag_Len);
            Len : Long_Long_Integer;
            H : Sim_Ckpt.Hash_T;
            Ok : Boolean;
         begin
            for K in 1 .. Sect_Count_Of (Fmt) loop   --  0.061: format 2 has no section "carry"
               Sim_Ckpt.Section_Head (Data, P, Tag, Len, H, Ok);
               if not Ok or else P + Sim_Ckpt.Sect_Head_Len + Ada.Streams.Stream_Element_Offset (Len) > Data.Last then
                  Why := To_Unbounded_String (Msg ("ckpt.why.corrupt", "section " & Sect_Name_Of (Fmt, K)));
                  return;
               end if;
               if Tag /= Sim_Ckpt.Pad_Tag (Sect_Name_Of (Fmt, K)) then
                  Why := To_Unbounded_String (Msg ("ckpt.why.layout", Sect_Name_Of (Fmt, K) & ", found " & Fx.Trim (Tag, Ada.Strings.Both)));
                  return;
               end if;
               declare
                  First : constant Ada.Streams.Stream_Element_Offset := P + Sim_Ckpt.Sect_Head_Len + 1;
                  Last : constant Ada.Streams.Stream_Element_Offset := P + Sim_Ckpt.Sect_Head_Len + Ada.Streams.Stream_Element_Offset (Len);
               begin
                  if Sim_Ckpt.Hash_Of (Data, First, Last) /= H then
                     Why := To_Unbounded_String (Msg ("ckpt.why.corrupt", "section " & Sect_Name_Of (Fmt, K)));
                     return;
                  end if;
                  if K < Sect_Count_Of (Fmt) then
                     L.From (K) := First;
                     L.To (K) := Last;
                  end if;
                  P := Last;
               end;
            end loop;
            if P /= Data.Last then Why := To_Unbounded_String (Msg ("ckpt.why.layout", "end")); end if;   --  more sections: a newer layout
            L.Have := Mods_Of (Fmt);
         end;
      end if;
   exception
      when others => Why := To_Unbounded_String (Msg ("ckpt.why.corrupt", "sections"));
   end Parse_Sections;

   --  The header and section checks shared by the start and by --verify: "" when the checkpoint has a format of this build's state
   --  layout, its payload is whole and every section fits, and the record files fit.  0.059: the build and data/ are no reason.
   function Ckpt_Fits (Head : Str_Vectors.Vector; Data : Sim_Ckpt.Mem_Stream; Pay_At : Ada.Streams.Stream_Element_Offset; L : out Layout) return String is
      use type Ada.Streams.Stream_Element_Offset;
      Fmt : constant Integer := Head_Format (Head);
      Why : Unbounded_String;
   begin
      L := (others => <>);
      if Fmt < 0 then return Msg ("ckpt.why.version", "format"); end if;
      if Fmt > Ckpt_Format then return Msg ("ckpt.why.version", "format " & Img (Fmt) & ", newer than this build's " & Img (Integer (Ckpt_Format))); end if;
      if Fmt < Ckpt_Layout_Since then
         return Msg ("ckpt.why.layout", "format " & Img (Fmt) & ", this build reads " & Img (Integer (Ckpt_Layout_Since)) & " .. " & Img (Integer (Ckpt_Format)));
      end if;
      if Head_Get (Head, "payload") /= Img (Int (Data.Last - Pay_At)) & " " & Sim_Ckpt.Hex (Sim_Ckpt.Hash_Of (Data, Pay_At + 1, Data.Last)) then
         return Msg ("ckpt.why.corrupt", "payload");
      end if;
      Parse_Sections (Head, Data, Fmt, Pay_At, L, Why);
      if Length (Why) > 0 then return To_String (Why); end if;
      if L.Have < Mod_Count then   --  0.061: no carry state in formats 1 and 2, 0.064: no Albanian state in 1 .. 3: only while no
         declare                    --  carry=1 / alb=1 session began before the checkpoint's tick
            C : constant Int := Int'Value (Head_Get (Head, "tick"));
         begin
            for R of Sessions loop
               if L.Have < 16 and then R.Carry and then R.Start < C then
                  return Msg ("ckpt.why.layout", "format " & Img (Fmt) & " has no carry state, carry=1 since session " & Img (R.N));
               end if;
               if R.Alb and then R.Start < C then
                  return Msg ("ckpt.why.layout", "format " & Img (Fmt) & " has no Albanian state, alb=1 since session " & Img (R.N));
               end if;
            end loop;
         end;
      end if;
      for HL of Head loop
         if HL'Length > 5 and then HL (HL'First .. HL'First + 4) = "file " then
            declare
               A : constant Natural := Fx.Index (HL, " ", HL'First + 5);
               B : constant Natural := (if A = 0 then 0 else Fx.Index (HL, " ", A + 1));
            begin
               if B = 0 then return Msg ("ckpt.why.corrupt", "file line"); end if;
               if Sim_Ckpt.File_Print (HL (B + 1 .. HL'Last), Long_Long_Integer'Value (HL (HL'First + 5 .. A - 1))) /= HL (A + 1 .. B - 1) then
                  return Msg ("ckpt.why.stale", HL (B + 1 .. HL'Last));
               end if;
            end;
         end if;
      end loop;
      return "";
   exception
      when others => return Msg ("ckpt.why.corrupt", "header");
   end Ckpt_Fits;

   --  0.059: the rule files of data/ that differ from the checkpoint's "datafile" lines (changed, new or gone), "a, b".
   function Data_Changed (Head : Str_Vectors.Vector) return String is
      R : Unbounded_String;
      procedure Add (N : String) is
      begin
         Append (R, (if Length (R) > 0 then ", " else "") & N);
      end Add;
      function Name_Of (L : String) return String is
        (if Fx.Index (L, " ") = 0 then L else L (L'First .. Fx.Index (L, " ") - 1));
   begin
      for L of Data_Lines loop
         if Head_Get (Head, "datafile " & Name_Of (L)) /= L (L'First + Name_Of (L)'Length + 1 .. L'Last) then Add (Name_Of (L)); end if;
      end loop;
      for H of Head loop
         if H'Length > 9 and then H (H'First .. H'First + 8) = "datafile " then
            declare
               N : constant String := Name_Of (H (H'First + 9 .. H'Last));
            begin
               if not (for some L of Data_Lines => Name_Of (L) = N) then Add (N); end if;
            end;
         end if;
      end loop;
      return To_String (R);
   end Data_Changed;

   --  Before the diaries are read: may this start use the checkpoint?  Sets Ckpt_Used (and Ckpt_Tick, Ckpt_Seed, Ckpt_Off) or Ckpt_Why.
   procedure Ckpt_Probe (From : String := Ckpt_Path) is
      Ok : Boolean;
      procedure No (Why : String) is
      begin
         Ckpt_Used := False;
         Ckpt_Why := To_Unbounded_String (Why);
         Sim_Ckpt.Clear (Ckpt_Data);
      end No;
   begin
      Ckpt_Used := False;
      if Replay_Opt then No (Msg ("ckpt.why.forced")); return; end if;
      if Limit ("ckpt.enabled", 1) = 0 then No (Msg ("ckpt.why.off")); return; end if;
      if not Ada.Directories.Exists (From) then No (Msg ("ckpt.why.missing")); return; end if;
      Sim_Ckpt.Read_File (From, Ckpt_Head, Ckpt_Data, Ok);
      if not Ok then No (Msg ("ckpt.why.corrupt", "unreadable")); return; end if;
      Ckpt_Pay_At := Ckpt_Data.Pos;
      declare
         Why : constant String := Ckpt_Fits (Ckpt_Head, Ckpt_Data, Ckpt_Pay_At, Ckpt_L);
         C : constant Natural := Natural'Value (Head_Get (Ckpt_Head, "tick"));
      begin
         if Why /= "" then No (Why); return; end if;
         if C = 0 then No (Msg ("ckpt.why.corrupt", "tick 0")); return; end if;
         if Explicit and then More < 0 and then Ticks >= 0 and then Ticks < Int (C) then
            No (Msg ("ckpt.why.ticks", Img (Ticks), Img (C)));
            return;
         end if;
         for E in Entity_Id loop
            Ckpt_Off (E) := Int'Value (Head_Get (Ckpt_Head, "diary" & Img (Integer (E))));
         end loop;
         --  0.059: a number the writer's start read from data/ (Init, Load_*) may sit in the state: if data/ gives another one now,
         --  the checkpoint holds the old one where a full replay would use the new one: replay
         for H of Ckpt_Head loop
            if H'Length > 9 and then H (H'First .. H'First + 8) = "startkey " then
               declare
                  KV : constant String := H (H'First + 9 .. H'Last);
                  Sp : constant Natural := Fx.Index (KV, " ");
               begin
                  if Sp > 0 and then Sim_Util.Key_Text (KV (KV'First .. Sp - 1)) /= KV (Sp + 1 .. KV'Last) then
                     No (Msg ("ckpt.why.data", KV (KV'First .. Sp - 1) & " " & KV (Sp + 1 .. KV'Last) & " -> " & Sim_Util.Key_Text (KV (KV'First .. Sp - 1))));
                     return;
                  end if;
               end;
            end if;
         end loop;
         Ckpt_Seed := Int'Value (Head_Get (Ckpt_Head, "seed"));
         Ckpt_Tick := C;
         Ckpt_Used := True;
         Ckpt_Fmt_Used := Head_Format (Ckpt_Head);
         --  0.059: data/ is information only (the rules of new behaviour come with session markers; make verify replays everything)
         if Ckpt_Fmt_Used >= 2 and then Head_Get (Ckpt_Head, "data") /= To_String (Data_Hash) then
            Data_Note := To_Unbounded_String (Msg ("ckpt.data.changed", Data_Changed (Ckpt_Head)));
         end if;
      end;
   exception
      when others => No (Msg ("ckpt.why.corrupt", "header"));
   end Ckpt_Probe;

   --  The whole diaries after all (the checkpoint does not fit after all): as a start without it.
   procedure Ckpt_Full_Diaries is
      Seed_D : Int := Disk_Seed;
   begin
      for E in Entity_Id loop
         declare
            Was_Open : constant Boolean := TIO.Is_Open (Out_File (E));   --  opened for the new ticks already: closed while it is read
         begin
            if Was_Open then TIO.Close (Out_File (E)); end if;
            Disk (E).Clear;
            Disk_Base (E) := 0;
            Load_Diary (E, Seed_D);
            if Was_Open then TIO.Open (Out_File (E), TIO.Append_File, Path (E)); end if;
         end;
      end loop;
   end Ckpt_Full_Diaries;

   --  After every Load_* of the start: the files must still give the counts of the checkpoint, then its payload replaces the state of
   --  ticks 1 .. C.  Anything that does not fit puts the state back as it was (Pristine) and the start replays everything.
   --  0.062: the session flags that are no state of their own (carry=2, moodrest=1): from the last session begun before tick C
   procedure Derive_Session_Flags (C : Int) is
      Lvl : Positive := 1;
      Mr : Boolean := False;
      Mr2 : Boolean := False;
   begin
      for R of Sessions loop
         if R.Start < C then Lvl := (if R.Carry2 then 2 else 1); Mr := R.Moodrest; Mr2 := R.Moodrest2; end if;
      end loop;
      Sim_Carry.Set_Level (Lvl);
      Moodrest_Active := Mr;
      Moodrest_Level := (if Mr2 then 2 else 1);
   end Derive_Session_Flags;

   procedure Ckpt_Restore is
      Pristine : aliased Sim_Ckpt.Mem_Stream;
      Pristine_L : Layout;
      C : constant Int := Int (Ckpt_Tick);
      Fail : Unbounded_String;
      Layout_Fail : Boolean := False;
   begin
      if not Ckpt_Used then return; end if;
      if Head_Get (Ckpt_Head, "counts") /= Ckpt_Counts (C) then
         Ckpt_Log ("counts at the write: " & Head_Get (Ckpt_Head, "counts") & "; now: " & Ckpt_Counts (C));
         Fail := To_Unbounded_String ("inputs or sessions before tick " & Img (C));
      elsif Natural (World_Stored.Length) < Natural'Value (Head_Get (Ckpt_Head, "world"))
        or else Natural (Eff_Stored.Length) < Natural'Value (Head_Get (Ckpt_Head, "eff"))
      then
         Fail := To_Unbounded_String ("world.txt / grants.txt");
      else
         for K in 1 .. Store_Count loop
            declare
               N : constant Natural := Natural'Value (Head_Get (Ckpt_Head, "store" & Img (K)));
               procedure Fit (S : in out Sim_Store.Store) is
               begin
                  if Length (Fail) = 0 and then not Sim_Store.Fits (S, N, C) then Fail := To_Unbounded_String (Sim_Store.Path_Of (S)); end if;
               end Fit;
            begin
               With_Store (K, Fit'Access);
            end;
         end loop;
      end if;
      if Length (Fail) = 0 then
         declare
            W : Unbounded_String;
         begin
            All_State_Write (Pristine'Access);
            Parse_Sections (Str_Vectors.Empty_Vector, Pristine, Ckpt_Format, 0, Pristine_L, W);
         end;
         begin
            All_State_Read (Ckpt_Data'Access, Ckpt_L);
            Sim_Games.Reindex;   --  0.060: the derived indices of the modules
            Sim_World.Reindex;
            Derive_Session_Flags (C);
            if Last_Done /= C then Fail := To_Unbounded_String ("tick");
            elsif World_Flushed > Natural (World_Stored.Length) then Fail := To_Unbounded_String ("world.txt");
            end if;
         exception
            when E : Layout_Error =>
               Fail := To_Unbounded_String (Ada.Exceptions.Exception_Message (E));
               Layout_Fail := True;
            when E : others => Fail := To_Unbounded_String ("payload: " & Ada.Exceptions.Exception_Message (E));
         end;
         if Length (Fail) > 0 then
            All_State_Read (Pristine'Access, Pristine_L);
            Sim_Games.Reindex;   --  0.060: the derived indices of the modules
            Sim_World.Reindex;
            Derive_Session_Flags (0);
         end if;
         Sim_Ckpt.Clear (Pristine);
      end if;
      Sim_Ckpt.Clear (Ckpt_Data);
      if Length (Fail) > 0 then
         Ckpt_Used := False;
         Data_Note := Null_Unbounded_String;
         Ckpt_Why := To_Unbounded_String (Msg ((if Layout_Fail then "ckpt.why.layout" else "ckpt.why.stale"), To_String (Fail)));
         Ckpt_Full_Diaries;
         return;
      end if;
      --  what the replay of 1 .. C would have marked in the lists read from the files
      for K in 1 .. Store_Count loop
         declare
            N : constant Natural := Natural'Value (Head_Get (Ckpt_Head, "store" & Img (K)));
            procedure Mark (S : in out Sim_Store.Store) is
            begin
               Sim_Store.Mark_First (S, N);
            end Mark;
         begin
            With_Store (K, Mark'Access);
         end;
      end loop;
      for G of Grants loop G.Done := G.Tick < C; end loop;   --  a grant of tick T takes effect before tick T + 1
      Sim_Govern.Inputs_Done_Before (C);
      Sim_Preport.Inputs_Done_Before (C);
      for X of Visit_Inputs loop X.Done := X.Tick <= C; end loop;   --  handled at their tick
      for X of Chat_Inputs loop X.Done := X.Tick <= C; end loop;
      Ckpt_Load_Secs := Since (T_Run);
      if Ckpt_Fmt_Used < Ckpt_Format then   --  an older format of the same layout (0.058): loaded; the next write is format 2
         Ckpt_Log (Msg ("ckpt.oldformat", Img (Ckpt_Fmt_Used), Head_Get (Ckpt_Head, "build"), Img (Integer (Ckpt_Format))));
      end if;
   end Ckpt_Restore;

   --  At the end of a run that wrote ticks (and at a clean stop, and after a passed make verify): the state of tick Last_Done, with
   --  the files as they are now.  Never fatal: a checkpoint that cannot be written is left out (the next start replays, or loads an
   --  older one and replays the rest).
   procedure Ckpt_Write is
      use type Ada.Streams.Stream_Element_Offset;
      T0 : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      C : constant Int := Last_Done;
      Data : aliased Sim_Ckpt.Mem_Stream;
      H : Unbounded_String;
      Files : Str_Vectors.Vector;
      Ok : Boolean := True;
      procedure Line (K, V : String) is
      begin
         Append (H, K & " " & V & ASCII.LF);
      end Line;
   begin
      if Preview or else (Ledger_Mode and then not Verify_View) or else C <= 0 or else Limit ("ckpt.enabled", 1) = 0 then return; end if;
      for E in Entity_Id loop
         if not Diary_Tail_Ok (Path (E), Natural (C)) then Ok := False; end if;
      end loop;
      for K in 1 .. Store_Count loop
         declare
            procedure Fit (S : in out Sim_Store.Store) is
            begin
               if not Sim_Store.Fits (S, Sim_Store.Count (S), C) then Ok := False; end if;
            end Fit;
         begin
            With_Store (K, Fit'Access);
         end;
      end loop;
      if not Ok then
         Ckpt_Log (Msg ("ckpt.notwritten", Img (C)));
         return;
      end if;
      All_State_Write (Data'Access);
      Append (H, Ckpt_Magic & Img (Integer (Ckpt_Format)) & ASCII.LF);
      Line ("build", Build);   --  information (0.059: not a reason to refuse)
      Line ("data", To_String (Data_Hash));   --  information: the rule files of data/ (Sim_Ckpt.Data_Prints), one line each below
      for D of Data_Lines loop Line ("datafile", D); end loop;
      for K of Start_Keys loop Line ("startkey", K); end loop;   --  the numbers of data/ the start read (a change: replay)
      Line ("seed", Img (Seed));
      Line ("tick", Img (C));
      Line ("written", Local_Stamp);
      for E in Entity_Id loop Line ("diary" & Img (Integer (E)), Img (Sim_Ckpt.File_Size (Path (E)))); end loop;
      Line ("counts", Ckpt_Counts (C));
      for K in 1 .. Store_Count loop
         declare
            procedure Cnt (S : in out Sim_Store.Store) is
            begin
               Line ("store" & Img (K), Img (Sim_Store.Count (S)));
            end Cnt;
         begin
            With_Store (K, Cnt'Access);
         end;
      end loop;
      Line ("world", Img (Integer (World_Stored.Length)));
      Line ("eff", Img (Integer (Eff_Stored.Length)));
      for K in 1 .. Sect_Count loop   --  information (format 2 reads the section heads of the payload)
         Line ("section" & Img (K), Sect_Name (K) & " " & Img (Int (Sect_At (K))) & " " & Img (Int (Sect_At (K + 1) - Sect_At (K) - Sim_Ckpt.Sect_Head_Len)));
      end loop;
      Line ("payload", Img (Int (Data.Last)) & " " & Sim_Ckpt.Hex (Sim_Ckpt.Hash_Of (Data, 1, Data.Last)));
      Sim_Ckpt.Record_Files (Files);
      for P of Files loop
         declare
            Size : constant Long_Long_Integer := Sim_Ckpt.File_Size (P);
         begin
            Line ("file " & Img (Int (Size)), Sim_Ckpt.File_Print (P, Size) & " " & P);
         end;
      end loop;
      Append (H, "end" & ASCII.LF);
      Sim_Ckpt.Write_File (Ckpt_Path, To_String (H), Data);
      Ckpt_Bytes := Int (Length (H)) + Int (Data.Last);
      Sim_Ckpt.Clear (Data);
      Ckpt_Write_Secs := Since (T0);
      Ckpt_Written := Ckpt_Written + 1;
      Ckpt_Last_Write := Ada.Calendar.Clock;
      Ckpt_Log (Msg ("ckpt.written", Img (C), Img (Ckpt_Bytes / 1024), Secs_Text (Ckpt_Write_Secs)));
   exception
      when E : others =>
         Sim_Ckpt.Clear (Data);
         begin
            if Ada.Directories.Exists (Ckpt_Path) then Ada.Directories.Delete_File (Ckpt_Path); end if;
         exception
            when others => null;
         end;
         Ckpt_Log (Msg ("ckpt.failed", Ada.Exceptions.Exception_Message (E)));
   end Ckpt_Write;

   --  --verify: the replay has rebuilt the state of its last tick; a checkpoint of that tick must hold exactly the same bytes, section
   --  by section (a format 1 checkpoint of build 0.058 too: the bodies are the same, only the framing differs).
   function Ckpt_Verify return String is
      use type Ada.Streams.Stream_Element_Offset, Ada.Streams.Stream_Element;
      Head : Str_Vectors.Vector;
      Ok : Boolean;
      Now : aliased Sim_Ckpt.Mem_Stream;
      L, NL : Layout;
      W : Unbounded_String;
      At_Diff : Ada.Streams.Stream_Element_Offset := 0;
      Diff_K : Positive := 1;
   begin
      Ckpt_Verify_Diff := False;
      if not Ada.Directories.Exists (Ckpt_Path) then return Msg ("ckpt.verify.skip", Msg ("ckpt.why.missing")); end if;
      Sim_Ckpt.Read_File (Ckpt_Path, Head, Ckpt_Data, Ok);
      if not Ok then return Msg ("ckpt.verify.skip", Msg ("ckpt.why.corrupt", "unreadable")); end if;
      declare
         Pay : constant Ada.Streams.Stream_Element_Offset := Ckpt_Data.Pos;
         Why : constant String := Ckpt_Fits (Head, Ckpt_Data, Pay, L);
         C : constant Int := Int'Value (Head_Get (Head, "tick"));
      begin
         if Why /= "" then Sim_Ckpt.Clear (Ckpt_Data); return Msg ("ckpt.verify.skip", Why); end if;
         if C /= Last_Done then Sim_Ckpt.Clear (Ckpt_Data); return Msg ("ckpt.verify.skip", Msg ("ckpt.why.tick", Img (C), Img (Last_Done))); end if;
         All_State_Write (Now'Access);
         Parse_Sections (Str_Vectors.Empty_Vector, Now, Ckpt_Format, 0, NL, W);
         Sections : for K in 1 .. Mod_Count loop
            if K > L.Have then   --  0.061 / 0.064: an older checkpoint holds no carry / Albanian state: the replay built none either
               if (if K = 16 then not Sim_Carry.Zero else not Sim_Albanian.Zero) then At_Diff := 1; Diff_K := K; exit Sections; end if;
               goto Next_Sect;
            end if;
            declare
               A_Len : constant Ada.Streams.Stream_Element_Offset := L.To (K) - L.From (K) + 1;
               B_Len : constant Ada.Streams.Stream_Element_Offset := NL.To (K) - NL.From (K) + 1;
            begin
               for I in 0 .. Ada.Streams.Stream_Element_Offset'Min (A_Len, B_Len) - 1 loop
                  if Ckpt_Data.Buf (L.From (K) + I) /= Now.Buf (NL.From (K) + I) then
                     At_Diff := I + 1;
                     Diff_K := K;
                     exit Sections;
                  end if;
               end loop;
               if A_Len /= B_Len then
                  At_Diff := Ada.Streams.Stream_Element_Offset'Min (A_Len, B_Len) + 1;
                  Diff_K := K;
                  exit Sections;
               end if;
            end;
            <<Next_Sect>>
         end loop Sections;
         Sim_Ckpt.Clear (Now);
         Sim_Ckpt.Clear (Ckpt_Data);
         if At_Diff = 0 then return Msg ("ckpt.verify.same", Img (C)); end if;
         if Ada.Directories.Exists (Ckpt_Path & ".bad") then Ada.Directories.Delete_File (Ckpt_Path & ".bad"); end if;
         Ada.Directories.Rename (Ckpt_Path, Ckpt_Path & ".bad");
         Ada.Command_Line.Set_Exit_Status (1);
         Ckpt_Verify_Diff := True;
         return Msg ("ckpt.verify.diff", Img (C), Sect_Name (Diff_K), Img (Int (At_Diff)));
      end;
   exception
      when E : others =>
         Sim_Ckpt.Clear (Ckpt_Data);
         return Msg ("ckpt.verify.skip", Ada.Exceptions.Exception_Message (E));
   end Ckpt_Verify;

   --  The line of the start: the checkpoint and how long the start took, or why everything is replayed.
   function Ckpt_Start_Text (Timed : Boolean) return String is   --  Timed: with the seconds (a night; a plain run keeps its console the same run by run)
     (if Ckpt_Used and then Timed then Msg ("ckpt.used", Img (Ckpt_Tick), Secs_Text (Ckpt_Load_Secs), Img (Integer'Max (0, Verify_To - Ckpt_Tick)))
      elsif Ckpt_Used then Msg ("ckpt.used.plain", Img (Ckpt_Tick), Img (Integer'Max (0, Verify_To - Ckpt_Tick)))
      else Msg ("ckpt.replay", To_String (Ckpt_Why), Img (Verify_To)));

   --  A night writes the checkpoint after a session when night.ckpt_seconds have passed since the last one, and after the session
   --  that is (most likely) its last: a limit, q or a signal.  A crash in between costs the replay of the sessions after it.
   function Night_Ckpt_Due return Boolean is
      Every_S : constant Int := Limit ("night.ckpt_seconds", 60);
   begin
      return Every_S <= 0 or else Since (Ckpt_Last_Write) >= Duration (Every_S)
        or else Sim_Quit.Requested or else Sim_Quit.Key_Q
        or else (Night_Max_S > 0 and then Int (Night_Done) + 1 >= Night_Max_S)
        or else (Night_Max_Secs > 0.0 and then Since (Night_T0) + Duration'Max (2.0, 2 * Last_Dur) >= Night_Max_Secs
                 and then (Last_Dur >= 0.5 or else Since (Ckpt_Last_Write) >= 0.5));   --  short sessions: at most 2 writes a second
   end Night_Ckpt_Due;

   Prog_Last_T : Ada.Calendar.Time := Prog_T0;
   Replay_T0 : Ada.Calendar.Time := Prog_T0;   --  0.060: the start of the replay of this run
   Prog_Last_Tick : Int := 0;
   procedure Progress_Line (Tick : Int) is   --  DIARY_REPLAY_PROGRESS: tick, seconds since the start, ticks/s since the last line
      Now : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      D : constant Duration := Now - Prog_Last_T;
   begin
      TIO.Put_Line (TIO.Standard_Error, "replay-progress: tick " & Img (Tick) & " at " & Tenths_Text (Now - Prog_T0) & " s, "
                    & Img (Int (Float (Tick - Prog_Last_Tick) / Float (Duration'Max (0.001, D)))) & " ticks/s");
      Prog_Last_T := Now;
      Prog_Last_Tick := Tick;
   end Progress_Line;

   --  0.060: seconds since 1970 (UTC), for --deadline
   function Unix_Now return Int is
     (Int (Ada.Calendar."-" (Ada.Calendar.Clock, Ada.Calendar.Formatting.Time_Of (1970, 1, 1, 0.0))));

   --  0.060: how long a replay of N ticks will take, from the last measured one in ckpt_log.txt ("replay done: <n> ticks in <s> s",
   --  written after every replay of at least 1000 ticks): the cost of a tick grows with the history, measured about as n ** 1.5 in
   --  total, so t = s * (N / n) ** 1.5; without a measurement N / 1500 ticks a second.  Src says which.
   function Replay_Estimate (N : Natural; Src : out Unbounded_String) return Duration is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Mark : constant String := " replay done: ";
      Got_N : Natural := 0;
      Got_S : Float := 0.0;
   begin
      Read_Lines ("ckpt_log.txt", Lines, Found);
      for L of Lines loop
         declare
            P : constant Natural := Fx.Index (L, Mark);
         begin
            if P > 0 then
               declare
                  R : constant String := L (P + Mark'Length .. L'Last);   --  "<n> ticks in <s> s ..."
                  A : constant Natural := Fx.Index (R, " ticks in ");
                  B : constant Natural := (if A > 0 then Fx.Index (R, " s", A + 10) else 0);
               begin
                  if A > R'First and then B > A + 10 then
                     Got_N := Natural'Value (R (R'First .. A - 1));
                     Got_S := Float'Value (R (A + 10 .. B - 1));
                  end if;
               exception
                  when others => null;
               end;
            end if;
         end;
      end loop;
      if Got_N >= 1000 and then Got_S > 0.0 then
         Src := To_Unbounded_String (Msg ("replay.est.measured", Img (Got_N), Tenths_Text (Duration (Got_S))));
         declare
            R : constant Float := Float (N) / Float (Got_N);
         begin
            return Duration (Got_S * R * Ada.Numerics.Elementary_Functions.Sqrt (R));
         end;
      end if;
      Src := To_Unbounded_String (Msg ("replay.est.default"));
      return Duration (Float (N) / 1500.0);
   end Replay_Estimate;

   function Minutes_Up (D : Duration) return Int is (Int'Max (1, (Int (D) + 59) / 60));

   --  0.060: verify_stamp.txt in the save folder: "full=<date> <ticks> <sim print> <format>" (the last passed verify from tick 1) and
   --  "incr=<date> <from> <to>" (the last passed incremental one); ship.sh reads it for checkin.txt (what is due).
   procedure Write_Verify_Stamp (Full : Boolean; From, To : Natural) is
      Old : Str_Vectors.Vector;
      Found : Boolean;
      F : TIO.File_Type;
      Key : constant String := (if Full then "full=" else "incr=");
      Now : constant String := Local_Stamp;
   begin
      Read_Lines ("verify_stamp.txt", Old, Found);
      TIO.Create (F, TIO.Out_File, "verify_stamp.txt.tmp");
      TIO.Put_Line (F, "# diary-sim verify stamp (make verify / make verify-full write it; checkin.txt reads it)");
      for L of Old loop
         if L'Length > 5 and then L (L'First .. L'First + 4) in "full=" | "incr=" and then L (L'First .. L'First + 4) /= Key then TIO.Put_Line (F, L); end if;
      end loop;
      if Full then
         TIO.Put_Line (F, Key & Now (Now'First .. Now'First + 15) & " " & Img (To) & " "
                       & (if Length (Sim_Print_Opt) > 0 then To_String (Sim_Print_Opt) else "-") & " " & Img (Integer (Ckpt_Format)));
      else
         TIO.Put_Line (F, Key & Now (Now'First .. Now'First + 15) & " " & Img (From) & " " & Img (To));
      end if;
      TIO.Close (F);
      if Ada.Directories.Exists ("verify_stamp.txt") then Ada.Directories.Delete_File ("verify_stamp.txt"); end if;
      Ada.Directories.Rename ("verify_stamp.txt.tmp", "verify_stamp.txt");
   exception
      when others => null;
   end Write_Verify_Stamp;

   procedure Night_Next_Session is
      Seed_D : Int := Disk_Seed;
      Old : constant Natural := Common;
   begin
      Common := Natural (Ticks);
      Longest := Common;
      Ent_Missing := 0;   --  the entities/ folders exist now
      Verified := Verified + Written;
      Written := 0;
      T_Run := Ada.Calendar.Clock;
      Ticks := Int (Common) + Night_Per;
      for E in Entity_Id loop
         Cur_Name := To_Unbounded_String (Name (E));
         if Disk_Len (E) /= Common or else not Diary_Tail_Ok (Path (E), Common) then   --  0.057: else the lines in memory are the file
            Disk (E).Clear;
            Disk_Base (E) := 0;
            Load_Diary (E, Seed_D);
         end if;
         if Disk_Len (E) /= Common then
            raise Diary_Error with Msg ("night.err.length", Name (E), Img (Integer (Disk_Len (E))), Img (Common), Img (Old));
         end if;
      end loop;
      Cur_Name := To_Unbounded_String ("-");
      Run_Learn := [others => 0];
      Run_Coin := [others => 0];
      Run_Bench_N := [others => 0];
      for E in Entity_Id loop
         TIO.Open (Out_File (E), TIO.Append_File, Path (E));
         for K in Side_Kind loop Open_Side (E, K); end loop;
      end loop;
   end Night_Next_Session;

begin
   Sim_Util.Record_Keys (True);   --  0.059: the numbers read up to the restore point (Start_Keys)
   Sim_Ckpt.Data_Prints (Ada.Directories.Containing_Directory (Data_Path ("limits.txt")), Data_Lines);   --  the rule files Load_Data reads
   Sim_Albanian.Set_Data_Dir (Ada.Directories.Full_Name (Ada.Directories.Containing_Directory (Data_Path ("limits.txt"))));   --  0.064: before Resolve_Home moves
   Data_Hash := To_Unbounded_String (Sim_Ckpt.Lines_Hash (Data_Lines));
   Ckpt_Test_Extra := To_Unbounded_String (GNAT.OS_Lib.Getenv ("DIARY_TEST_CKPT_EXTRA").all);
   Replay_Wait_Ms := Natural'Value ("0" & GNAT.OS_Lib.Getenv ("DIARY_TEST_REPLAY_MS").all);
   Replay_Progress := Natural'Value ("0" & GNAT.OS_Lib.Getenv ("DIARY_REPLAY_PROGRESS").all);
   Tick_Wait_Ms := Natural'Value ("0" & GNAT.OS_Lib.Getenv ("DIARY_TEST_TICK_MS").all);
   Load_Data;
   while I <= Ada.Command_Line.Argument_Count loop
      declare
         A   : constant String := Ada.Command_Line.Argument (I);
         Eq  : constant Natural := Fx.Index (A, "=");
         Opt : constant String := (if Eq > 0 then A (A'First .. Eq - 1) else A);
         Num : constant Boolean := Opt in "--ticks" | "--seed" | "--every" | "--crash-at" | "--more" | "--session-ticks" | "--max-sessions" | "--end-check-ticks" | "--since-session" | "--deadline" | "--reserve";
         Sep : constant Boolean := (Num or else Opt in "--max-hours" | "--home" | "--sim-print" | "--run-label" | "--say" | "--text" | "--as" | "--grant" | "--veto" | "--approve" | "--challenge" | "--debug-section" | "--chat-script" | "--visit" | "--visit-script") and then Eq = 0 and then I < Ada.Command_Line.Argument_Count;   --  --ticks 200
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
         elsif Opt = "--replay" then Replay_Opt := True;   --  0.058: replay from tick 1, the checkpoint is not loaded (it is written again)
         elsif Opt = "--yes" then Yes := True;
         elsif Opt = "--verbose" then Verbose := True;
         elsif Opt = "--report" then Report_Mode := True;
         elsif Opt = "--runlog" then Runlog_Mode := True;
         elsif Opt = "--trend" then Trend_Mode := True;
         elsif Opt = "--folder" then Folder_Mode := True;
         elsif Opt = "--continuous" then Night_Mode := True;
         elsif Opt = "--chat" then Chat_Mode := True;
         elsif Opt = "--chat-script" then Chat_Script_Opt := To_Unbounded_String (Val);
         elsif Opt = "--chatlog" then Chatlog_Mode := True;
         elsif Opt = "--wordstat" then Wordstat_Mode := True;
         elsif Opt = "--evolve" then Evolve_Mode := True;
         elsif Opt = "--frustration" then Frust_Mode := True;
         elsif Opt = "--active" then Active_Mode := True;
         elsif Opt = "--session-ticks" then Night_Ticks := Number (Opt, Val);
         elsif Opt = "--max-sessions" then Night_Sessions := Number (Opt, Val);
         elsif Opt = "--end-check-ticks" then End_Check_Max := Number (Opt, Val);
         elsif Opt = "--since-session" then Since_Session := Natural (Number (Opt, Val));
         elsif Opt = "--max-hours" then
            if Val'Length not in 1 .. 8 or else (for some C of Val => C not in '0' .. '9' | '.') or else Val (Val'First) = '.' or else Val (Val'Last) = '.'
              or else (for some I in Val'Range => Val (I) = '.' and then (for some J in Val'Range => J > I and then Val (J) = '.'))
            then raise Usage_Error with Msg ("err.number", Opt, Val); end if;
            Night_Hours := To_Unbounded_String (Val);
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
         elsif Opt = "--verify" then Ledger_Mode := True; Verify_View := True; Verify_Incr := True;
         elsif Opt = "--verify-full" then Ledger_Mode := True; Verify_View := True; Verify_Incr := False;
         elsif Opt = "--sim-print" then Sim_Print_Opt := To_Unbounded_String (Val);
         elsif Opt = "--deadline" then Deadline_Opt := Number (Opt, Val);
         elsif Opt = "--reserve" then Reserve_Opt := Number (Opt, Val);
         elsif Opt = "--run-label" then Run_Label := To_Unbounded_String (if Val = "" then "night" else Val);
         elsif Opt = "--elo" then Ledger_Mode := True; Elo_View := True;
         elsif Opt = "--voices" then Ledger_Mode := True; Voices_View := True;
         elsif Opt = "--govern" then Ledger_Mode := True; Govern_View := True;
         elsif Opt = "--veto" or else Opt = "--approve" then Veto_Mode := True; Veto_Approve := Opt = "--approve"; Veto_Opt := To_Unbounded_String (Val);
         elsif Opt = "--audit" then Ledger_Mode := True; Audit_View := True;
         elsif Opt = "--trials" then Ledger_Mode := True; Trial_View := True;
         elsif Opt = "--divergence" then Ledger_Mode := True; Rec_View := True;
         elsif Opt = "--dictionary" then Ledger_Mode := True; Dict_View := True;
         elsif Opt = "--ballots" then Ledger_Mode := True; Bal_View := True;
         elsif Opt = "--next" then Ledger_Mode := True; Next_View := True;
         elsif Opt = "--next-ticks" then Next_Ticks_Mode := True;
         elsif Opt = "--visit" then Visit_Mode := True; Visit_Opt := To_Unbounded_String (Val);
         elsif Opt = "--visit-script" then Visit_Script := To_Unbounded_String (Val);
         elsif Opt = "--challenge" then Challenge_Mode := True; Challenge_Opt := To_Unbounded_String (Val);
         elsif Opt = "--robot" then Ledger_Mode := True; Robot_View := True;
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
   if Length (Chat_Script_Opt) > 0 and then not Chat_Mode then raise Usage_Error with Msg ("chat.err.noscript"); end if;
   if Chat_Mode then   --  --chat: the night machinery with one paced session (--session-ticks N, default chat.session_ticks)
      Night_Mode := True;
      if Night_Sessions < 0 then Night_Sessions := 1; end if;
      if Length (Chat_Script_Opt) > 0 then
         declare
            Found : Boolean;
         begin
            Read_Lines (To_String (Chat_Script_Opt), Chat_Script, Found);
            if not Found then raise Usage_Error with Msg ("chat.err.script", To_String (Chat_Script_Opt)); end if;
            for I in reverse 1 .. Natural (Chat_Script.Length) loop
               if Script_At (Chat_Script.Element (I)) < 0 then Chat_Script.Delete (I); end if;   --  blank lines, # lines and anything without a leading number
            end loop;
         end;
      end if;
   end if;
   if Night_Mode and then (Ticks >= 0 or else More >= 0 or else Fresh or else Preview or else Visit_Mode or else Menu_Opt) then raise Usage_Error with Msg ("night.err.opts"); end if;
   if Length (Visit_Script) > 0 and then not Visit_Mode then raise Usage_Error with Msg ("visit.err.nocmd"); end if;
   if Visit_Mode then   --  --visit <name|id|1..4> [--more N]: the length defaults to visit.ticks of data/visit.txt
      declare
         T : constant String := Internal_Id (Ada.Characters.Handling.To_Lower (Fx.Trim (To_String (Visit_Opt), Ada.Strings.Both)));
      begin
         if T = "" then raise Usage_Error with Msg ("visit.err.nocmd"); end if;
         Visit_Who := Sim_Dharma.Find_Wesen (T);
         if Visit_Who = 0 and then T'Length = 1 and then T (T'First) in '1' .. '4' then Visit_Who := Natural'Value (T); end if;
         if Visit_Who = 0 then raise Usage_Error with Msg ("visit.err.who", To_String (Visit_Opt)); end if;
      end;
      if not Sim_Visit.Enabled then raise Usage_Error with Msg ("visit.err.off"); end if;
      if Length (Visit_Script) > 0 then
         begin
            TIO.Open (Script_File, TIO.In_File, To_String (Visit_Script));
            Script_On := True;
         exception
            when others => raise Usage_Error with Msg ("visit.err.script", To_String (Visit_Script));
         end;
      end if;
      if Ticks < 0 and then More < 0 then More := Int (Sim_Visit.Default_Ticks); end if;
   end if;
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
   Resolve_Home (Header => not (Menu_Wanted or else Inbox_Mode or else Map_Mode or else Ledger_Mode or else Grant_Mode or else Veto_Mode or else Challenge_Mode or else Next_Ticks_Mode or else Say_Mode or else Answer_Mode or else Report_Mode or else Runlog_Mode or else Trend_Mode or else Folder_Mode or else Wordstat_Mode or else Evolve_Mode or else Active_Mode or else Frust_Mode or else (Length (Section_Opt) > 0 and then not Preview)));
   Saved_Line := To_Unbounded_String (Msg ("saved", To_String (Home_Path)));
   if Map_Mode then
      Do_Map;
      Con.Put_Line (To_String (Saved_Line));
      return;
   elsif Folder_Mode then   --  make share: where the save folder is
      Con.Put_Line (To_String (Home_Path));
      return;
   elsif Runlog_Mode then   --  make runlog: the last lines of run_log.txt
      Print_Tail ("run_log.txt", "report.log_tail", "runlog.none");
      return;
   elsif Trend_Mode then    --  make trend: the last lines of trend.txt
      Print_Tail ("trend.txt", "report.trend_tail", "trend.none");
      return;
   elsif Chatlog_Mode then   --  make chatlog: the last lines of diaries/chat.txt
      Print_Chatlog;
      return;
   elsif Wordstat_Mode then   --  make wordstat: what the wesen know and where it came from (read-only)
      Print_Wordstat;
      return;
   elsif Evolve_Mode or else Active_Mode then   --  make evolve / make active: the evolution preview (read-only)
      Print_Wordstat (Evolve_Mode, Active_Mode);
      return;
   elsif Frust_Mode then   --  make frustration: the MiniMax report, refusals and mood per wesen, the load per player (read-only)
      Print_Frustration;
      return;
   elsif Night_Mode then    --  make night: sessions back to back, in this process (Night_Begin ... Night_End)
      if not Ada.Directories.Exists (Self_Exe) then raise Usage_Error with Msg ("night.err.exe", Self_Exe); end if;
      Night_Begin;
      Yes := True;
      Explicit := True;
      More := Night_Per;
      Every := Int'Max (1, Night_Per);
   elsif Report_Mode then   --  make report: the last run_report.txt as it is (already in display names)
      Print_Report;
      return;
   elsif Inbox_Mode then
      Con.Put (Inbox_Page);
      Con.Put_Line (To_String (Saved_Line));
      return;
   elsif Grant_Mode then
      Do_Grant;
      Con.Put_Line (To_String (Saved_Line));
      return;
   elsif Veto_Mode then
      Do_Veto;
      Con.Put_Line (To_String (Saved_Line));
      return;
   elsif Next_Ticks_Mode then
      Do_Next_Ticks;
      return;
   elsif Challenge_Mode then
      Do_Challenge;
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
   if Has_Diaries and then not Fresh and then not Verify_View then   --  0.058: the checkpoint, if it fits (else Ckpt_Why says why not)
      Ckpt_Probe;
   elsif Has_Diaries and then Verify_View and then Verify_Incr then   --  0.060: make verify: from the last verified checkpoint, if it fits
      Ckpt_Probe (Verified_Path);
      if Ckpt_Used then
         Verify_From := Ckpt_Tick;
      else
         Ckpt_Why := To_Unbounded_String (Msg ("verify.incr.none", To_String (Ckpt_Why)));
      end if;
   else
      Ckpt_Why := To_Unbounded_String (Msg (if Verify_View then "ckpt.why.verify" else "ckpt.why.missing"));
   end if;
   if Ckpt_Used then
      begin
         Disk_Seed := Ckpt_Seed;
         for E in Entity_Id loop
            Cur_Name := To_Unbounded_String (Name (E));
            Load_Diary_From (E, Ckpt_Off (E), Ckpt_Tick, Disk_Seed);   --  only the lines after the checkpoint's tick
         end loop;
      exception
         when Ex : others =>   --  the diary does not go on from the checkpoint: the whole diaries, as without one
            Ckpt_Used := False;
            Ckpt_Why := To_Unbounded_String (Msg ("ckpt.why.stale", Ada.Exceptions.Exception_Message (Ex)));
            Disk_Seed := -1;
            for E in Entity_Id loop
               Disk (E).Clear;
               Disk_Base (E) := 0;
            end loop;
      end;
   end if;
   for E in Entity_Id loop
      Cur_Name := To_Unbounded_String (Name (E));
      if not Ckpt_Used then Load_Diary (E, Disk_Seed); end if;
      Common := (if E = 1 then Disk_Len (E) else Natural'Min (Common, Disk_Len (E)));
      Longest := Natural'Max (Longest, Disk_Len (E));
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
      if Disk_Len (E) < Longest then
         Warn (Msg ("warn.behind", Name (E), Img (Integer (Disk_Len (E))), Img (Longest), Img (Common)));
      end if;
   end loop;

   --  Every run starts from the vocabulary and replays from tick 1.
   Sim_World.Init (Vocab, Seed, Start_Pct);
   Sim_Dharma.Init (Seed);
   Sim_Things.Init (Seed);
   Sim_Screen.Init (Seed, Coin_Cap);
   Sim_Games.Init (Seed);
   Sim_Robot.Init (Seed);
   Sim_Govern.Init (Seed);
   Sim_Preport.Init (Seed);
   Sim_Next.Init (Seed);
   Sim_Trial.Init (Seed);
   Sim_Records.Init (Seed);
   Sim_Visit.Init (Seed);
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
   Sim_Store.Open (Robot_Store, Robot_Path, "# seed " & Img (Seed));
   Robot_N := 0;
   Sim_Store.Open (Govern_Store, Govern_Path, "# seed " & Img (Seed));
   Load_Vetoes;
   Sim_Store.Open (Preport_Store, Preport_Path, "# seed " & Img (Seed));
   Sim_Store.Open (Next_Store, Next_Path, "# seed " & Img (Seed));
   Sim_Store.Open (Trial_Store, Trial_Path, "# seed " & Img (Seed));
   Sim_Store.Open (Votes_Store, Votes_Path, "# seed " & Img (Seed));
   Sim_Store.Open (Pets_Store, Pets_Path, "# seed " & Img (Seed));
   Sim_Store.Open (Dict_Store, Dict_Path, "# seed " & Img (Seed));
   Sim_Store.Open (Anns_Store, Anns_Path, "# seed " & Img (Seed));
   Sim_Store.Open (Bals_Store, Bals_Path, "# seed " & Img (Seed));
   Sim_Store.Open (Visit_Store, Visit_Path, "# seed " & Img (Seed));
   Load_Visit;
   Sim_Chat.Init (Seed);
   Sim_Store.Open (Chat_Store, Chat_Path, "# seed " & Img (Seed));
   Load_Chat;
   Sim_Store.Open (Active_Store, Active_Path, "# seed " & Img (Seed));
   Active_N := 0;
   Load_Active_Params;
   Load_Challenges;
   Set_Ledger_From;
   if Ent_Missing > 0 and then Ckpt_Used then   --  the replay writes the entity files again: it has to run
      Ckpt_Used := False;
      Ckpt_Why := To_Unbounded_String (Msg ("ckpt.why.stale", "entities/"));
      Sim_Ckpt.Clear (Ckpt_Data);
      Ckpt_Full_Diaries;
   end if;
   Ckpt_Restore;   --  0.058: the state of ticks 1 .. Ckpt_Tick from state.ckpt (or nothing, and Ckpt_Used is False)
   Sim_Util.Record_Keys (False);   --  0.059: what Init and the Load_* read from data/ (a module may keep it in its state)
   Sim_Util.Recorded_Keys (Start_Keys);
   if not Ledger_Mode then Write_Debug ("RUN", ""); end if;   --  stub: a kill -9 still leaves a file

   Sessions_Loop : loop   --  once for a normal run; a night run goes round once per session (the replay below only in the first)
   --  Phase 1: replay what every diary has (verify only), then confirm the import.
   Verify_To := (if Explicit then Natural'Min (Common, Natural (Ticks)) else Common);
   if Night_Done = 0 then
      Night_Phase := 0;
      Ckpt_Start_Line := To_Unbounded_String (Ckpt_Start_Text (Timed => Night_On));   --  0.058: how this start got its state
      if Ledger_Mode then
         null;
      elsif Night_On then
         Recent.Append (To_String (Ckpt_Start_Line));
         if not Tty_Out then Con.Put_Line_Now (To_String (Ckpt_Start_Line)); Flush_Out; end if;
      else
         Con.Put_Line (To_String (Ckpt_Start_Line));
      end if;
      if not Ledger_Mode then Ckpt_Log (Ckpt_Start_Text (Timed => True)); end if;
      if Ckpt_Used and then Length (Data_Note) > 0 and then not Ledger_Mode then   --  0.059: information, the checkpoint is loaded anyway
         if Night_On then
            Recent.Append (To_String (Data_Note));
            if not Tty_Out then Con.Put_Line_Now (To_String (Data_Note)); Flush_Out; end if;
         else
            Con.Put_Line (To_String (Data_Note));
         end if;
         Ckpt_Log (To_String (Data_Note));
      end if;
      if not Ckpt_Used and then Verify_To >= 1000 and then (Night_On or else Verify_View) then   --  0.060: what the replay will cost, first
         declare
            Src : Unbounded_String;
            Est : constant Duration := Replay_Estimate (Verify_To, Src);
            Lines : Str_Vectors.Vector;
         begin
            Lines.Append (Msg ("replay.est", Img (Verify_To), Img (Minutes_Up (Est)), To_String (Src)));
            if Deadline_Opt > 0 then
               declare
                  Late : constant Int := Unix_Now + Int (Est) + Reserve_Opt - Deadline_Opt;
               begin
                  if Late > 0 then Lines.Append (Msg ("replay.budget", Img (Minutes_Up (Est)), Img (Minutes_Up (Duration (Late))))); end if;
               end;
            end if;
            for L of Lines loop
               if Night_On then
                  Recent.Append (L);
                  if not Tty_Out then Con.Put_Line_Now (L); Flush_Out; end if;
               else
                  Con.Put_Line (L);
               end if;
               Ckpt_Log (L);
               if Night_On then Append_Log ("NIGHT", L & ASCII.LF); end if;
            end loop;
         end;
      end if;
      Replay_T0 := Ada.Calendar.Clock;
      if Ckpt_Used then
         Start_Sessions_At (Int (Ckpt_Tick));   --  a session the replay would begin at the checkpoint's tick
      else
         Check_Sessions_At (0);
      end if;
      for Tick in Int range (if Ckpt_Used then Int (Ckpt_Tick) + 1 else 1) .. Int (Verify_To) loop
         Do_Tick (Tick);
         Check_Sessions_At (Tick);
         if Replay_Wait_Ms > 0 then delay Duration (Replay_Wait_Ms) / 1000.0; end if;   --  tests only: a long replay on a small save
         if Replay_Progress > 0 and then Tick mod Int (Replay_Progress) = 0 then Progress_Line (Tick); end if;
         if Night_On and then Tick mod 8 = 0 then Night_Tick; end if;
         Quit_Seen := Sim_Quit.Requested or else (Night_On and then Sim_Quit.Key_Q);
         exit when Quit_Seen;
      end loop;
      if not Quit_Seen and then not Ckpt_Used and then Verify_To >= 1000 then   --  0.060: the measurement for the next estimate
         declare
            D : constant Duration := Since (Replay_T0);
         begin
            Ckpt_Log (Msg ("replay.done", Img (Verify_To), Tenths_Text (D), Img (Int (Float (Verify_To) / Float (Duration'Max (0.1, D))))));
         end;
      end if;
   end if;
   if not Quit_Seen then
      declare
         Total : Natural := 0;
      begin
         for E in Entity_Id loop Total := Total + Disk_Len (E); end loop;
         Import_Done := True;
         Import_Block := To_Unbounded_String (Import_Text (Total));
         if not Ledger_Mode then Con.Put_Line (To_String (Import_Block)); end if;
      end;
      if Ledger_Mode then   --  replayed and verified, nothing decided, nothing written: print the ledger
         for F of Out_File loop TIO.Close (F); end loop;
         for F of Side_Out loop TIO.Close (F); end loop;
         if Verify_View then   --  the files of the whole history against the replay: the checks of the end of a run, nothing written
            Verify_Inbox (Last_Done);
            Verify_Edits (Last_Done);
            Verify_Grants (Last_Done);
            Verify_Screens (Last_Done);
            Verify_Chess (Last_Done);
            Verify_Robot (Last_Done);
            Verify_Govern (Last_Done);
            Verify_Preport (Last_Done);
            Verify_Next (Last_Done);
            Verify_Trial (Last_Done);
            Verify_Records (Last_Done);
            Verify_Visit (Last_Done);
            Verify_Chat (Last_Done);
            Verify_Active (Last_Done);
            if Verify_From > 0 then   --  0.060: incremental: the ticks after the last verified checkpoint
               Con.Put_Line (Msg ("verify.ok.incr", Img (Verify_From + 1), Img (Verify_To), Img (Verify_From), Img (Integer (Sessions.Length)),
                                  Tenths_Text (Ada.Calendar."-" (Ada.Calendar.Clock, T_Run))));
            else
               Con.Put_Line (Msg ("verify.ok", Img (Verify_To), Img (Integer (Sessions.Length)), Tenths_Text (Ada.Calendar."-" (Ada.Calendar.Clock, T_Run))));
            end if;
            Con.Put_Line (Ckpt_Verify);   --  0.058: the checkpoint against the state the replay has just rebuilt
            if not Ckpt_Verify_Diff then   --  0.059: passed: run_log.txt says so (checkin.txt: last full verify), a fresh checkpoint
               if Verify_From > 0 then
                  Append_Log ("VERIFY", Msg ("verify.log.incr", Img (Verify_From + 1), Img (Verify_To), Img (Integer (Sessions.Length)), Tenths_Text (Ada.Calendar."-" (Ada.Calendar.Clock, T_Run))));
               else
                  Append_Log ("VERIFY", Msg ("verify.log", Img (Verify_To), Img (Integer (Sessions.Length)), Tenths_Text (Ada.Calendar."-" (Ada.Calendar.Clock, T_Run))));
               end if;
               Write_Verify_Stamp (Verify_From = 0, Verify_From, Verify_To);
               Ckpt_Write;
               if Ckpt_Written > 0 then
                  Con.Put_Line (Msg ("ckpt.verify.written", Img (Last_Done), Img (Ckpt_Bytes / 1024), Secs_Text (Ckpt_Write_Secs)));
                  begin   --  0.060: the next make verify starts here
                     Ada.Directories.Copy_File (Ckpt_Path, Verified_Path & ".tmp");
                     if Ada.Directories.Exists (Verified_Path) then Ada.Directories.Delete_File (Verified_Path); end if;
                     Ada.Directories.Rename (Verified_Path & ".tmp", Verified_Path);
                     Ckpt_Log (Msg ("verify.verified.written", Img (Last_Done)));
                  exception
                     when others => null;
                  end;
               end if;
            end if;
         elsif Voices_View then Con.Put (Voices_Text); elsif Elo_View then Con.Put (Elo_Text); elsif Govern_View then Con.Put (Govern_Text); elsif Audit_View then Con.Put (Audit_Text); elsif Next_View then Con.Put (Next_Text); elsif Trial_View then Con.Put (Trials_Text); elsif Rec_View then Con.Put (Lines_Text (Sim_Records.Divergence)); elsif Dict_View then Con.Put (Lines_Text (Sim_Records.Dictionary)); elsif Bal_View then Con.Put (Lines_Text (Sim_Records.Ballots)); elsif Robot_View then Con.Put (Robot_Text); elsif Screens_View then Con.Put (Screens_Text); else Con.Put_Line (Sim_Ledger.Report (Seed, Ledger_From, Ledger_Full)); end if;
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
      if Night_On and then Night_Done = 0 and then not Sessions.Is_Empty then   --  make night / checkin: the replay is over, the NEW sessions begin
         declare
            Lv : constant String := Token (Session_Line (Sessions.Last_Element), "active");
         begin
            Night_Replay_Line := To_Unbounded_String
              (Msg ("night.replay_done", Img (Verify_To), Img (Base_S), Tenths_Text (Since (Night_T0)), Img (Sessions.Last_Element.N), Img (Verify_To + 1),
                    (if Lv = "" then Msg ("night.active_off") else "active=" & Lv)));
            Append_Log ("NIGHT", To_String (Night_Replay_Line) & ASCII.LF & To_String (Ckpt_Start_Line) & ASCII.LF);
            if not Tty_Out then Con.Put_Line_Now (To_String (Night_Replay_Line)); Flush_Out; end if;
         end;
      end if;
      Con.Put_Line (To_String (Kalpa_Line));
      if Visit_Mode and then Visit_Active then Con.Put_Line (Msg ("visit.start", Name (Visit_E), Img (Visit_End - Visit_Start))); end if;
   end if;

   --  Phase 2: the rest of the run (ticks beyond the common tick are appended where missing).
   if not Quit_Seen then
      Night_Phase := 1;
      S_Start := Ada.Calendar.Clock;
      for Tick in Int range Int (Verify_To) + 1 .. Ticks loop
         Do_Tick (Tick);
         if Tick_Wait_Ms > 0 then delay Duration (Tick_Wait_Ms) / 1000.0; end if;   --  tests only
         if Night_On and then (Chat_Mode or else Tick mod 8 = 0) then Night_Tick; end if;
         Check_Dharma_At (Tick);   --  a stored session end beyond the common tick (a diary was behind)
         if Tick > Int (Common) and then Tick mod Every = 0 and then not (Visit_Mode and then Visit_Active and then not Visit_Left) then
            Con.Put_Line (Msg ("progress", Img (Tick), Img (Ticks), Img (Integer (Entity_Id'Last)), Img (Events)));
            Write_Debug ("RUN", "");   --  refresh the stub
         end if;
         Quit_Seen := Sim_Quit.Requested or else (Chat_Mode and then Sim_Quit.Key_Q);   --  --chat: q stops at the next tick (a rerun resumes the session)
         exit when Quit_Seen;
      end loop;
      Loop_End := Ada.Calendar.Clock;
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
      Verify_Robot (Last_Done);
      Verify_Govern (Last_Done);
      Verify_Preport (Last_Done);
      Verify_Next (Last_Done);
      Verify_Trial (Last_Done);
      Verify_Records (Last_Done);
      Verify_Visit (Last_Done);
      Verify_Chat (Last_Done);
      Verify_Active (Last_Done);
      if not Night_On or else Night_Ckpt_Due then Ckpt_Write; end if;   --  0.058: the state of this session end (a night: see Night_Ckpt_Due)
   end if;
   if Quit_Seen and then Last_Done > Int (Common) then Ckpt_Write; end if;   --  a clean stop inside the session: the state of its last tick
   if Quit_Seen then   --  Ctrl-C / SIGTERM / SIGHUP: everything written so far is flushed; a rerun resumes
      declare
         By_Key : constant Boolean := Night_On and then not Sim_Quit.Requested;   --  q during the replay of the first session: nothing new exists
      begin
         if Night_On then Night_Release (Tail => False); end if;
         if By_Key then
            Con.Put_Line (Msg ((if Chat_Mode and then Night_Phase /= 0 then "chat.q.stopped" else "night.q.stopped"), Img (Last_Done), Img (Verify_To)));
         else
            Con.Put_Line (Msg ("quit", Sim_Quit.Which, Img (Last_Done)));
         end if;
         Write_Petitions;
         Write_Debug ("QUIT", Msg ("debug.quit", (if By_Key then "q" else Sim_Quit.Which), Img (Last_Done)));
         if not By_Key and then not Ledger_Mode then Con.Put_Line (Msg ("debug.attach")); end if;
         Put_Saved;
         if By_Key then
            Night_End ("q");
         else
            Ada.Command_Line.Set_Exit_Status (130);
            Night_End ("signal");
         end if;
         return;
      end;
   end if;

   declare
      Console, Text, Json, Rep, Fails : Unbounded_String;
      Marks : Str_Vectors.Vector;   --  "name:offset in Rep": where each section of the report starts (the headers of run_report.txt)
      Brief_A, Brief_B, Brief_C : Natural := 0;   --  Rep offsets for the short console form: the entity table ends at Brief_A, the action table at Brief_B, the session lines at Brief_C
      procedure Mark (Name : String) is
      begin
         Marks.Append (Name & ":" & Img (Length (Rep)));
      end Mark;
      D_Files, D_Lines, E_Files, N, Js_Lines : Natural := 0;
      procedure Save (File : String; Content : Unbounded_String) is
         F : TIO.File_Type;
      begin
         TIO.Create (F, TIO.Out_File, File);
         TIO.Put (F, Sim_World.Show (To_String (Content)));
         TIO.Flush (F);
         TIO.Close (F);
      end Save;
      Show_All : constant Boolean := Verbose or else GNAT.OS_Lib.Getenv ("DIARY_VERBOSE").all = "1";   --  the whole report on the console
      Trace_Text : Unbounded_String;                                                               --  the @@TRACE marker block (2 lines)

      --  run_report.txt: ALWAYS the complete report (the previous one is kept as run_report_prev.txt), in sections with "== name ==" header
      --  lines and, on the first two lines, the @@TRACE marker (build, seed, session, ticks, anomalies, files) and @@SECTIONS (name=line of
      --  the headers), so that grep finds what it needs.  The anomalies are information only (data/limits.txt report.warn_*): nothing in
      --  the simulation reads them.  The console shows the same marker in its short form.
      procedure Report_Out is
         Body_T, Index, Anom, Boxes_T : Unbounded_String;
         Ln : Natural := 3;   --  the next line of run_report.txt (the marker takes lines 1 and 2)
         Items : Str_Vectors.Vector;
         procedure Sect (Name, Text : String) is
            Lf : Natural := 0;
         begin
            if Text'Length = 0 then return; end if;
            Append (Index, (if Length (Index) > 0 then "," else "") & Name & "=" & Img (Ln));
            Append (Body_T, "== " & Name & " ==" & ASCII.LF & Text);
            for C of Text loop if C = ASCII.LF then Lf := Lf + 1; end if; end loop;
            if Text (Text'Last) /= ASCII.LF then Append (Body_T, ASCII.LF); Lf := Lf + 1; end if;
            Ln := Ln + 1 + Lf;
         end Sect;
      begin
         Sect ("import", To_String (Import_Block) & ASCII.LF & To_String (Kalpa_Line) & ASCII.LF);
         for I in 1 .. Natural (Marks.Length) loop
            declare
               M : constant String := Marks (I);
               Cut : constant Natural := Fx.Index (M, ":");
               From : constant Natural := Natural'Value (M (Cut + 1 .. M'Last));
               N_M : constant String := (if I < Natural (Marks.Length) then Marks (I + 1) else "");
               To : constant Natural := (if N_M = "" then Length (Rep) else Natural'Value (N_M (Fx.Index (N_M, ":") + 1 .. N_M'Last)));
            begin
               if To > From then Sect (M (M'First .. Cut - 1), To_String (Unbounded_Slice (Rep, From + 1, To))); end if;
            end;
         end loop;
         Sect ("votes", To_String (Console));
         Sect ("ledger", Sim_Ledger.Report (Seed, Ledger_From, True) & ASCII.LF);
         Append (Boxes_T, Msg ("debug.attach") & ASCII.LF);
         Append (Boxes_T, Msg ("pet.file", Img (Integer'Min (Petition_Total, Integer (Limit ("propose.file_cap", 40)))),
                               Img (Petition_Total), Ada.Directories.Full_Name ("petitions.txt")) & ASCII.LF);
         Append (Boxes_T, Msg ("pet.attach") & ASCII.LF);
         Append (Boxes_T, To_String (Saved_Line) & ASCII.LF);
         if Preport_Active then Append (Boxes_T, Sim_Preport.Boxes (Ticks, Mood_Now, Pets_Now, Next_Extra (Ticks)));
         elsif Next_Active then for X of Next_Extra (Ticks) loop Append (Boxes_T, X & ASCII.LF); end loop; end if;
         Sect ("tail", To_String (Boxes_T));
         for E in Entity_Id loop   --  anomalies: information only
            if Int (St (E).Energy) < Limit ("report.warn_energy", 25) then Items.Append ("energy<" & Img (Limit ("report.warn_energy", 25)) & ":" & Sim_World.Show (Name (E))); end if;
            if Int (St (E).Mood) < Limit ("report.warn_mood", -50) then Items.Append ("mood<" & Img (Limit ("report.warn_mood", -50)) & ":" & Sim_World.Show (Name (E))); end if;
         end loop;
         if Warnings > 0 then Items.Append ("warnings:" & Img (Warnings)); end if;
         if Length (Fails) > 0 then Items.Append ("export-failed"); end if;
         if Items.Is_Empty then
            Anom := To_Unbounded_String ("none");
         else
            Anom := To_Unbounded_String (Img (Natural (Items.Length)) & "[");
            for I in 1 .. Natural'Min (3, Natural (Items.Length)) loop Append (Anom, (if I > 1 then "," else "") & Items (I)); end loop;
            Append (Anom, "]");
         end if;
         Trace_Text := To_Unbounded_String
           ("@@TRACE build=" & Build & " seed=" & Img (Seed) & " session=" & Img (Session_N) & " ticks=" & Img (Int'Min (Int (Common) + 1, Ticks)) & ".." & Img (Ticks)
            & " anomalies=" & To_String (Anom) & " files=run_report.txt,debug.txt,summary.txt,summary.jsonl,petitions.txt,diaries/,entities/"
            & (if Preport_Active then ",player_reports.txt" else "") & (if Ada.Directories.Exists ("run_report.txt") then ",run_report_prev.txt" else "") & ASCII.LF
            & "@@SECTIONS " & To_String (Index) & ASCII.LF);
         begin
            if Ada.Directories.Exists ("run_report.txt") then
               if Ada.Directories.Exists ("run_report_prev.txt") then Ada.Directories.Delete_File ("run_report_prev.txt"); end if;
               Ada.Directories.Copy_File ("run_report.txt", "run_report_prev.txt");
            end if;
         exception
            when others => null;   --  the previous report is a nicety
         end;
         Save ("run_report.txt", Trace_Text & Body_T);
         Append_Log ("RUN", To_String (Trace_Text) & "report: " & Ada.Directories.Full_Name ("run_report.txt") & ASCII.LF);
         if Ticks > Int (Common) then   --  a session that added ticks: its line in trend.txt
            declare
               Mo, En, Wo, Pe : Unbounded_String;
               --  0.057: the speed of this session (wall clock, new lines only): secs = from its first new tick to here (end report included),
               --  loop = the tick loop alone, tps = new ticks per second of the loop
               function Speed_Text return String is
                  Whole : constant Duration := Ada.Calendar."-" (Ada.Calendar.Clock, S_Start);
                  Lp : constant Duration := Ada.Calendar."-" (Loop_End, S_Start);
                  N : constant Int := Ticks - Int (Common);
               begin
                  if Lp <= 0.0 or else Whole <= 0.0 then return ""; end if;
                  return " secs=" & Tenths_Text (Whole) & " loop=" & Tenths_Text (Lp) & " tps=" & Img (Int (Float (N) / Float (Lp)));
               exception
                  when others => return "";
               end Speed_Text;
            begin
               for E in Entity_Id loop
                  Append (Mo, (if E = Entity_Id'First then "" else ",") & Img (St (E).Mood));
                  Append (En, (if E = Entity_Id'First then "" else ",") & Img (St (E).Energy));
                  Append (Wo, (if E = Entity_Id'First then "" else ",") & Img (Known_Count (E)));
                  Append (Pe, (if E = Entity_Id'First then "" else ",") & Img (Petitions_Of (E)));
               end loop;
               Append_Trend ("T session=" & Img (Session_N) & " tick=" & Img (Ticks) & " time=" & Local_Stamp & " elapsed=" & Tenths_Text (Ada.Calendar."-" (Ada.Calendar.Clock, T_Run)) & " size=" & Img (Folder_Bytes (".")) & " mood=" & To_String (Mo)
                             & " energy=" & To_String (En) & " words=" & To_String (Wo) & " pets=" & To_String (Pe) & Sim_Records.Trend
                             & " trials=" & Img (Sim_Trial.Count) & " anomalies=" & Img (Natural (Items.Length)) & Speed_Text);
            end;
         end if;
      end Report_Out;
   begin
      Summarize (Seed, Ticks, Votes_Of, Console, Text, Json);
      Save ("summary.txt", Text);
      Save ("summary.jsonl", Json);
      --  Export check: re-open and count what is on disk now.
      for E in Entity_Id loop
         Check_File (Path (E), Natural'Max (Disk_Len (E), Natural (Ticks)), 'd', N, Fails);
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
      Marks.Append ("report:0");
      for E in Entity_Id loop
         Append (Rep, Fx.Head (Name (E), 10) & Fx.Tail (Img (Start_Known (E)), 8) & " ->" & Fx.Tail (Img (Known_Count (E)), 6)
                 & Fx.Tail (Img (Run_Learn (E)), 9) & Fx.Tail (Img (Run_Coin (E)), 7) & Fx.Tail (Img (Run_Bench_N (E)), 6)
                 & " | " & Fx.Tail (Sgn (Int (St (E).Mood)), 5) & Fx.Tail (Img (St (E).Energy), 7)
                 & Fx.Tail (Img (Petitions_Of (E)), 5) & ASCII.LF);
      end loop;
      Brief_A := Length (Rep);
      Mark ("actions");
      Append (Rep, Msg ("report.mixcols") & ASCII.LF);
      for E in Entity_Id loop
         Append (Rep, Fx.Head (Name (E), 10));
         for A in Action loop Append (Rep, Fx.Tail (Img (Act_Count (E, A)), (if A in Explore | Propose then 8 else 7))); end loop;
         Append (Rep, ASCII.LF);
      end loop;
      Brief_B := Length (Rep);
      Mark ("petitions");
      declare
         Per : Unbounded_String;
      begin
         for E in Entity_Id loop
            Append (Per, (if E = 1 then "" else " ") & Name (E) & " " & Img (Petitions_Of (E)));
         end loop;
         Append (Rep, Msg ("report.pet", Img (Petition_Total), To_String (Per), Top_Topics (3)) & ASCII.LF);
      end;
      Mark ("session");
      Since_Head := To_Unbounded_String (Since_Text);
      Append (Rep, Since_Head);
      Brief_C := Length (Rep);
      if World_Active then   --  the treadmill: where the wesen are and what lies around them
         Mark ("treadmill");
         Append (Rep, Msg ("map.head", Img (Ticks)) & ASCII.LF);
         for L of Sim_Things.Treadmill_Now loop Append (Rep, L & ASCII.LF); end loop;
      end if;
      if Rest_Active then   --  recovery: rate, cool-downs taken, rests cut short
         Mark ("recovery");
         Append (Rep, Msg ("rest.head") & ASCII.LF);
         for E in Entity_Id loop Append (Rep, Rest_Text (E) & ASCII.LF); end loop;
      end if;
      if Screen_Active then   --  the screens: shown / left / read, and the words they taught and coined
         Mark ("screens");
         Append (Rep, Msg ("screen.rep") & ASCII.LF);
         for E in Entity_Id loop Append (Rep, Sim_Screen.Summary (E) & ASCII.LF); end loop;
      end if;
      if Chess_Active then   --  chess: ratings and results per competitor, then every game with its moves
         Mark ("chess");
         Append (Rep, Msg ("chess.rep") & ASCII.LF);
         for C in Sim_Games.Comp_Id loop Append (Rep, Sim_Games.Summary (C) & ASCII.LF); end loop;
         Append (Rep, Msg ("chess.head") & ASCII.LF);
         for L of Sim_Games.Report (True) loop Append (Rep, Game_Names (L) & ASCII.LF); end loop;
      end if;
      if Robot_Active then   --  the robot: state, commands and errors per wesen
         Mark ("robot");
         for L of Sim_Robot.Report loop Append (Rep, L & ASCII.LF); end loop;
      end if;
      if Govern_Active then   --  the players' decisions: counts per player, trust and standing, the last decisions
         Mark ("governance");
         Append (Rep, Msg ("govern.rep") & ASCII.LF);
         for P in Sim_Dharma.Player_Id range 1 .. Sim_Dharma.Last_Player loop
            Append (Rep, Msg ("govern.player", Sim_Dharma.Player_Name (P), Sim_Govern.Counter_Line (P)) & ASCII.LF);
         end loop;
         for E in Entity_Id loop
            Append (Rep, "  " & Msg ("govern.wesen", Name (E), Img (Sim_Govern.Trust_Of (E)), Img (Sim_Govern.Standing_Of (E)),
                                    Sgn (Int (Sim_Govern.Off (E, Sim_Govern.Rate))), Sgn (Int (Sim_Govern.Off (E, Sim_Govern.Cool))),
                                    Sgn (Int (Sim_Govern.Off (E, Sim_Govern.Work))), Sgn (Int (Sim_Govern.Off (E, Sim_Govern.Quick)))) & ASCII.LF);
         end loop;
      end if;
      if not Robot_Active or else not Govern_Active then   --  one line: why a block is missing (robot / governance)
         declare
            R : constant String := (if Robot_Active then "" else Msg ("robot.off", Msg ((if Robot_Wanted then "off.session" else "off.data"), "robot")));
            G : constant String := (if Govern_Active then "" else Msg ("govern.off", Msg ((if Govern_Wanted then "off.session" else "off.data"), "govern")));
         begin
            Append (Rep, R & (if R'Length > 0 and then G'Length > 0 then ", " else "") & G & ASCII.LF);
         end;
      end if;
      if not Grant_Report.Is_Empty then   --  granted petitions and the recovery rates they changed
         Mark ("grants");
         Append (Rep, Msg ("grant.head") & ASCII.LF);
         for L of Grant_Report loop Append (Rep, L & ASCII.LF); end loop;
      end if;
      Mark ("words");
      if Length (Words_Text) > 0 then Append (Rep, To_String (Words_Text) & ASCII.LF); end if;
      Mark ("dharma");
      for L of Sim_Dharma.Table_Lines loop Append (Rep, L & ASCII.LF); end loop;
      for L of Sim_Dharma.Since_Lines loop Append (Rep, L & ASCII.LF); end loop;
      if not Sim_Dharma.Table_Lines.Is_Empty then
         Append (Rep, Msg ("since.players", Sim_Dharma.Address_Counts (Int (Common))) & ASCII.LF);
      end if;
      if not Sim_Dharma.Latest_Report.Is_Empty then
         Mark ("inbox");
         Append (Rep, Msg ("inbox.head", Img (Integer (Sim_Dharma.Latest_Report.Length)), Img (Sim_Dharma.Inbox_Count)) & ASCII.LF);
         for L of Sim_Dharma.Latest_Report loop Append (Rep, L & ASCII.LF); end loop;
         Append (Rep, Msg ("inbox.answer") & ASCII.LF);
      end if;
      Mark ("export");
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
      if Preport_Active then Save ("player_reports.txt", To_Unbounded_String (Sim_Preport.Boxes (Ticks, Mood_Now, Pets_Now, Next_Extra (Ticks)))); end if;
      Report_Out;
      if not Ada.Directories.Exists ("run_report.txt") or else Ada.Directories.Size ("run_report.txt") = 0 then
         Append (Rep, Msg ("export.failed", "run_report.txt not written") & ASCII.LF);
         Ada.Command_Line.Set_Exit_Status (1);
      end if;
      Write_Petitions;
      if Visit_Mode and then Visit_Active then
         Con.Put_Line (Msg ("visit.done", Name (Visit_E), Img (Sim_Visit.Commands), Sgn (Int (Sim_Visit.Bond_Of (Visit_E)))));
      end if;
      Write_Debug ((if Length (Fails) = 0 then "OK" else "DRIFT"), (if Length (Fails) = 0 then "" else "error: " & To_String (Export_Line)));
      if Show_All then   --  --verbose: everything, as before
         Con.Put (To_String (Rep));
         Con.Put (To_String (Console));
         Con.Put_Line (Msg ("debug.attach"));
         Con.Put_Line (Msg ("pet.file", Img (Integer'Min (Petition_Total, Integer (Limit ("propose.file_cap", 40)))),
                            Img (Petition_Total), Ada.Directories.Full_Name ("petitions.txt")));
         Con.Put_Line (Msg ("pet.attach"));
         Put_Saved;
         if Preport_Active then Put_Frames (Sim_Preport.Boxes (Ticks, Mood_Now, Pets_Now, Next_Extra (Ticks)));
         elsif Next_Active then for X of Next_Extra (Ticks) loop Con.Put_Line (Sim_World.Show (X)); end loop; end if;   --  the last thing Robert sees: the boxes of the players
      else   --  the short form: entity table, petitions, session lines, the boxes of the players (no marker and no pointer: the technical lines are in run_log.txt)
         Con.Put (To_String (Unbounded_Slice (Rep, 1, Brief_A)));
         Con.Put (To_String (Unbounded_Slice (Rep, Brief_B + 1, Brief_C)));
         if Length (Fails) > 0 then Con.Put_Line (To_String (Export_Line)); end if;
         if Length (Digest_Note) > 0 then Con.Put_Line (To_String (Digest_Note)); end if;
         if Preport_Active then Put_Frames (Sim_Preport.Boxes (Ticks, Mood_Now, Pets_Now, Next_Extra (Ticks)));
         elsif Next_Active then for X of Next_Extra (Ticks) loop Con.Put_Line (Sim_World.Show (X)); end loop; end if;
      end if;
   end;
   exit Sessions_Loop when not Night_On or else Night_After_Session;

   --  The next session of a night run starts where this one ended: the world goes on in memory (see Night_Next_Session).
   Night_Next_Session;
   end loop Sessions_Loop;
   Night_End (To_String (Night_Why));
exception
   when E : Usage_Error =>
      if Night_On then Night_Release (Tail => False); Night_End ("error"); end if;
      TIO.Put_Line (TIO.Standard_Error, Ada.Exceptions.Exception_Message (E));
      Write_Debug ("USAGE", "error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (2);
   when E : Drift_Error =>   --  stored lines differ from the replay: an expected stop, no traceback
      if Night_On then Night_Release (Tail => True); end if;
      Validation_Stop (Ada.Exceptions.Exception_Message (E), True);
      Night_End ("drift");
   when E : Diary_Error =>   --  bad diary, seed mismatch, misplaced folder: also an expected stop
      if Night_On then Night_Release (Tail => True); end if;
      Validation_Stop (Ada.Exceptions.Exception_Message (E), False);
      Night_End ("error");
   when E : others =>
      if Night_On then Night_Release (Tail => True); end if;
      if not Import_Done then Con.Put_Line (Msg ("import.failed", Ada.Exceptions.Exception_Message (E))); end if;
      if Import_Done then Write_Petitions; end if;
      Write_Debug ("CRASH", Error_Brief (E));
      Report (E);
      Write_Digest ("CRASH", Error_Brief (E));   --  again: last_error.txt exists now
      if Length (Digest_Note) > 0 then Con.Put_Line (To_String (Digest_Note)); end if;
      Ada.Command_Line.Set_Exit_Status (1);
      Night_End ("error");
end Diary_Sim;
