--  Version: 0.001
--  See sim_chat.ads.
pragma Ada_2022;

with Ada.Characters.Handling;
with Ada.Strings;
with Ada.Strings.Fixed;

package body Sim_Chat is

   package Fx renames Ada.Strings.Fixed;

   Seed_V : Int := 0;

   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
   end Init;

   function Enabled return Boolean is (Limit ("chat.enabled", 1) /= 0);
   function Me return String is (Msg ("chat.id.you"));
   function Sys return String is (Msg ("chat.id.system"));

   function Lower (S : String) return String is (Ada.Characters.Handling.To_Lower (S));
   function Trim (S : String) return String is (Fx.Trim (S, Ada.Strings.Both));
   function Max_Reply return Positive is (Positive (Int'Max (20, Limit ("chat.reply_chars", 150))));

   --  ---- the stored line ----------------------------------------------------------------------------------------------------
   function Seal (N : Positive; Tick : Int; Who, To_Id, Text : String) return Positive is
      H : Positive := 1;
      S : constant String := Who & ">" & To_Id & ":" & Text;
   begin
      for C of S loop
         H := Roll (Seed_V, H, Tick * 1000 + Int (N mod 1000) + Int (Character'Pos (C)) * 7, 18400, 99_991);
      end loop;
      return H;
   end Seal;

   function Line_Of (N : Positive; Tick : Int; Who, To_Id, Text : String) return String is
     ("C" & Img (Int (N)) & " t=" & Img (Tick) & " who=" & Who & " to=" & To_Id & " h=" & Img (Int (Seal (N, Tick, Who, To_Id, Text))) & " text=" & Text);

   procedure Parse_Line (L : String; P : out Parsed; OK : out Boolean) is
      Pos : Natural := L'First;

      --  The value after " key=" at Pos up to the next blank (or the end; Rest: up to the end).
      function Take (Key : String; Rest : Boolean := False) return String is
         Mark : constant String := " " & Key & "=";
         Q : constant Natural := Fx.Index (L, Mark, Pos);
      begin
         if Q /= Pos then OK := False; return ""; end if;
         declare
            Start : constant Natural := Q + Mark'Length;
            Stop : constant Natural := (if Rest then 0 else Fx.Index (L, " ", Start));
            Last : constant Natural := (if Stop = 0 then L'Last else Stop - 1);
         begin
            Pos := (if Rest or else Stop = 0 then L'Last + 1 else Stop);
            return L (Start .. Last);
         end;
      end Take;

      function Num (T : String) return Int is
        (if T'Length in 1 .. 15 and then (for all C of T => C in '0' .. '9') then Int'Value (T) else -1);
   begin
      P := (others => <>);
      OK := L'Length > 3 and then L (L'First) = 'C';
      if not OK then return; end if;
      declare
         Sp : constant Natural := Fx.Index (L, " ", L'First);
      begin
         OK := Sp > L'First + 1 and then Num (L (L'First + 1 .. Sp - 1)) > 0;
         if not OK then return; end if;
         P.N := Natural (Num (L (L'First + 1 .. Sp - 1)));
         Pos := Sp;
      end;
      declare
         T : constant String := Take ("t");
         W : constant String := Take ("who");
         D : constant String := Take ("to");
         H : constant String := Take ("h");
         X : constant String := Take ("text", Rest => True);
      begin
         if not OK then return; end if;
         P.Tick := Num (T);
         P.Who := To_Unbounded_String (W);
         P.To_Id := To_Unbounded_String (D);
         P.Text := To_Unbounded_String (X);
         OK := P.Tick >= 0 and then W /= "" and then D /= "" and then Num (H) = Int (Seal (P.N, P.Tick, W, D, X));
      end;
   exception
      when Constraint_Error => OK := False;
   end Parse_Line;

   --  ---- names ----------------------------------------------------------------------------------------------------------------
   --  The index of the person called Name (exact: the shown name or the id, any case; else the only one whose name or id starts with
   --  it).  0: nobody; Many: the names that fit when there are several.
   procedure Find (W : World; Name : String; Idx : out Natural; Many : out Unbounded_String) is
      L : constant String := Lower (Name);
      Hits : Natural := 0;
   begin
      Idx := 0;
      Many := Null_Unbounded_String;
      if L = "" then return; end if;
      for I in 1 .. Natural (W.People.Length) loop
         if Lower (To_String (W.People (I).Name)) = L or else Lower (To_String (W.People (I).Id)) = L then
            Idx := I;
            return;
         end if;
      end loop;
      for I in 1 .. Natural (W.People.Length) loop
         declare
            Pn : constant String := Lower (To_String (W.People (I).Name));
            Pi : constant String := Lower (To_String (W.People (I).Id));
         begin
            if (Pn'Length >= L'Length and then Pn (Pn'First .. Pn'First + L'Length - 1) = L)
              or else (Pi'Length >= L'Length and then Pi (Pi'First .. Pi'First + L'Length - 1) = L)
            then
               Hits := Hits + 1;
               if Idx = 0 then Idx := I; end if;
               Append (Many, (if Length (Many) > 0 then ", " else "") & To_String (W.People (I).Name));
            end if;
         end;
      end loop;
      if Hits /= 1 then Idx := 0; end if;
      if Hits <= 1 then Many := Null_Unbounded_String; end if;
   end Find;

   function Names_Of (W : World; K : Kind_T) return String is
      R : Unbounded_String;
   begin
      for P of W.People loop
         if P.Kind = K and then P.Present then Append (R, (if Length (R) > 0 then ", " else "") & To_String (P.Name)); end if;
      end loop;
      return To_String (R);
   end Names_Of;

   --  ---- what a character says --------------------------------------------------------------------------------------------
   function Has_Word (Text, List : String) return Boolean is
      T : constant String := " " & Lower (Text) & " ";
      Pos : Natural := List'First;
   begin
      while Pos <= List'Last loop
         declare
            Sp : constant Natural := Fx.Index (List, " ", Pos);
            Stop : constant Natural := (if Sp = 0 then List'Last else Sp - 1);
         begin
            if Stop >= Pos and then Fx.Index (T, " " & List (Pos .. Stop) & " ") > 0 then return True; end if;
            Pos := Stop + 2;
         end;
      end loop;
      return False;
   end Has_Word;

   type Intent_T is (Worry, Petition, Words, Energy, Mood, Thanks, Greet, Other);
   function Intent_Name (I : Intent_T) return String is
     (case I is when Worry => "worry", when Petition => "petition", when Words => "words", when Energy => "energy", when Mood => "mood",
                when Thanks => "thanks", when Greet => "greet", when Other => "other");

   --  Only letters count as parts of words ("how are you?" -> "how are you").
   function Plain (S : String) return String is
      R : String := S;
   begin
      for C of R loop if C not in 'a' .. 'z' and then C not in 'A' .. 'Z' then C := ' '; end if; end loop;
      return R;
   end Plain;

   function Intent_Of (Text : String) return Intent_T is
      T : constant String := Plain (Text);
   begin
      if Trim (T) = "" then return Greet; end if;
      for I in Intent_T range Worry .. Greet loop
         if Has_Word (T, Msg ("chat.kw." & Intent_Name (I))) then return I; end if;
      end loop;
      return Other;
   end Intent_Of;

   function Count_Of (Id : String; I : Intent_T) return Natural is
      N : Natural := 0;
   begin
      while N < 9 and then Has ("chat." & Id & "." & Intent_Name (I) & "." & Img (Int (N + 1))) loop N := N + 1; end loop;
      return N;
   end Count_Of;

   function Tone (Mood : Integer) return String is
     (Msg (if Mood <= Integer (Limit ("mood.tone_low", -34)) then "voice.tone.low"
           elsif Mood >= Integer (Limit ("mood.tone_high", 34)) then "voice.tone.high" else "voice.tone.mid"));

   function Or_Else (S, Key : String) return String is (if S = "" then Msg (Key) else S);

   function Say (W : World; Idx : Positive; I : Intent_T; N : Positive) return String is
      P : Person renames W.People (Idx);
      Id : constant String := To_String (P.Id);
      Use_Id : constant String := (if Count_Of (Id, I) > 0 then Id else Msg ("chat.id.any"));
      Count : constant Natural := Count_Of (Use_Id, I);
      K : constant Positive := (if Count = 0 then 1 else Roll (Seed_V, Idx + 16 * (N mod 1000), W.Tick, 18100 + Intent_T'Pos (I), Count));
      Key : constant String := "chat." & Use_Id & "." & Intent_Name (I) & "." & Img (Int (K));
      F : Sim_Voice.Facts renames P.Facts;
   begin
      if Count = 0 then return Msg ("chat.none", To_String (P.Name)); end if;
      case P.Kind is
         when Wesen =>
            return Msg (Key, Tone (F.Mood), Img (F.Energy), Img (F.Words), Or_Else (To_String (F.Topic), "chat.topic.none"),
                        Msg ("chat.out." & (if Length (F.Outcome) > 0 then To_String (F.Outcome) else "none")),
                        (if Length (F.Act) > 0 then Msg ("voice.act." & To_String (F.Act)) else ""),
                        Or_Else (To_String (F.Word), "chat.word.none"));
         when Player =>
            return Msg (Key, To_String (P.Watches), Img (P.Watch_Mood), Img (P.Granted), Img (P.Refused), Img (P.Open),
                        Msg (if P.Stance >= 15 then "chat.stance.high" elsif P.Stance <= -15 then "chat.stance.low" else "chat.stance.mid"),
                        Img (P.Watch_Energy));
         when Observer =>
            declare
               Open, Wd : Natural := 0;
            begin
               for Q of W.People loop
                  if Q.Kind = Wesen then Open := Open + Q.Facts.Open; Wd := Wd + Q.Facts.Words; end if;
               end loop;
               return Msg (Key, Img (W.Tick), Img (Int (W.Session)), Img (Int (W.Sessions)), Img (Int (Open)), Img (Int (Wd)));
            end;
      end case;
   end Say;

   --  ---- the orders and the whole line ----------------------------------------------------------------------------------
   procedure Add (R : in out Result; Who, To_Id, Text : String) is
   begin
      R.Replies.Append (Reply'(Who => To_Unbounded_String (Who), To_Id => To_Unbounded_String (To_Id),
                               Text => To_Unbounded_String (Sim_Voice.Cut (Text, Max_Reply))));
   end Add;

   procedure Sys_Line (R : in out Result; Text : String) is
   begin
      Add (R, Sys, Me, Text);
   end Sys_Line;

   function Join_Wesen (W : World; Key : String; Value : not null access function (P : Person) return String) return String is
      R : Unbounded_String;
   begin
      for P of W.People loop
         if P.Kind = Wesen then
            Append (R, (if Length (R) > 0 then ", " else "") & Msg (Key, To_String (P.Name), Value (P)));
         end if;
      end loop;
      return To_String (R);
   end Join_Wesen;

   function Mood_Of (P : Person) return String is (Sgn (Int (P.Facts.Mood)));
   function Energy_Of (P : Person) return String is (Img (P.Facts.Energy));
   function Words_Of (P : Person) return String is (Img (P.Facts.Words));
   function Mood_Energy_Of (P : Person) return String is (Sgn (Int (P.Facts.Mood)) & "/" & Img (P.Facts.Energy));

   procedure Order (W : World; Text : String; R : in out Result) is
      Sp : constant Natural := Fx.Index (Text, " ");
      Cmd : constant String := Lower ((if Sp = 0 then Text (Text'First + 1 .. Text'Last) else Text (Text'First + 1 .. Sp - 1)));
      Arg : constant String := (if Sp = 0 then "" else Trim (Text (Sp + 1 .. Text'Last)));
      Idx : Natural;
      Many : Unbounded_String;

      --  /mood /energy /words: all wesen, or the one called Arg
      procedure Show (All_Key, One_Key : String; Value : not null access function (P : Person) return String) is
      begin
         if Arg = "" then
            Sys_Line (R, Msg (All_Key, Join_Wesen (W, "chat.fmt.pair", Value)));
            return;
         end if;
         Find (W, Arg, Idx, Many);
         if Idx = 0 then
            Sys_Line (R, (if Length (Many) > 0 then Msg ("chat.err.ambiguous", Arg, To_String (Many)) else Msg ("chat.err.unknown_name", Arg)));
         elsif W.People (Idx).Kind /= Wesen then
            Sys_Line (R, Msg ("chat.err.notwesen", To_String (W.People (Idx).Name)));
         else
            declare
               P : Person renames W.People (Idx);
            begin
               Sys_Line (R, Msg (One_Key, To_String (P.Name), Value (P), Tone (P.Facts.Mood), Or_Else (To_String (P.Word_List), "chat.word.none"),
                                 Sgn (Int (P.Facts.Change))));
            end;
         end if;
      end Show;
   begin
      R.To := To_Unbounded_String (Sys);
      if Cmd = "help" then
         for K in 1 .. 12 loop
            exit when not Has ("chat.help." & Img (Int (K)));
            Sys_Line (R, Msg ("chat.help." & Img (Int (K))));
         end loop;
      elsif Cmd = "who" then
         Sys_Line (R, Msg ("chat.who", Names_Of (W, Wesen), Names_Of (W, Player), Names_Of (W, Observer)));
      elsif Cmd = "status" then
         Sys_Line (R, Msg ("chat.status.1", Img (W.Tick), Img (Int (W.Session)), Img (Int (W.Sessions)), Img (Seed_V)));
         Sys_Line (R, Join_Wesen (W, "chat.fmt.sample", Mood_Energy_Of'Access));
      elsif Cmd = "mood" then
         Show ("chat.mood.all", "chat.mood.one", Mood_Of'Access);
      elsif Cmd = "energy" then
         Show ("chat.energy.all", "chat.energy.one", Energy_Of'Access);
      elsif Cmd = "words" then
         Show ("chat.words.all", "chat.words.one", Words_Of'Access);
      elsif Cmd = "trend" then
         declare
            Max : constant Natural := Natural (Int'Max (1, Limit ("chat.trend_max", 12)));
            N : Natural := 5;
            Total : constant Natural := Natural (W.Samples.Length);
         begin
            if Arg /= "" then
               if Arg'Length in 1 .. 4 and then (for all C of Arg => C in '0' .. '9') then
                  N := Natural'Max (1, Natural (Int'Value (Arg)));
               else
                  Sys_Line (R, Msg ("chat.err.number", Arg));
                  return;
               end if;
            end if;
            N := Natural'Min (N, Max);
            if Total = 0 then
               Sys_Line (R, Msg ("chat.trend.none"));
            else
               N := Natural'Min (N, Total);
               Sys_Line (R, Msg ("chat.trend.head", Img (Int (N)), Img (Limit ("chat.trend_step", 100))));
               for I in Total - N + 1 .. Total loop
                  declare
                     S : Sample renames W.Samples (I);
                     Line : Unbounded_String;
                     K : Natural := 0;
                  begin
                     for P of W.People loop
                        if P.Kind = Wesen then
                           K := K + 1;
                           Append (Line, (if K > 1 then " " else "") & Msg ("chat.fmt.sample", To_String (P.Name), Sgn (Int (S.Mood (K))) & "/" & Img (Int (S.Energy (K)))));
                        end if;
                     end loop;
                     Sys_Line (R, Msg ("chat.trend.row", Img (S.Tick), To_String (Line)));
                  end;
               end loop;
            end if;
         end;
      elsif Cmd = "pause" then
         R.Effect := Pause;
         Sys_Line (R, Msg ("chat.pause", Img (W.Tick)));
      elsif Cmd = "resume" then
         R.Effect := Resume;
         Sys_Line (R, Msg ("chat.resume", Img (W.Tick)));
      elsif Cmd = "quit" then
         R.Effect := Quit;
         Sys_Line (R, Msg ("chat.quit"));
      elsif Cmd = "clear" then
         R.Effect := Clear;
         Sys_Line (R, Msg ("chat.clear"));
      elsif Cmd = "voices" then
         if Lower (Arg) = "on" then
            R.Effect := Voices_On;
            Sys_Line (R, Msg ("chat.voices.on"));
         elsif Lower (Arg) = "off" then
            R.Effect := Voices_Off;
            Sys_Line (R, Msg ("chat.voices.off"));
         else
            Sys_Line (R, Msg ("chat.voices.usage"));
         end if;
      else
         Sys_Line (R, Msg ("chat.err.unknown_cmd", Cmd));
      end if;
   end Order;

   function Handle (W : World; N : Positive; Text : String) return Result is
      R : Result;
      T : constant String := Trim (Text);
   begin
      R.To := To_Unbounded_String (Sys);
      if T'Length = 0 then
         return R;
      elsif T (T'First) = '/' then
         Order (W, T, R);
      elsif T (T'First) = '@' then
         declare
            Sp : constant Natural := Fx.Index (T, " ");
            Name : constant String := (if Sp = 0 then T (T'First + 1 .. T'Last) else T (T'First + 1 .. Sp - 1));
            Said : constant String := (if Sp = 0 then "" else Trim (T (Sp + 1 .. T'Last)));
            Idx : Natural;
            Many : Unbounded_String;
         begin
            if Name = "" then
               Sys_Line (R, Msg ("chat.err.empty_name"));
               return R;
            end if;
            Find (W, Name, Idx, Many);
            if Idx = 0 then
               Sys_Line (R, (if Length (Many) > 0 then Msg ("chat.err.ambiguous", Name, To_String (Many)) else Msg ("chat.err.unknown_name", Name)));
            elsif not W.People (Idx).Present then
               Sys_Line (R, Msg ("chat.err.absent", To_String (W.People (Idx).Name)));
            else
               R.To := W.People (Idx).Id;
               Add (R, To_String (W.People (Idx).Id), Me, Say (W, Idx, Intent_Of (Said), N));
            end if;
         end;
      else
         Sys_Line (R, Msg ("chat.err.empty_name"));
      end if;
      return R;
   end Handle;

end Sim_Chat;
