pragma Style_Checks (Off);
pragma Warnings (Off);
package body Ada.Streams.Stream_IO is
   procedure Create (File : in out File_Type; Mode : File_Mode; Name : String) is
      pragma Unreferenced (Mode, Name);
   begin
      File.Open := True;
   end Create;

   procedure Open (File : in out File_Type; Mode : File_Mode; Name : String) is
      pragma Unreferenced (Mode, Name);
   begin
      File.Open := True;
   end Open;

   procedure Close (File : in out File_Type) is
   begin
      File.Open := False;
   end Close;

   function Is_Open (File : File_Type) return Boolean is (File.Open);
   function End_Of_File (File : File_Type) return Boolean is
      pragma Unreferenced (File);
   begin
      return True;
   end End_Of_File;

   procedure Read (File : File_Type; Item : out Stream_Element_Array; Last : out Stream_Element_Offset) is
      pragma Unreferenced (File);
   begin
      Last := Item'First - 1;
   end Read;

   procedure Write (File : File_Type; Item : Stream_Element_Array) is
      pragma Unreferenced (File, Item);
   begin
      null;
   end Write;

   function Size (File : File_Type) return Count is
      pragma Unreferenced (File);
   begin
      return 0;
   end Size;

   procedure Set_Index (File : File_Type; To : Positive_Count) is
      pragma Unreferenced (File, To);
   begin
      null;
   end Set_Index;

   function Stream (File : File_Type) return Stream_Access is
      pragma Unreferenced (File);
   begin
      return null;
   end Stream;
end Ada.Streams.Stream_IO;
