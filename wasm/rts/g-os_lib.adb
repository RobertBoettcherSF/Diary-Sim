pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Unchecked_Deallocation;
with System.Machine_Code;

package body GNAT.OS_Lib is
   procedure Dealloc is new Ada.Unchecked_Deallocation (String, String_Access);

   procedure Free (X : in out String_Access) is
   begin
      Dealloc (X);
   end Free;

   function Non_Blocking_Spawn (Program_Name : String; Args : Argument_List) return Process_Id is
      pragma Unreferenced (Program_Name, Args);
   begin
      return 0;
   end Non_Blocking_Spawn;

   procedure Spawn (Program_Name : String; Args : Argument_List; Success : out Boolean) is
      pragma Unreferenced (Program_Name, Args);
   begin
      Success := False;
   end Spawn;

   procedure Kill (Pid : Process_Id; Hard_Kill : Boolean := False) is
      pragma Unreferenced (Pid, Hard_Kill);
   begin
      null;
   end Kill;

   procedure Wait_Process (Pid : Process_Id; Success : out Boolean) is
      pragma Unreferenced (Pid);
   begin
      Success := True;
   end Wait_Process;

   function Pid_To_Integer (Pid : Process_Id) return Integer is (Integer (Pid));
   function Current_Process_Id return Process_Id is (1);

   function Getenv (Name : String) return String_Access is
      pragma Unreferenced (Name);
   begin
      return new String'("");
   end Getenv;

   function Locate_Exec_On_Path (Exec_Name : String) return String_Access is
      pragma Unreferenced (Exec_Name);
   begin
      return null;
   end Locate_Exec_On_Path;

   procedure OS_Exit (Status : Integer) is
      pragma Unreferenced (Status);
   begin
      System.Machine_Code.Asm ("unreachable", Volatile => True);
   end OS_Exit;
end GNAT.OS_Lib;
