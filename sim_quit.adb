--  Version: 0.002
pragma Ada_2022;

with Ada.Interrupts.Names, Ada.Text_IO, Sim_Util, System;

package body Sim_Quit is

   protected Flag with Interrupt_Priority => System.Interrupt_Priority'Last is
      procedure Got_Int with Attach_Handler => Ada.Interrupts.Names.SIGINT;
      procedure Got_Term with Attach_Handler => Ada.Interrupts.Names.SIGTERM;
      procedure Got_Hup with Attach_Handler => Ada.Interrupts.Names.SIGHUP;
      function Signal return Natural;   --  0 none, 1 SIGINT, 2 SIGTERM, 3 SIGHUP
   private
      Sig : Natural := 0;
   end Flag;

   protected body Flag is
      procedure Got_Int is
      begin
         if Sig = 0 then Sig := 1; end if;
      end Got_Int;
      procedure Got_Term is
      begin
         if Sig = 0 then Sig := 2; end if;
      end Got_Term;
      procedure Got_Hup is
      begin
         if Sig = 0 then Sig := 3; end if;
      end Got_Hup;
      function Signal return Natural is (Sig);
   end Flag;

   function Requested return Boolean is (Flag.Signal /= 0);
   function Which return String is
     (case Flag.Signal is when 1 => "SIGINT", when 2 => "SIGTERM", when 3 => "SIGHUP", when others => "");

   Enabled, Q : Boolean := False;

   procedure Watch_Keys (On : Boolean) is
   begin
      Enabled := On;
   end Watch_Keys;

   function Watching return Boolean is (Enabled and then Sim_Util.Foreground);
   function Key_Q return Boolean is (Q);

   procedure Poll is
      C : Character;
      Av : Boolean;
   begin
      if not Watching then return; end if;
      loop
         Ada.Text_IO.Get_Immediate (C, Av);
         exit when not Av;
         if C in 'q' | 'Q' then Q := True; end if;
      end loop;
   exception
      when others => Enabled := False;   --  end of input or a terminal that cannot be read: no keys any more
   end Poll;

end Sim_Quit;
