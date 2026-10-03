--  Version: 0.001
--  See sim_robot.ads.
pragma Ada_2022;

with Sim_Screen;
with Sim_Things;

package body Sim_Robot is

   use Ada.Strings.Unbounded;

   Max_Verbs : constant := 8;
   Max_Args : constant := 6;
   type Word_Array is array (1 .. Max_Args) of Natural;
   type Text_Array is array (1 .. Max_Args) of Unbounded_String;
   type Verb_Rec is record
      Text : Unbounded_String;
      Word : Natural := 0;
      N_Args : Natural := 0;
      Arg_Text : Text_Array;
      Arg_Word : Word_Array := [others => 0];
   end record;
   type Verb_Array is array (1 .. Max_Verbs) of Verb_Rec;
   type Ints is array (Entity_Id) of Int;
   type Counts is array (Entity_Id) of Natural;

   Seed_V : Int := 0;
   Is_Started : Boolean := False;
   Verbs : Verb_Array;
   N_Verbs : Natural := 0;
   RX, RY, Heading, Battery : Integer := 0;
   Carry : Boolean := False;
   Carry_T : Sim_Things.Thing;
   Ctl_Until : Ints := [others => -1];
   Issued, Errs : Counts := [others => 0];
   Replies : array (Entity_Id) of Unbounded_String;
   Last_Exec : Int := -1_000_000;
   Cmd_N, Err_N, Share_N : Natural := 0;
   Log : Str_Vectors.Vector;     --  the last commands, for the view

   --  the pending command
   Pend_Valid : Boolean := False;
   Pend_Who : Entity_Id := 1;
   Pend_Verb, Pend_Arg : Natural := 0;     --  0: unknown verb / no direction given
   Pend_Text : Unbounded_String;
   Pend_Ready : Int := 0;

   Reach, Max_B, Start_B, Charge, Radius, Trickle, Delay_B, Delay_X, Gap, Contact_Pct, Cmd_Pct, Sloppy_Pct, Window, Start_LM : Integer := 1;
   Cost_Go, Cost_Turn, Cost_Look, Cost_Pick, Cost_Push : Integer := 1;

   function L (Key : String; D, Lo, Hi : Integer) return Integer is
     (Integer'Max (Lo, Integer'Min (Hi, Integer (Limit (Key, Int (D))))));

   Dir_X : constant array (0 .. 3) of Integer := [0, 1, 0, -1];
   Dir_Y : constant array (0 .. 3) of Integer := [-1, 0, 1, 0];

   --  "a,b,c" -> the items
   function Items (T : String) return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
      From : Positive := T'First;
   begin
      if T'Length = 0 or else T (T'First) = '[' then return R; end if;
      for I in T'First .. T'Last + 1 loop
         if I > T'Last or else T (I) = ',' then
            if I > From then R.Append (T (From .. I - 1)); end if;
            From := I + 1;
         end if;
      end loop;
      return R;
   end Items;

   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
      Is_Started := False;
      N_Verbs := 0;
      Verbs := [others => (Text => Null_Unbounded_String, Word => 0, N_Args => 0, Arg_Text => [others => Null_Unbounded_String],
                           Arg_Word => [others => 0])];
      Ctl_Until := [others => -1];
      Issued := [others => 0]; Errs := [others => 0];
      for E in Entity_Id loop Replies (E) := Null_Unbounded_String; end loop;
      Pend_Valid := False;
      Last_Exec := -1_000_000;
      Cmd_N := 0; Err_N := 0; Share_N := 0;
      Carry := False;
      Log.Clear;
      Max_B := L ("robot.battery.max", 100, 10, 10_000);
      Start_B := L ("robot.battery.start", 100, 0, 10_000);
      Charge := L ("robot.charge", 10, 0, 1000);
      Radius := L ("robot.charge.radius", 2, 0, 20);
      Trickle := L ("robot.trickle", 10, 1, 100_000);
      Delay_B := L ("robot.delay", 3, 0, 1000);
      Delay_X := L ("robot.delay_extra", 3, 0, 1000);
      Gap := L ("robot.gap", 4, 1, 1000);
      Contact_Pct := L ("robot.contact_pct", 20, 0, 100);
      Cmd_Pct := L ("robot.cmd_pct", 12, 0, 100);
      Sloppy_Pct := L ("robot.sloppy_pct", 15, 0, 100);
      Window := L ("robot.window", 150, 1, 1_000_000);
      Start_LM := L ("robot.start", 1, 0, 3);
      Reach := L ("robot.reach", 3, 1, 10);
      Cost_Go := L ("robot.cost.go", 4, 0, 1000);
      Cost_Turn := L ("robot.cost.turn", 1, 0, 1000);
      Cost_Look := L ("robot.cost.look", 1, 0, 1000);
      Cost_Pick := L ("robot.cost.pick", 3, 0, 1000);
      Cost_Push := L ("robot.cost.push", 5, 0, 1000);
   end Init;

   function Started return Boolean is (Is_Started);
   function Steers (E : Entity_Id; Tick : Int) return Boolean is (Ctl_Until (E) >= Tick);
   function Count_Commands return Natural is (Cmd_N);
   function Count_Errors return Natural is (Err_N);

   function Verb_Index (Text : String) return Natural is
   begin
      for V in 1 .. N_Verbs loop
         if To_String (Verbs (V).Text) = Text then return V; end if;
      end loop;
      return 0;
   end Verb_Index;

   function Cost_Of (V : Natural) return Integer is
     (if V = 0 then 0 else
        (if To_String (Verbs (V).Text) = "go" then Cost_Go elsif To_String (Verbs (V).Text) = "turn" then Cost_Turn
         elsif To_String (Verbs (V).Text) = "look" then Cost_Look elsif To_String (Verbs (V).Text) = "pick" then Cost_Pick
         else Cost_Push));

   procedure Begin_Life (Tick : Int) is
      Names : constant Str_Vectors.Vector := Items (Msg ("robot.verbs"));
   begin
      if Is_Started then return; end if;
      Is_Started := True;
      N_Verbs := Natural'Min (Max_Verbs, Natural (Names.Length));
      for V in 1 .. N_Verbs loop
         Verbs (V).Text := To_Unbounded_String (Names (V));
         Verbs (V).Word := Sim_Things.Prop_Word (Names (V), Msg ("robot.meaning"));
         declare
            A : constant Str_Vectors.Vector := Items (Msg ("robot.args." & Names (V)));
         begin
            Verbs (V).N_Args := Natural'Min (Max_Args, Natural (A.Length));
            for K in 1 .. Verbs (V).N_Args loop
               Verbs (V).Arg_Text (K) := To_Unbounded_String (A (K));
               Verbs (V).Arg_Word (K) := Sim_Things.Prop_Word (A (K), Msg ("robot.meaning"));
            end loop;
         end;
      end loop;
      RX := Sim_Things.Landmark_X (Start_LM) + 1;
      RY := Sim_Things.Landmark_Y (Start_LM);
      Heading := 0;
      Battery := Integer'Min (Max_B, Start_B);
      Last_Exec := Tick - Int (Gap);
   end Begin_Life;

   function Heading_Text (H : Integer) return String is (Msg ("robot.dir." & Img (H mod 4)));
   function Glyph return Character is
      G : constant String := Msg ("robot.glyph");
   begin
      return (if G'Length >= 4 and then G (G'First) /= '[' then G (G'First + Heading mod 4) else 'R');
   end Glyph;

   function Camera_Text (Rows : Str_Vectors.Vector) return String is
      R : Unbounded_String;
   begin
      for I in 1 .. Natural (Rows.Length) loop Append (R, (if I = 1 then "" else "|") & Rows (I)); end loop;
      return To_String (R);
   end Camera_Text;

   function Carry_Text return String is
     (if Carry then Sim_Things.Description (Carry_T) else Msg ("robot.nothing"));

   --  ---- the robot acts -----------------------------------------------------------------------------------------------
   procedure Execute (Tick : Int; Lines : in out Str_Vectors.Vector) is
      E : constant Entity_Id := Pend_Who;
      Err : Unbounded_String;
      Reply : Unbounded_String;
      Text : constant String := To_String (Pend_Text);
      Cost : constant Integer := Cost_Of (Pend_Verb);

      procedure See (T : Sim_Things.Thing) is   --  the controller's screen gets the name of a thing the robot met
      begin
         Sim_Screen.Note (E, Sim_Things.Name_Word (T), "robot");
      end See;
   begin
      Pend_Valid := False;
      Last_Exec := Tick;
      if Pend_Verb = 0 then
         Err := To_Unbounded_String (Msg ("robot.err.unknown", Text));
      elsif Verbs (Pend_Verb).N_Args > 0 and then Pend_Arg = 0 then
         Err := To_Unbounded_String (Msg ("robot.err.noarg", Text));
      elsif Battery < Cost then
         Err := To_Unbounded_String (Msg ("robot.err.battery", Img (Battery)));
      else
         declare
            Verb : constant String := To_String (Verbs (Pend_Verb).Text);
         begin
            Battery := Battery - Cost;
            if Verb = "go" then
               Heading := Pend_Arg - 1;
               RX := RX + Dir_X (Heading);
               RY := RY + Dir_Y (Heading);
               Reply := To_Unbounded_String (Msg ("robot.ok.go", Heading_Text (Heading), Img (RX), Img (RY)));
            elsif Verb = "turn" then
               Heading := (Heading + (if To_String (Verbs (Pend_Verb).Arg_Text (Pend_Arg)) = "left" then 3 else 1)) mod 4;
               Reply := To_Unbounded_String (Msg ("robot.ok.turn", Heading_Text (Heading)));
            elsif Verb = "look" then
               declare
                  Seen : Natural := 0;
               begin
                  for Dy in -2 .. 2 loop
                     for Dx in -2 .. 2 loop
                        for T of Sim_Things.Things_At (RX + Dx, RY + Dy) loop
                           if Seen < 3 then See (T); Seen := Seen + 1; end if;
                        end loop;
                     end loop;
                  end loop;
                  Reply := To_Unbounded_String (Msg ("robot.ok.look", Img (Seen)));
               end;
            elsif Verb = "pick" then
               declare
                  Here : constant Sim_Things.Thing_Vectors.Vector := Sim_Things.Things_At (RX, RY);
               begin
                  if Carry then
                     Err := To_Unbounded_String (Msg ("robot.err.full"));
                     Battery := Battery + Cost;
                  elsif Here.Is_Empty then
                     Err := To_Unbounded_String (Msg ("robot.err.nothing"));
                     Battery := Battery + Cost;
                  else
                     Carry := True;
                     Carry_T := Here (1);
                     Sim_Things.Edit (Tick, Sim_Things.Gone, Carry_T, RX, RY, "robot");
                     See (Carry_T);
                     Reply := To_Unbounded_String (Msg ("robot.ok.pick", Sim_Things.Description (Carry_T)));
                  end if;
               end;
            else   --  push: the thing in front moves one cell on
               declare
                  Fx0 : constant Integer := RX + Dir_X (Heading);
                  Fy0 : constant Integer := RY + Dir_Y (Heading);
                  Ahead : constant Sim_Things.Thing_Vectors.Vector := Sim_Things.Things_At (Fx0, Fy0);
               begin
                  if Ahead.Is_Empty then
                     Err := To_Unbounded_String (Msg ("robot.err.ahead"));
                     Battery := Battery + Cost;
                  else
                     Sim_Things.Edit (Tick, Sim_Things.Gone, Ahead (1), Fx0, Fy0, "robot");
                     Sim_Things.Edit (Tick, Sim_Things.Add, Ahead (1), Fx0 + Dir_X (Heading), Fy0 + Dir_Y (Heading), "robot");
                     See (Ahead (1));
                     Reply := To_Unbounded_String (Msg ("robot.ok.push", Sim_Things.Description (Ahead (1))));
                  end if;
               end;
            end if;
         end;
      end if;
      declare
         Cam : constant Str_Vectors.Vector := Sim_Things.Camera (RX, RY, Glyph);
         Line : constant String := "exec " & Name (E) & " " & (if Text = "" then "-" else Text)
           & (if Length (Err) > 0 then " err=" & To_String (Err) else " ok") & " pos=" & Img (RX) & "," & Img (RY)
           & " h=" & Img (Heading) & " bat=" & Img (Battery) & " cam=" & Camera_Text (Cam);
      begin
         Lines.Append (Line);
         Log.Append ("t" & Img (Tick) & " " & Name (E) & " " & Text & ": "
                     & (if Length (Err) > 0 then To_String (Err) else To_String (Reply)));
         if Natural (Log.Length) > 8 then Log.Delete_First; end if;
         if Length (Err) > 0 then
            Err_N := Err_N + 1;
            Errs (E) := Errs (E) + 1;
            Sim_Screen.Set_Frame (E, Cam, To_String (Err));
            Replies (E) := To_Unbounded_String (Msg ("robot.reply.err", To_String (Err)));
         else
            Sim_Screen.Set_Frame (E, Cam, "");
            Replies (E) := To_Unbounded_String (To_String (Reply) & ", " & Msg ("robot.battery", Img (Battery)));
         end if;
      end;
   end Execute;

   procedure Tick_Begin (Tick : Int; Lines : in out Str_Vectors.Vector) is
   begin
      if not Is_Started then return; end if;
      if Charge > 0 and then Sim_Things.Near_Landmark (RX, RY, Radius) then
         Battery := Integer'Min (Max_B, Battery + Charge);
      elsif Tick mod Int (Trickle) = 0 then
         Battery := Integer'Min (Max_B, Battery + 1);
      end if;
      if Pend_Valid and then Tick >= Pend_Ready and then Tick - Last_Exec >= Int (Gap) then Execute (Tick, Lines); end if;
   end Tick_Begin;

   --  ---- the controller's step ------------------------------------------------------------------------------------------
   procedure Control (E : Entity_Id; Tick : Int; Lines : in out Str_Vectors.Vector; Learned : in out Str_Vectors.Vector;
                      Detail : in out Unbounded_String) is
      Eid : constant Positive := Positive (E);
      Contact : constant Boolean := Sim_Things.Placed (E) and then abs (Sim_Things.X (E) - RX) + abs (Sim_Things.Y (E) - RY) <= Reach;
      Pin_A, Pin_B : Natural := 0;
      Text : Unbounded_String;
      Verb, Arg : Natural := 0;
   begin
      if not Is_Started then return; end if;
      if Contact then
         Ctl_Until (E) := Tick + Int (Window);
         if Int (Roll (Seed_V, Eid, Tick, 9600, 100)) <= Int (Contact_Pct) then   --  the robot shows a command word it is not known by
            declare
               Unknown : Str_Vectors.Vector;
               Words : array (1 .. Max_Verbs * (Max_Args + 1)) of Natural;
            begin
               for V in 1 .. N_Verbs loop
                  if not Knows (E, Verbs (V).Word) then Unknown.Append (Img (Verbs (V).Word)); Words (Natural (Unknown.Length)) := Verbs (V).Word; end if;
                  for K in 1 .. Verbs (V).N_Args loop
                     if not Knows (E, Verbs (V).Arg_Word (K)) then
                        Unknown.Append (Img (Verbs (V).Arg_Word (K)));
                        Words (Natural (Unknown.Length)) := Verbs (V).Arg_Word (K);
                     end if;
                  end loop;
               end loop;
               if not Unknown.Is_Empty then
                  declare
                     W : constant Positive := Words (Roll (Seed_V, Eid, Tick, 9601, Natural (Unknown.Length)));
                  begin
                     Learn_From_World (E, W);
                     Learned.Append (Img (W));
                     Lines.Append ("learn " & Name (E) & " w=" & Img (W));
                     Append (Detail, (if Length (Detail) > 0 then "; " else "") & Msg ("detail.robot_learn", Word (W)));
                  end;
               end if;
            end;
         end if;
      end if;
      --  send a command: only while steering, and only when the robot is free
      if Ctl_Until (E) >= Tick and then not Pend_Valid and then Tick - Last_Exec >= Int (Gap)
        and then Int (Roll (Seed_V, Eid, Tick, 9602, 100)) <= Int (Cmd_Pct)
      then
         if Int (Roll (Seed_V, Eid, Tick, 9603, 100)) <= Int (Sloppy_Pct) and then Sim_Screen.Count (E) > 0 then
            declare   --  any word of the screen: a command word, or not
               W : constant Positive := Sim_Screen.Word_At (E, Roll (Seed_V, Eid, Tick, 9604, Sim_Screen.Count (E)));
            begin
               Text := To_Unbounded_String (Word (W));
               Verb := Verb_Index (Word (W));
               Pin_A := W;
            end;
         else
            declare
               Known : Str_Vectors.Vector;
            begin
               for V in 1 .. N_Verbs loop
                  if Knows (E, Verbs (V).Word) then Known.Append (Img (V)); end if;
               end loop;
               if Known.Is_Empty then return; end if;
               Verb := Positive'Value (Known (Roll (Seed_V, Eid, Tick, 9605, Natural (Known.Length))));
               Text := Verbs (Verb).Text;
               Pin_A := Verbs (Verb).Word;
               if Verbs (Verb).N_Args > 0 then
                  declare
                     Args : Str_Vectors.Vector;
                  begin
                     for K in 1 .. Verbs (Verb).N_Args loop
                        if Knows (E, Verbs (Verb).Arg_Word (K)) then Args.Append (Img (K)); end if;
                     end loop;
                     if not Args.Is_Empty then
                        Arg := Positive'Value (Args (Roll (Seed_V, Eid, Tick, 9606, Natural (Args.Length))));
                        Pin_B := Verbs (Verb).Arg_Word (Arg);
                        Text := Text & " " & Verbs (Verb).Arg_Text (Arg);
                     end if;   --  no direction word known: the robot will answer with an error
                  end;
               end if;
            end;
         end if;
         Sim_Screen.Pin_Command (E, Pin_A, Pin_B);
         Pend_Valid := True;
         Pend_Who := E;
         Pend_Verb := Verb;
         Pend_Arg := Arg;
         Pend_Text := Text;
         Pend_Ready := Tick + Int (Delay_B) + Int (Roll (Seed_V, Eid, Tick, 9607, Delay_X + 1)) - 1;
         Issued (E) := Issued (E) + 1;
         Cmd_N := Cmd_N + 1;
         Lines.Append ("cmd " & Name (E) & " " & To_String (Text) & " ready=" & Img (Pend_Ready));
         Append (Detail, (if Length (Detail) > 0 then "; " else "") & Msg ("detail.robot_cmd", To_String (Text)));
      end if;
   end Control;

   procedure Share (Viewer, Owner : Entity_Id; Tick : Int; Lines : in out Str_Vectors.Vector) is
   begin
      if Is_Started and then Viewer /= Owner and then Ctl_Until (Owner) >= Tick and then Sim_Screen.Has_Frame (Owner) then
         declare
            Fresh : constant Boolean := Ctl_Until (Viewer) < Tick or else not Str_Vectors."=" (Sim_Screen.Frame_Of (Viewer), Sim_Screen.Frame_Of (Owner));
         begin
            Ctl_Until (Viewer) := Tick + Int (Window);
            if Fresh then   --  a viewer who already steers and has this view needs no new record
               Sim_Screen.Set_Frame (Viewer, Sim_Screen.Frame_Of (Owner), "");
               Share_N := Share_N + 1;
               Lines.Append ("share " & Name (Owner) & ">" & Name (Viewer) & " until=" & Img (Ctl_Until (Viewer)));
            end if;
         end;
      end if;
   end Share;

   function Take_Reply (E : Entity_Id) return String is
      R : constant String := To_String (Replies (E));
   begin
      Replies (E) := Null_Unbounded_String;
      return R;
   end Take_Reply;

   --  ---- views ---------------------------------------------------------------------------------------------------------------------
   function View (Tick : Int) return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
   begin
      if not Is_Started then
         R.Append (Msg ("robot.none"));
         return R;
      end if;
      R.Append (Msg ("robot.state", Msg ("robot.name"), Img (RX), Img (RY), Heading_Text (Heading), Img (Battery), Img (Max_B)));
      R.Append (Msg ("robot.carry", Carry_Text, Msg ("robot.queue", (if Pend_Valid then Name (Pend_Who) & ": " & To_String (Pend_Text) else Msg ("robot.idle")))));
      for Row of Sim_Things.Camera (RX, RY, Glyph) loop R.Append ("  " & Row); end loop;
      declare
         C : Unbounded_String;
      begin
         for E in Entity_Id loop
            if Ctl_Until (E) >= Tick then Append (C, (if Length (C) > 0 then ", " else "") & Name (E)); end if;
         end loop;
         R.Append (Msg ("robot.steer", (if Length (C) = 0 then Msg ("robot.nobody") else To_String (C))));
      end;
      R.Append (Msg ("robot.counts", Img (Cmd_N), Img (Err_N), Img (Share_N)));
      for L of Log loop R.Append ("  " & L); end loop;
      return R;
   end View;

   function Report return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
   begin
      R.Append (Msg ("robot.rep"));
      if Is_Started then
         R.Append (Msg ("robot.state", Msg ("robot.name"), Img (RX), Img (RY), Heading_Text (Heading), Img (Battery), Img (Max_B)));
         R.Append (Msg ("robot.counts", Img (Cmd_N), Img (Err_N), Img (Share_N)));
         for E in Entity_Id loop R.Append (Msg ("robot.per", Name (E), Img (Issued (E)), Img (Errs (E)))); end loop;
      else
         R.Append (Msg ("robot.none"));
      end if;
      return R;
   end Report;

end Sim_Robot;
