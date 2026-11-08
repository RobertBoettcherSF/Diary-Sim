pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Streams;

package Ada.Streams.Stream_IO is
   type File_Type is limited private;
   type File_Mode is (In_File, Out_File, Append_File);
   type Count is range 0 .. 2**62 - 1;
   subtype Positive_Count is Count range 1 .. Count'Last;
   type Stream_Access is access all Root_Stream_Type'Class;

   procedure Create (File : in out File_Type; Mode : File_Mode; Name : String);
   procedure Open (File : in out File_Type; Mode : File_Mode; Name : String);
   procedure Close (File : in out File_Type);
   function Is_Open (File : File_Type) return Boolean;
   function End_Of_File (File : File_Type) return Boolean;
   procedure Read (File : File_Type; Item : out Stream_Element_Array; Last : out Stream_Element_Offset);
   procedure Write (File : File_Type; Item : Stream_Element_Array);
   function Size (File : File_Type) return Count;
   procedure Set_Index (File : File_Type; To : Positive_Count);
   function Stream (File : File_Type) return Stream_Access;

private
   type File_Type is limited record
      Open : Boolean := False;
   end record;
end Ada.Streams.Stream_IO;
