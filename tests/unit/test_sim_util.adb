--  Unit tests of the pure helpers in Sim_Util (deterministic, no files, no clock).
--  Built and run by scripts/unit_tests.sh (make test).  Exit status 0 = all passed.
pragma Ada_2022;

with Ada.Command_Line;
with Ada.Text_IO;
with Sim_Util; use Sim_Util;

procedure Test_Sim_Util is
   Passed, Failed : Natural := 0;

   procedure Check (Cond : Boolean; Name : String) is
   begin
      if Cond then
         Passed := Passed + 1;
      else
         Failed := Failed + 1;
         Ada.Text_IO.Put_Line ("  FAIL -- " & Name);
      end if;
   end Check;

   Line : constant String :=
     "{""v"":1,""seed"":42,""tick"":7,""ts"":""2026-10-03T02:19:00"",""energy"":55,""mood"":-12,""location"":3,""x"":{}}";
begin
   --  Img, Sgn, Clamp
   Check (Img (Int (42)) = "42" and then Img (Int (-5)) = "-5" and then Img (Integer (0)) = "0", "Img has no leading blank");
   Check (Sgn (12) = "+12" and then Sgn (-5) = "-5" and then Sgn (0) = "0", "Sgn signs positive numbers only");
   Check (Clamp (5, 0, 10) = 5 and then Clamp (-3, 0, 10) = 0 and then Clamp (99, 0, 10) = 10, "Clamp");

   --  Field
   Check (Field (Line, "tick") = 7, "Field reads a positive number");
   Check (Field (Line, "mood") = -12, "Field reads a negative number");
   Check (Field (Line, "missing") = No_Value, "Field: missing key = No_Value");
   Check (Field ("{""a"":x}", "a") = No_Value, "Field: not a number = No_Value");
   Check (Field ("{""a"":99999999999999999999999}", "a") = No_Value, "Field: overflow = No_Value");

   --  Complete and No_Ts
   Check (Complete (Line), "Complete accepts a whole diary line");
   Check (not Complete (Line (Line'First .. Line'Last - 1)), "Complete rejects a half-written line");
   Check (not Complete ("{}"), "Complete rejects a short line");
   Check (No_Ts (Line) = "{""v"":1,""seed"":42,""tick"":7,""ts"":"""",""energy"":55,""mood"":-12,""location"":3,""x"":{}}",
          "No_Ts empties the timestamp");
   Check (No_Ts ("{""a"":1}") = "{""a"":1}", "No_Ts leaves a line without ts alone");

   --  Esc
   Check (Esc ("a""b\c") = "a\""b\\c", "Esc escapes quotes and backslashes");
   Check (Esc ("plain") = "plain", "Esc leaves plain text alone");

   --  Diff_At
   Check (Diff_At ("abcdef", "abcXef")'Length > 0 and then Diff_At ("abcdef", "abcXef") (1 .. 9) = "column 4:",
          "Diff_At names the first differing column");

   --  Roll and Pick60: pure functions of their inputs, inside their ranges
   declare
      Same  : Boolean := True;
      Range_Ok : Boolean := True;
      Seen  : array (1 .. 6) of Boolean := [others => False];
      Seen60 : array (0 .. 59) of Boolean := [others => False];
      R : Integer;
      P : Integer;
   begin
      for T in Int range 0 .. 4_999 loop
         R := Roll (42, 1, T, 3, 6);
         Same := Same and then R = Roll (42, 1, T, 3, 6);
         Range_Ok := Range_Ok and then R in 1 .. 6;
         if R in 1 .. 6 then Seen (R) := True; end if;
         P := Pick60 (42, 2, T, 10);
         Same := Same and then P = Pick60 (42, 2, T, 10);
         Range_Ok := Range_Ok and then P in 0 .. 59;
         if P in 0 .. 59 then Seen60 (P) := True; end if;
      end loop;
      Check (Same, "Roll and Pick60 are deterministic");
      Check (Range_Ok, "Roll stays in 1 .. Sides and Pick60 in 0 .. 59");
      Check (Seen = [1 .. 6 => True], "Roll reaches every side of a D6 in 5000 ticks");
      Check (Seen60 = [0 .. 59 => True], "Pick60 reaches every value in 5000 ticks");
      Check ((for some T in Int range 0 .. 99 => Roll (42, 1, T, 3, 20) /= Roll (43, 1, T, 3, 20)),
             "another seed gives other rolls");
      Check ((for some T in Int range 0 .. 99 => Roll (42, 1, T, 3, 20) /= Roll (42, 2, T, 3, 20)),
             "another entity gives other rolls");
   end;

   Ada.Text_IO.Put_Line ("  unit tests (Sim_Util):" & Passed'Image & " passed," & Failed'Image & " failed");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Sim_Util;
