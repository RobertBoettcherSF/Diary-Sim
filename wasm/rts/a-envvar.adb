pragma Style_Checks (Off);
pragma Warnings (Off);
package body Ada.Environment_Variables is
   function Value (Name : String; Default : String := "") return String is
      pragma Unreferenced (Name);
   begin
      return Default;
   end Value;

   function Exists (Name : String) return Boolean is
      pragma Unreferenced (Name);
   begin
      return False;
   end Exists;
end Ada.Environment_Variables;
