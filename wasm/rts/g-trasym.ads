pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Exceptions;

package GNAT.Traceback.Symbolic is
   function Symbolic_Traceback (E : Ada.Exceptions.Exception_Occurrence) return String;
end GNAT.Traceback.Symbolic;
