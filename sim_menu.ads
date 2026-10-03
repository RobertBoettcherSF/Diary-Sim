--  Version: 0.003
--  The main menu of diary_sim (terminal only): a Game-of-Life intro that reveals the title,
--  the title in block letters (data/fonts.txt), the tagline (data/menu.txt) and five entries.
--  Every screen is built as one string and written with a single Put (one frame).
--  Plain Ada, standard library only; all text comes from data/ (menu.txt, fonts.txt).
pragma Ada_2022;

with Sim_Util;

package Sim_Menu is

   type Choice is (New_Game, Load_Game, Inbox, Settings, Quit);

   --  data/fonts.txt lines; call before Intro / Show (a missing font gives plain letters).
   procedure Load_Font (Lines : Sim_Util.Str_Vectors.Vector);

   --  The title rises out of the cells that die in a Conway Game of Life (B3/S23, torus).
   --  Ends with the full title on screen.  Needs a terminal (ANSI cursor codes).
   --  Info (the menu's info lines) only sizes the title so that the menu fits the screen.
   procedure Intro (Seed : Natural; Info : Sim_Util.Str_Vectors.Vector);

   --  The menu screen, at most screen.rows (80x24) rows, one string: title (a smaller size if
   --  it would not fit), tagline, Info lines (clipped), the five entries as a plain list with
   --  the cursor mark ">" on Default, Notice or the hint, prompt.
   function Frame (Info : Sim_Util.Str_Vectors.Vector; Notice : String; Default : Choice) return String;

   --  Shows the menu once and reads one answer (1-5, n/l/i/s/q, a name; Enter = Default);
   --  End_Of_File = Quit.  A bad answer shows the notice menu.bad and asks again.
   function Ask (Info : Sim_Util.Str_Vectors.Vector; Default : Choice) return Choice;

   --  The settings screen for this session only: seed and every (-1 = default) and the
   --  limits named in menu.txt settings.keys (Sim_Util.Set_Limit).  Returns on an empty answer.
   procedure Edit_Settings (Seed, Every : in out Sim_Util.Int);

end Sim_Menu;
