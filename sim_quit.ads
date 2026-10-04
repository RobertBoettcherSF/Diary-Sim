--  Version: 0.002
--  Ctrl-C (SIGINT), SIGTERM and SIGHUP (the terminal was closed) only set a flag; the tick loop of diary_sim checks it
--  between ticks and stops cleanly (diaries are already flushed).  Standard library
--  only (Ada.Interrupts).  SIGKILL cannot be caught: debug.txt then keeps the
--  'in progress' stub that is refreshed every --every ticks.
--  The key q (make night): Poll looks at the keyboard without waiting (Ada.Text_IO.Get_Immediate with its Available form, which
--  switches the terminal to single-key mode only for the moment of the call and puts it back, so the terminal is never left changed).
--  It does nothing unless Watch_Keys (True) was called, stdin is a terminal and this process is in the foreground of it (a job in
--  the background must not change the terminal modes: it would be stopped).
pragma Ada_2022;

package Sim_Quit is
   function Requested return Boolean;
   function Which return String;   --  "SIGINT", "SIGTERM", "SIGHUP" or ""
   procedure Watch_Keys (On : Boolean);
   function Watching return Boolean;   --  keys are read (On, a terminal, foreground)
   procedure Poll;                     --  read the typed keys; q or Q sets Key_Q; other keys are dropped
   function Key_Q return Boolean;
end Sim_Quit;
