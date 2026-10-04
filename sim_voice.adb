--  Version: 0.001
--  See sim_voice.ads.
pragma Ada_2022;

with Ada.Strings.Fixed;

package body Sim_Voice is

   package Fx renames Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;

   type Situation is (Tired, Low, High, Up, Down, Doing, Place, Word, Granted, Partial, Deferred, Refused, Waiting, Trial);

   function Sit_Name (S : Situation) return String is
      (case S is
          when Tired => "tired", when Low => "low", when High => "high", when Up => "up", when Down => "down",
          when Doing => "doing", when Place => "place", when Word => "word", when Granted => "granted",
          when Partial => "partial", when Deferred => "deferred", when Refused => "refused", when Waiting => "waiting",
          when Trial => "trial");

   function Key (S : Situation; Id : String; K : Positive) return String is
      ("voice." & Sit_Name (S) & "." & Id & "." & Img (K));

   --  How many templates a situation has for this id (0 when none).
   function Count_Of (S : Situation; Id : String) return Natural is
      N : Natural := 0;
   begin
      while N < 9 and then Has (Key (S, Id, N + 1)) loop N := N + 1; end loop;
      return N;
   end Count_Of;

   function Applies (S : Situation; F : Facts) return Boolean is
      Delta_Min : constant Integer := Integer (Limit ("voice.delta", 8));
      Out_K     : constant String := To_String (F.Outcome);
   begin
      return (case S is
                 when Tired => F.Energy <= Integer (Limit ("voice.low_energy", 30)),
                 when Low => F.Mood <= Integer (Limit ("mood.tone_low", -34)),
                 when High => F.Mood >= Integer (Limit ("mood.tone_high", 34)),
                 when Up => F.Change >= Delta_Min,
                 when Down => F.Change <= -Delta_Min,
                 when Doing => Length (F.Act) > 0,
                 when Place => Length (F.Place) > 0,
                 when Word => Length (F.Word) > 0,
                 when Granted => Out_K = "grant" and then F.Open = 0,
                 when Partial => Out_K = "partial" and then F.Open = 0,
                 when Deferred => Out_K = "defer" and then F.Open > 0,
                 when Refused => Out_K in "refuse" | "veto" and then F.Open = 0,
                 when Waiting => F.Open > 0 and then Length (F.Topic) > 0 and then Out_K /= "defer",
                 when Trial => F.Trials > 0);
   end Applies;

   function Tone (F : Facts) return String is
     (Msg (if F.Mood <= Integer (Limit ("mood.tone_low", -34)) then "voice.tone.low"
           elsif F.Mood >= Integer (Limit ("mood.tone_high", 34)) then "voice.tone.high" else "voice.tone.mid"));

   function Cut (Text : String; Max : Positive) return String is
   begin
      if Text'Length <= Max then return Text; end if;
      declare
         Room : constant Natural := (if Max > 3 then Max - 3 else 0);
         Stop : Natural := Text'First + Room - 1;   --  last character kept
         P    : Natural;
      begin
         if Room = 0 then return Text (Text'First .. Text'First + Max - 1); end if;
         if Text (Stop + 1) /= ' ' then   --  inside a word: back to the blank before it, if that keeps most of the text
            P := Stop;
            while P > Text'First and then Text (P) /= ' ' loop P := P - 1; end loop;
            if P > Text'First + Room / 2 then Stop := P - 1; end if;
         end if;
         while Stop > Text'First and then Text (Stop) in ' ' | ',' | ';' | ':' loop Stop := Stop - 1; end loop;
         return Text (Text'First .. Stop) & "...";
      end;
   end Cut;

   function Wrap (Text : String; Width : Positive) return Str_Vectors.Vector is
      R    : Str_Vectors.Vector;
      Line : Unbounded_String;
      P    : Natural := Text'First;
   begin
      while P <= Text'Last loop
         declare
            Sp   : constant Natural := Fx.Index (Text, " ", P);
            Stop : constant Natural := (if Sp = 0 then Text'Last else Sp - 1);
            Word : constant String := Text (P .. Stop);
         begin
            if Word'Length > 0 then
               if Length (Line) > 0 and then Length (Line) + 1 + Word'Length > Width then
                  R.Append (To_String (Line));
                  Line := Null_Unbounded_String;
               end if;
               if Length (Line) > 0 then Append (Line, ' '); end if;
               if Word'Length > Width then   --  a word longer than a line: split it
                  declare
                     Q : Natural := Word'First;
                  begin
                     while Word'Last - Q + 1 > Width loop
                        R.Append (Word (Q .. Q + Width - 1));
                        Q := Q + Width;
                     end loop;
                     Append (Line, Word (Q .. Word'Last));
                  end;
               else
                  Append (Line, Word);
               end if;
            end if;
            P := Stop + 2;
         end;
      end loop;
      if Length (Line) > 0 then R.Append (To_String (Line)); end if;
      return R;
   end Wrap;

   function Fit (Text : String; Width : Positive; Rows : Positive) return Str_Vectors.Vector is
      Max : Positive := Positive'Max (20, Text'Length);
      V   : Str_Vectors.Vector := Wrap (Text, Width);
   begin
      while Natural (V.Length) > Rows and then Max > 20 loop
         Max := Positive'Max (20, Max - 8);
         V := Wrap (Cut (Text, Max), Width);
      end loop;
      return V;
   end Fit;

   function Message (F : Facts; Seed, Tick : Int; Slot : Positive) return String is
      Id      : constant String := To_String (F.Id);
      Avail   : array (1 .. Situation'Pos (Situation'Last) + 1) of Situation;
      N       : Natural := 0;
      Max     : constant Positive := Positive (Int'Max (20, Limit ("voice.max_chars", 150)));
      Chosen  : Situation;
      Who     : Unbounded_String := To_Unbounded_String (Id);
      Count   : Natural;
      Text    : Unbounded_String;
   begin
      for S in Situation loop
         if Applies (S, F) and then (Count_Of (S, Id) > 0 or else Count_Of (S, "any") > 0) then
            N := N + 1;
            Avail (N) := S;
         end if;
      end loop;
      if N = 0 then
         Text := To_Unbounded_String (Msg ("voice.fallback", To_String (F.Name), Tone (F), Img (F.Words)));
      else
         Chosen := Avail (Roll (Seed, Slot, Tick, 18000, N));
         Count := Count_Of (Chosen, Id);
         if Count = 0 then Who := To_Unbounded_String ("any"); Count := Count_Of (Chosen, "any"); end if;
         Text := To_Unbounded_String
           (Msg (Key (Chosen, To_String (Who), Roll (Seed, Slot, Tick, 18001 + Situation'Pos (Chosen), Count)),
                 (if Length (F.Act) > 0 then Msg ("voice.act." & To_String (F.Act)) else ""), To_String (F.Place), To_String (F.Word), To_String (F.Topic),
                 Tone (F), Img (F.Energy), Img (F.Words)));
      end if;
      return Cut (Msg ("voice.prefix", To_String (F.Name), To_String (Text)), Max);
   end Message;

end Sim_Voice;
