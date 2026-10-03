--  Version: 0.001
--  Ctrl-C (SIGINT) and SIGTERM only set a flag; the tick loop of diary_sim checks it
--  between ticks and stops cleanly (diaries are already flushed).  Standard library
--  only (Ada.Interrupts).  SIGKILL cannot be caught: debug.txt then keeps the
--  'in progress' stub that is refreshed every --every ticks.
pragma Ada_2022;

package Sim_Quit is
   function Requested return Boolean;
   function Which return String;   --  "SIGINT", "SIGTERM" or ""
end Sim_Quit;
