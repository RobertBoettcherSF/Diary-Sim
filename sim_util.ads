--  Version: 0.009
--  Pure helpers of diary_sim: deterministic hash rolls and the diary line
--  format (read side).  Standard library only.
pragma Ada_2022;

with Ada.Containers.Indefinite_Vectors;

package Sim_Util is

   subtype Int is Long_Long_Integer;
   package Str_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, String);
   No_Value : constant Int := Int'First;   --  Field: key missing or not a number

   --  ---- data/ files: "key = text" lines and wording ------------------------
   function Data_Path (File : String) return String;   --  ./data or <project root>/data
   --  The project (source) folder: the folder above bin/ that holds the executable (or the
   --  executable's own folder), absolute and fixed at the first call (call it before any cd).
   function Project_Root return String;
   --  The absolute path of this executable (call it before any cd: a relative name would no longer resolve).
   function Exe_Path return String;
   --  Copies a folder with everything in it (never moves or deletes anything).
   procedure Copy_Tree (From, To : String);
   procedure Read_Lines (File : String; Into : in out Str_Vectors.Vector; Found : out Boolean);
   procedure Load_Keys (Lines : Str_Vectors.Vector);   --  keep every "key = text" line
   --  A loaded text with {1}..{7} filled in and \n as line break; if the key
   --  is unknown (file missing) the key and the values.
   function Msg (Key : String; A1, A2, A3, A4, A5, A6, A7 : String := "") return String;
   function Limit (Key : String; Default : Int) return Int;   --  loaded whole number, signed
   procedure Set_Limit (Key : String; Value : Int);   --  this run only (the Settings menu); no file is written
   function Ends_With_Lf (File : String) return Boolean;

   function Img (N : Int) return String;         --  no leading blank
   function Img (N : Integer) return String;
   function Clamp (V, Lo, Hi : Integer) return Integer;
   function Sgn (V : Int) return String;   --  +12 or -5 or 0
   function Stamp return String;                      --  2026-10-03T02:19:00
   --  True when file descriptor Fd (0 = stdin, 1 = stdout) is a terminal (libc isatty).
   function Is_Tty (Fd : Integer) return Boolean;
   function Plain_Stamp return String;                --  20261003_021900
   --  Where two lines first differ, as: column N: stored "..." vs generated "..." (~36 characters of each).
   function Diff_At (A, B : String) return String;
   --  The frames with source lines of a GNAT symbolic traceback, one per line.
   function Frames (Trace : String) return String;

   --  1 .. Sides, a pure function of (seed, entity, tick, salt): no RNG stream.
   function Roll (Seed : Int; Entity : Positive; Tick : Int; Salt : Natural; Sides : Positive) return Positive;
   --  Base-60 pick, 0 .. 59: D4 (reroll on 1) = block 1/2/3 of 20, then D20.
   --  Salt_Base keeps independent picks of one tick apart (uses Salt_Base .. +40).
   function Pick60 (Seed : Int; Entity : Positive; Tick : Int; Salt_Base : Natural) return Natural;

   function Field (L, Key : String) return Int;   --  "key":-12 -> -12, else No_Value
   function Complete (L : String) return Boolean;  --  a whole diary line?
   function No_Ts (L : String) return String;      --  the line without its "ts"
   function Esc (S : String) return String;        --  JSON string escaping

end Sim_Util;
