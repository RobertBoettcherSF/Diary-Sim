pragma Style_Checks (Off);
pragma Warnings (Off);
package Ada.Calendar.Formatting is
   function Time_Of
     (Year : Year_Number; Month : Month_Number; Day : Day_Number; Seconds : Day_Duration := 0.0) return Time;
   function Image (Date : Time; Include_Time_Fraction : Boolean := False) return String;
end Ada.Calendar.Formatting;
