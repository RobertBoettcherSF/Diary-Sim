pragma Style_Checks (Off);
pragma Warnings (Off);
package Ada.Directories is
   type File_Size is range 0 .. 2**62 - 1;
   type File_Kind is (Directory, Ordinary_File, Special_File);
   type Filter_Type is array (File_Kind) of Boolean;

   type Directory_Entry_Type is limited private;
   type Search_Type is limited private;

   function Exists (Name : String) return Boolean;
   function Size (Name : String) return File_Size;
   function Size (Directory_Entry : Directory_Entry_Type) return File_Size;
   function Kind (Name : String) return File_Kind;
   function Kind (Directory_Entry : Directory_Entry_Type) return File_Kind;
   function Simple_Name (Name : String) return String;
   function Simple_Name (Directory_Entry : Directory_Entry_Type) return String;
   function Full_Name (Name : String) return String;
   function Full_Name (Directory_Entry : Directory_Entry_Type) return String;
   function Containing_Directory (Name : String) return String;
   function Current_Directory return String;
   procedure Set_Directory (Directory : String);
   procedure Create_Path (New_Directory : String);
   procedure Delete_File (Name : String);
   procedure Rename (Old_Name, New_Name : String);
   procedure Copy_File (Source_Name, Target_Name : String);

   procedure Start_Search
     (Search : in out Search_Type; Directory : String; Pattern : String;
      Filter : Filter_Type := (others => True));
   function More_Entries (Search : Search_Type) return Boolean;
   procedure Get_Next_Entry (Search : in out Search_Type; Directory_Entry : out Directory_Entry_Type);
   procedure End_Search (Search : in out Search_Type);

private
   type Directory_Entry_Type is limited record
      Name : access String;
   end record;
   type Search_Type is limited record
      Live : Boolean := False;
   end record;
end Ada.Directories;
