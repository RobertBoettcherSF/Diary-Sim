--  Headless stand-in for signals and the keyboard.  Preview never polls them.
--  The native body is sim_quit.adb.
package body Sim_Quit is
   function Requested return Boolean is (False);
   function Which return String is ("");

   procedure Watch_Keys (On : Boolean) is
      pragma Unreferenced (On);
   begin
      null;
   end Watch_Keys;

   function Watching return Boolean is (False);
   procedure Poll is null;
   function Key_Q return Boolean is (False);
   procedure Ask_Quit is null;
   procedure Forget_Q is null;

   procedure Set_Lines (On : Boolean; Max_Len : Positive := 120) is
      pragma Unreferenced (On, Max_Len);
   begin
      null;
   end Set_Lines;

   function Lines_On return Boolean is (False);
   function Typing return String is ("");
   function Changed return Natural is (0);
   function Pending return Boolean is (False);
   function Take return String is ("");
   procedure Restore is null;
end Sim_Quit;
