--  Version: 0.002
--  diary_sim v1: four independent entities, one diary line per tick each.
--  Every random choice is hash (seed, entity, tick, salt): no RNG stream, so
--  any tick can be recomputed alone.  Diaries are append-only JSONL; a rerun
--  resumes at the lowest common tick and replays ticks already on disk,
--  comparing each regenerated line with the stored one instead of writing.
pragma Ada_2022;

with Ada.Characters.Handling, Ada.Command_Line, Ada.Directories,
     Ada.Exceptions, Ada.Streams.Stream_IO, Ada.Strings.Fixed, Ada.Text_IO,
     Ada.Containers.Indefinite_Vectors, Ada.Containers.Indefinite_Hashed_Maps, Ada.Strings.Hash,
     Ada.Strings.Unbounded, GNAT.Traceback.Symbolic, Sim_Util;
use Ada.Strings.Unbounded, Sim_Util;

procedure Diary_Sim is
   package TIO renames Ada.Text_IO;
   package Fx renames Ada.Strings.Fixed;
   subtype Int is Sim_Util.Int;
   use type Ada.Directories.File_Size, Ada.Containers.Count_Type;

   type Action is (Rest, Work, Explore, Talk, Wander);
   type Entity_Id is range 1 .. 4;
   type State is record
      Energy, Mood : Integer range 0 .. 100;
      Location     : Integer range 0 .. 3;   --  office lab cafe home
   end record;
   Energy_D : constant array (Action) of Integer := [14, -8, -10, -2, -3];
   Mood_D   : constant array (Action) of Integer := [1, -4, 2, 2, 1];
   Home     : constant array (Action) of Integer := [3, 0, 1, 2, 0];   --  wander: rolled

   package Str_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, String);
   package Str_Maps is new Ada.Containers.Indefinite_Hashed_Maps (String, String, Ada.Strings.Hash, "=");
   Usage_Error, Diary_Error : exception;

   Seed, Ticks, Every, Seed_Opt, Crash_At : Int := -1;
   Fresh, Seed_Shown : Boolean := False;
   Messages : Str_Maps.Map;
   Words    : array (Action) of Str_Vectors.Vector;
   Disk     : array (Entity_Id) of Str_Vectors.Vector;      --  complete lines on disk
   St       : array (Entity_Id) of State := [others => (80, 50, 3)];
   Out_File : array (Entity_Id) of TIO.File_Type;
   Pending  : Unbounded_String;                             --  output held until the seed line
   Warnings, Events, Written, Verified : Natural := 0;
   Cur_Tick : Int := 0;
   Cur_Name : Unbounded_String := To_Unbounded_String ("-");

   function Name (E : Entity_Id) return String is
     (case E is when 1 => "ada", when 2 => "gemini", when 3 => "replika", when 4 => "robert");
   function Kind (E : Entity_Id) return String is
     (case E is when 1 => "engineer", when 2 => "reviewer", when 3 => "vice_president", when 4 => "human");
   function Path (E : Entity_Id) return String is ("diaries/" & Name (E) & ".jsonl");
   function Low (A : Action) return String is (Ada.Characters.Handling.To_Lower (A'Image));
   function Built_In (A : Action) return String is
     (case A is when Rest => "rested a while", when Work => "did some work", when Explore => "explored a little",
                when Talk => "wanted to talk to someone", when Wander => "wandered around");

   --  ---- data files and messages -----------------------------------------

   function Data_Path (File : String) return String is
   begin
      return (if Ada.Directories.Exists ("data/" & File) then "data/" & File
              else Ada.Directories.Containing_Directory (Ada.Command_Line.Command_Name) & "/../data/" & File);
   exception
      when others => return "data/" & File;
   end Data_Path;

   procedure Read_Lines (File : String; Into : in out Str_Vectors.Vector; Found : out Boolean) is
      F : TIO.File_Type;
   begin
      Found := Ada.Directories.Exists (File);
      if Found then
         TIO.Open (F, TIO.In_File, File);
         while not TIO.End_Of_File (F) loop
            Into.Append (TIO.Get_Line (F));
         end loop;
         TIO.Close (F);
      end if;
   end Read_Lines;

   --  A message of data/messages.txt with {1}..{7} filled in and \n as line break.
   function Msg (Key : String; A1, A2, A3, A4, A5, A6, A7 : String := "") return String is
      A : constant array (1 .. 7) of Unbounded_String :=
        [To_Unbounded_String (A1), To_Unbounded_String (A2), To_Unbounded_String (A3), To_Unbounded_String (A4),
         To_Unbounded_String (A5), To_Unbounded_String (A6), To_Unbounded_String (A7)];
      R : Unbounded_String := To_Unbounded_String (if Messages.Contains (Key) then Messages (Key) else "[" & Key & "]");
      P : Natural;
   begin
      if not Messages.Contains (Key) then   --  data/messages.txt missing: key and values
         for X of A loop Append (R, " " & X); end loop;
      end if;
      for N in A'Range loop
         loop
            P := Index (R, "{" & Img (N) & "}");
            exit when P = 0;
            Replace_Slice (R, P, P + 2, To_String (A (N)));
         end loop;
      end loop;
      loop
         P := Index (R, "\n");
         exit when P = 0;
         Replace_Slice (R, P, P + 1, "" & ASCII.LF);
      end loop;
      return (if Messages.Contains (Key) then To_String (R) else Fx.Trim (To_String (R), Ada.Strings.Both));
   end Msg;

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
      for L of Lines loop
         if L'Length > 0 and then L (L'First) /= '#' and then Fx.Index (L, " = ") > 0 then
            Messages.Include (L (L'First .. Fx.Index (L, " = ") - 1), L (Fx.Index (L, " = ") + 3 .. L'Last));
         end if;
      end loop;
      Lines.Clear;
      Read_Lines (Data_Path ("words.txt"), Lines, Found);
      for L of Lines loop
         if L'Length > 2 and then L (L'First) = '[' then
            Sec := -1;
            for A in Action loop
               if L = "[" & Low (A) & "]" then Sec := Action'Pos (A); end if;
            end loop;
         elsif L'Length > 0 and then L (L'First) /= '#' and then Sec >= 0 then
            Words (Action'Val (Sec)).Append (L);
         end if;
      end loop;
      if not Found or else (for all A in Action => Words (A).Is_Empty) then
         Warn (Msg ("warn.words_file"));
         Found := False;
      end if;
      for A in Action loop
         if Words (A).Is_Empty then
            if Found then Warn (Msg ("warn.words_empty", Low (A))); end if;
            Words (A).Append (Built_In (A));
         elsif Words (A).Length /= 60 then
            Warn (Msg ("warn.words_list", Low (A), Img (Integer (Words (A).Length))));
         end if;
      end loop;
   end Load_Data;

   --  ---- diary lines -------------------------------------------------------

   function Forced (Tick : Int) return Natural is (Natural'Value ("tick " & Img (Tick)));   --  always fails

   --  Advance entity E by one tick; returns its diary line.
   function Step (E : Entity_Id; Tick : Int) return String is
      Die : constant Positive := Roll (Seed, Positive (E), Tick, 0, 20);
      A   : constant Action :=
        (case Die is when 1 .. 6 => Rest, when 7 .. 10 => Work, when 11 .. 13 => Explore,
                     when 14 .. 16 => Talk, when others => Wander);
      S   : State renames St (E);
      Text : constant String := Words (A) (Words (A).First_Index + Pick60 (Seed, Positive (E), Tick) mod Natural (Words (A).Length));
   begin
      S.Energy := Clamp (S.Energy + Energy_D (A), 100);
      S.Mood := Clamp (S.Mood + Mood_D (A), 100);
      S.Location := (if A = Wander then Roll (Seed, Positive (E), Tick, 1, 4) - 1 else Home (A));
      return "{""v"":1,""seed"":" & Img (Seed) & ",""tick"":" & Img (Tick) & ",""ts"":""" & Stamp
        & """,""t"":""" & Low (A) & """,""text"":""" & Esc (Text)
        & """,""state"":{""energy"":" & Img (S.Energy) & ",""mood"":" & Img (S.Mood)
        & ",""location"":" & Img (S.Location) & "}}";
   end Step;

   --  ---- autoload and errors -----------------------------------------------

   procedure Load_Diary (E : Entity_Id; Disk_Seed : in out Int) is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      Read_Lines (Path (E), Lines, Found);
      for I in 1 .. Natural (Lines.Length) loop
         declare
            L : constant String := Lines (I);
            N : constant String := Img (Int (Disk (E).Length) + 1);
         begin
            if Complete (L) then
               if Field (L, "tick") /= Int (Disk (E).Length) + 1 then
                  raise Diary_Error with Msg ("err.gap", Name (E), Img (I), Img (Field (L, "tick")), N);
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

   function Ends_With_Lf (File : String) return Boolean is
      F : Ada.Streams.Stream_IO.File_Type;
      C : Character := ASCII.LF;
   begin
      Ada.Streams.Stream_IO.Open (F, Ada.Streams.Stream_IO.In_File, File);
      Ada.Streams.Stream_IO.Set_Index (F, Ada.Streams.Stream_IO.Size (F));
      Character'Read (Ada.Streams.Stream_IO.Stream (F), C);
      Ada.Streams.Stream_IO.Close (F);
      return C = ASCII.LF;
   end Ends_With_Lf;

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
begin
   Load_Data;
   for I in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         A   : constant String := Ada.Command_Line.Argument (I);
         Eq  : constant Natural := Fx.Index (A, "=");
         Opt : constant String := (if Eq > 0 then A (A'First .. Eq - 1) else A);
         Val : constant String := (if Eq > 0 then A (Eq + 1 .. A'Last) else "");
      begin
         if Opt = "--help" or else Opt = "-h" then
            declare
               Help  : Str_Vectors.Vector;
               Found : Boolean;
            begin
               Read_Lines (Data_Path ("help.txt"), Help, Found);
               for L of Help loop TIO.Put_Line (L); end loop;
               if not Found then TIO.Put_Line ("diary_sim: data/help.txt not found (--ticks --seed --every --fresh --crash-at)"); end if;
               return;
            end;
         elsif Opt = "--fresh" then Fresh := True;
         elsif Opt = "--ticks" then Ticks := Number (Opt, Val);
         elsif Opt = "--seed" then Seed_Opt := Number (Opt, Val);
         elsif Opt = "--every" then Every := Number (Opt, Val);
         elsif Opt = "--crash-at" then Crash_At := Number (Opt, Val);
         else raise Usage_Error with Msg ("err.option", A);
         end if;
      end;
   end loop;
   Ticks := (if Ticks < 0 then 1000 else Ticks);
   Every := (if Every < 0 then 100 else Int'Max (1, Every));

   if Fresh and then Ada.Directories.Exists ("diaries") then
      Ada.Directories.Rename ("diaries", "diaries_old_" & Plain_Stamp);
      Say (Msg ("fresh.moved", "diaries_old_" & Plain_Stamp));
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
      if Common > 0 then   --  resume state comes from the line at the common tick
         declare
            L : constant String := Disk (E) (Common);
         begin
            St (E) := (Clamp (Integer (Field (L, "energy")), 100), Clamp (Integer (Field (L, "mood")), 100),
                       Clamp (Integer (Field (L, "location")), 3));
         end;
      end if;
   end loop;
   if Int (Common) >= Ticks then
      TIO.Put_Line (Msg ("nothing", Img (Common), Img (Ticks)));
      return;
   end if;
   TIO.Put_Line (Msg ("resume", Img (Common), Img (Ticks)));

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

   for Tick in Int (Common) + 1 .. Ticks loop
      Cur_Tick := Tick;
      for E in Entity_Id loop      --  fixed id order
         Cur_Name := To_Unbounded_String (Name (E));
         if Tick = Crash_At and then E = 1 then Events := Forced (Tick); end if;
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
         end;
      end loop;
      if Tick mod Every = 0 then
         TIO.Put_Line (Msg ("progress", Img (Tick), Img (Ticks), Img (Integer (Entity_Id'Last)), Img (Events)));
      end if;
   end loop;
   for F of Out_File loop TIO.Close (F); end loop;
   TIO.Put_Line (Msg ("summary", Img (Common + 1), Img (Ticks), Img (Integer (Entity_Id'Last)), Img (Events),
                      Img (Written), Img (Verified), Img (Warnings)));
exception
   when E : Usage_Error =>
      TIO.Put_Line (TIO.Standard_Error, Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (2);
   when E : others =>
      Report (E);
      Ada.Command_Line.Set_Exit_Status (1);
end Diary_Sim;
