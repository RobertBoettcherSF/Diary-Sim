--  Version: 0.001
--  See the spec.  Counting only: integer arithmetic, no dice, no clock, no files.
pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Characters.Handling;
with Sim_World;

package body Sim_Active is

   use Sim_World;

   type Word_State is record
      Seen  : Boolean := False;   --  counted since the first active=1 session
      Born  : Natural := 0;       --  session in which the window first saw it (or in which it woke): the probation starts there
      Fit10 : Natural := 0;       --  running fitness in tenths of a point per session
      Idle  : Natural := 0;       --  sessions in a row at or under the line (after the probation)
      Paid  : Boolean := False;   --  the agreed points were paid
      U, G, A : Natural := 0;     --  uses, granted mentions, agreed meanings in the open window
   end record;
   package State_Vectors is new Ada.Containers.Vectors (Positive, Word_State);
   States : array (Entity_Id) of State_Vectors.Vector;
   Pr : Sim_Evolve.Word_Params;
   Window : Boolean := False;
   Cur : Natural := 0;            --  the session of the open window
   Params_Done : Boolean := False;
   Out_Lines : Str_Vectors.Vector;
   N_Dorm, N_Wake : array (Entity_Id) of Natural := [others => 0];

   procedure Reset (Pr : Sim_Evolve.Word_Params) is
   begin
      Sim_Active.Pr := Pr;
      for E in Entity_Id loop States (E).Clear; end loop;
      Window := False;
      Cur := 0;
      Params_Done := False;
      Out_Lines.Clear;
      N_Dorm := [others => 0];
      N_Wake := [others => 0];
      Use_Dormant (False);
   end Reset;

   function Params return Sim_Evolve.Word_Params is (Pr);

   function Params_Text (Pr : Sim_Evolve.Word_Params) return String is
     ("use_pts=" & Img (Pr.Use_Pts) & " use_cap=" & Img (Pr.Use_Cap) & " grant_pts=" & Img (Pr.Grant_Pts) & " agree_pts=" & Img (Pr.Agree_Pts)
      & " line10=" & Img (Pr.Line10) & " fit_cap=" & Img (Pr.Fit_Cap) & " probation=" & Img (Pr.Probation) & " idle=" & Img (Pr.Idle)
      & " retire_max=" & Img (Pr.Retire_Max) & " floor=" & Img (Pr.Min_Active) & " cap=" & Img (Pr.Cap));

   --  The value of "key=value" in a blank-separated line ("" if none).
   function Tok (L, Key : String) return String is
      P : Natural := L'First;
   begin
      while P <= L'Last loop
         declare
            Stop : Natural := P;
         begin
            while Stop <= L'Last and then L (Stop) /= ' ' loop Stop := Stop + 1; end loop;
            if Stop - P > Key'Length and then L (P .. P + Key'Length - 1) = Key and then L (P + Key'Length) = '=' then
               return L (P + Key'Length + 1 .. Stop - 1);
            end if;
            P := Stop + 1;
         end;
      end loop;
      return "";
   end Tok;

   function Field (L : String; N : Positive) return String is   --  N-th blank-separated field
      P : Natural := L'First;
      K : Natural := 0;
   begin
      while P <= L'Last loop
         declare
            Stop : Natural := P;
         begin
            while Stop <= L'Last and then L (Stop) /= ' ' loop Stop := Stop + 1; end loop;
            K := K + 1;
            if K = N then return L (P .. Stop - 1); end if;
            P := Stop + 1;
         end;
      end loop;
      return "";
   end Field;

   function Num (S : String) return Natural is
      V : Natural := 0;
   begin
      if S'Length = 0 or else S'Length > 9 then return 0; end if;
      for C of S loop
         if C not in '0' .. '9' then return 0; end if;
         V := V * 10 + Character'Pos (C) - Character'Pos ('0');
      end loop;
      return V;
   end Num;

   procedure Parse_Params (Line : String; Pr : in out Sim_Evolve.Word_Params; OK : out Boolean) is
   begin
      OK := Tok (Line, "use_pts") /= "" and then Tok (Line, "cap") /= "" and then Tok (Line, "floor") /= "";
      if not OK then return; end if;
      Pr := (Use_Pts => Num (Tok (Line, "use_pts")), Use_Cap => Num (Tok (Line, "use_cap")), Grant_Pts => Num (Tok (Line, "grant_pts")),
             Agree_Pts => Num (Tok (Line, "agree_pts")), Line10 => Num (Tok (Line, "line10")), Fit_Cap => Num (Tok (Line, "fit_cap")),
             Probation => Num (Tok (Line, "probation")), Idle => Num (Tok (Line, "idle")), Retire_Max => Num (Tok (Line, "retire_max")),
             Min_Active => Num (Tok (Line, "floor")), Cap => Num (Tok (Line, "cap")));
   end Parse_Params;

   function Ent_Of (S : String) return Natural is
   begin
      for E in Entity_Id loop
         if Name (E) = S then return Natural (E); end if;
      end loop;
      return 0;
   end Ent_Of;

   procedure Ensure (E : Entity_Id; W : Positive) is
   begin
      while Natural (States (E).Length) < W loop States (E).Append (Word_State'(others => <>)); end loop;
   end Ensure;

   type Kind is (Use_K, Grant_K, Agree_K);

   --  One use of word W by E, made by the record line Key at tick T.
   procedure Event (E : Entity_Id; W : Positive; K : Kind; T : String; Key : String) is
   begin
      if W > Count or else not Knows (E, W) or else Is_Symbol (W) then return; end if;
      Ensure (E, W);
      declare
         S : Word_State renames States (E) (W);
      begin
         case K is
            when Use_K => S.U := S.U + 1;
            when Grant_K => S.G := S.G + 1;
            when Agree_K => S.A := S.A + 1;
         end case;
         if Is_Dormant (E, W) then   --  used again: it wakes, with a new probation
            Set_Dormant (E, W, False);
            S.Seen := True;
            S.Born := Cur;
            S.Idle := 0;
            N_Wake (E) := N_Wake (E) + 1;
            Out_Lines.Append ("t=" & T & " s=" & Img (Cur) & " " & Name (E) & " wake w=" & Img (W) & " word=" & Word (W) & " by=" & Key);
         end if;
      end;
   end Event;

   procedure Ids (E : Natural; List : String; K : Kind; T, Key : String) is   --  "*12,5,40": every number is a word id
      Acc : Natural := 0;
      Have : Boolean := False;
   begin
      if E = 0 then return; end if;
      for I in List'First .. List'Last + 1 loop
         if I <= List'Last and then List (I) in '0' .. '9' then
            if Acc < 100_000_000 then Acc := Acc * 10 + Character'Pos (List (I)) - Character'Pos ('0'); end if;
            Have := True;
         else
            if Have and then Acc > 0 then Event (Entity_Id (E), Acc, K, T, Key); end if;
            Acc := 0;
            Have := False;
         end if;
      end loop;
   end Ids;

   procedure Texts (E : Natural; List : String; K : Kind; T, Key : String) is   --  letters and digits make a word, anything else separates
      From : Natural := 0;
   begin
      if E = 0 then return; end if;
      for I in List'First .. List'Last + 1 loop
         if I <= List'Last and then List (I) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | Character'Val (128) .. Character'Val (255) then
            if From = 0 then From := I; end if;
         else
            if From /= 0 then
               declare
                  W : constant Natural := Find (Ada.Characters.Handling.To_Lower (List (From .. I - 1)));
               begin
                  if W > 0 then Event (Entity_Id (E), W, K, T, Key); end if;
               end;
            end if;
            From := 0;
         end if;
      end loop;
   end Texts;

   procedure Note_Line (Line : String) is
   begin
      if not Window or else Line'Length < 2 then return; end if;
      declare
         Key : constant String := Field (Line, 1);
         T : constant String := Tok (Line, "t");
      begin
         case Line (Line'First) is
            when 'K' =>   --  a screen change (the same ops as make evolve)
               declare
                  Op : constant String := Field (Line, 4);
                  E : constant Natural := Ent_Of (Field (Line, 3));
               begin
                  if Op = "show" or else Op = "read" or else Op = "pin" or else Op = "cmd" or else Op = "leave" or else Op = "blend" then
                     Ids (E, Tok (Line, "w"), Use_K, T, Key);
                     if Op = "blend" then Ids (E, Tok (Line, "a"), Use_K, T, Key); Ids (E, Tok (Line, "b"), Use_K, T, Key); end if;
                  end if;
               end;
            when 'V' =>   --  a favourite word vote
               if Tok (Line, "kind") = "favourite" then Texts (Ent_Of (Tok (Line, "voter")), Tok (Line, "choice"), Use_K, T, Key); end if;
            when 'P' =>   --  a decided petition
               Texts (Ent_Of (Tok (Line, "wesen")), Tok (Line, "req"), (if Tok (Line, "out") = "grant" then Grant_K else Use_K), T, Key);
            when 'L' =>   --  a dictionary decision: only the meaning (a base word) is a word of the lists
               Texts (Ent_Of (Tok (Line, "by")), Tok (Line, "mean"), (if Tok (Line, "st") = "A" then Agree_K else Use_K), T, Key);
            when others => null;
         end case;
      end;
   end Note_Line;

   type Cand is record
      Fit : Natural;
      W : Positive;
   end record;
   package Cand_Vectors is new Ada.Containers.Vectors (Positive, Cand);
   function Weaker (A, B : Cand) return Boolean is (A.Fit < B.Fit or else (A.Fit = B.Fit and then A.W < B.W));
   package Cand_Sort is new Cand_Vectors.Generic_Sorting ("<" => Weaker);

   --  The end of the window of session Cur at Tick, for E: the fitness of the session, then the dormancies.
   procedure Close_One (E : Entity_Id; Tick : Int) is
      Active, Known_W, Symbols, Base_N : Natural := 0;
      Idle_C, Cap_C : Cand_Vectors.Vector;
      Left : Natural := Pr.Retire_Max;
      procedure Retire (C : Cand; Why : String) is
      begin
         Set_Dormant (E, C.W, True);
         States (E) (C.W).Idle := 0;
         Active := Active - 1;
         Left := Left - 1;
         N_Dorm (E) := N_Dorm (E) + 1;
         Out_Lines.Append ("t=" & Img (Tick) & " s=" & Img (Cur) & " " & Name (E) & " dormant w=" & Img (C.W) & " word=" & Word (C.W)
                           & " fit=" & Img (C.Fit) & " why=" & Why);
      end Retire;
   begin
      Ensure (E, Natural'Max (1, Count));
      for W in 1 .. Count loop
         declare
            S : Word_State renames States (E) (W);
         begin
            if Knows (E, W) then
               Known_W := Known_W + 1;
               if Is_Symbol (W) then
                  Symbols := Symbols + 1;
               else
                  if not S.Seen then S.Seen := True; S.Born := Cur; end if;
                  if not Is_Dormant (E, W) then
                     declare
                        Pts : constant Natural := Natural'Min (Pr.Use_Cap, S.U) * Pr.Use_Pts + S.G * Pr.Grant_Pts
                                                  + (if S.A > 0 and then not S.Paid then Pr.Agree_Pts else 0);
                        Base : constant Boolean := Is_Start (E, W);
                     begin
                        if S.A > 0 then S.Paid := True; end if;
                        S.Fit10 := Natural'Min (Pr.Fit_Cap * 10, (3 * S.Fit10 + 40 * Pts) / 4);
                        if not Base and then Cur - S.Born >= Pr.Probation and then S.Fit10 <= Pr.Line10 then
                           S.Idle := S.Idle + 1;
                        else
                           S.Idle := 0;
                        end if;
                        Active := Active + 1;
                        if Base then
                           Base_N := Base_N + 1;
                        else
                           if S.Idle >= Natural'Max (1, Pr.Idle) then Idle_C.Append (Cand'(S.Fit10, W)); end if;
                           if Pr.Cap > 0 and then Cur - S.Born >= Pr.Probation then Cap_C.Append (Cand'(S.Fit10, W)); end if;
                        end if;
                     end;
                  end if;
               end if;
            end if;
            S.U := 0;
            S.G := 0;
            S.A := 0;
         end;
      end loop;
      Cand_Sort.Sort (Idle_C);
      Cand_Sort.Sort (Cap_C);
      for C of Idle_C loop
         exit when Left = 0 or else Active <= Pr.Min_Active;
         Retire (C, "idle");
      end loop;
      if Pr.Cap > 0 then
         for C of Cap_C loop
            exit when Left = 0 or else Active <= Pr.Cap;
            if not Is_Dormant (E, C.W) then Retire (C, "cap"); end if;
         end loop;
      end if;
      Out_Lines.Append ("t=" & Img (Tick) & " s=" & Img (Cur) & " " & Name (E) & " state known=" & Img (Known_W) & " symbols=" & Img (Symbols)
                        & " active=" & Img (Active) & " dormant=" & Img (Dormant_Count (E)) & " base=" & Img (Base_N)
                        & " went=" & Img (Pr.Retire_Max - Left) & " woke=" & Img (N_Wake (E)));
   end Close_One;

   procedure Open (N : Positive; Tick : Int; On : Boolean) is
   begin
      if Window then
         for E in Entity_Id loop Close_One (E, Tick); end loop;
      end if;
      Window := On;
      Cur := N;
      if On and then not Params_Done then
         Params_Done := True;
         Out_Lines.Append ("t=" & Img (Tick) & " s=" & Img (N) & " params " & Params_Text (Pr));
      end if;
      Use_Dormant (On);
   end Open;

   function Is_Open return Boolean is (Window);

   procedure Drain (Into : in out Str_Vectors.Vector) is
   begin
      for L of Out_Lines loop Into.Append (L); end loop;
      Out_Lines.Clear;
   end Drain;

   function Dormancies (E : Positive) return Natural is (N_Dorm (Entity_Id (E)));
   function Wakes (E : Positive) return Natural is (N_Wake (Entity_Id (E)));

end Sim_Active;
