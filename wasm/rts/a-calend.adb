pragma Style_Checks (Off);
pragma Warnings (Off);
package body Ada.Calendar is

   --  A fixed clock.  Preview output does not include the wall time; differences
   --  that would not fit in this runtime's Duration are reported as zero.
   Epoch : constant Time := (Secs => 0);

   function Clock return Time is (Epoch);

   function Year (Date : Time) return Year_Number is
      pragma Unreferenced (Date);
   begin
      return 2026;
   end Year;
   function Month (Date : Time) return Month_Number is
      pragma Unreferenced (Date);
   begin
      return 1;
   end Month;
   function Day (Date : Time) return Day_Number is
      pragma Unreferenced (Date);
   begin
      return 1;
   end Day;
   function Seconds (Date : Time) return Day_Duration is
      pragma Unreferenced (Date);
   begin
      return 0.0;
   end Seconds;

   procedure Split
     (Date : Time; Year : out Year_Number; Month : out Month_Number; Day : out Day_Number; Seconds : out Day_Duration) is
   begin
      Year := Ada.Calendar.Year (Date);
      Month := Ada.Calendar.Month (Date);
      Day := Ada.Calendar.Day (Date);
      Seconds := Ada.Calendar.Seconds (Date);
   end Split;

   function Time_Of
     (Year : Year_Number; Month : Month_Number; Day : Day_Number; Seconds : Day_Duration := 0.0) return Time is
      pragma Unreferenced (Month, Day, Seconds);
   begin
      return (Secs => Long_Long_Integer (Year));
   end Time_Of;

   function "+" (Left : Time; Right : Duration) return Time is
      pragma Unreferenced (Right);
   begin
      return Left;
   end "+";
   function "+" (Left : Duration; Right : Time) return Time is
      pragma Unreferenced (Left);
   begin
      return Right;
   end "+";
   function "-" (Left : Time; Right : Duration) return Time is
      pragma Unreferenced (Right);
   begin
      return Left;
   end "-";
   function "-" (Left : Time; Right : Time) return Duration is
      pragma Unreferenced (Left, Right);
   begin
      return 0.0;
   end "-";
   function "<" (Left, Right : Time) return Boolean is (Left.Secs < Right.Secs);
   function "<=" (Left, Right : Time) return Boolean is (Left.Secs <= Right.Secs);
   function ">" (Left, Right : Time) return Boolean is (Left.Secs > Right.Secs);
   function ">=" (Left, Right : Time) return Boolean is (Left.Secs >= Right.Secs);
end Ada.Calendar;
