--  Version: 0.002
--  Pure helpers of diary_sim: deterministic hash rolls and the diary line
--  format (read side).  Standard library only.
pragma Ada_2022;

package Sim_Util is

   subtype Int is Long_Long_Integer;

   function Img (N : Int) return String;         --  no leading blank
   function Img (N : Integer) return String;
   function Clamp (V, Hi : Integer) return Integer;   --  0 .. Hi
   function Stamp return String;                      --  2026-10-03T02:19:00
   function Plain_Stamp return String;                --  20261003_021900
   --  Where two lines first differ, as "column N" plus ~36 characters of each.
   function Diff_At (A, B : String) return String;
   --  The frames with source lines of a GNAT symbolic traceback, one per line.
   function Frames (Trace : String) return String;

   --  1 .. Sides, a pure function of (seed, entity, tick, salt): no RNG stream.
   function Roll (Seed : Int; Entity : Positive; Tick : Int; Salt : Natural; Sides : Positive) return Positive;
   --  Base-60 pick, 0 .. 59: D4 (reroll on 1) = block 1/2/3 of 20, then D20.
   function Pick60 (Seed : Int; Entity : Positive; Tick : Int) return Natural;

   function Field (L, Key : String) return Int;   --  "key":123 -> 123, else -1
   function Complete (L : String) return Boolean;  --  a whole diary line?
   function No_Ts (L : String) return String;      --  the line without its "ts"
   function Esc (S : String) return String;        --  JSON string escaping

end Sim_Util;
