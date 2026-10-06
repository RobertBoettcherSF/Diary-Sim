--  Version: 0.002
--  See sim_visit.ads.
pragma Ada_2022;

with Sim_Ckpt;

with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Sim_Dharma;
with Sim_Things;
with Sim_Screen;

package body Sim_Visit is

   use Ada.Strings.Unbounded;
   package Fx renames Ada.Strings.Fixed;

   Seed_V : Int := 0;
   type Bonds is array (Entity_Id) of Integer;
   Bond : Bonds := [others => 0];
   Cur_N : Natural := 0;                  --  number of the latest visit session
   Cur_E : Entity_Id := 1;
   Bond_Start : Integer := 0;
   Said_N, Cmd_N, Acts_N : Natural := 0;   --  say commands, all commands, say / teach / show commands of the visit
   Learned_Total : Natural := 0;          --  words learned from the human in this visit
   Turn_Tick : Int := -1;
   Turn_Words : Natural := 0;             --  ... at the tick Turn_Tick
   Log : Str_Vectors.Vector;

   --  ---- small helpers (data, text) -----------------------------------------------------------------------------------
   function Lower (S : String) return String is (Ada.Characters.Handling.To_Lower (S));

   function Is_Num (T : String) return Boolean is
     (T'Length in 1 .. 9 and then (for all C of T => C in '0' .. '9'));

   function Num (Key : String; D : Integer) return Integer is
      T : constant String := Fx.Trim (Msg (Key), Ada.Strings.Both);
   begin
      return (if T'Length > 1 and then T (T'First) = '-' and then Is_Num (T (T'First + 1 .. T'Last)) then -Integer'Value (T (T'First + 1 .. T'Last))
              elsif Is_Num (T) then Integer'Value (T) else D);
   end Num;

   function Lim (Key : String; D : Integer) return Integer is (Integer (Limit (Key, Int (D))));

   function Missing (T : String) return Boolean is (T'Length = 0 or else T (T'First) = '[');

   --  The N-th blank separated token of T ("" if none).
   function Nth_Tok (T : String; N : Positive) return String is
      Pos : Natural := T'First;
      K : Natural := 0;
   begin
      while Pos <= T'Last loop
         if T (Pos) = ' ' then
            Pos := Pos + 1;
         else
            declare
               Stop : Natural := Pos;
            begin
               while Stop < T'Last and then T (Stop + 1) /= ' ' loop Stop := Stop + 1; end loop;
               K := K + 1;
               if K = N then return T (Pos .. Stop); end if;
               Pos := Stop + 1;
            end;
         end if;
      end loop;
      return "";
   end Nth_Tok;

   function Cut (Key : String; N : Positive; D : Integer) return Integer is
      T : constant String := Nth_Tok (Msg (Key), N);
   begin
      return (if T'Length > 1 and then T (T'First) = '-' and then Is_Num (T (T'First + 1 .. T'Last)) then -Integer'Value (T (T'First + 1 .. T'Last))
              elsif Is_Num (T) then Integer'Value (T) else D);
   end Cut;

   function Variants (Prefix : String) return Natural is
      N : Natural := 0;
   begin
      while N < 30 and then not Missing (Msg (Prefix & Img (N + 1))) loop N := N + 1; end loop;
      return N;
   end Variants;

   function Band_Of (Mood : Integer) return Positive is
      B : Positive := 1;
   begin
      for K in 1 .. 4 loop
         if Mood >= Cut ("visit.cuts", K, 0) then B := K + 1; end if;
      end loop;
      return B;
   end Band_Of;

   function Trust_Band (V : Integer) return Positive is
      B : Positive := 1;
   begin
      for K in 1 .. 4 loop
         if V >= Cut ("visit.trust.cuts", K, 0) then B := K + 1; end if;
      end loop;
      return B;
   end Trust_Band;

   --  The word id of a lower case text (the table holds "I" in capitals); 0 if the vocabulary has no such word.
   function Lookup (T : String) return Natural is
   begin
      if T'Length = 0 then return 0; end if;
      for W in 1 .. Count loop
         if Lower (Word (W)) = T then return W; end if;
      end loop;
      return 0;
   end Lookup;

   --  The letters-only words of a typed text, lower case (at most 12).
   function Split_Words (Text : String) return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
      Cur : Unbounded_String;
      procedure Flush is
      begin
         if Length (Cur) > 0 and then Natural (R.Length) < 12 then R.Append (To_String (Cur)); end if;
         Cur := Null_Unbounded_String;
      end Flush;
   begin
      for C of Lower (Text) loop
         if C in 'a' .. 'z' then Append (Cur, C);
         elsif C /= ''' then Flush;
         end if;
      end loop;
      Flush;
      return R;
   end Split_Words;

   function Join (V : Str_Vectors.Vector) return String is
      R : Unbounded_String;
   begin
      for X of V loop Append (R, (if Length (R) > 0 then "," else "") & X); end loop;
      return (if Length (R) = 0 then "-" else To_String (R));
   end Join;

   function Spaced (V : Str_Vectors.Vector) return String is
      R : Unbounded_String;
   begin
      for X of V loop Append (R, (if Length (R) > 0 then " " else "") & X); end loop;
      return To_String (R);
   end Spaced;

   --  ---- parsing the commands -----------------------------------------------------------------------------------------
   function Clean_Text (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         if C < ' ' or else C >= ASCII.DEL or else C in '{' | '}' | '\' then C := ' '; end if;
      end loop;
      declare
         T : constant String := Fx.Trim (Lower (R), Ada.Strings.Both);
      begin
         return (if T'Length > 120 then Fx.Trim (T (T'First .. T'First + 119), Ada.Strings.Both) else T);
      end;
   end Clean_Text;

   function Parse (Line : String) return Command is
      T : constant String := Clean_Text (Line);
      Sp : constant Natural := Fx.Index (T, " ");
      Verb : constant String := (if Sp = 0 then T else T (T'First .. Sp - 1));
      Rest : constant String := (if Sp = 0 then "" else Fx.Trim (T (Sp + 1 .. T'Last), Ada.Strings.Both));
      R : Command;
   begin
      R.Text := To_Unbounded_String (T);
      if T = "" then
         R.Kind := Wait;
         R.N := 1;
      elsif Verb = "say" and then Rest /= "" then
         R.Kind := Say;
         R.Text := To_Unbounded_String (Rest);
      elsif Verb = "teach" and then Rest /= "" then
         declare
            W : constant Str_Vectors.Vector := Split_Words (Rest);
         begin
            if not W.Is_Empty then
               R.Kind := Teach;
               R.Text := To_Unbounded_String (W.First_Element);
            end if;
         end;
      elsif Verb = "show" then
         R.Kind := Show_Cmd;
         R.Text := Null_Unbounded_String;
      elsif Verb = "wait" then
         R.Kind := Wait;
         R.N := (if Rest = "" then 1 elsif Is_Num (Rest) then Integer'Min (Integer'Value (Rest), 999) else 0);
         if R.N = 0 then R.Kind := Bad; end if;
      elsif Verb in "leave" | "quit" | "q" | "exit" and then Rest = "" then
         R.Kind := Leave;
         R.Text := Null_Unbounded_String;
      end if;
      return R;
   end Parse;

   function Cmd_Name (K : Cmd_Kind) return String is (if K = Show_Cmd then "show" else Lower (Cmd_Kind'Image (K)));

   --  The check number of an input line: a hash chain over its content, own salt 9990.
   function Check (N : Positive; Tick : Int; S : String) return Natural is
      H : Positive := 1;
   begin
      for C of S loop
         H := Roll (Seed_V, H, Tick * 1000 + Int (N mod 1000) + Int (Character'Pos (C)) * 7, 9990, 99_991);
      end loop;
      return H;
   end Check;

   function Payload (C : Command) return String is
     (case C.Kind is
        when Say | Teach => To_String (C.Text),
        when Wait => Img (C.N),
        when others => "");

   function Input_Line (N : Positive; Tick : Int; C : Command) return String is
     ("V" & Img (N) & " t=" & Img (Tick) & " cmd=" & Cmd_Name (C.Kind) & (if C.Kind = Wait then " n=" & Img (C.N) else "")
      & " h=" & Img (Check (N, Tick, Cmd_Name (C.Kind) & ":" & Payload (C)))
      & (if C.Kind in Say | Teach then " text=" & To_String (C.Text) else ""));

   function Tok (L, Key : String) return String is
      Pat : constant String := " " & Key & "=";
      P : constant Natural := Fx.Index (L, Pat);
   begin
      if P = 0 then return ""; end if;
      declare
         From : constant Natural := P + Pat'Length;
         Stop : constant Natural := Fx.Index (L, " ", From);
      begin
         return L (From .. (if Stop = 0 then L'Last else Stop - 1));
      end;
   end Tok;

   procedure Parse_Input (L : String; N : out Natural; Tick : out Int; C : out Command; OK : out Boolean) is
      Sp : constant Natural := Fx.Index (L, " ");
      Cm : constant String := Tok (L, "cmd");
      Tp : constant Natural := Fx.Index (L, " text=");
   begin
      N := 0;
      Tick := -1;
      C := (others => <>);
      OK := L'Length > 3 and then L (L'First) = 'V' and then Sp > 2 and then Is_Num (L (L'First + 1 .. Sp - 1)) and then Is_Num (Tok (L, "t"));
      if not OK then return; end if;
      N := Integer'Value (L (L'First + 1 .. Sp - 1));
      Tick := Int'Value (Tok (L, "t"));
      OK := N > 0;
      for K in Cmd_Kind range Say .. Leave loop
         if Cm = Cmd_Name (K) then C.Kind := K; end if;
      end loop;
      if C.Kind = Bad then OK := False; return; end if;
      if C.Kind in Say | Teach then
         OK := Tp > 0;
         if OK then C.Text := To_Unbounded_String (L (Tp + 6 .. L'Last)); end if;
      elsif C.Kind = Wait then
         OK := Is_Num (Tok (L, "n"));
         if OK then C.N := Integer'Value (Tok (L, "n")); end if;
      end if;
      --  the line must be exactly what Input_Line makes of the parsed fields (the check number h= included)
      OK := OK and then L = Input_Line (Positive (Integer'Max (1, N)), Tick, C);
   end Parse_Input;

   --  ---- the answer: templates filled with KNOWN words only ----------------------------------------------------------
   --  Pool members (words of data/visit.txt visit.pool.<name>) that E knows now.
   function Pool_Pick (E : Entity_Id; Pool : String; Key : Int; Salt : Natural) return Natural is
      T : constant String := Msg ("visit.pool." & Pool);
      Members : Word_Vectors.Vector;
   begin
      if Missing (T) then return 0; end if;
      for K in 1 .. 60 loop
         declare
            Tk : constant String := Nth_Tok (T, K);
            W : constant Natural := Lookup (Lower (Tk));
         begin
            exit when Tk = "";
            if W > 0 and then Knows (E, W) and then not Members.Contains (W) then Members.Append (W); end if;
         end;
      end loop;
      if Members.Is_Empty then return 0; end if;
      return Members (Roll (Seed_V, Positive (E), Key, Salt, Natural (Members.Length)));
   end Pool_Pick;

   function Fill (T : String; E : Entity_Id; Key : Int; Echo : Word_Vectors.Vector) return String is
      R : Unbounded_String;
      Slot : Natural := 0;
      procedure Add_Word (W : String) is
      begin
         if Length (R) > 0 then Append (R, " "); end if;
         Append (R, W);
      end Add_Word;
   begin
      for K in 1 .. 24 loop
         declare
            Tk : constant String := Nth_Tok (T, K);
         begin
            exit when Tk = "";
            if Tk (Tk'First) = '{' and then Tk (Tk'Last) = '}' then
               declare
                  Name : constant String := Tk (Tk'First + 1 .. Tk'Last - 1);
                  Salt : constant Natural := 9910 + Slot mod 40;
                  W : Natural := 0;
               begin
                  Slot := Slot + 1;
                  if Name = "echo" then
                     if not Echo.Is_Empty then W := Echo (Roll (Seed_V, Positive (E), Key, Salt, Natural (Echo.Length))); end if;
                  elsif Name = "any" then
                     if Known_Count (E) > 0 then W := Nth_Known (E, Roll (Seed_V, Positive (E), Key, Salt, Known_Count (E))); end if;
                  else
                     W := Pool_Pick (E, Name, Key, Salt);
                  end if;
                  if W > 0 then Add_Word (Lower (Word (W))); end if;
               end;
            elsif (for all C of Tk => C in '.' | ',' | '?' | '!') then
               if Length (R) > 0 then Append (R, Tk); end if;
            else
               declare
                  From : Positive := Tk'First;
                  Done : Boolean := False;
               begin
                  while not Done and then From <= Tk'Last + 1 loop
                     declare
                        Stop : constant Natural := Fx.Index (Tk, "|", From);
                        Last : constant Natural := (if Stop = 0 then Tk'Last else Stop - 1);
                        Alt : constant String := Lower (Tk (From .. Last));
                        W : constant Natural := Lookup (Alt);
                     begin
                        if W > 0 and then Knows (E, W) then Add_Word (Alt); Done := True; end if;
                        exit when Stop = 0;
                        From := Stop + 1;
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;
      return (if (for some C of To_String (R) => C in 'a' .. 'z') then To_String (R) else "");
   end Fill;

   function Reply_From (Prefix : String; E : Entity_Id; Key : Int; Echo : Word_Vectors.Vector) return String is
      N : constant Natural := Variants (Prefix);
   begin
      if N = 0 then return ""; end if;
      return Fill (Msg (Prefix & Img (Roll (Seed_V, Positive (E), Key, 9907, N))), E, Key, Echo);
   end Reply_From;

   function Say_Prefix (E : Entity_Id; Key : Int; Mood, Energy, Pets : Integer; Heard, Unknown : Natural) return String is
      function Dice (Salt : Natural) return Integer is (Integer (Roll (Seed_V, Positive (E), Key, Salt, 100)));
   begin
      if Heard = 0 then return "visit.unk.";
      elsif Unknown > 0 and then Dice (9901) <= Lim ("visit.unk_pct", 50) then return "visit.unk.";
      elsif Pets > 0 and then Dice (9902) <= Lim ("visit.pet_pct", 40) then return "visit.pet.";
      elsif Energy < Lim ("visit.tired_energy", 25) and then Dice (9903) <= Lim ("visit.tired_pct", 50) then return "visit.tired.";
      elsif Bond (E) >= Lim ("visit.fond_at", 5) and then Dice (9904) <= Lim ("visit.fond_pct", 40) then return "visit.fond.";
      elsif Bond (E) <= Lim ("visit.cold_at", -3) and then Dice (9905) <= Lim ("visit.fond_pct", 40) then return "visit.cold.";
      else return "visit.say." & Img (Band_Of (Mood)) & ".";
      end if;
   end Say_Prefix;

   --  ---- state --------------------------------------------------------------------------------------------------------
   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
      Bond := [others => 0];
      Cur_N := 0;
      Cmd_N := 0;
      Said_N := 0;
      Learned_Total := 0;
      Turn_Tick := -1;
      Turn_Words := 0;
      Log.Clear;
   end Init;

   procedure Begin_Session (N : Positive; E : Entity_Id) is
   begin
      Cur_N := N;
      Cur_E := E;
      Bond_Start := Bond (E);
      Said_N := 0;
      Cmd_N := 0;
      Acts_N := 0;
      Learned_Total := 0;
      Turn_Tick := -1;
      Turn_Words := 0;
      Log.Clear;
   end Begin_Session;

   function Enabled return Boolean is (Lim ("visit.enabled", 1) /= 0);
   function Default_Ticks return Natural is (Natural (Integer'Max (1, Num ("visit.ticks", 60))));
   function Every return Positive is (Positive (Integer'Max (1, Num ("visit.every", 1))));
   function Bond_Of (E : Entity_Id) return Integer is (Bond (E));
   function Talks return Natural is (Said_N);
   function Commands return Natural is (Cmd_N);
   function Visit_Session return Natural is (Cur_N);

   procedure Add_Bond (E : Entity_Id; By : Integer) is
   begin
      Bond (E) := Clamp (Bond (E) + By, Lim ("visit.bond_min", -20), Lim ("visit.bond_max", 20));
   end Add_Bond;

   procedure Say_Log (L : String) is
   begin
      Log.Append (L);
      while Natural (Log.Length) > Natural'Max (1, Lim ("visit.log_lines", 5)) loop Log.Delete_First; end loop;
   end Say_Log;

   --  May one more word be learned at this tick (the per tick cap, like screen.read, and the cap of the visit)?
   function May_Learn (Tick : Int) return Boolean is
   begin
      if Turn_Tick /= Tick then
         Turn_Tick := Tick;
         Turn_Words := 0;
      end if;
      return Turn_Words < Natural (Lim ("visit.turn_cap", 3)) and then Learned_Total < Natural (Lim ("visit.session_cap", 20));
   end May_Learn;

   procedure Did_Learn is
   begin
      Turn_Words := Turn_Words + 1;
      Learned_Total := Learned_Total + 1;
   end Did_Learn;

   --  What the wesen says (or the line that tells it said nothing), for the log.
   procedure Log_Reply (E : Entity_Id; Key : Int; Reply : String) is
   begin
      if Reply /= "" then
         Say_Log (Msg ("visit.log.reply", Show (Name (E)), Reply));
      else
         declare
            N : constant Natural := Variants ("visit.nothing.");
         begin
            Say_Log (if N = 0 then Show (Name (E)) & " ..." else Msg ("visit.nothing." & Img (Roll (Seed_V, Positive (E), Key, 9908, N)), Show (Name (E))));
         end;
      end if;
   end Log_Reply;

   procedure Apply (C : Command; E : Entity_Id; Tick : Int; N : Positive; Mood, Energy, Pets : Integer;
                    Answer : out Unbounded_String; Learned : out Word_Vectors.Vector) is
      Key : constant Int := Tick * 1000 + Int (N mod 1000);
      Head : constant String := "A" & Img (N) & " t=" & Img (Tick) & " cmd=" & Cmd_Name (C.Kind);
      Echo : Word_Vectors.Vector;
   begin
      Answer := Null_Unbounded_String;
      Learned.Clear;
      Cmd_N := Cmd_N + 1;
      if C.Kind in Say | Teach | Show_Cmd then Acts_N := Acts_N + 1; end if;
      case C.Kind is
         when Say =>
            declare
               Words : constant Str_Vectors.Vector := Split_Words (To_String (C.Text));
               Heard, Unknown : Str_Vectors.Vector;
               Reply : Unbounded_String;
               Before : constant Integer := Bond (E);
            begin
               Said_N := Said_N + 1;
               for X of Words loop
                  declare
                     W : constant Natural := Lookup (X);
                  begin
                     if W > 0 and then Knows (E, W) then
                        Heard.Append (X);
                        if not Echo.Contains (W) then Echo.Append (W); end if;
                     else
                        Unknown.Append (X);
                     end if;
                  end;
               end loop;
               Reply := To_Unbounded_String
                 (Reply_From (Say_Prefix (E, Key, Mood, Energy, Pets, Natural (Heard.Length), Natural (Unknown.Length)), E, Key, Echo));
               if not Heard.Is_Empty then Add_Bond (E, Lim ("visit.bond_say", 1));
               elsif not Words.Is_Empty then Add_Bond (E, Lim ("visit.bond_unknown", -1));
               end if;
               Say_Log (Msg ("visit.log.you", To_String (C.Text)));
               if not Heard.Is_Empty then Say_Log (Msg ("visit.log.heard", Show (Name (E)), Spaced (Heard))); end if;
               if not Unknown.Is_Empty then Say_Log (Msg ("visit.log.unk", Show (Name (E)), Spaced (Unknown))); end if;
               Log_Reply (E, Key, To_String (Reply));
               Answer := To_Unbounded_String (Head & " mood=" & Img (Band_Of (Mood)) & " heard=" & Join (Heard) & " unk=" & Join (Unknown)
                                              & " bond=" & Sgn (Int (Bond (E) - Before)) & "/" & Img (Bond (E)) & " reply=" & To_String (Reply));
            end;
         when Teach =>
            declare
               Text : constant String := To_String (C.Text);
               W : constant Natural := Lookup (Text);
               Res : Unbounded_String;
               Before : constant Integer := Bond (E);
               Reply : Unbounded_String;
            begin
               if W = 0 then
                  Res := To_Unbounded_String ("nosuch");
                  Reply := To_Unbounded_String (Reply_From ("visit.unk.", E, Key, Echo));
               elsif Knows (E, W) then
                  Res := To_Unbounded_String ("known");
                  Echo.Append (W);
                  Reply := To_Unbounded_String (Reply_From ("visit.teach.known.", E, Key, Echo));
               elsif not May_Learn (Tick) then
                  Res := To_Unbounded_String ("cap");
                  Reply := To_Unbounded_String (Reply_From ("visit.teach.cap.", E, Key, Echo));
               elsif Integer (Roll (Seed_V, Positive (E), Key, 9906, 100)) > Lim ("visit.teach_pct", 60) then
                  Res := To_Unbounded_String ("missed");
                  Reply := To_Unbounded_String (Reply_From ("visit.teach.miss.", E, Key, Echo));
               else
                  Learn_Word (E, W);
                  Did_Learn;
                  Learned.Append (W);
                  Echo.Append (W);
                  Res := To_Unbounded_String ("learned");
                  Add_Bond (E, Lim ("visit.bond_teach", 2));
                  Reply := To_Unbounded_String (Reply_From ("visit.teach.ok.", E, Key, Echo));
               end if;
               Say_Log (Msg ("visit.log.teach." & To_String (Res), Show (Name (E)), Text));
               Log_Reply (E, Key, To_String (Reply));
               Answer := To_Unbounded_String (Head & " word=" & Text & " res=" & To_String (Res)
                                              & " bond=" & Sgn (Int (Bond (E) - Before)) & "/" & Img (Bond (E)) & " reply=" & To_String (Reply));
            end;
         when Show_Cmd =>
            declare
               Shown : Unbounded_String;
               Marks : Unbounded_String;
               Got : Natural := 0;
               Before : constant Integer := Bond (E);
               Reply : Unbounded_String;
            begin
               for K in 1 .. Lim ("visit.show_words", 3) loop
                  declare
                     W : constant Positive := Roll (Seed_V, Positive (E), Key, 9960 + K mod 30, Integer'Max (1, Base_Count));
                     Mark : Character := 'k';
                  begin
                     if not Knows (E, W) then
                        if May_Learn (Tick) and then Integer (Roll (Seed_V, Positive (E), Key, 9970 + K mod 20, 100)) <= Lim ("visit.show_pct", 35)
                        then
                           Learn_Word (E, W);
                           Did_Learn;
                           Learned.Append (W);
                           Echo.Append (W);
                           Got := Got + 1;
                           Mark := 'l';
                        else
                           Mark := 'n';
                        end if;
                     end if;
                     Append (Shown, (if Length (Shown) > 0 then " " else "") & Lower (Word (W)));
                     Append (Marks, (if Length (Marks) > 0 then "," else "") & Lower (Word (W)) & ":" & Mark);
                  end;
               end loop;
               if Got > 0 then Add_Bond (E, Lim ("visit.bond_show", 1)); end if;
               Reply := To_Unbounded_String (Reply_From ((if Got > 0 then "visit.show.ok." else "visit.show.none."), E, Key, Echo));
               Say_Log (Msg ("visit.log.show", Show (Name (E)), To_String (Shown), Img (Got)));
               Log_Reply (E, Key, To_String (Reply));
               Answer := To_Unbounded_String (Head & " words=" & To_String (Marks) & " learned=" & Img (Got)
                                              & " bond=" & Sgn (Int (Bond (E) - Before)) & "/" & Img (Bond (E)) & " reply=" & To_String (Reply));
            end;
         when Wait | Leave | Bad =>
            null;
      end case;
   end Apply;

   --  ---- the comment of a player -------------------------------------------------------------------------------------
   function Comment (Session : Natural; Players : Positive) return String is
      Delta_B : constant Integer := Bond (Cur_E) - Bond_Start;
      Band : constant String := (if Acts_N = 0 then "quiet" elsif Delta_B >= 2 then "warm" elsif Delta_B <= -2 then "cool" else "flat");
      N : constant Natural := Variants ("rbox.visit." & Band & ".");
   begin
      if Session = 0 or else Session /= Cur_N or else N = 0 then return ""; end if;
      if Integer (Roll (Seed_V, 1, Int (Session), 9909, 100)) > Lim ("visit.comment_pct", 70) then return ""; end if;
      return Msg ("rbox.visit." & Band & "." & Img (Roll (Seed_V, 2, Int (Session), 9909, N)),
                  Sim_Dharma.Player_Name (Sim_Dharma.Player_Id (Roll (Seed_V, 3, Int (Session), 9909, Players))),
                  Name (Cur_E), Img (Said_N), Sgn (Int (Delta_B)));
   end Comment;

   --  ---- the frame ----------------------------------------------------------------------------------------------------
   function Json_Str (L, Key : String) return String is
      Pat : constant String := """" & Key & """:""";
      P : constant Natural := Fx.Index (L, Pat);
      R : Unbounded_String;
      I : Natural;
   begin
      if P = 0 then return ""; end if;
      I := P + Pat'Length;
      while I <= L'Last and then L (I) /= '"' loop
         if L (I) = '\' and then I < L'Last then
            I := I + 1;
            Append (R, (if L (I) = 'n' then ' ' else L (I)));
         else
            Append (R, L (I));
         end if;
         I := I + 1;
      end loop;
      return To_String (R);
   end Json_Str;

   function Fit (S : String; W : Positive) return String is (Fx.Head (S, W));

   --  Word wrap into lines of at most Width characters, the first line after Lead; at most Max_Lines (the rest is cut with "...").
   procedure Wrap (Into : in out Str_Vectors.Vector; Lead, Text : String; Width : Positive; Max_Lines : Positive) is
      Cur : Unbounded_String := To_Unbounded_String (Lead);
      Used : Natural := 0;
      Pad : constant String := String'[1 .. Lead'Length => ' '];
      Cut_Off : Boolean := False;
   begin
      for K in 1 .. 80 loop
         declare
            Tk : constant String := Nth_Tok (Text, K);
         begin
            exit when Tk = "" or else Cut_Off;
            if Length (Cur) + Tk'Length + 1 > Width and then Length (Cur) > Pad'Length then
               Into.Append (To_String (Cur));
               Used := Used + 1;
               Cur := To_Unbounded_String (Pad);
               if Used >= Max_Lines then Cut_Off := True; end if;
            end if;
            if not Cut_Off then
               Append (Cur, (if Length (Cur) > Pad'Length then " " else "") & Tk);
            end if;
         end;
      end loop;
      if Cut_Off then
         Into.Replace_Element (Into.Last_Index, Fx.Trim (Fit (Into.Last_Element, Width - 3), Ada.Strings.Right) & "...");
      elsif Length (Cur) > Pad'Length then
         Into.Append (To_String (Cur));
      end if;
   end Wrap;

   function Frame (S : Scene) return String is
      E : constant Entity_Id := S.E;
      Rows : Str_Vectors.Vector;
      Cam : Str_Vectors.Vector;
      Box : Str_Vectors.Vector;
      Stat : Str_Vectors.Vector;
      Nm : constant String := Show (Name (E));
      Diary : constant String := To_String (S.Diary);
      Verb : constant String := Json_Str (Diary, "t");
      Does : constant String := Json_Str (Diary, "text");
      function Plain (K : String; A1, A2, A3, A4 : String := "") return String is (Show (Msg (K, A1, A2, A3, A4)));
   begin
      Rows.Append (Fit (Plain ("visit.head", Nm, Img (S.Tick), Img (S.Index) & "/" & Img (S.Total), Sgn (Int (Bond (E)))), 79));
      --  the three panels: camera (cols 0 .. 15), screen (17 .. 38), status (41 .. 78)
      if S.World and then Sim_Things.Placed (E) then
         for R of Sim_Things.Camera (Sim_Things.X (E), Sim_Things.Y (E), '@') loop
            declare
               Cells : String (1 .. 9);
            begin
               for K in 1 .. 5 loop
                  Cells (2 * K - 1) := R (R'First + K - 1);
                  if K < 5 then Cells (2 * K) := ' '; end if;
               end loop;
               Cam.Append (Cells);
            end;
         end loop;
         --  the human stands beside the wesen: one cell to the east of the centre
         Cam.Replace_Element (3, Cam (3) (1 .. 6) & "H" & Cam (3) (8 .. 9));
         Cam.Append (Plain ("visit.legend.1", Nm));
         Cam.Append (Plain ("visit.legend.2"));
      else
         Cam.Append (Plain ("visit.noworld"));
      end if;
      if S.Screen then
         declare
            Full : constant Str_Vectors.Vector := Sim_Screen.Box (E);
            Limit_Rows : constant Natural := Natural (Lim ("screen.height", 6)) + 2;
         begin
            for I in 1 .. Natural'Min (Limit_Rows, Natural (Full.Length)) loop Box.Append (Full (I)); end loop;
         end;
      else
         Box.Append (Plain ("visit.noscreen"));
      end if;
      Stat.Append (Plain ("visit.stat.mood", Img (S.Mood), Msg ("visit.band." & Img (Band_Of (S.Mood)))));
      Stat.Append (Plain ("visit.stat.energy", Img (S.Energy)));
      Stat.Append (Plain ("visit.stat.place", Img (S.Location)));
      Stat.Append (Plain ("visit.stat.words", Img (Known_Count (E))));
      Stat.Append (Plain ("visit.stat.pet", Img (S.Pets)));
      Stat.Append (Plain ("visit.stat.trust", Sgn (Int (Bond (E))), Msg ("visit.trust." & Img (Trust_Band (Bond (E))))));
      if Verb /= "" then Stat.Append (Plain ("visit.stat.doing", Verb)); end if;
      Rows.Append (Fit (" " & Plain ("visit.title.view"), 17) & Fit (Plain ("visit.title.screen", Nm), 24) & Plain ("visit.title.status"));
      for I in 1 .. Natural'Max (Natural (Box.Length), Natural'Max (Natural (Cam.Length), Natural (Stat.Length))) loop
         Rows.Append (Fit ((if I <= Natural (Cam.Length) then " " & Cam.Element (I) else ""), 17)
                      & Fit ((if I <= Natural (Box.Length) then Box.Element (I) else ""), 24)
                      & (if I <= Natural (Stat.Length) then Stat.Element (I) else ""));
      end loop;
      --  what it does, who and what is near
      Wrap (Rows, Plain ("visit.now") & " ", Show (Does), 79, 3);
      declare
         Folk, Stuff : Unbounded_String;
         Items : Natural := 0;
      begin
         if S.World and then Sim_Things.Placed (E) then
            for O in Entity_Id loop
               if O /= E and then Sim_Things.Placed (O) and then Sim_Things.Adjacent (E, O) then
                  Append (Folk, (if Length (Folk) > 0 then ", " else "") & Show (Name (O)));
               end if;
            end loop;
            for It of Sim_Things.Reach (E) loop
               exit when Items >= 3;
               Items := Items + 1;
               Append (Stuff, (if Length (Stuff) > 0 then ", " else "") & Sim_Things.Description (It.T));
            end loop;
         end if;
         Wrap (Rows, Plain ("visit.near") & " ",
               (if Length (Folk) > 0 then To_String (Folk) else Plain ("visit.near.nobody")) & "; "
               & (if Length (Stuff) > 0 then To_String (Stuff) else Plain ("visit.near.nothing")), 79, 2);
      end;
      for L of Log loop Rows.Append (Fit (L, 79)); end loop;
      if S.Note /= Null_Unbounded_String then Rows.Append (Fit (Show (To_String (S.Note)), 79)); end if;
      declare
         R : Unbounded_String;
      begin
         for I in 1 .. Natural'Min (Natural (Rows.Length), (if S.Prompt then 22 else 23)) loop
            Append (R, Fx.Trim (Rows (I), Ada.Strings.Right) & ASCII.LF);
         end loop;
         if S.Prompt then Append (R, Plain ("visit.prompt")); end if;
         return To_String (R);
      end;
   end Frame;

   function Leave_Text (E : Entity_Id) return String is (Msg ("visit.leave", Name (E)));
   function Help_Text return String is (Msg ("visit.help"));

   --  0.058: the checkpoint.
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Integer);
      procedure IO is new Sim_Ckpt.IO (Int);
      procedure IO is new Sim_Ckpt.IO (Entity_Id);
      procedure IO is new Sim_Ckpt.IO (Bonds);
      procedure IO is new Sim_Ckpt.IO (Str_Vectors.Vector);
   begin
      IO (S, Save, Seed_V);
      IO (S, Save, Bond);
      IO (S, Save, Cur_N);
      IO (S, Save, Cur_E);
      IO (S, Save, Bond_Start);
      IO (S, Save, Said_N); IO (S, Save, Cmd_N); IO (S, Save, Acts_N);
      IO (S, Save, Learned_Total);
      IO (S, Save, Turn_Tick);
      IO (S, Save, Turn_Words);
      IO (S, Save, Log);
   end State_IO;

end Sim_Visit;
