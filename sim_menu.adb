--  Version: 0.002
pragma Ada_2022;

with Ada.Characters.Handling, Ada.Strings.Fixed, Ada.Strings.Unbounded, Ada.Text_IO, Sim_Util;
use Ada.Strings.Unbounded, Sim_Util;

package body Sim_Menu is

   package TIO renames Ada.Text_IO;
   package Fx renames Ada.Strings.Fixed;

   ESC : constant Character := ASCII.ESC;
   Width : constant := 80;   --  the screen is assumed to be 80 columns wide

   --  ---- the block font -------------------------------------------------------------------
   type Size_Id is (Small, Medium, Large);
   type Glyph is record
      Rows : Str_Vectors.Vector;   --  empty: no such glyph
   end record;
   Font : array (Size_Id, Character) of Glyph;

   --  PROOF-LATER: Importance 2/10, Urgency 1/10, SPARK2 (parsing of data/fonts.txt)
   procedure Load_Font (Lines : Str_Vectors.Vector) is
      Size : Size_Id := Small;
      Have_Size : Boolean := False;
      Cur : Character := ' ';
      Have_Glyph : Boolean := False;
   begin
      for L of Lines loop
         declare
            T : constant String := Fx.Trim (L, Ada.Strings.Right);
         begin
            if T = "[small]" then Size := Small; Have_Size := True; Have_Glyph := False;
            elsif T = "[medium]" then Size := Medium; Have_Size := True; Have_Glyph := False;
            elsif T = "[large]" then Size := Large; Have_Size := True; Have_Glyph := False;
            elsif T'Length >= 9 and then T (T'First .. T'First + 7) = "glyph = " then
               declare
                  V : constant String := T (T'First + 8 .. T'Last);
               begin
                  Cur := (if V = "space" then ' ' elsif V'Length = 1 then V (V'First) else '?');
                  Have_Glyph := Have_Size and then (V = "space" or else V'Length = 1);
                  if Have_Glyph then Font (Size, Cur).Rows.Clear; end if;
               end;
            elsif Have_Glyph and then T'Length >= 2 and then T (T'First) = '|' and then T (T'Last) = '|' then
               Font (Size, Cur).Rows.Append (T (T'First + 1 .. T'Last - 1));
            end if;
         end;
      end loop;
   end Load_Font;

   function Glyph_Of (Size : Size_Id; C : Character) return Glyph is
      U : constant Character := Ada.Characters.Handling.To_Upper (C);
   begin
      if not Font (Size, U).Rows.Is_Empty then return Font (Size, U); end if;
      return Font (Size, '?');
   end Glyph_Of;

   --  The title word as rows of text ('#' = ink), one blank column between letters.
   function Title_Rows (Word : String; Size : Size_Id) return Str_Vectors.Vector is
      Res : Str_Vectors.Vector;
      H   : Natural := 0;
   begin
      for C of Word loop H := Natural'Max (H, Natural (Glyph_Of (Size, C).Rows.Length)); end loop;
      if H = 0 then   --  no font: plain spaced letters
         declare
            S : Unbounded_String;
         begin
            for C of Word loop Append (S, C & " "); end loop;
            Res.Append (Fx.Trim (To_String (S), Ada.Strings.Right));
            return Res;
         end;
      end if;
      for R in 1 .. H loop
         declare
            Row : Unbounded_String;
         begin
            for I in Word'Range loop
               declare
                  G : constant Glyph := Glyph_Of (Size, Word (I));
                  Cell : constant String := (if R <= Natural (G.Rows.Length) then G.Rows (R) else "");
               begin
                  for C of Cell loop Append (Row, (if C = ' ' then ' ' else '#')); end loop;
                  if I < Word'Last then Append (Row, ' '); end if;
               end;
            end loop;
            Res.Append (To_String (Row));
         end;
      end loop;
      return Res;
   end Title_Rows;

   function Title_Size return Size_Id is
      T : constant String := Msg ("title.size");
   begin
      return (if T = "small" then Small elsif T = "medium" then Medium else Large);
   end Title_Size;

   function Pad (N : Natural) return String is (Fx."*" (N, ' '));
   function Centered (S : String) return String is (if S'Length >= Width then S else Pad ((Width - S'Length) / 2) & S);

   --  ---- frames: one Put per screen ---------------------------------------------------------
   --  Home, then every row cleared to its end, then the rest of the screen cleared.
   function Frame_Text (Rows : Str_Vectors.Vector; Tail : String := "") return String is
      R : Unbounded_String := To_Unbounded_String (ESC & "[H");
   begin
      for L of Rows loop Append (R, L & ESC & "[K" & ASCII.LF); end loop;
      Append (R, ESC & "[J" & Tail);
      return To_String (R);
   end Frame_Text;

   procedure Put_Frame (S : String) is
   begin
      TIO.Put (S);
      TIO.Flush;
   end Put_Frame;

   --  ---- Life intro ------------------------------------------------------------------------
   H_Board : constant := 11;
   W_Board : constant := 60;
   type Board is array (1 .. H_Board, 1 .. W_Board) of Boolean;

   procedure Soup (B : out Board; Seed : in out Long_Long_Integer) is
   begin
      for R in Board'Range (1) loop
         for C in Board'Range (2) loop
            Seed := (Seed * 1_664_525 + 1_013_904_223) mod 4_294_967_296;
            B (R, C) := (Seed / 65_536) mod 100 < 35;
         end loop;
      end loop;
   end Soup;

   procedure Step (Cur : Board; Nxt : out Board) is
   begin
      for R in Board'Range (1) loop
         for C in Board'Range (2) loop
            declare
               N : Natural := 0;
            begin
               for DR in -1 .. 1 loop
                  for DC in -1 .. 1 loop
                     if DR /= 0 or else DC /= 0 then
                        if Cur ((R - 1 + DR + H_Board) mod H_Board + 1, (C - 1 + DC + W_Board) mod W_Board + 1) then
                           N := N + 1;
                        end if;
                     end if;
                  end loop;
               end loop;
               Nxt (R, C) := N = 3 or else (Cur (R, C) and then N = 2);
            end;
         end loop;
      end loop;
   end Step;

   procedure Intro (Seed : Natural) is
      Art : constant Str_Vectors.Vector := Title_Rows (Msg ("title"), Title_Size);
      Ink, Cells, Nxt, Seen : Board := [others => [others => False]];
      S : Long_Long_Integer := Long_Long_Integer (Seed) + 1;
      Frames : constant Natural := Natural (Int'Max (1, Limit ("intro.frames", 90)));
      Pause  : constant Duration := Duration (Int'Max (0, Limit ("intro.ms", 70))) / 1000.0;
      Top : constant Natural := Natural'Max (0, (H_Board - Natural (Art.Length)) / 2);
      Ink_Total, Seen_Ink : Natural := 0;

      function Frame_Of (Final : Boolean) return String is
         Rows : Str_Vectors.Vector;
      begin
         for R in Board'Range (1) loop
            declare
               Row : String (1 .. W_Board);
            begin
               for C in Board'Range (2) loop
                  Row (C) := (if Final then (if Ink (R, C) then '#' else ' ')
                              elsif Cells (R, C) then 'o'
                              elsif Seen (R, C) and then Ink (R, C) then '#'
                              else ' ');
               end loop;
               Rows.Append (Pad ((Width - W_Board) / 2) & Row);
            end;
         end loop;
         return Frame_Text (Rows);
      end Frame_Of;
   begin
      --  the hidden title: the art centred on the board
      for R in 1 .. Natural (Art.Length) loop
         declare
            Line : constant String := Art (R);
            Left : constant Natural := Natural'Max (0, (W_Board - Line'Length) / 2);
         begin
            for C in Line'Range loop
               if Line (C) = '#' and then Top + R <= H_Board and then Left + (C - Line'First + 1) <= W_Board then
                  Ink (Top + R, Left + (C - Line'First + 1)) := True;
                  Ink_Total := Ink_Total + 1;
               end if;
            end loop;
         end;
      end loop;
      Soup (Cells, S);
      Put_Frame (ESC & "[2J" & ESC & "[?25l" & Frame_Of (False));
      for Gen in 1 .. Frames loop
         Step (Cells, Nxt);
         for R in Board'Range (1) loop   --  a cell that dies reveals what is hidden under it
            for C in Board'Range (2) loop
               if Cells (R, C) and then not Nxt (R, C) then Seen (R, C) := True; end if;
            end loop;
         end loop;
         Cells := Nxt;
         Seen_Ink := 0;
         for R in Board'Range (1) loop
            for C in Board'Range (2) loop
               if Seen (R, C) and then Ink (R, C) then Seen_Ink := Seen_Ink + 1; end if;
            end loop;
         end loop;
         if Gen mod 20 = 0 and then Seen_Ink < Ink_Total then Soup (Cells, S); end if;   --  fresh life
         Put_Frame (Frame_Of (False));
         if Pause > 0.0 then delay Pause; end if;
         exit when Seen_Ink >= Ink_Total and then Gen >= 10;
      end loop;
      Put_Frame (Frame_Of (True) & ESC & "[?25h");
   end Intro;

   --  ---- the menu ---------------------------------------------------------------------------
   function Frame (Info : Str_Vectors.Vector; Notice : String) return String is
      Rows : Str_Vectors.Vector;
      Art  : constant Str_Vectors.Vector := Title_Rows (Msg ("title"), Title_Size);
   begin
      for L of Art loop Rows.Append (Centered (L)); end loop;
      Rows.Append ("");
      Rows.Append (Centered (Msg ("tagline")));
      Rows.Append ("");
      for L of Info loop Rows.Append ("  " & L); end loop;
      Rows.Append ("");
      for I in 1 .. 5 loop Rows.Append ("    " & Img (I) & ") " & Msg ("entry." & Img (I))); end loop;
      Rows.Append (if Notice = "" then "" else "  " & Notice);
      return Frame_Text (Rows, Msg ("menu.prompt") & " ");
   end Frame;

   function Ask (Info : Str_Vectors.Vector) return Choice is
      Notice : Unbounded_String;
   begin
      loop
         Put_Frame (ESC & "[2J" & Frame (Info, To_String (Notice)));
         declare
            A : constant String := Ada.Characters.Handling.To_Lower (Fx.Trim (TIO.Get_Line, Ada.Strings.Both));
            F : constant Character := (if A'Length > 0 then A (A'First) else ' ');
         begin
            if A = "1" or else (A'Length > 0 and then F = 'n') then return New_Game;
            elsif A = "2" or else (A'Length > 0 and then F = 'l') then return Load_Game;
            elsif A = "3" or else (A'Length > 0 and then F = 'i') then return Inbox;
            elsif A = "4" or else (A'Length > 0 and then F = 's') then return Settings;
            elsif A = "5" or else (A'Length > 0 and then F = 'q') then return Quit;
            end if;
            Notice := To_Unbounded_String (Msg ("menu.bad"));
         end;
      end loop;
   exception
      when TIO.End_Error =>
         TIO.New_Line;
         return Quit;
   end Ask;

   procedure Edit_Settings (Seed, Every : in out Int) is
      Keys : Str_Vectors.Vector;
      Notice : Unbounded_String;
   begin
      declare   --  the key names, split at blanks
         L : constant String := Msg ("settings.keys");
         From : Positive := L'First;
      begin
         for I in L'Range loop
            if L (I) = ' ' then
               if I > From then Keys.Append (L (From .. I - 1)); end if;
               From := I + 1;
            end if;
         end loop;
         if From <= L'Last then Keys.Append (L (From .. L'Last)); end if;
      end;
      loop
         declare
            Rows : Str_Vectors.Vector;
            N : constant Natural := Natural (Keys.Length) + 2;
         begin
            Rows.Append ("  " & Msg ("settings.title"));
            Rows.Append ("");
            Rows.Append ("    1) " & Msg ("settings.seed") & ": " & (if Seed < 0 then "42" else Img (Seed)));
            Rows.Append ("    2) " & Msg ("settings.every") & ": " & (if Every < 0 then "100" else Img (Every)));
            for I in 1 .. Natural (Keys.Length) loop
               Rows.Append ("    " & Img (I + 2) & ") " & Keys (I) & ": " & Img (Limit (Keys (I), 0)));
            end loop;
            Rows.Append ("");
            Rows.Append ("  " & Msg ("settings.warn"));
            Rows.Append (if Notice = "" then "" else "  " & To_String (Notice));
            Notice := Null_Unbounded_String;
            Put_Frame (ESC & "[2J" & Frame_Text (Rows, "  " & Msg ("settings.prompt") & " "));
            declare
               A : constant String := Fx.Trim (TIO.Get_Line, Ada.Strings.Both);
               Pick : constant Integer := (if A'Length in 1 .. 2 and then (for all C of A => C in '0' .. '9') then Integer'Value (A) else 0);
            begin
               exit when A = "";
               if Pick in 1 .. N then
                  declare
                     Name : constant String := (if Pick = 1 then "seed" elsif Pick = 2 then "every" else Keys (Pick - 2));
                  begin
                     TIO.Put (Msg ("settings.value", Name) & " ");
                     TIO.Flush;
                     declare
                        V : constant String := Fx.Trim (TIO.Get_Line, Ada.Strings.Both);
                     begin
                        if V'Length in 1 .. 9 and then (for all C of V => C in '0' .. '9') then
                           if Pick = 1 then Seed := Int'Value (V);
                           elsif Pick = 2 then Every := Int'Max (1, Int'Value (V));
                           else Set_Limit (Name, Int'Value (V));
                           end if;
                        else
                           Notice := To_Unbounded_String (Msg ("settings.bad"));
                        end if;
                     end;
                  end;
               else
                  Notice := To_Unbounded_String (Msg ("settings.bad"));
               end if;
            end;
         end;
      end loop;
   exception
      when TIO.End_Error => null;
   end Edit_Settings;

end Sim_Menu;
