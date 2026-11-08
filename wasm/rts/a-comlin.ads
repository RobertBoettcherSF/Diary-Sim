pragma Style_Checks (Off);
pragma Warnings (Off);
package Ada.Command_Line is
   subtype Exit_Status is Integer;
   procedure Set_Exit_Status (Code : Exit_Status);
   function Command_Name return String;
   function Argument_Count return Natural;
   function Argument (Number : Positive) return String;
   procedure Set_Seed (Value : Integer);
   procedure Set_Ticks (Value : Integer);
   pragma Export (C, Set_Seed, "ds_set_seed");
   pragma Export (C, Set_Ticks, "ds_set_ticks");
end Ada.Command_Line;
