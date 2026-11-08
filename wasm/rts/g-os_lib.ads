pragma Style_Checks (Off);
pragma Warnings (Off);
package GNAT.OS_Lib is
   type String_Access is access String;
   procedure Free (X : in out String_Access);

   type Argument_List is array (Positive range <>) of String_Access;
   type Process_Id is private;

   function Non_Blocking_Spawn (Program_Name : String; Args : Argument_List) return Process_Id;
   procedure Spawn (Program_Name : String; Args : Argument_List; Success : out Boolean);
   procedure Kill (Pid : Process_Id; Hard_Kill : Boolean := False);
   procedure Wait_Process (Pid : Process_Id; Success : out Boolean);
   function Pid_To_Integer (Pid : Process_Id) return Integer;
   function Current_Process_Id return Process_Id;
   function Getenv (Name : String) return String_Access;
   function Locate_Exec_On_Path (Exec_Name : String) return String_Access;
   procedure OS_Exit (Status : Integer);

private
   type Process_Id is new Integer;
end GNAT.OS_Lib;
