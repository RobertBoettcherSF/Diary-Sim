--  Version: 0.003
--  See sim_ckpt.ads.
pragma Ada_2022;

with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;

package body Sim_Ckpt is

   use type Interfaces.Unsigned_64;
   package SIO renames Ada.Streams.Stream_IO;
   procedure Free is new Ada.Unchecked_Deallocation (Stream_Element_Array, Buffer_Access);

   overriding procedure Read (S : in out Mem_Stream; Item : out Stream_Element_Array; Last : out Stream_Element_Offset) is
      N : constant Stream_Element_Offset := Stream_Element_Offset'Min (Item'Length, S.Last - S.Pos);
   begin
      if N <= 0 then
         Last := Item'First - 1;
         return;
      end if;
      Item (Item'First .. Item'First + N - 1) := S.Buf (S.Pos + 1 .. S.Pos + N);
      S.Pos := S.Pos + N;
      Last := Item'First + N - 1;
   end Read;

   overriding procedure Write (S : in out Mem_Stream; Item : Stream_Element_Array) is
   begin
      if S.Buf = null then
         S.Buf := new Stream_Element_Array (1 .. Stream_Element_Offset'Max (1_048_576, 2 * Item'Length));
      elsif S.Last + Item'Length > S.Buf'Last then
         declare
            Bigger : constant Buffer_Access :=
              new Stream_Element_Array (1 .. Stream_Element_Offset'Max (2 * S.Buf'Last, S.Last + 2 * Item'Length));
            Old : Buffer_Access := S.Buf;
         begin
            Bigger (1 .. S.Last) := S.Buf (1 .. S.Last);
            S.Buf := Bigger;
            Free (Old);
         end;
      end if;
      S.Buf (S.Last + 1 .. S.Last + Item'Length) := Item;
      S.Last := S.Last + Item'Length;
   end Write;

   procedure Clear (S : in out Mem_Stream) is
   begin
      Free (S.Buf);
      S.Last := 0;
      S.Pos := 0;
   end Clear;

   procedure Rewind (S : in out Mem_Stream) is
   begin
      S.Pos := 0;
   end Rewind;

   --  the bytes of a string (a loop: GNAT 12 rejects the iterated aggregate over a String here)
   function To_Bytes (S : String) return Stream_Element_Array is
      R : Stream_Element_Array (1 .. Stream_Element_Offset (S'Length));
      K : Stream_Element_Offset := 0;
   begin
      for C of S loop
         K := K + 1;
         R (K) := Stream_Element (Character'Pos (C));
      end loop;
      return R;
   end To_Bytes;

   function Hash (A : Stream_Element_Array; H : Hash_T := Hash_Start) return Hash_T is
      R : Hash_T := H;
   begin
      for B of A loop
         R := (R xor Hash_T (B)) * 16#0000_0100_0000_01B3#;
      end loop;
      return R;
   end Hash;

   function Hash_Of (S : Mem_Stream; From, To : Stream_Element_Offset) return Hash_T is
     (if S.Buf = null or else To < From then Hash_Start else Hash (S.Buf (From .. To)));

   function Hex (H : Hash_T) return String is
      D : constant String := "0123456789abcdef";
      R : String (1 .. 16);
      V : Hash_T := H;
   begin
      for I in reverse R'Range loop
         R (I) := D (Natural (V and 15) + 1);
         V := Interfaces.Shift_Right (V, 4);
      end loop;
      return R;
   end Hex;

   function File_Size (Path : String) return Long_Long_Integer is
   begin
      if not Ada.Directories.Exists (Path) then return -1; end if;
      return Long_Long_Integer (Ada.Directories.Size (Path));
   exception
      when others => return -1;
   end File_Size;

   function File_Print (Path : String; Size : Long_Long_Integer) return String is
      F : SIO.File_Type;
      Tail_W : constant Long_Long_Integer := 65_536;
      Block : constant Long_Long_Integer := 4_096;
      Samples : constant := 32;
      Full_Max : constant Long_Long_Integer := 1_048_576;
      H1, H2 : Hash_T := Hash_Start;
      procedure Take (From, Len : Long_Long_Integer; H : in out Hash_T) is   --  From: 0-based
         B : Stream_Element_Array (1 .. Stream_Element_Offset (Len));
         N : Stream_Element_Offset;
      begin
         if Len <= 0 then return; end if;
         SIO.Set_Index (F, SIO.Positive_Count (From + 1));
         SIO.Read (F, B, N);
         if N /= B'Last then raise Constraint_Error; end if;
         H := Hash (B, H);
      end Take;
   begin
      if File_Size (Path) < Size then return ""; end if;
      SIO.Open (F, SIO.In_File, Path);
      Take (Long_Long_Integer'Max (0, Size - Tail_W), Long_Long_Integer'Min (Size, Tail_W), H1);
      if Size > Tail_W and then Size <= Full_Max then   --  a small file (the inputs: says, grants, vetoes ...): every byte
         declare
            At_B : Long_Long_Integer := 0;
         begin
            while At_B < Size loop
               Take (At_B, Long_Long_Integer'Min (Tail_W, Size - At_B), H2);
               At_B := At_B + Tail_W;
            end loop;
         end;
      elsif Size > Tail_W then
         for I in 0 .. Samples - 1 loop
            declare
               At_B : constant Long_Long_Integer := Size * Long_Long_Integer (I) / Samples;
            begin
               Take (At_B, Long_Long_Integer'Min (Block, Size - At_B), H2);
            end;
         end loop;
      end if;
      SIO.Close (F);
      return Hex (H1) & "-" & Hex (H2);
   exception
      when others =>
         if SIO.Is_Open (F) then SIO.Close (F); end if;
         return "";
   end File_Print;


   procedure Sorted_Names (Dir : String; Pattern : String; Files : Boolean; Into : in out Sim_Util.Str_Vectors.Vector) is
      use Ada.Directories;
      S : Search_Type;
      D : Directory_Entry_Type;
      Got : Sim_Util.Str_Vectors.Vector;
   begin
      if not Exists (Dir) then return; end if;
      Start_Search (S, Dir, Pattern, [Ordinary_File => Files, Directory => not Files, others => False]);
      while More_Entries (S) loop
         Get_Next_Entry (S, D);
         if Simple_Name (D) /= "." and then Simple_Name (D) /= ".." then Got.Append (Simple_Name (D)); end if;
      end loop;
      End_Search (S);
      declare
         package Sorting is new Sim_Util.Str_Vectors.Generic_Sorting;
      begin
         Sorting.Sort (Got);
      end;
      for N of Got loop Into.Append (N); end loop;
   end Sorted_Names;

   procedure Record_Files (Into : in out Sim_Util.Str_Vectors.Vector) is
      Names, Ents : Sim_Util.Str_Vectors.Vector;
   begin
      Sorted_Names ("diaries", "*", True, Names);
      for N of Names loop
         if N /= "inbox.txt" and then (N'Length < 4 or else N (N'Last - 3 .. N'Last) /= ".tmp") then   --  inbox.txt: a view, rewritten
            Into.Append ("diaries/" & N);
         end if;
      end loop;
      Sorted_Names ("entities", "*", False, Ents);
      for E of Ents loop
         Names.Clear;
         Sorted_Names ("entities/" & E, "*", True, Names);
         for N of Names loop Into.Append ("entities/" & E & "/" & N); end loop;
      end loop;
   end Record_Files;

   function Dir_Hash (Dir : String) return String is
      Names : Sim_Util.Str_Vectors.Vector;
      H : Hash_T := Hash_Start;
   begin
      Sorted_Names (Dir, "*.txt", True, Names);
      for N of Names loop
         declare
            P : constant String := Dir & "/" & N;
            Size : constant Long_Long_Integer := File_Size (P);
            F : SIO.File_Type;
         begin
            H := Hash (To_Bytes (N), H);
            if Size > 0 then
               declare
                  B : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
                  Got : Stream_Element_Offset;
               begin
                  SIO.Open (F, SIO.In_File, P);
                  SIO.Read (F, B, Got);
                  SIO.Close (F);
                  H := Hash (B (1 .. Got), H);
               end;
            end if;
         end;
      end loop;
      return Hex (H);
   end Dir_Hash;

   procedure IO (S : not null access Root_Stream_Type'Class; Save : Boolean; X : in out T) is
   begin
      if Save then T'Write (S, X); else T'Read (S, X); end if;
   end IO;

   procedure Write_File (Path, Head : String; S : Mem_Stream) is
      F : SIO.File_Type;
      Tmp : constant String := Path & ".tmp";
   begin
      SIO.Create (F, SIO.Out_File, Tmp);
      SIO.Write (F, To_Bytes (Head));
      if S.Buf /= null and then S.Last > 0 then SIO.Write (F, S.Buf (1 .. S.Last)); end if;
      SIO.Close (F);
      if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
      Ada.Directories.Rename (Tmp, Path);
   end Write_File;

   procedure Read_File (Path : String; Head : out Sim_Util.Str_Vectors.Vector; S : in out Mem_Stream; OK : out Boolean) is
      F : SIO.File_Type;
      Size : constant Long_Long_Integer := File_Size (Path);
      Line_Start : Stream_Element_Offset := 1;
   begin
      Head.Clear;
      Clear (S);
      OK := False;
      if Size <= 0 then return; end if;
      S.Buf := new Stream_Element_Array (1 .. Stream_Element_Offset (Size));
      SIO.Open (F, SIO.In_File, Path);
      SIO.Read (F, S.Buf.all, S.Last);
      SIO.Close (F);
      for I in 1 .. S.Last loop
         if S.Buf (I) = 10 then
            declare
               L : String (1 .. Natural (I - Line_Start));
            begin
               for J in L'Range loop L (J) := Character'Val (S.Buf (Line_Start + Stream_Element_Offset (J) - 1)); end loop;
               Line_Start := I + 1;
               if L = "end" then
                  S.Pos := I;   --  the payload follows
                  OK := True;
                  return;
               end if;
               Head.Append (L);
               exit when Natural (Head.Length) > 10_000;
            end;
         end if;
      end loop;
   exception
      when others =>
         if SIO.Is_Open (F) then SIO.Close (F); end if;
         OK := False;
   end Read_File;

end Sim_Ckpt;
