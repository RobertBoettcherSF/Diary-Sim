pragma Style_Checks (Off);
pragma Warnings (Off);
package body GNAT.Traceback.Symbolic is
   function Symbolic_Traceback (E : Ada.Exceptions.Exception_Occurrence) return String is
      pragma Unreferenced (E);
   begin
      return "";
   end Symbolic_Traceback;
end GNAT.Traceback.Symbolic;
