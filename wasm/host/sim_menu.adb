--  Headless stand-in for the terminal menu.  The preview calls Load_Font while it
--  reads data/ and never draws a screen.  The native body is sim_menu.adb.
package body Sim_Menu is
   procedure Load_Font (Lines : Sim_Util.Str_Vectors.Vector) is
      pragma Unreferenced (Lines);
   begin
      null;
   end Load_Font;

   procedure Intro (Seed : Natural; Info : Sim_Util.Str_Vectors.Vector) is
      pragma Unreferenced (Seed, Info);
   begin
      null;
   end Intro;

   function Frame (Info : Sim_Util.Str_Vectors.Vector; Notice : String; Default : Choice) return String is
      pragma Unreferenced (Info, Notice, Default);
   begin
      return "";
   end Frame;

   function Ask (Info : Sim_Util.Str_Vectors.Vector; Default : Choice) return Choice is
      pragma Unreferenced (Info, Default);
   begin
      return Quit;
   end Ask;

   procedure Edit_Settings (Seed, Every : in out Sim_Util.Int) is
      pragma Unreferenced (Seed, Every);
   begin
      null;
   end Edit_Settings;
end Sim_Menu;
