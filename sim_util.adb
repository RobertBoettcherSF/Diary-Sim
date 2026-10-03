--  Version: 0.006
pragma Ada_2022;

with Ada.Calendar.Formatting, Ada.Command_Line, Ada.Containers.Indefinite_Hashed_Maps, Ada.Directories,
     Ada.Streams.Stream_IO, Ada.Strings.Fixed, Ada.Strings.Hash, Ada.Strings.Unbounded, Ada.Text_IO, Interfaces, Interfaces.C;

package body Sim_Util is

   function C_Isatty (Fd : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Isatty, "isatty");
   use type Interfaces.C.int;
   function Is_Tty (Fd : Integer) return Boolean is (C_Isatty (Interfaces.C.int (Fd)) = 1);

   package Fx renames Ada.Strings.Fixed;
   package Str_Maps is new Ada.Containers.Indefinite_Hashed_Maps (String, String, Ada.Strings.Hash, "=");
   subtype U64 is Interfaces.Unsigned_64;
   use type U64;
   Texts : Str_Maps.Map;   --  everything loaded by Load_Keys

   function Img (N : Int) return String is (Fx.Trim (N'Image, Ada.Strings.Both));
   function Img (N : Integer) return String is (Img (Int (N)));

   function Clamp (V, Lo, Hi : Integer) return Integer is (Integer'Max (Lo, Integer'Min (Hi, V)));
   function Sgn (V : Int) return String is ((if V > 0 then "+" else "") & Img (V));

   function Data_Path (File : String) return String is
   begin
      return (if Ada.Directories.Exists ("data/" & File) then "data/" & File
              else Ada.Directories.Containing_Directory (Ada.Command_Line.Command_Name) & "/../data/" & File);
   exception
      when others => return "data/" & File;
   end Data_Path;

   procedure Read_Lines (File : String; Into : in out Str_Vectors.Vector; Found : out Boolean) is
      F : Ada.Text_IO.File_Type;
   begin
      Found := Ada.Directories.Exists (File);
      if Found then
         Ada.Text_IO.Open (F, Ada.Text_IO.In_File, File);
         while not Ada.Text_IO.End_Of_File (F) loop
            Into.Append (Ada.Text_IO.Get_Line (F));
         end loop;
         Ada.Text_IO.Close (F);
      end if;
   end Read_Lines;

   procedure Load_Keys (Lines : Str_Vectors.Vector) is
   begin
      for L of Lines loop
         if L'Length > 0 and then L (L'First) /= '#' and then Fx.Index (L, " = ") > 0 then
            Texts.Include (L (L'First .. Fx.Index (L, " = ") - 1), L (Fx.Index (L, " = ") + 3 .. L'Last));
         end if;
      end loop;
   end Load_Keys;

   function Msg (Key : String; A1, A2, A3, A4, A5, A6, A7 : String := "") return String is
      use Ada.Strings.Unbounded;
      A : constant array (1 .. 7) of Unbounded_String :=
        [To_Unbounded_String (A1), To_Unbounded_String (A2), To_Unbounded_String (A3), To_Unbounded_String (A4),
         To_Unbounded_String (A5), To_Unbounded_String (A6), To_Unbounded_String (A7)];
      R : Unbounded_String := To_Unbounded_String (if Texts.Contains (Key) then Texts (Key) else "[" & Key & "]");
      P : Natural;
   begin
      if not Texts.Contains (Key) then
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
      return (if Texts.Contains (Key) then To_String (R) else Fx.Trim (To_String (R), Ada.Strings.Both));
   end Msg;

   function Limit (Key : String; Default : Int) return Int is
      T : constant String := (if Texts.Contains (Key) then Fx.Trim (Texts (Key), Ada.Strings.Both) else "");
      Neg : constant Boolean := T'Length > 1 and then T (T'First) = '-';
      D : constant String := (if Neg then T (T'First + 1 .. T'Last) else T);
   begin
      if D'Length not in 1 .. 9 or else (for some C of D => C not in '0' .. '9') then
         return Default;
      end if;
      return (if Neg then -Int'Value (D) else Int'Value (D));
   end Limit;

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

   function Mix (X : U64) return U64 is
      Z : U64 := (X xor Interfaces.Shift_Right (X, 30)) * 16#BF58476D1CE4E5B9#;
   begin
      Z := (Z xor Interfaces.Shift_Right (Z, 27)) * 16#94D049BB133111EB#;
      return Z xor Interfaces.Shift_Right (Z, 31);
   end Mix;

   --  1 .. Sides from hash (seed, entity, tick, salt).
   function Roll (Seed : Int; Entity : Positive; Tick : Int; Salt : Natural; Sides : Positive) return Positive is
     (Natural (Mix (Mix (Mix (Mix (U64 (Seed) + 16#9E3779B97F4A7C15#) + U64 (Entity)) + U64 (Tick)) + U64 (Salt))
               mod U64 (Sides)) + 1);

   --  Base-60 pick, 0 .. 59: D4 (reroll on 1) = block 1/2/3 of 20, then D20.
   function Pick60 (Seed : Int; Entity : Positive; Tick : Int; Salt_Base : Natural) return Natural is
      Salt : Natural := Salt_Base;
      D4   : Positive;
   begin
      loop
         D4 := Roll (Seed, Entity, Tick, Salt, 4);
         Salt := Salt + 1;
         exit when D4 > 1 or else Salt > Salt_Base + 30;
      end loop;
      return (if D4 = 1 then 0 else D4 - 2) * 20 + Roll (Seed, Entity, Tick, Salt_Base + 40, 20) - 1;
   end Pick60;

   function Field (L, Key : String) return Int is   --  "key":-12 -> -12, else No_Value
      K : constant String := """" & Key & """:";
      P : constant Natural := Fx.Index (L, K);
      I : Natural := P + K'Length;
      Neg : constant Boolean := P > 0 and then I <= L'Last and then L (I) = '-';
      V : Int := 0;
   begin
      if Neg then I := I + 1; end if;
      if P = 0 or else I > L'Last or else L (I) not in '0' .. '9' then return No_Value; end if;
      while I <= L'Last and then L (I) in '0' .. '9' loop
         if V > Int'Last / 20 then return No_Value; end if;
         V := V * 10 + Int (Character'Pos (L (I)) - 48);
         I := I + 1;
      end loop;
      return (if Neg then -V else V);
   end Field;

   function Complete (L : String) return Boolean is
     (L'Length > 40 and then L (L'First .. L'First + 6) = "{""v"":1," and then L (L'Last - 1 .. L'Last) = "}}"
      and then Field (L, "seed") >= 0 and then Field (L, "tick") >= 0 and then Field (L, "energy") >= 0
      and then Field (L, "mood") /= No_Value and then Field (L, "location") >= 0);

   function No_Ts (L : String) return String is   --  the line without its timestamp
      P : constant Natural := Fx.Index (L, """ts"":""");
      Q : constant Natural := (if P = 0 then 0 else Fx.Index (L, """", P + 6));
   begin
      return (if Q = 0 then L else L (L'First .. P + 5) & L (Q .. L'Last));
   end No_Ts;

   function Stamp return String is   --  2026-10-03T02:19:00
      S : String := Ada.Calendar.Formatting.Image (Ada.Calendar.Clock);
   begin
      S (S'First + 10) := 'T';
      return S;
   end Stamp;

   function Esc (S : String) return String is
      R : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for C of S loop
         if C = '"' or else C = '\' then
            Ada.Strings.Unbounded.Append (R, '\');
         end if;
         Ada.Strings.Unbounded.Append (R, C);
      end loop;
      return Ada.Strings.Unbounded.To_String (R);
   end Esc;

   function Plain_Stamp return String is
      R : String (1 .. 15);
      N : Natural := 0;
   begin
      for C of Stamp loop
         if C in '0' .. '9' or else C = 'T' then
            N := N + 1;
            R (N) := (if C = 'T' then '_' else C);
         end if;
      end loop;
      return R;
   end Plain_Stamp;

   function Diff_At (A, B : String) return String is
      I : Positive := 1;
   begin
      while I <= A'Length and then I <= B'Length and then A (A'First + I - 1) = B (B'First + I - 1) loop
         I := I + 1;
      end loop;
      declare
         From : constant Positive := Integer'Max (1, I - 10);
         function Cut (S : String) return String is
           (if From > S'Length then "" else S (S'First + From - 1 .. S'First + Integer'Min (S'Length, From + 35) - 1));
      begin
         return "column" & I'Image & ": stored """ & Cut (A) & """ vs generated """ & Cut (B) & """";
      end;
   end Diff_At;

   function Frames (Trace : String) return String is
      R    : Ada.Strings.Unbounded.Unbounded_String;
      From : Positive := Trace'First;
   begin
      for I in Trace'Range loop
         if Trace (I) = ASCII.LF then
            declare
               L : constant String := Trace (From .. I - 1);
            begin
               if Fx.Index (L, " at ") > 0 and then Fx.Index (L, "???") = 0 and then Fx.Index (L, "b~") = 0 then
                  Ada.Strings.Unbounded.Append (R, L (Fx.Index (L, " ") + 1 .. L'Last) & ASCII.LF);   --  without the address
               end if;
            end;
            From := I + 1;
         end if;
      end loop;
      return Ada.Strings.Unbounded.To_String (R);
   end Frames;

end Sim_Util;
