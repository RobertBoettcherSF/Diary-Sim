--  Version: 0.008
--  See sim_screen.ads.
pragma Ada_2022;

with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Characters.Handling;
with Sim_Things;

package body Sim_Screen is

   use Ada.Strings.Unbounded;

   type Entry_Rec is record
      W : Positive := 1;
      Pinned : Boolean := False;
      Cmd : Boolean := False;       --  pinned by a robot command
   end record;
   package Entry_Vectors is new Ada.Containers.Vectors (Positive, Entry_Rec);
   package Word_Lists is new Ada.Containers.Vectors (Positive, Positive);
   type Note_Rec is record
      Owner : Entity_Id := 1;
      Tick : Int := 0;
      Words : Word_Lists.Vector;
   end record;
   package Note_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Note_Rec);
   type Counts is array (Entity_Id) of Natural;
   type Bools is array (Entity_Id) of Boolean;
   type Screens is array (Entity_Id) of Entry_Vectors.Vector;

   Scr : Screens;
   Notes : Note_Maps.Map;
   Started : Bools := [others => False];
   C_Taught, C_Coined, C_Shown, C_Left, C_Read, C_Pins : Counts := [others => 0];
   Pend : Str_Vectors.Vector;
   Reads : Read_Vectors.Vector;
   type Frames is array (Entity_Id) of Str_Vectors.Vector;
   Cam_Frame : Frames;
   Frame_Err : array (Entity_Id) of Unbounded_String;
   Seed_V, Cap_V : Int := 0;
   Scoin_On : Boolean := False;                 --  this session is a scoin=1 session
   Ses_Coined : Counts := [others => 0];        --  screen blends per wesen in this session (scoin=1)
   Coin_Pct_S, Coin_Cap_S : Integer := 1;
   Cols, Rows, Max_Pins, Start_N, Pin_Pct, Drop_Pct, Show_Pct, Read_N, Learn_Pct, Leave_Pct, Leave_N, Note_Pct,
     Blend_Pct, Own_Blend_Pct : Integer := 1;

   function L (Key : String; D, Lo, Hi : Integer) return Integer is
     (Integer'Max (Lo, Integer'Min (Hi, Integer (Limit (Key, Int (D))))));

   procedure Init (Seed, Coin_Cap : Int) is
   begin
      Seed_V := Seed;
      Cap_V := Coin_Cap;
      for E in Entity_Id loop Scr (E).Clear; end loop;
      Notes.Clear;
      Pend.Clear;
      Reads.Clear;
      for E in Entity_Id loop Cam_Frame (E).Clear; Frame_Err (E) := Null_Unbounded_String; end loop;
      Started := [others => False];
      Scoin_On := False; Ses_Coined := [others => 0];
      C_Taught := [others => 0]; C_Coined := [others => 0]; C_Shown := [others => 0];
      C_Left := [others => 0]; C_Read := [others => 0]; C_Pins := [others => 0];
      Cols := L ("screen.width", 20, 8, 40);
      Rows := L ("screen.height", 6, 2, 12);
      Max_Pins := L ("screen.pins", 3, 0, 8);
      Start_N := L ("screen.start", 5, 0, 12);
      Pin_Pct := L ("screen.pin_pct", 8, 0, 100);
      Drop_Pct := L ("screen.drop_pct", 8, 0, 100);
      Show_Pct := L ("screen.show_pct", 30, 0, 100);
      Read_N := L ("screen.read", 3, 1, 8);
      Learn_Pct := L ("screen.learn_pct", 35, 0, 100);
      Leave_Pct := L ("screen.leave_pct", 6, 0, 100);
      Leave_N := L ("screen.leave_words", 4, 1, 8);
      Note_Pct := L ("screen.note_pct", 15, 0, 100);
      Blend_Pct := L ("screen.blend_pct", 10, 0, 100);
      Own_Blend_Pct := L ("screen.own_blend_pct", 2, 0, 100);
      Coin_Pct_S := L ("screen.coin_pct", 5, 0, 100);
      Coin_Cap_S := L ("screen.coin_cap", 8, 0, 100);
   end Init;

   procedure Begin_Session (Scoin : Boolean) is
   begin
      Scoin_On := Scoin;
      Ses_Coined := [others => 0];
   end Begin_Session;

   --  ---- the layout: words in order, wrapped at Cols, Rows rows at most ------------------------------------------
   function Cell (E : Entity_Id; R : Entry_Rec) return String is
     ((if R.Pinned then "*" else "") & (if Knows (E, R.W) then "" else "?") & Word (R.W));

   --  Rows the entries (and one extra cell) would need; Natural'Last if a cell is wider than the screen.
   function Rows_Needed (E : Entity_Id; Extra : String) return Natural is
      Used, N : Natural := 0;
      procedure Put (T : String) is
      begin
         if Used = 0 then
            Used := T'Length; N := N + 1;
         elsif Used + 1 + T'Length <= Cols then
            Used := Used + 1 + T'Length;
         else
            Used := T'Length; N := N + 1;
         end if;
      end Put;
   begin
      for R of Scr (E) loop Put (Cell (E, R)); end loop;
      if Extra /= "" then Put (Extra); end if;
      return N;
   end Rows_Needed;

   function Index_Of (E : Entity_Id; W : Positive) return Natural is
   begin
      for I in 1 .. Natural (Scr (E).Length) loop
         if Scr (E) (I).W = W then return I; end if;
      end loop;
      return 0;
   end Index_Of;

   function Words_Of (E : Entity_Id) return String is
      R : Unbounded_String;
   begin
      for I in 1 .. Natural (Scr (E).Length) loop
         Append (R, (if I = 1 then "" else ",") & (if Scr (E) (I).Pinned then "*" else "") & Img (Scr (E) (I).W));
      end loop;
      return (if Length (R) = 0 then "-" else To_String (R));
   end Words_Of;

   function Count (E : Entity_Id) return Natural is (Natural (Scr (E).Length));

   procedure Event (E : Entity_Id; What : String) is
   begin
      Pend.Append (Name (E) & " " & What & " s=" & Words_Of (E));
   end Event;

   --  Evict the oldest unpinned words (never Keep) until the screen fits; False if it cannot.
   function Fit (E : Entity_Id; Keep : Positive) return Boolean is
   begin
      while Rows_Needed (E, "") > Rows loop
         declare
            Gone : Natural := 0;
         begin
            for I in 1 .. Natural (Scr (E).Length) loop
               if Gone = 0 and then not Scr (E) (I).Pinned and then Scr (E) (I).W /= Keep then Gone := I; end if;
            end loop;
            if Gone = 0 then return False; end if;
            Scr (E).Delete (Gone);
         end;
      end loop;
      return True;
   end Fit;

   --  Put W on E's screen (the oldest unpinned word makes room).  True if it was added.
   function Put (E : Entity_Id; W : Positive; Src : String) return Boolean is
      Probe : constant String := (if Knows (E, W) then "" else "?") & Word (W);
   begin
      if Index_Of (E, W) > 0 or else Probe'Length >= Cols then return False; end if;   --  one column stays free for "*"
      Scr (E).Append (Entry_Rec'(W => W, Pinned => False, Cmd => False));
      if not Fit (E, W) then
         Scr (E).Delete_Last;   --  nothing to drop: the new word does not fit
         return False;
      end if;
      Event (E, "add w=" & Img (W) & " src=" & Src);
      return True;
   end Put;

   procedure Note (E : Entity_Id; W : Positive; Src : String) is
      Ignore : Boolean;
   begin
      Ignore := Put (E, W, Src);
   end Note;

   --  ---- reading another screen or a note ------------------------------------------------------------------------
   function Pins_Of (E : Entity_Id) return Natural is
      N : Natural := 0;
   begin
      for R of Scr (E) loop N := N + Boolean'Pos (R.Pinned); end loop;
      return N;
   end Pins_Of;

   --  The viewer meets word W of the screen of Owner: known words are only seen; an unknown one is learned by chance.
   procedure Read_One (V, Owner : Entity_Id; W : Positive; Tick : Int; J : Natural;
                       Learned : in out Learn_Vectors.Vector; Got : in out Unbounded_String; N_Got : in out Natural) is
      Ignore : Boolean;
   begin
      if Knows (V, W) then
         Ignore := Put (V, W, "seen");
      elsif Blocked (W) or else Asleep (Owner, W) then   --  symbols=1: an old chess string is seen, never learned; active=1: nor a word dormant for the owner
         Ignore := Put (V, W, "seen");
      elsif Int (Roll (Seed_V, Positive (V), Tick, 9150 + J mod 10, 100)) <= Int (Learn_Pct)
        and then Slow_Pass (Seed_V, V, Tick + Int (J), Slow_Screen)   --  active=2 mint-slow: a viewer at the cap (salt 20872)
      then
         Learn_Word (V, W, Natural (Owner));
         Learned.Append (Learn_Rec'(Who => V, W => W, From => Natural (Owner), Coined => False));
         C_Taught (V) := C_Taught (V) + 1;
         N_Got := N_Got + 1;
         Append (Got, (if N_Got = 1 then "" else ",") & Img (W));
         Ignore := Put (V, W, "taught");
      else
         Ignore := Put (V, W, "seen");
      end if;
   end Read_One;

   --  A coined blend of A and B by Who: the head of A, a syllable of the name table (by chance) and the tail of B.
   procedure Try_Blend (Who : Entity_Id; A, B : Positive; Tick : Int; Salt : Natural;
                        Learned : in out Learn_Vectors.Vector; Detail : in out Unbounded_String; Done : out Boolean) is
      Wa : constant String := Word (A);
      Wb : constant String := Word (B);
      Ha : constant Natural := Natural'Min (Wa'Length, Natural'Max (2, (Wa'Length + 1) / 2));
      Tb : constant Natural := Natural'Min (Wb'Length, Natural'Max (2, Wb'Length / 2));
      Bridge : constant String :=
        (if Roll (Seed_V, Positive (Who), Tick, Salt, 2) = 1 then Sim_Things.Blend_Syllable (Who, Tick, Salt + 1) else "");
      Text : constant String := Ada.Characters.Handling.To_Lower (Wa (Wa'First .. Wa'First + Ha - 1) & Bridge
                                                                  & Wb (Wb'Last - Tb + 1 .. Wb'Last));
   begin
      Done := False;
      if (if Scoin_On then Ses_Coined (Who) >= Natural (Coin_Cap_S) else Int (Coined_Total) >= Cap_V) or else Text'Length < 3 or else Text'Length > 24
        or else (for some C of Text => C = ' ') or else Find (Text) /= 0
        or else Blocked (A) or else Blocked (B) or else Asleep (Who, A) or else Asleep (Who, B)   --  active=1: no blend from a dormant word
        or else Blocked_Text (Text)   --  symstrict=1: a blend that would read as a chess or number string (53+36 = 5336) is not made
        or else (Is_Clean and then not (Plain (A) and then Plain (B)))   --  records=1: no chess move is blended into a word
        or else not Slow_Pass (Seed_V, Who, Tick, Slow_Blend)   --  active=2 mint-slow: a wesen at the cap (salt 20873)
      then
         return;
      end if;
      declare
         W : constant Positive := Add_Coined (Text, A, B, Who);
         Ignore : Boolean;
      begin
         Use_Word (Who, A);
         Use_Word (Who, B);
         Learn_Word (Who, W);
         Learned.Append (Learn_Rec'(Who => Who, W => W, From => 0, Coined => True));
         C_Coined (Who) := C_Coined (Who) + 1;
         Ses_Coined (Who) := Ses_Coined (Who) + 1;
         Event (Who, "blend a=" & Img (A) & " b=" & Img (B) & " w=" & Img (W));
         Ignore := Put (Who, W, "coined");
         Append (Detail, (if Length (Detail) > 0 then "; " else "") & Msg ("detail.scr_blend", Text, Wa, Wb));
         Done := True;
      end;
   end Try_Blend;

   procedure Step (E : Entity_Id; Tick : Int; Lines : in out Str_Vectors.Vector;
                   Learned : in out Learn_Vectors.Vector; Detail : in out Unbounded_String) is
      Eid : constant Positive := Positive (E);
      Ignore : Boolean;

      procedure Say (T : String) is
      begin
         Append (Detail, (if Length (Detail) > 0 then "; " else "") & T);
      end Say;

      --  The viewer V reads up to Read_N consecutive words from List (a screen or a note).
      procedure Read_List (V, Owner : Entity_Id; List : Word_Lists.Vector; Kind : String; Where : String) is
         N : constant Natural := Natural (List.Length);
         Take : constant Natural := Natural'Min (N, Read_N);
         First : constant Natural := Roll (Seed_V, Positive (Owner), Tick, 9108, Positive'Max (1, N)) - 1;
         Got : Unbounded_String;
         N_Got : Natural := 0;
         Seen_W : Unbounded_String;
         Pair_Done : Boolean := False;
      begin
         for J in 0 .. Take - 1 loop
            declare
               W : constant Positive := List ((First + J) mod N + 1);
            begin
               Append (Seen_W, (if J = 0 then "" else ",") & Img (W));
               Read_One (V, Owner, W, Tick, J, Learned, Got, N_Got);
            end;
         end loop;
         Reads.Append (Read_Rec'(Viewer => V, Owner => Owner));
         Event (Owner, Kind & " " & Name (V) & Where & " w=" & To_String (Seen_W) & " l=" & (if N_Got = 0 then "-" else To_String (Got)));
         for J in 0 .. Take - 2 loop   --  two words side by side may blend
            declare
               A : constant Positive := List ((First + J) mod N + 1);
               B : constant Positive := List ((First + J + 1) mod N + 1);
            begin
               if not Pair_Done and then A /= B and then Knows (V, A) and then Knows (V, B)
                 and then Int (Roll (Seed_V, Positive (V), Tick, 9160 + J mod 8, 100)) <= Int (if Scoin_On then Coin_Pct_S else Blend_Pct)
               then
                  declare
                     Lc : Learn_Vectors.Vector;
                     Dt : Unbounded_String;
                  begin
                     Try_Blend (V, A, B, Tick, 9180 + 2 * (J mod 8), Lc, Dt, Pair_Done);
                     for X of Lc loop Learned.Append (X); end loop;
                     if Pair_Done and then V = E then Say (To_String (Dt)); end if;
                  end;
               end if;
            end;
         end loop;
         Say (Msg ((if Kind = "show" then "detail.scr_show" else "detail.scr_read"), Name (V), Img (Take), Img (N_Got)));
      end Read_List;

      function Screen_List (O : Entity_Id) return Word_Lists.Vector is
         R : Word_Lists.Vector;
      begin
         for X of Scr (O) loop R.Append (X.W); end loop;
         return R;
      end Screen_List;
   begin
      Lines.Append_Vector (Pend);
      Pend.Clear;
      --  the first screen tick: a few words E knows
      if not Started (E) then
         Started (E) := True;
         for I in 1 .. Start_N loop
            if Usable_Count (E) > 0 then
               Ignore := Put (E, Nth_Usable (E, Roll (Seed_V, Eid, Tick, 9100 + I, Usable_Count (E))), "init");   --  active=1: no dormant word
            end if;
         end loop;
      end if;
      --  pin and drop
      if Count (E) > 0 and then Int (Roll (Seed_V, Eid, Tick, 9101, 100)) <= Int (Pin_Pct) and then Pins_Of (E) < Max_Pins then
         declare
            I : constant Positive := Roll (Seed_V, Eid, Tick, 9102, Count (E));
         begin
            if not Scr (E) (I).Pinned then
               declare
                  R : Entry_Rec := Scr (E) (I);
               begin
                  R.Pinned := True;
                  Scr (E).Delete (I);
                  Scr (E).Insert (1, R);   --  pinned words stay at the top
                  if Fit (E, R.W) then
                     C_Pins (E) := C_Pins (E) + 1;
                     Event (E, "pin w=" & Img (R.W));
                     Say (Msg ("detail.scr_pin", Word (R.W)));
                  else
                     R.Pinned := False;   --  the "*" does not fit: nothing changes
                     Scr (E).Delete (1);
                     Scr (E).Insert (I, R);
                  end if;
               end;
            end if;
         end;
      end if;
      if Count (E) > 0 and then Int (Roll (Seed_V, Eid, Tick, 9103, 100)) <= Int (Drop_Pct) then
         declare
            Free : Natural := 0;
         begin
            for R of Scr (E) loop Free := Free + Boolean'Pos (not R.Pinned); end loop;
            if Free > 0 then
               declare
                  K : Integer := Roll (Seed_V, Eid, Tick, 9104, Free);
                  W : Natural := 0;
               begin
                  for I in 1 .. Count (E) loop
                     if not Scr (E) (I).Pinned then
                        K := K - 1;
                        if K = 0 and then W = 0 then W := I; end if;
                     end if;
                  end loop;
                  declare
                     Gone : constant Positive := Scr (E) (W).W;
                  begin
                     Scr (E).Delete (W);
                     Event (E, "drop w=" & Img (Gone));
                     Say (Msg ("detail.scr_drop", Word (Gone)));
                  end;
               end;
            end if;
         end;
      end if;
      --  two words side by side on its own screen
      if Count (E) >= 2 and then Int (Roll (Seed_V, Eid, Tick, 9111, 100)) <= Int (Own_Blend_Pct) then
         declare
            I : constant Positive := Roll (Seed_V, Eid, Tick, 9112, Count (E) - 1);
            A : constant Positive := Scr (E) (I).W;
            B : constant Positive := Scr (E) (I + 1).W;
            Lc : Learn_Vectors.Vector;
            Done : Boolean;
         begin
            if Knows (E, A) and then Knows (E, B) then
               Try_Blend (E, A, B, Tick, 9196, Lc, Detail, Done);
               for X of Lc loop Learned.Append (X); end loop;
            end if;
         end;
      end if;
      --  show the screen to a wesen in the same or a neighbouring cell
      declare
         Adj : Natural := 0;
      begin
         for O in Entity_Id loop
            if O /= E and then Sim_Things.Adjacent (E, O) then Adj := Adj + 1; end if;
         end loop;
         if Adj > 0 and then Count (E) > 0 and then Int (Roll (Seed_V, Eid, Tick, 9106, 100)) <= Int (Show_Pct) then
            declare
               K : Integer := Roll (Seed_V, Eid, Tick, 9105, Adj);
               V : Entity_Id := E;
            begin
               for O in Entity_Id loop
                  if O /= E and then Sim_Things.Adjacent (E, O) then
                     K := K - 1;
                     if K = 0 then V := O; end if;
                  end if;
               end loop;
               C_Shown (E) := C_Shown (E) + 1;
               Read_List (V, E, Screen_List (E), "show", "");
            end;
         end if;
      end;
      --  a note left on a thing within reach; and leaving one
      declare
         R : constant Sim_Things.Reach_Vectors.Vector := Sim_Things.Reach (E);
         Read_Done : Boolean := False;
      begin
         for I in 1 .. Natural (R.Length) loop
            declare
               Key : constant String := Sim_Things.Thing_Key (R (I).X, R (I).Y, R (I).T);
            begin
               if not Read_Done and then Notes.Contains (Key) and then Notes (Key).Owner /= E
                 and then Int (Roll (Seed_V, Eid, Tick, 9170 + I mod 8, 100)) <= Int (Note_Pct)
               then
                  Read_Done := True;
                  C_Read (E) := C_Read (E) + 1;
                  Read_List (E, Notes (Key).Owner, Notes (Key).Words, "read", " at=" & Key);
               end if;
            end;
         end loop;
         if not R.Is_Empty and then Count (E) > 0 and then Int (Roll (Seed_V, Eid, Tick, 9120, 100)) <= Int (Leave_Pct) then
            declare
               It : constant Sim_Things.Reach_Item := R (Roll (Seed_V, Eid, Tick, 9121, Natural (R.Length)));
               Key : constant String := Sim_Things.Thing_Key (It.X, It.Y, It.T);
               Nt : Note_Rec;
               Ids : Unbounded_String;
            begin
               Nt.Owner := E;
               Nt.Tick := Tick;
               for X of Scr (E) loop
                  if Natural (Nt.Words.Length) < Leave_N then
                     Nt.Words.Append (X.W);
                     Append (Ids, (if Length (Ids) = 0 then "" else ",") & Img (X.W));
                  end if;
               end loop;
               Notes.Include (Key, Nt);
               C_Left (E) := C_Left (E) + 1;
               Event (E, "leave at=" & Key & " w=" & To_String (Ids));
               Say (Msg ("detail.scr_leave", Img (Natural (Nt.Words.Length))));
            end;
         end if;
      end;
      Lines.Append_Vector (Pend);
      Pend.Clear;
   end Step;

   --  ---- the robot's hooks ----------------------------------------------------------------------------------------------
   procedure Pin_Command (E : Entity_Id; W1, W2 : Natural) is
      Ignore : Boolean;
      Todo : constant array (1 .. 2) of Natural := [W1, W2];
   begin
      for I in 1 .. Natural (Scr (E).Length) loop   --  release the earlier command
         if Scr (E) (I).Cmd then Scr (E) (I).Cmd := False; Scr (E) (I).Pinned := False; end if;
      end loop;
      for W of Todo loop
         if W > 0 then
            Ignore := Put (E, W, "robot");
            declare
               I : constant Natural := Index_Of (E, W);
            begin
               if I > 0 and then not Scr (E) (I).Pinned then
                  declare
                     R : Entry_Rec := Scr (E) (I);
                  begin
                     R.Pinned := True;
                     R.Cmd := True;
                     Scr (E).Delete (I);
                     Scr (E).Insert (1, R);
                     if not Fit (E, W) then   --  the "*" does not fit
                        R.Pinned := False; R.Cmd := False;
                        Scr (E).Delete (1);
                        Scr (E).Insert (Natural'Min (I, Natural (Scr (E).Length) + 1), R);
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
      Event (E, "cmd w=" & Words_Of (E));
   end Pin_Command;

   procedure Set_Frame (E : Entity_Id; Rows : Str_Vectors.Vector; Err : String) is
   begin
      Cam_Frame (E) := Rows;
      Frame_Err (E) := To_Unbounded_String (Err);
   end Set_Frame;

   function Has_Frame (E : Entity_Id) return Boolean is (not Cam_Frame (E).Is_Empty);
   function Frame_Of (E : Entity_Id) return Str_Vectors.Vector is (Cam_Frame (E));
   function Word_At (E : Entity_Id; I : Positive) return Positive is (Scr (E) (I).W);

   function Take_Reads return Read_Vectors.Vector is
      R : constant Read_Vectors.Vector := Reads;
   begin
      Reads.Clear;
      return R;
   end Take_Reads;

   function Box (E : Entity_Id) return Str_Vectors.Vector is
      Res : Str_Vectors.Vector;
      Frame : constant String := Msg ("screen.frame");   --  corner, horizontal, vertical
      Bar : constant String := Frame (Frame'First) & String'[1 .. Cols => Frame (Frame'First + 1)] & Frame (Frame'First);
      Side : constant Character := Frame (Frame'First + 2);
      Row : Unbounded_String;
      Used : Natural := 0;
      procedure Flush is
      begin
         Res.Append (Side & To_String (Row) & String'[1 .. Integer'Max (0, Cols - Length (Row)) => ' '] & Side);
         Row := Null_Unbounded_String;
         Used := Used + 1;
      end Flush;
   begin
      Res.Append (Bar);
      for R of Scr (E) loop
         declare
            T : constant String := Cell (E, R);
         begin
            if Length (Row) > 0 and then Length (Row) + 1 + T'Length > Cols then Flush; end if;
            Append (Row, (if Length (Row) > 0 then " " else "") & T);
         end;
      end loop;
      if Length (Row) > 0 then Flush; end if;
      for I in Used + 1 .. Rows loop
         Res.Append (Side & String'[1 .. Cols => ' '] & Side);
      end loop;
      Res.Append (Bar);
      --  below the frame (never a frame line): the camera view the robot wrote back, and its error
      for Line of Cam_Frame (E) loop Res.Append ("  " & Line); end loop;
      if Length (Frame_Err (E)) > 0 then Res.Append ("  " & Msg ("robot.screen_err", To_String (Frame_Err (E)))); end if;
      return Res;
   end Box;

   function Taught_From (E : Entity_Id) return Natural is (C_Taught (E));
   function Coined_From (E : Entity_Id) return Natural is (C_Coined (E));

   function Coined_All return Natural is
      N : Natural := 0;
   begin
      for E in Entity_Id loop N := N + C_Coined (E); end loop;
      return N;
   end Coined_All;
   function Shown (E : Entity_Id) return Natural is (C_Shown (E));
   function Left_Notes (E : Entity_Id) return Natural is (C_Left (E));
   function Read_Notes (E : Entity_Id) return Natural is (C_Read (E));
   function Notes_Now return Natural is (Natural (Notes.Length));

   function Summary (E : Entity_Id) return String is
     (Msg ("screen.sum", Name (E), Img (Count (E)), Img (Pins_Of (E)), Img (C_Shown (E)), Img (C_Left (E)), Img (C_Read (E)))
      & ASCII.LF & "  " & Msg ("screen.sum2", Img (C_Taught (E)), Img (C_Coined (E))));

end Sim_Screen;
