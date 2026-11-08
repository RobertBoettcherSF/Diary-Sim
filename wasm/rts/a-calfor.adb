pragma Style_Checks (Off);
pragma Warnings (Off);
package body Ada.Calendar.Formatting is
   function Time_Of
     (Year : Year_Number; Month : Month_Number; Day : Day_Number; Seconds : Day_Duration := 0.0) return Time is
     (Ada.Calendar.Time_Of (Year, Month, Day, Seconds));

   function Image (Date : Time; Include_Time_Fraction : Boolean := False) return String is
      pragma Unreferenced (Date, Include_Time_Fraction);
   begin
      return "2026-01-01 00:00:00";
   end Image;
end Ada.Calendar.Formatting;
