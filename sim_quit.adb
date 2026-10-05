--  Version: 0.004
pragma Ada_2022;

with Ada.Directories, Ada.Finalization, Ada.Interrupts.Names, Ada.Strings.Unbounded, Ada.Text_IO, GNAT.OS_Lib, Sim_Util, System;

package body Sim_Quit is

   use Ada.Strings.Unbounded;

   protected Flag with Interrupt_Priority => System.Interrupt_Priority'Last is
      procedure Got_Int with Attach_Handler => Ada.Interrupts.Names.SIGINT;
      procedure Got_Term with Attach_Handler => Ada.Interrupts.Names.SIGTERM;
      procedure Got_Hup with Attach_Handler => Ada.Interrupts.Names.SIGHUP;
      function Signal return Natural;   --  0 none, 1 SIGINT, 2 SIGTERM, 3 SIGHUP
   private
      Sig : Natural := 0;
   end Flag;

   protected body Flag is
      procedure Got_Int is
      begin
         if Sig = 0 then Sig := 1; end if;
      end Got_Int;
      procedure Got_Term is
      begin
         if Sig = 0 then Sig := 2; end if;
      end Got_Term;
      procedure Got_Hup is
      begin
         if Sig = 0 then Sig := 3; end if;
      end Got_Hup;
      function Signal return Natural is (Sig);
   end Flag;

   function Requested return Boolean is (Flag.Signal /= 0);
   function Which return String is
     (case Flag.Signal is when 1 => "SIGINT", when 2 => "SIGTERM", when 3 => "SIGHUP", when others => "");

   Enabled, Q : Boolean := False;

   procedure Watch_Keys (On : Boolean) is
   begin
      Enabled := On;
   end Watch_Keys;

   function Watching return Boolean is (Enabled and then Sim_Util.Foreground);
   function Key_Q return Boolean is (Q);
   procedure Ask_Quit is begin Q := True; end Ask_Quit;
   procedure Forget_Q is begin Q := False; end Forget_Q;

   --  ---- typed lines -------------------------------------------------------------------------------------------------------
   Lines_Mode : Boolean := False;
   Max_Chars : Positive := 120;
   Buf : Unbounded_String;                 --  the line being typed
   Active : Boolean := False;              --  a line is open (its first key was @ or /)
   Queue : Sim_Util.Str_Vectors.Vector;    --  finished lines
   Version : Natural := 0;
   Esc_State : Natural := 0;               --  0 normal, 1 after Esc, 2 inside an escape sequence, 3 the bytes of a mouse report
   Esc_Late : Boolean := False;            --  the last poll ended with a lone Esc: a '[' or 'O' first in this poll still starts a sequence
   Seq_Len : Natural := 0;                 --  bytes of the sequence after ESC [ (a legacy mouse report is ESC [ M and three bytes)
   Skip : Natural := 0;                    --  mouse report bytes still to skip
   Raw_On : Boolean := False;
   Saved : Unbounded_String;               --  the terminal settings before (stty -g)

   function Sh (Command : String) return Boolean is
      Args : GNAT.OS_Lib.Argument_List (1 .. 2);
      Code : Integer;
   begin
      Args (1) := new String'("-c");
      Args (2) := new String'(Command);
      Code := GNAT.OS_Lib.Spawn ("/bin/sh", Args);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));
      return Code = 0;
   exception
      when others => return False;
   end Sh;

   procedure Run (Command : String) is
      Done : constant Boolean := Sh (Command);
      pragma Unreferenced (Done);
   begin
      null;
   end Run;

   procedure Restore is
   begin
      if Raw_On then
         Raw_On := False;
         if Length (Saved) > 0 then
            Run ("stty " & To_String (Saved));
         else
            Run ("stty sane");
         end if;
      end if;
   end Restore;

   procedure Set_Lines (On : Boolean; Max_Len : Positive := 120) is
   begin
      if not On then
         Lines_Mode := False;
         Restore;
         return;
      end if;
      Max_Chars := Max_Len;
      Lines_Mode := Watching;
      if Lines_Mode and then not Raw_On then
         declare
            Args : GNAT.OS_Lib.Argument_List (1 .. 2);
            Ok : Boolean;
            Code : Integer;
            Name : constant String := "stty_" & Sim_Util.Img (Sim_Util.Int (GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id))) & ".tmp";
         begin
            Args (1) := new String'("-c");
            Args (2) := new String'("stty -g");
            GNAT.OS_Lib.Spawn ("/bin/sh", Args, Name, Ok, Code, False);
            GNAT.OS_Lib.Free (Args (1));
            GNAT.OS_Lib.Free (Args (2));
            Saved := Null_Unbounded_String;
            if Ok and then Code = 0 and then Ada.Directories.Exists (Name) then
               declare
                  Lines : Sim_Util.Str_Vectors.Vector;
                  Found : Boolean;
               begin
                  Sim_Util.Read_Lines (Name, Lines, Found);
                  if not Lines.Is_Empty and then Lines.First_Element'Length > 0
                    and then (for all C of Lines.First_Element => C in '0' .. '9' | 'a' .. 'f' | ':')
                  then
                     Saved := To_Unbounded_String (Lines.First_Element);
                  end if;
               end;
            end if;
            if Ada.Directories.Exists (Name) then Ada.Directories.Delete_File (Name); end if;
            Raw_On := Length (Saved) > 0 and then Sh ("stty -echo -icanon min 0 time 0");
         exception
            when others => Raw_On := False;
         end;
      end if;
   end Set_Lines;

   function Lines_On return Boolean is (Lines_Mode);
   function Typing return String is (To_String (Buf));
   function Changed return Natural is (Version);
   function Pending return Boolean is (not Queue.Is_Empty);

   function Take return String is
   begin
      if Queue.Is_Empty then return ""; end if;
      declare
         L : constant String := Queue.First_Element;
      begin
         Queue.Delete_First;
         return L;
      end;
   end Take;

   procedure Cancel is
   begin
      if Active or else Length (Buf) > 0 then Version := Version + 1; end if;
      Buf := Null_Unbounded_String;
      Active := False;
   end Cancel;

   --  The bytes of an escape sequence: True while C belongs to one (it is not a key).  ESC [ ... ends with a byte in '@' .. '~' (an arrow
   --  key and the like), ESC O x is one more byte (F1 .. F4: ESC O P .. S), ESC [ M is a legacy mouse report with three more bytes.
   --  After a lone Esc (Esc_State 1) any other byte is a key again; the caller decides what the lone Esc meant.
   function Skip_Sequence (C : Character) return Boolean is
   begin
      if Esc_Late then   --  a lone Esc ended the last poll: a '[' or 'O' now is the rest of a split sequence
         Esc_Late := False;
         if C in '[' | 'O' then
            Esc_State := 2;
            Seq_Len := (if C = 'O' then 99 else 0);
            return True;
         end if;
      end if;
      case Esc_State is
         when 1 =>
            if C in '[' | 'O' then
               Esc_State := 2;
               Seq_Len := (if C = 'O' then 99 else 0);   --  99: ESC O x, the next byte ends it
               return True;
            end if;
            return False;
         when 2 =>
            Seq_Len := Seq_Len + 1;
            if Seq_Len = 100 then Esc_State := 0;   --  ESC O x
            elsif C = 'M' and then Seq_Len = 1 then Esc_State := 3; Skip := 3;   --  ESC [ M: a legacy mouse report
            elsif C in '@' .. '~' then Esc_State := 0;
            end if;
            return True;
         when 3 =>
            Skip := Skip - 1;
            if Skip = 0 then Esc_State := 0; end if;
            return True;
         when others =>
            if C = ASCII.ESC then
               Esc_State := 1;
               return True;
            end if;
            return False;
      end case;
   end Skip_Sequence;

   --  One typed key of the line editor.
   procedure Feed (C : Character) is
   begin
      if Skip_Sequence (C) then return; end if;
      if Esc_State = 1 then
         Esc_State := 0;
         Cancel;                       --  Esc and then an ordinary key: the line is cancelled, the key counts
      end if;
      case C is
         when ASCII.ESC => Esc_State := 1;   --  Esc Esc: the first one cancelled the line, the second starts again
         when ASCII.LF | ASCII.CR =>
            if Active and then Length (Buf) > 0 then Queue.Append (To_String (Buf)); end if;
            Cancel;
         when ASCII.BS | ASCII.DEL =>
            if Active then
               Delete (Buf, Length (Buf), Length (Buf));
               if Length (Buf) = 0 then Active := False; end if;
               Version := Version + 1;
            end if;
         when ASCII.NAK => Cancel;
         when ' ' .. '~' =>
            if Active then
               if Length (Buf) < Max_Chars then Append (Buf, C); Version := Version + 1; end if;
            elsif C in '@' | '/' then
               Active := True;
               Buf := To_Unbounded_String ("" & C);
               Version := Version + 1;
            elsif C in 'q' | 'Q' then
               Q := True;
            end if;
         when others => null;
      end case;
   end Feed;

   procedure Poll is
      C : Character;
      Av : Boolean;
   begin
      if not Watching then return; end if;
      loop
         Ada.Text_IO.Get_Immediate (C, Av);
         exit when not Av;
         if Lines_Mode then
            Feed (C);
         elsif not Skip_Sequence (C) then
            Esc_State := (if C = ASCII.ESC then 1 else 0);
            if C in 'q' | 'Q' then Q := True; end if;   --  only a q typed as a key (not a byte of an escape sequence)
         end if;
      end loop;
      if Esc_State = 1 then   --  a lone Esc: the line is cancelled now; a '[' or 'O' first in the next poll is still a split sequence
         Esc_State := 0;
         Esc_Late := True;
         if Lines_Mode then Cancel; end if;
      end if;
   exception
      when others => Enabled := False;   --  end of input or a terminal that cannot be read: no keys any more
   end Poll;

   type Guard is new Ada.Finalization.Limited_Controlled with null record;
   overriding procedure Finalize (G : in out Guard);
   procedure Finalize (G : in out Guard) is
      pragma Unreferenced (G);
   begin
      Restore;
   end Finalize;
   The_Guard : Guard;
   pragma Unreferenced (The_Guard);

end Sim_Quit;
