pragma Style_Checks (Off);
pragma Warnings (Off);
package Ada.Environment_Variables is
   function Value (Name : String; Default : String := "") return String;
   function Exists (Name : String) return Boolean;
end Ada.Environment_Variables;
