--  Version: 0.001
pragma Ada_2022;

with Ada.Interrupts.Names, System;

package body Sim_Quit is

   protected Flag with Interrupt_Priority => System.Interrupt_Priority'Last is
      procedure Got_Int with Attach_Handler => Ada.Interrupts.Names.SIGINT;
      procedure Got_Term with Attach_Handler => Ada.Interrupts.Names.SIGTERM;
      function Signal return Natural;   --  0 none, 1 SIGINT, 2 SIGTERM
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
      function Signal return Natural is (Sig);
   end Flag;

   function Requested return Boolean is (Flag.Signal /= 0);
   function Which return String is
     (case Flag.Signal is when 1 => "SIGINT", when 2 => "SIGTERM", when others => "");

end Sim_Quit;
