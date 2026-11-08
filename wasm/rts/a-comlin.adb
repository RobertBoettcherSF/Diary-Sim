pragma Style_Checks (Off);
pragma Warnings (Off);
package body Ada.Command_Line is
   procedure Set_Exit_Status (Code : Exit_Status) is
      pragma Unreferenced (Code);
   begin
      null;
   end Set_Exit_Status;

   Seed_V : Integer := 42;
   Ticks_V : Integer := 200;

   function Trim (N : Integer) return String is
      Img : constant String := Integer'Image (N);
   begin
      if Img'Length > 0 and then Img (Img'First) = ' ' then
         return Img (Img'First + 1 .. Img'Last);
      end if;
      return Img;
   end Trim;

   function Command_Name return String is ("diary_sim");
   function Argument_Count return Natural is (5);
   function Argument (Number : Positive) return String is
   begin
      case Number is
         when 1 => return "--preview";
         when 2 => return "--ticks";
         when 3 => return Trim (Ticks_V);
         when 4 => return "--seed";
         when 5 => return Trim (Seed_V);
         when others => return "";
      end case;
   end Argument;

   procedure Set_Seed (Value : Integer) is
   begin
      Seed_V := Value;
   end Set_Seed;

   procedure Set_Ticks (Value : Integer) is
   begin
      Ticks_V := Value;
   end Set_Ticks;
end Ada.Command_Line;
