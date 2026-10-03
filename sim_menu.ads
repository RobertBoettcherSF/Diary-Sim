--  Version: 0.001
--  The main menu of diary_sim (terminal only): a Game-of-Life intro that reveals the title,
--  the title in block letters (data/fonts.txt), the tagline (data/menu.txt) and four entries.
--  Every screen is built as one string and written with a single Put (one frame).
--  Plain Ada, standard library only; all text comes from data/ (menu.txt, fonts.txt).
pragma Ada_2022;

with Sim_Util;

package Sim_Menu is

   type Choice is (New_Game, Load_Game, Settings, Quit);

   --  data/fonts.txt lines; call before Intro / Show (a missing font gives plain letters).
   procedure Load_Font (Lines : Sim_Util.Str_Vectors.Vector);

   --  The title rises out of the cells that die in a Conway Game of Life (B3/S23, torus).
   --  Ends with the full title on screen.  Needs a terminal (ANSI cursor codes).
   procedure Intro (Seed : Natural);

   --  The menu screen: title, tagline, Info lines, the four entries, Notice, prompt.
   function Frame (Info : Sim_Util.Str_Vectors.Vector; Notice : String) return String;

   --  Shows the menu once and reads one answer (1-4, n/l/s/q, a name); End_Of_File = Quit.
   --  A bad answer shows the notice menu.bad and asks again.
   function Ask (Info : Sim_Util.Str_Vectors.Vector) return Choice;

   --  The settings screen for this session only: seed and every (-1 = default) and the
   --  limits named in menu.txt settings.keys (Sim_Util.Set_Limit).  Returns on an empty answer.
   procedure Edit_Settings (Seed, Every : in out Sim_Util.Int);

end Sim_Menu;
