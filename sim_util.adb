--  Version: 0.001
pragma Ada_2022;

with Ada.Calendar.Formatting, Ada.Strings.Fixed, Ada.Strings.Unbounded, Interfaces;

package body Sim_Util is

   package Fx renames Ada.Strings.Fixed;
   subtype U64 is Interfaces.Unsigned_64;
   use type U64;

   function Img (N : Int) return String is (Fx.Trim (N'Image, Ada.Strings.Both));
   function Img (N : Integer) return String is (Img (Int (N)));

   function Clamp (V, Hi : Integer) return Integer is (Integer'Max (0, Integer'Min (Hi, V)));
   function Clip (S : String) return String is (if S'Length > 100 then S (S'First .. S'First + 99) & "..." else S);

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
   function Pick60 (Seed : Int; Entity : Positive; Tick : Int) return Natural is
      Salt : Natural := 10;
      D4   : Positive;
   begin
      loop
         D4 := Roll (Seed, Entity, Tick, Salt, 4);
         Salt := Salt + 1;
         exit when D4 > 1 or else Salt > 40;
      end loop;
      return (if D4 = 1 then 0 else D4 - 2) * 20 + Roll (Seed, Entity, Tick, 50, 20) - 1;
   end Pick60;

   function Field (L, Key : String) return Int is   --  "key":123 -> 123, else -1
      K : constant String := """" & Key & """:";
      P : constant Natural := Fx.Index (L, K);
      V : Int := 0;
      I : Natural := P + K'Length;
   begin
      if P = 0 or else I > L'Last or else L (I) not in '0' .. '9' then return -1; end if;
      while I <= L'Last and then L (I) in '0' .. '9' loop
         if V > Int'Last / 20 then return -1; end if;
         V := V * 10 + Int (Character'Pos (L (I)) - 48);
         I := I + 1;
      end loop;
      return V;
   end Field;

   function Complete (L : String) return Boolean is
     (L'Length > 40 and then L (L'First .. L'First + 6) = "{""v"":1," and then L (L'Last - 1 .. L'Last) = "}}"
      and then Field (L, "seed") >= 0 and then Field (L, "tick") >= 0 and then Field (L, "energy") >= 0
      and then Field (L, "mood") >= 0 and then Field (L, "location") >= 0);

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

end Sim_Util;
