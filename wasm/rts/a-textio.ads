pragma Style_Checks (Off);
pragma Warnings (Off);
with System;

package Ada.Text_IO is

   type File_Type is private;
   type File_Mode is (In_File, Out_File, Append_File);

   type Count is range 0 .. Integer'Last;
   subtype Positive_Count is Count range 1 .. Count'Last;
   Unbounded : constant Count := 0;

   subtype Field is Integer range 0 .. 255;
   subtype Number_Base is Integer range 2 .. 16;

   End_Error, Status_Error, Mode_Error, Name_Error, Use_Error, Device_Error, Data_Error, Layout_Error : exception;

   function Standard_Input return File_Type;
   function Standard_Output return File_Type;
   function Standard_Error return File_Type;

   procedure Create (File : in out File_Type; Mode : File_Mode; Name : String);
   procedure Open (File : in out File_Type; Mode : File_Mode; Name : String);
   procedure Close (File : in out File_Type);
   function Is_Open (File : File_Type) return Boolean;
   function End_Of_File (File : File_Type) return Boolean;
   function Get_Line (File : File_Type) return String;
   function Get_Line return String;
   procedure Get_Immediate (Item : out Character; Available : out Boolean);
   procedure Put (File : File_Type; Item : String);
   procedure Put (Item : String);
   procedure Put_Line (File : File_Type; Item : String);
   procedure Put_Line (Item : String);
   procedure New_Line (File : File_Type; Spacing : Positive_Count := 1);
   procedure New_Line (Spacing : Positive_Count := 1);
   procedure Flush (File : File_Type);
   procedure Flush;
   procedure Skip_Line (File : File_Type; Spacing : Positive_Count := 1);
   procedure Skip_Line (Spacing : Positive_Count := 1);
   function Known (Name : String) return Boolean;

   --  The preview text, flattened on the first call after the run.
   function Output_Ptr return System.Address;
   function Output_Len return Natural;
   pragma Export (C, Output_Ptr, "ds_out_ptr");
   pragma Export (C, Output_Len, "ds_out_len");

private
   --  The visible File_Type is limited, so a function can still move the read
   --  position: the position lives in the designated state, not in the value.
   type Kind_Id is (None, Stdout, Stderr, Disk);
   type State is record
      Kind : Kind_Id := None;
      Text : access String := null;
      Pos  : Natural := 1;
   end record;
   type State_Access is access all State;
   type File_Type is record
      Ptr : State_Access := null;
   end record;
end Ada.Text_IO;
