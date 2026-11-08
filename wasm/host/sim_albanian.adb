--  Headless stand-in.  The 200-tick preview never opens an alb=1 session, so the
--  book, the noun tables and the sentences are not part of that run.  Set_Data_Dir
--  is called while the program starts; everything else stays at the reset state.
--  The native body in sim_albanian.adb is what `make` builds.
with Ada.Streams;

package body Sim_Albanian is
   procedure Set_Data_Dir (Dir : String) is
      pragma Unreferenced (Dir);
   begin
      null;
   end Set_Data_Dir;

   procedure Reset is
   begin
      null;
   end Reset;

   function Zero return Boolean is (True);
   function Found return Natural is (0);
   function Genders_Now return String is ("uuuu");

   procedure Session (Seed : Int; N : Positive; Start : Int; Genders : String; Lines : in out Str_Vectors.Vector) is
      pragma Unreferenced (Seed, N, Start, Genders, Lines);
   begin
      null;
   end Session;

   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      pragma Unreferenced (S, Save);
   begin
      null;
   end State_IO;
end Sim_Albanian;
