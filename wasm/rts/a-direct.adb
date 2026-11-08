pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Text_IO;

package body Ada.Directories is

   function Slash (Name : String) return Natural is
   begin
      for I in reverse Name'Range loop
         if Name (I) = '/' then
            return I;
         end if;
      end loop;
      return 0;
   end Slash;

   function Simple_Name (Name : String) return String is
      S : constant Natural := Slash (Name);
   begin
      if S = 0 then
         return Name;
      end if;
      return Name (S + 1 .. Name'Last);
   end Simple_Name;

   function Containing_Directory (Name : String) return String is
      S : constant Natural := Slash (Name);
   begin
      if S <= Name'First then
         return ".";
      end if;
      return Name (Name'First .. S - 1);
   end Containing_Directory;

   function Full_Name (Name : String) return String is (Name);
   function Current_Directory return String is ("/diary");
   procedure Set_Directory (Directory : String) is null;
   procedure Create_Path (New_Directory : String) is null;
   procedure Delete_File (Name : String) is null;
   procedure Rename (Old_Name, New_Name : String) is null;
   procedure Copy_File (Source_Name, Target_Name : String) is null;

   --  A file is present when Text_IO can read it.  The directory itself is
   --  not listed, so checkpoint hashing (which walks the folder) stays idle
   --  on the preview path; Load_Data still opens data/<file>.
   function Exists (Name : String) return Boolean is
      Base : constant String := Simple_Name (Name);
   begin
      if Base'Length = 0 or else Base = "data" or else Name = "data" then
         return False;
      end if;
      return Ada.Text_IO.Known (Base) or else Ada.Text_IO.Known (Name);
   end Exists;

   function Size (Name : String) return File_Size is
     (if Exists (Name) then 1 else 0);
   function Size (Directory_Entry : Directory_Entry_Type) return File_Size is
      pragma Unreferenced (Directory_Entry);
   begin
      return 0;
   end Size;

   function Kind (Name : String) return File_Kind is
     (if Exists (Name) then Ordinary_File else Directory);

   function Kind (Directory_Entry : Directory_Entry_Type) return File_Kind is (Ordinary_File);
   function Simple_Name (Directory_Entry : Directory_Entry_Type) return String is ("");
   function Full_Name (Directory_Entry : Directory_Entry_Type) return String is ("");

   procedure Start_Search
     (Search : in out Search_Type; Directory : String; Pattern : String;
      Filter : Filter_Type := (others => True)) is
   begin
      Search.Live := False;
   end Start_Search;

   function More_Entries (Search : Search_Type) return Boolean is (False);
   procedure Get_Next_Entry (Search : in out Search_Type; Directory_Entry : out Directory_Entry_Type) is
   begin
      Directory_Entry.Name := null;
   end Get_Next_Entry;
   procedure End_Search (Search : in out Search_Type) is
   begin
      Search.Live := False;
   end End_Search;

end Ada.Directories;
