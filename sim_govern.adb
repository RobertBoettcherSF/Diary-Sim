--  Version: 0.010
--  See sim_govern.ads.
pragma Ada_2022;

with Sim_Ckpt;

with Ada.Containers.Vectors;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Sim_Records;

package body Sim_Govern is

   use Ada.Strings.Unbounded;
   use Sim_Dharma;
   package Fx renames Ada.Strings.Fixed;

   type Kind_T is (Grant, Partial, Defer, Refuse, Veto, Approve);
   Kind_Name : constant array (Kind_T) of String (1 .. 7) := ["grant  ", "partial", "defer  ", "refuse ", "veto   ", "approve"];
   function KN (K : Kind_T) return String is (Fx.Trim (Kind_Name (K), Ada.Strings.Right));

   type Offs is array (Entity_Id, Lever) of Integer;
   type Ints is array (Entity_Id) of Integer;
   type Cnt_Topic is array (Entity_Id, 1 .. 40) of Natural;

   type Pend_Rec is record
      Pet : Positive := 1;
      E : Entity_Id := 1;
      Mood : Integer := 0;
      Due : Int := 0;
      Defers : Natural := 0;
   end record;
   package Pend_Vectors is new Ada.Containers.Vectors (Positive, Pend_Rec);

   type In_Rec is record
      N : Positive := 1;
      Tick : Int := 0;
      Dec : Positive := 1;
      Approve : Boolean := False;
      Done : Boolean := False;
   end record;
   package In_Vectors is new Ada.Containers.Vectors (Positive, In_Rec);

   --  what a decision changed (to revert it) - the D line itself is the record
   type Dec_Rec is record
      Kind : Kind_T := Refuse;
      E : Entity_Id := 1;
      Lev : Lever := Rate;
      Delta_V : Integer := 0;
      Acted : Boolean := False;
   end record;
   package Dec_Vectors is new Ada.Containers.Vectors (Positive, Dec_Rec);

   Seed_V : Int := 0;
   Is_Started : Boolean := False;
   Off_V : Offs := [others => [others => 0]];
   Trust, Stand, Mood_P : Ints := [others => 0];
   Refused_At : array (Entity_Id) of Int := [others => -1];   --  tick of the latest refusal of a petition of E (trial=1 appeals)
   Reps : Cnt_Topic := [others => [others => 0]];
   Pend : Pend_Vectors.Vector;
   Inputs : In_Vectors.Vector;
   Decs : Dec_Vectors.Vector;
   Dec_Lines : Str_Vectors.Vector;     --  every D line, in order (the records the reports are built from)

   Trust_Start, Stand_Start, Delay_B, Delay_X, Base, Gen_W, Strict_W, Trust_W, Attn_W, Mood_W, Grant_Share, Defer_Base, Defer_W,
     Defer_Ticks, Max_Defer, Spam_At, Trust_Rise, Trust_Fall, Stand_Rise, Stand_Fall, Mood_Grant, Mood_Partial, Mood_Refuse, Urgency,
     Veto_Stand, Veto_Trust, Appr_Stand, Appr_Trust : Integer := 0;

   function L (Key : String; D : Integer) return Integer is (Integer (Limit (Key, Int (D))));

   --  ---- text helpers ----------------------------------------------------------------------------------------------------
   function Tok (Line, Key : String) return String is
      Pat : constant String := " " & Key & "=";
      P : constant Natural := Fx.Index (Line, Pat);
      Q : Natural;
   begin
      if P = 0 then return ""; end if;
      Q := Fx.Index (Line, " ", P + Pat'Length);
      return Line (P + Pat'Length .. (if Q = 0 then Line'Last else Q - 1));
   end Tok;

   --  "a b c" -> the k-th integer
   function Num_At (T : String; K : Positive) return Integer is
      From : Natural := T'First;
      N : Natural := 0;
   begin
      for I in T'First .. T'Last + 1 loop
         if I > T'Last or else T (I) = ' ' then
            if I > From then
               N := N + 1;
               if N = K then return Integer'Value (T (From .. I - 1)); end if;
            end if;
            From := I + 1;
         end if;
      end loop;
      return 0;
   end Num_At;

   function Lever_Name (V : Lever) return String is (case V is when Rate => "rate", when Cool => "cool", when Work => "work", when Quick => "quick");
   function Lo_Of (V : Lever) return Integer is (Num_At (Msg ("lever." & Lever_Name (V)), 1));
   function Hi_Of (V : Lever) return Integer is (Num_At (Msg ("lever." & Lever_Name (V)), 2));
   function Step_Of (V : Lever) return Integer is (Integer'Max (1, Num_At (Msg ("lever." & Lever_Name (V)), 3)));
   function Label_Of (V : Lever) return String is (Msg ("lever." & Lever_Name (V) & ".label"));
   function Sg (N : Integer) return String is (if N > 0 then "+" & Img (N) else Img (N));

   --  the lever (and direction) of a topic: Has = False when the topic has no lever
   procedure Lever_Of (Topic : String; Has : out Boolean; V : out Lever; Sign : out Integer) is
      T : constant String := Msg ("topic." & Topic);
   begin
      Has := False; V := Rate; Sign := 1;
      if T'Length >= 3 and then T (T'First) /= '[' then
         declare
            Sp : constant Natural := Fx.Index (T, " ");
         begin
            if Sp > 0 and then Sp < T'Last then
               V := Lever'Value (T (T'First .. Sp - 1));
               Sign := (if T (Sp + 1) = '-' then -1 else 1);
               Has := True;
            end if;
         end;
      end if;
   exception
      when Constraint_Error => Has := False;
   end Lever_Of;

   --  ---- life ------------------------------------------------------------------------------------------------------------------
   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
      Is_Started := False;
      Off_V := [others => [others => 0]];
      Trust := [others => 0]; Stand := [others => 0]; Mood_P := [others => 0]; Refused_At := [others => -1];
      Reps := [others => [others => 0]];
      Pend.Clear; Inputs.Clear; Decs.Clear; Dec_Lines.Clear;
      Trust_Start := L ("govern.trust_start", 50);
      Stand_Start := L ("govern.stand_start", 50);
      Delay_B := L ("govern.delay", 3);
      Delay_X := L ("govern.delay_extra", 3);
      Base := L ("govern.base", 45);
      Gen_W := L ("govern.gen_w", 60);
      Strict_W := L ("govern.strict_w", 40);
      Trust_W := L ("govern.trust_w", 50);
      Attn_W := L ("govern.attn_w", 30);
      Mood_W := L ("govern.mood_w", 10);
      Grant_Share := L ("govern.grant_share", 55);
      Defer_Base := L ("govern.defer_base", 25);
      Defer_W := L ("govern.defer_w", 30);
      Defer_Ticks := Integer'Max (1, L ("govern.defer_ticks", 40));
      Max_Defer := L ("govern.max_defer", 2);
      Spam_At := L ("govern.spam", 3);
      Trust_Rise := L ("govern.trust_rise", 2);
      Trust_Fall := L ("govern.trust_fall", 6);
      Stand_Rise := L ("govern.stand_rise", 1);
      Stand_Fall := L ("govern.stand_fall", 1);
      Mood_Grant := L ("govern.mood_grant", 2);
      Mood_Partial := L ("govern.mood_partial", 1);
      Mood_Refuse := L ("govern.mood_refuse", -2);
      Urgency := L ("govern.urgency", 12);
      Veto_Stand := L ("govern.veto_stand", 10);
      Veto_Trust := L ("govern.veto_trust", 8);
      Appr_Stand := L ("govern.approve_stand", 5);
      Appr_Trust := L ("govern.approve_trust", 4);
   end Init;

   procedure Begin_Life (Tick : Int) is
      pragma Unreferenced (Tick);
   begin
      if Is_Started then return; end if;
      Is_Started := True;
      Trust := [others => Integer'Max (0, Integer'Min (100, Trust_Start))];
      Stand := [others => Integer'Max (0, Integer'Min (100, Stand_Start))];
   end Begin_Life;

   function Started return Boolean is (Is_Started);
   function Off (E : Entity_Id; L : Lever) return Integer is (Off_V (E, L));
   function Trust_Of (E : Entity_Id) return Integer is (Trust (E));
   function Standing_Of (E : Entity_Id) return Integer is (Stand (E));
   function Decision_Count return Natural is (Natural (Dec_Lines.Length));

   function Take_Mood (E : Entity_Id) return Integer is
      M : constant Integer := Mood_P (E);
   begin
      Mood_P (E) := 0;
      return M;
   end Take_Mood;

   procedure Filed (Pet : Positive; E : Entity_Id; Tick : Int; Mood : Integer) is
      T : constant Natural := Topic_Id (Petition_Topic (Pet));
   begin
      if not Is_Started then return; end if;
      if T in 1 .. 40 then Reps (E, T) := Reps (E, T) + 1; end if;
      Pend.Append (Pend_Rec'(Pet => Pet, E => E, Mood => Mood,
                             Due => Tick + Int (Delay_B) + Int (Roll (Seed_V, Positive (E), Tick, 9720, Delay_X + 1)) - 1, Defers => 0));
   end Filed;

   procedure Add_Input (N : Positive; Tick : Int; Dec : Positive; Approve : Boolean) is
   begin
      Inputs.Append (In_Rec'(N => N, Tick => Tick, Dec => Dec, Approve => Approve, Done => False));
   end Add_Input;

   --  ---- the D line ------------------------------------------------------------------------------------------------------------
   function Make_Line (Tick : Int; Pet : Positive; E : Entity_Id; Topic, Lev : String; K : Kind_T; Why : String; Old, Nw : Integer;
                       Tr0, Tr1, St0, St1 : Integer; Extra : String) return String is
     ("D" & Img (Natural (Dec_Lines.Length) + 1) & " t=" & Img (Tick) & " pet=P" & Img (Pet) & " player=" & Player_Name (Watcher (E))
      & " wesen=" & Name (E) & " topic=" & Topic & " lever=" & Lev & " kind=" & KN (K) & " why=" & Why & " old=" & Img (Old) & " new=" & Img (Nw)
      & " trust=" & Img (Tr0) & ">" & Img (Tr1) & " stand=" & Img (St0) & ">" & Img (St1) & Extra);

   procedure Put (Lines : in out Str_Vectors.Vector; Line : String; D : Dec_Rec) is
   begin
      Lines.Append (Line);
      Dec_Lines.Append (Line);
      Decs.Append (D);
   end Put;

   --  ---- a decision ------------------------------------------------------------------------------------------------------------
   procedure Decide (Tick : Int; P : in out Pend_Rec; Done : out Boolean; Lines : in out Str_Vectors.Vector) is
      E : constant Entity_Id := P.E;
      Eid : constant Positive := Positive (E);
      Pl : constant Player_Id := Watcher (E);
      Topic : constant String := Petition_Topic (P.Pet);
      Tn : constant Natural := Topic_Id (Topic);
      Has : Boolean;
      V : Lever;
      Sign : Integer;
      Old_Tr : constant Integer := Trust (E);
      Old_St : constant Integer := Stand (E);
      Old_Off : Integer;
      K : Kind_T := Refuse;
      Why : Unbounded_String;
      Mood_D : Integer := 0;
      New_Off : Integer;
      Amount : Integer := 0;
      Spam : Boolean;
      Bound : Boolean := False;
      Keep : Boolean := False;
   begin
      Done := True;
      Lever_Of (Topic, Has, V, Sign);
      Spam := Tn in 1 .. 40 and then Reps (E, Tn) > Spam_At;
      if not Has then
         Why := To_Unbounded_String ("refuse.nolever");
         Put (Lines, Make_Line (Tick, P.Pet, E, Topic, "-", Refuse, "refuse.nolever", 0, 0, Old_Tr, Old_Tr, Old_St, Old_St, ""),
              Dec_Rec'(Kind => Refuse, E => E, Lev => Rate, Delta_V => 0, Acted => False));
         return;
      end if;
      Old_Off := Off_V (E, V);
      New_Off := Integer'Max (Lo_Of (V), Integer'Min (Hi_Of (V), Old_Off + Sign * Step_Of (V)));
      Bound := New_Off = Old_Off;
      if Spam then
         K := Refuse; Why := To_Unbounded_String ("refuse.spam");
         Trust (E) := Integer'Max (0, Trust (E) - Trust_Fall);
         Stand (E) := Integer'Max (0, Stand (E) - Stand_Fall);
         Mood_D := Mood_Refuse - (50 - Old_St) / 25;
         if Tn in 1 .. 40 then Reps (E, Tn) := 0; end if;
      elsif Bound then
         K := Refuse; Why := To_Unbounded_String ("refuse.bound");
      else
         declare
            Warm : constant Integer := Warm_Of (Pl);
            Brev : constant Integer := Brev_Of (Pl);
            Attn : constant Integer := Attn_Of (Pl);
            Score : constant Integer := Base + Warm * Gen_W / 100 - (Brev - 50) * Strict_W / 100 + (Trust (E) - 50) * Trust_W / 100
                                        - Attn * Attn_W / 100 + Integer'Max (0, -P.Mood) * Mood_W / 100
                                        + Sim_Records.Shift (E, Topic, Tick);   --  records=1: what was announced (0 otherwise)
            Pct : constant Integer := Integer'Max (5, Integer'Min (95, Score));
            R : constant Integer := Roll (Seed_V, Eid, Tick, 9700 + P.Defers, 100);
            Step : constant Integer := Step_Of (V);
         begin
            if R <= Pct * Grant_Share / 100 then
               K := Grant; Amount := Step;
               Why := To_Unbounded_String (if Trust (E) >= 65 then "grant.trust" elsif Warm > 10 then "grant.generous" else "grant.fair");
            elsif R <= Pct then
               K := Partial; Amount := Integer'Max (1, Step / 2);
               Why := To_Unbounded_String (if Trust (E) < 45 then "partial.careful" else "partial.trial");
            elsif P.Defers < Max_Defer and then Roll (Seed_V, Eid, Tick, 9710 + P.Defers, 100) <= Defer_Base + Attn * Defer_W / 100 then
               K := Defer; Keep := True;
               Why := To_Unbounded_String (if Attn >= 50 then "defer.busy" else "defer.think");
            else
               K := Refuse;
               Why := To_Unbounded_String (if Trust (E) < 35 then "refuse.distrust" elsif Brev >= 60 then "refuse.strict" else "refuse.later");
            end if;
            case K is
               when Grant | Partial =>
                  New_Off := Integer'Max (Lo_Of (V), Integer'Min (Hi_Of (V), Old_Off + Sign * Amount));
                  Off_V (E, V) := New_Off;
                  Trust (E) := Integer'Min (100, Trust (E) + Trust_Rise);
                  if K = Grant then Stand (E) := Integer'Min (100, Stand (E) + Stand_Rise); end if;
                  Mood_D := (if K = Grant then Mood_Grant + (Old_St - 50) / 25 else Mood_Partial);
                  if Tn in 1 .. 40 then Reps (E, Tn) := 0; end if;
               when Refuse =>
                  Stand (E) := Integer'Max (0, Stand (E) - Stand_Fall);
                  Mood_D := Mood_Refuse - (50 - Old_St) / 25;
               when others => null;
            end case;
         end;
      end if;
      if K = Defer then
         P.Due := Tick + Int (Defer_Ticks);
         P.Defers := P.Defers + 1;
         Done := not Keep;
         Put (Lines, Make_Line (Tick, P.Pet, E, Topic, Lever_Name (V), Defer, To_String (Why), Old_Off, Old_Off, Old_Tr, Trust (E), Old_St, Stand (E),
                                " until=" & Img (P.Due)), Dec_Rec'(Kind => Defer, E => E, Lev => V, Delta_V => 0, Acted => False));
         return;
      end if;
      if K = Refuse and then not Bound then   --  asked and turned down: the next petition on this topic is likelier
         Add_Urgency (E, Tn, Natural (Integer'Max (0, Urgency)));
      end if;
      Mood_P (E) := Mood_P (E) + Mood_D;
      if K = Refuse then Refused_At (E) := Tick; end if;
      Put (Lines, Make_Line (Tick, P.Pet, E, Topic, Lever_Name (V), K, To_String (Why), Old_Off,
                             (if K in Grant | Partial then Off_V (E, V) else Old_Off), Old_Tr, Trust (E), Old_St, Stand (E), ""),
           Dec_Rec'(Kind => K, E => E, Lev => V, Delta_V => (if K in Grant | Partial then Off_V (E, V) - Old_Off else 0), Acted => False));
   end Decide;

   --  ---- Robert's veto / approval --------------------------------------------------------------------------------------
   function Apply_Input (Tick : Int; I : In_Rec; Lines : in out Str_Vectors.Vector) return Boolean is
   begin
      if I.Dec > Natural (Decs.Length) then return False; end if;
      declare
         D : Dec_Rec := Decs (I.Dec);
         Old_Line : constant String := Dec_Lines (I.Dec);
         Pet : constant Positive := Positive'Value (Tok (Old_Line, "pet") (Tok (Old_Line, "pet")'First + 1 .. Tok (Old_Line, "pet")'Last));
         Topic : constant String := Tok (Old_Line, "topic");
         Lev : constant String := Tok (Old_Line, "lever");
         E : constant Entity_Id := D.E;
         Old_Tr : constant Integer := Trust (E);
         Old_St : constant Integer := Stand (E);
         Extra : constant String := " of=D" & Img (I.Dec);
      begin
         if D.Acted then return False; end if;
         if I.Approve then
            if D.Kind not in Grant | Partial | Refuse then return False; end if;
            Trust (E) := Integer'Min (100, Trust (E) + Appr_Trust);
            Stand (E) := Integer'Min (100, Stand (E) + Appr_Stand);
            D.Acted := True;
            Decs.Replace_Element (I.Dec, D);
            Put (Lines, Make_Line (Tick, Pet, E, Topic, Lev, Approve, "approve", Off_V (E, D.Lev), Off_V (E, D.Lev), Old_Tr, Trust (E), Old_St, Stand (E), Extra),
                 Dec_Rec'(Kind => Approve, E => E, Lev => D.Lev, Delta_V => 0, Acted => True));
         else
            if D.Kind not in Grant | Partial then return False; end if;
            declare
               Cur : constant Integer := Off_V (E, D.Lev);
               Back : constant Integer := Integer'Max (Lo_Of (D.Lev), Integer'Min (Hi_Of (D.Lev), Cur - D.Delta_V));
            begin
               Off_V (E, D.Lev) := Back;
               Trust (E) := Integer'Max (0, Trust (E) - Veto_Trust);
               Stand (E) := Integer'Max (0, Stand (E) - Veto_Stand);
               D.Acted := True;
               Decs.Replace_Element (I.Dec, D);
               Put (Lines, Make_Line (Tick, Pet, E, Topic, Lev, Veto, "veto", Cur, Back, Old_Tr, Trust (E), Old_St, Stand (E), Extra),
                    Dec_Rec'(Kind => Veto, E => E, Lev => D.Lev, Delta_V => 0, Acted => True));
            end;
         end if;
      end;
      return True;
   exception
      when Constraint_Error => return False;
   end Apply_Input;

   procedure Tick_Begin (Tick : Int; Lines : in out Str_Vectors.Vector; Bad : out Natural) is
      I : Natural := 1;
   begin
      Bad := 0;
      if not Is_Started then return; end if;
      for K in 1 .. Natural (Inputs.Length) loop
         declare
            X : In_Rec := Inputs (K);
         begin
            if not X.Done and then X.Tick = Tick - 1 then
               X.Done := True;
               Inputs.Replace_Element (K, X);
               if not Apply_Input (Tick, X, Lines) then Bad := X.N; end if;
            end if;
         end;
      end loop;
      while I <= Natural (Pend.Length) loop
         declare
            P : Pend_Rec := Pend (I);
            Done : Boolean := False;
         begin
            if P.Due <= Tick then
               Decide (Tick, P, Done, Lines);
               if Done then Pend.Delete (I); else Pend.Replace_Element (I, P); I := I + 1; end if;
            else
               I := I + 1;
            end if;
         end;
      end loop;
   end Tick_Begin;

   --  ---- reports (from the D lines only) ---------------------------------------------------------------------------
   subtype Count5 is Counts_T;
   package Seen_Sets is new Ada.Containers.Indefinite_Hashed_Sets (String, Ada.Strings.Hash, "=");
   function Count_For (Pl : String) return Count5 is
      C : Count5 := [others => 0];
      Seen : Seen_Sets.Set;   --  0.060: a hash set (was a list searched line by line: O(decisions^2) per report)
   begin
      for Ln of Dec_Lines loop
         if Pl = "" or else Tok (Ln, "player") = Pl then
            declare
               K : constant String := Tok (Ln, "kind");
               Pet : constant String := Tok (Ln, "pet");
            begin
               if K in "grant" | "partial" | "defer" | "refuse" and then not Seen.Contains (Pet & "/" & Tok (Ln, "player")) then
                  Seen.Insert (Pet & "/" & Tok (Ln, "player"));
                  C (1) := C (1) + 1;
               end if;
               if K = "grant" then C (2) := C (2) + 1;
               elsif K = "partial" then C (3) := C (3) + 1;
               elsif K = "defer" then C (4) := C (4) + 1;
               elsif K = "refuse" then C (5) := C (5) + 1;
               elsif K = "veto" then C (6) := C (6) + 1;
               end if;
            end;
         end if;
      end loop;
      return C;
   end Count_For;

   function Counter_Of (C : Count5) return String is
     (Msg ("govern.counter", Img (C (1)), Img (C (2)), Img (C (3)), Img (C (4)), Img (C (5)))
      & (if C (6) > 0 then Msg ("govern.counter.veto", Img (C (6))) else ""));

   function Counts_Of (P : Player_Id) return Counts_T is (Count_For (Player_Name (P)));

   function Last_Line_Of (E : Entity_Id) return String is
   begin
      for I in reverse 1 .. Natural (Dec_Lines.Length) loop
         if Tok (Dec_Lines (I), "wesen") = Name (E) then return Dec_Lines (I); end if;
      end loop;
      return "";
   end Last_Line_Of;

   function Open_Of (E : Entity_Id) return Natural is
      N : Natural := 0;
   begin
      for P of Pend loop if P.E = E then N := N + 1; end if; end loop;
      return N;
   end Open_Of;

   function Deferred_Of (E : Entity_Id) return Natural is
      N : Natural := 0;
   begin
      for P of Pend loop if P.E = E and then P.Defers > 0 then N := N + 1; end if; end loop;
      return N;
   end Deferred_Of;

   function Top_Concern (P : Player_Id) return String is
      Score : array (1 .. 40) of Natural := [others => 0];
      Pl : constant String := Player_Name (P);
      Best : Natural := 0;
   begin
      for Ln of Dec_Lines loop
         if Tok (Ln, "player") = Pl and then Tok (Ln, "kind") in "grant" | "partial" | "defer" | "refuse" then
            declare
               T : constant Natural := Topic_Id (Tok (Ln, "topic"));
            begin
               if T in 1 .. 40 then Score (T) := Score (T) + (if Tok (Ln, "kind") in "defer" | "refuse" then 2 else 1); end if;
            end;
         end if;
      end loop;
      for T in Score'Range loop
         if Score (T) > 0 and then (Best = 0 or else Score (T) > Score (Best)) then Best := T; end if;
      end loop;
      return (if Best = 0 then "" else Topic_Name (Best));
   end Top_Concern;

   function Refusal_Tick (E : Entity_Id) return Int is (Refused_At (E));

   procedure Adjust (E : Entity_Id; Trust_By, Stand_By : Integer) is
   begin
      Trust (E) := Integer'Max (0, Integer'Min (100, Trust (E) + Trust_By));
      Stand (E) := Integer'Max (0, Integer'Min (100, Stand (E) + Stand_By));
   end Adjust;

   procedure Lower_Standing (E : Entity_Id; By : Natural) is
   begin
      Stand (E) := Integer'Max (0, Stand (E) - By);
   end Lower_Standing;

   function Counter_Line (P : Player_Id) return String is (Counter_Of (Count_For (Player_Name (P))));
   function Totals_Line return String is
      C : constant Count5 := Count_For ("");
   begin
      return Img (C (1)) & "/" & Img (C (2)) & "/" & Img (C (3)) & "/" & Img (C (4)) & "/" & Img (C (5)) & (if C (6) > 0 then "/v" & Img (C (6)) else "");
   end Totals_Line;

   function Lever_Label (Name_T : String) return String is
   begin
      return Label_Of (Lever'Value (Name_T));
   exception
      when Constraint_Error => return Name_T;
   end Lever_Label;

   function Describe (Line : String) return String is
     (Msg ("govern.desc", Line (Line'First .. Fx.Index (Line, " ") - 1), Sim_World.Show (Tok (Line, "player")) & "/" & Sim_World.Show (Tok (Line, "wesen")), Tok (Line, "topic"),
           Msg ("kind." & Tok (Line, "kind")), Lever_Label (Tok (Line, "lever")), Tok (Line, "old") & ">" & Tok (Line, "new"),
           Msg ("why." & Tok (Line, "why"))));

   function Report (P : Player_Id; Since : Int; Variant : String) return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
      Pl : constant String := Player_Name (P);
   begin
      R.Append (Counter_Of (Count_For (Pl)));
      for Ln of Dec_Lines loop
         if Tok (Ln, "player") = Pl and then Tok (Ln, "kind") in "grant" | "partial" | "veto" then
            declare
               T : constant Int := Int'Value (Tok (Ln, "t"));
               Dv : constant Integer := Integer'Value (Tok (Ln, "new")) - Integer'Value (Tok (Ln, "old"));
            begin
               if T > Since then
                  R.Append (Msg ("govern.chg." & Variant, Ln (Ln'First .. Fx.Index (Ln, " ") - 1), Tok (Ln, "wesen"), Lever_Label (Tok (Ln, "lever")),
                                 Sg (Dv), Msg ("kind." & Tok (Ln, "kind")), Msg ("why." & Tok (Ln, "why"))));
               end if;
            end;
         end if;
      end loop;
      return R;
   end Report;

   function View return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
   begin
      if not Is_Started then
         R.Append (Msg ("govern.none"));
         return R;
      end if;
      R.Append (Msg ("govern.head"));
      for P in Player_Id range 1 .. Last_Player loop
         R.Append (Msg ("govern.player", Player_Name (P), Counter_Line (P)));
         for E in Entity_Id loop
            if Watcher (E) = P then
               R.Append ("  " & Msg ("govern.wesen", Name (E), Img (Trust (E)), Img (Stand (E)), Sg (Off_V (E, Rate)), Sg (Off_V (E, Cool)),
                                    Sg (Off_V (E, Work)), Sg (Off_V (E, Quick))));
            end if;
         end loop;
      end loop;
      R.Append (Msg ("govern.last"));
      for K in Integer'Max (1, Natural (Dec_Lines.Length) - 9) .. Natural (Dec_Lines.Length) loop
         R.Append ("  " & Describe (Dec_Lines (K)));
      end loop;
      return R;
   end View;

   --  0.058: the checkpoint.  Not in it: Inputs (Robert's vetoes and approvals, read from diaries/vetoes.txt at every start; then
   --  Inputs_Done_Before marks those the replay before the checkpoint has passed).
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Int);
      procedure IO is new Sim_Ckpt.IO (Boolean);
      procedure IO is new Sim_Ckpt.IO (Offs);
      procedure IO is new Sim_Ckpt.IO (Ints);
      procedure IO is new Sim_Ckpt.IO (Cnt_Topic);
      procedure IO is new Sim_Ckpt.IO (Pend_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Dec_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Str_Vectors.Vector);
   begin
      IO (S, Save, Seed_V);
      IO (S, Save, Is_Started);
      IO (S, Save, Off_V);
      IO (S, Save, Trust); IO (S, Save, Stand); IO (S, Save, Mood_P);
      for E in Entity_Id loop IO (S, Save, Refused_At (E)); end loop;
      IO (S, Save, Reps);
      IO (S, Save, Pend);
      IO (S, Save, Decs);
      IO (S, Save, Dec_Lines);
   end State_IO;

   procedure Inputs_Done_Before (Tick : Int) is
   begin
      for X of Inputs loop X.Done := X.Tick < Tick; end loop;   --  an input of tick T takes effect at T + 1
   end Inputs_Done_Before;

   function Inputs_Before (Tick : Int) return Natural is
      N : Natural := 0;
   begin
      for X of Inputs loop
         if X.Tick < Tick then N := N + 1; end if;
      end loop;
      return N;
   end Inputs_Before;

end Sim_Govern;
