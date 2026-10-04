--  Version: 0.003
--  Ctrl-C (SIGINT), SIGTERM and SIGHUP (the terminal was closed) only set a flag; the tick loop of diary_sim checks it
--  between ticks and stops cleanly (diaries are already flushed).  Standard library
--  only (Ada.Interrupts).  SIGKILL cannot be caught: debug.txt then keeps the
--  'in progress' stub that is refreshed every --every ticks.
--  The key q (make night): Poll looks at the keyboard without waiting (Ada.Text_IO.Get_Immediate with its Available form, which
--  switches the terminal to single-key mode only for the moment of the call and puts it back, so the terminal is never left changed).
--  It does nothing unless Watch_Keys (True) was called, stdin is a terminal and this process is in the foreground of it (a job in
--  the background must not change the terminal modes: it would be stopped).
--  Typed lines (the chat, B2): after Set_Lines (True) Poll also edits one input line.  A line starts with @ or / (a bare q on an empty
--  line still quits, any other first key is dropped); Backspace deletes, Ctrl-U clears, Enter sends the line to the queue (Pending / Take),
--  Esc cancels the line, arrow and other escape sequences are ignored.  For this the terminal is switched, once, to "no echo, no line
--  buffering" with stty (the old settings are kept and put back by Restore, at the end of the run and by the finalization of this
--  package, so a crash does not leave the terminal changed; if it ever is: `stty sane`).  The program draws the line itself.
pragma Ada_2022;

package Sim_Quit is
   function Requested return Boolean;
   function Which return String;   --  "SIGINT", "SIGTERM", "SIGHUP" or ""
   procedure Watch_Keys (On : Boolean);
   function Watching return Boolean;   --  keys are read (On, a terminal, foreground)
   procedure Poll;                     --  read the typed keys; q or Q sets Key_Q; other keys are dropped
   function Key_Q return Boolean;
   procedure Ask_Quit;                 --  the same as the key q (the order /quit)
   procedure Set_Lines (On : Boolean; Max_Len : Positive := 120);   --  accept typed lines (needs Watching; the terminal is switched, see above)
   function Lines_On return Boolean;
   function Typing return String;      --  the line being typed ("" when none)
   function Changed return Natural;    --  counts every change of the line: the screen is drawn again when it moved
   function Pending return Boolean;    --  a finished line waits
   function Take return String;        --  the oldest finished line (removed)
   procedure Restore;                  --  the terminal as it was before Set_Lines (True); harmless when nothing was changed
end Sim_Quit;
