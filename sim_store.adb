--  Version: 0.001
--  See sim_store.ads.
pragma Ada_2022;

with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Sim_Store is

   use Ada.Strings.Unbounded;

   function Key_Of (Line : String) return String is
      Sp : constant Natural := Ada.Strings.Fixed.Index (Line, " ");
   begin
      return (if Sp = 0 then Line else Line (Line'First .. Sp - 1));
   end Key_Of;

   --  The number after " t=" (-1 when there is none).
   function Tick_Of (Line : String) return Int is
      P : constant Natural := Ada.Strings.Fixed.Index (Line, " t=");
      N : Int := 0;
      I : Natural := P + 3;
   begin
      if P = 0 then return -1; end if;
      while I <= Line'Last and then Line (I) in '0' .. '9' and then N < 10 ** 12 loop
         N := N * 10 + Int (Character'Pos (Line (I)) - Character'Pos ('0'));
         I := I + 1;
      end loop;
      return N;
   end Tick_Of;

   procedure Clear (S : in out Store) is
   begin
      S.Lines.Clear;
      S.Hit.Clear;
      S.Index.Clear;
   end Clear;

   procedure Open (S : in out Store; Path, Header : String) is
      Lines : Str_Vectors.Vector;
      Found : Boolean;
   begin
      Clear (S);
      S.Path := To_Unbounded_String (Path);
      S.Header := To_Unbounded_String (Header);
      if not Ada.Directories.Exists (Path) then return; end if;
      Read_Lines (Path, Lines, Found);
      for L of Lines loop
         if L'Length > 1 and then L (L'First) /= '#' then
            S.Lines.Append (To_Unbounded_String (L));
            S.Hit.Append (False);
            S.Index.Include (Key_Of (L), Natural (S.Lines.Length));
         end if;
      end loop;
   end Open;

   procedure Emit (S : in out Store; Line : String; Write : Boolean; Result : out Status;
                   Old : out Unbounded_String) is
      Key : constant String := Key_Of (Line);
      C : constant Key_Maps.Cursor := S.Index.Find (Key);
      F : Ada.Text_IO.File_Type;
   begin
      Old := Null_Unbounded_String;
      if Key_Maps.Has_Element (C) then
         declare
            I : constant Positive := Key_Maps.Element (C);
         begin
            S.Hit.Replace_Element (I, True);
            if To_String (S.Lines (I)) = Line then
               Result := Same;
            else
               Old := S.Lines (I);
               Result := Differs;
            end if;
         end;
      elsif Write and then Length (S.Path) > 0 then
         if Ada.Directories.Exists (To_String (S.Path)) then
            Ada.Text_IO.Open (F, Ada.Text_IO.Append_File, To_String (S.Path));
         else
            Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, To_String (S.Path));
            Ada.Text_IO.Put_Line (F, To_String (S.Header));
         end if;
         Ada.Text_IO.Put_Line (F, Line);
         Ada.Text_IO.Close (F);
         S.Lines.Append (To_Unbounded_String (Line));
         S.Hit.Append (True);
         S.Index.Include (Key, Natural (S.Lines.Length));
         Result := Appended;
      else
         Result := Skipped;
      end if;
   end Emit;

   function Orphan (S : Store; Upto : Int) return String is
   begin
      for I in 1 .. Natural (S.Lines.Length) loop
         if not S.Hit (I) and then Tick_Of (To_String (S.Lines (I))) in 0 .. Upto then
            return To_String (S.Lines (I));
         end if;
      end loop;
      return "";
   end Orphan;

   function Count (S : Store) return Natural is (Natural (S.Lines.Length));

end Sim_Store;
