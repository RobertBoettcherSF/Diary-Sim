--  Version: 0.005
--  See sim_records.ads.
pragma Ada_2022;

with Sim_Ckpt;

with Ada.Characters.Handling;
with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Sim_Dharma;
with Sim_Things;

package body Sim_Records is

   use Ada.Strings.Unbounded;
   use type Sim_Dharma.Player_Id;
   package Fx renames Ada.Strings.Fixed;

   --  ---- state -----------------------------------------------------------------------------------------------------------
   Seed_V : Int := 0;
   Is_Active : Boolean := False;
   Is_Quality : Boolean := False;                  --  records=2 session: the quality rules for proposals
   Sess_N : Natural := 0;
   Scan_Init : Boolean := False;
   Last_Scan : Natural := 0;
   V_N, A_N, L_N, B_N : Natural := 0;
   Voted_N, Agreed_N : Natural := 0;               --  words voted / agreed in the current session
   Ses_Agreed, Ses_Rejected, Ses_Ann : Natural := 0;

   type Prop_Rec is record
      Text, Mean : Unbounded_String;
      Slot : Natural := 1;                          --  1 coined, 2 made-up name
      By : Entity_Id := 1;
      At_T : Int := 0;
      Ann : Boolean := False;
   end record;
   package Prop_Vectors is new Ada.Containers.Vectors (Positive, Prop_Rec);
   Pending : Prop_Vectors.Vector;

   type Ann_Rec is record
      Kind : Natural := 1;                          --  1 wesen, 2 player, 3 a word
      Who : Natural := 0;
      Topic : Unbounded_String;
      At_T : Int := 0;
      Counter : Boolean := False;
   end record;
   package Ann_Vectors is new Ada.Containers.Vectors (Positive, Ann_Rec);
   Anns : Ann_Vectors.Vector;

   type Sess_Rec is record
      N : Positive := 1;
      Start : Int := 0;
      On : Boolean := False;
   end record;
   package Sess_Vectors is new Ada.Containers.Vectors (Positive, Sess_Rec);
   Sess_List : Sess_Vectors.Vector;

   Mood_P : array (Entity_Id) of Integer := [others => 0];
   Cost_P : array (Entity_Id) of Natural := [others => 0];
   Votes_Out, Pets_Out, Dict_Out, Anns_Out, Bals_Out : Str_Vectors.Vector;
   Votes_All, Pets_All, Dict_All, Anns_All, Bals_All : Str_Vectors.Vector;

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

   function Num (S : String) return Int is   --  the leading whole number of S (signed), 0 if none
      R : Int := 0;
      Neg : Boolean := False;
   begin
      for C of S loop
         if C = '-' and then R = 0 and then not Neg then Neg := True;
         elsif C in '0' .. '9' then R := R * 10 + Int (Character'Pos (C) - 48);
         else exit;
         end if;
      end loop;
      return (if Neg then -R else R);
   end Num;

   function Dashed (S : String) return String is
      R : String := S;
   begin
      for C of R loop if C = ' ' then C := '-'; end if; end loop;
      return R;
   end Dashed;

   function Part (S : String; K : Positive; Sep : Character) return String is   --  the K-th piece of S split at Sep ("" if none)
      From : Natural := S'First;
      N : Natural := 0;
   begin
      for I in S'First .. S'Last + 1 loop
         if I > S'Last or else S (I) = Sep then
            N := N + 1;
            if N = K then return S (From .. I - 1); end if;
            From := I + 1;
         end if;
      end loop;
      return "";
   end Part;

   function Pad_Left (S : String; W : Positive) return String is (if S'Length >= W then S else [1 .. W - S'Length => ' '] & S);
   function Pad_Right (S : String; W : Positive) return String is (if S'Length >= W then S else S & [1 .. W - S'Length => ' ']);

   --  ---- init / session ---------------------------------------------------------------------------------------------------
   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
      Is_Active := False; Is_Quality := False; Sess_N := 0; Scan_Init := False; Last_Scan := 0;
      V_N := 0; A_N := 0; L_N := 0; B_N := 0; Voted_N := 0; Agreed_N := 0;
      Ses_Agreed := 0; Ses_Rejected := 0; Ses_Ann := 0;
      Pending.Clear; Anns.Clear; Sess_List.Clear;
      Mood_P := [others => 0]; Cost_P := [others => 0];
      Votes_Out.Clear; Pets_Out.Clear; Dict_Out.Clear; Anns_Out.Clear; Bals_Out.Clear;
      Votes_All.Clear; Pets_All.Clear; Dict_All.Clear; Anns_All.Clear; Bals_All.Clear;
   end Init;

   procedure Begin_Session (N : Positive; Start : Int; On : Boolean; Quality : Boolean := False) is
   begin
      Is_Active := On;
      Is_Quality := On and then Quality;
      Sess_N := N;
      Sess_List.Append (Sess_Rec'(N => N, Start => Start, On => On));
      Voted_N := 0; Agreed_N := 0; Ses_Agreed := 0; Ses_Rejected := 0; Ses_Ann := 0;
      if On or else Scan_Init then Last_Scan := Count; end if;   --  words coined in a session without the marker are no proposals
      if On then Scan_Init := True; end if;
      Sim_World.Set_Clean (On);
   end Begin_Session;

   function Active return Boolean is (Is_Active);

   --  ---- the lines --------------------------------------------------------------------------------------------------------
   procedure Vote (Tick : Int; Voter, Kind, Subj, Choice, W : String; Extra : String := "") is
      V : constant String := "V" & Img (V_N + 1) & " t=" & Img (Tick) & " s=" & Img (Sess_N) & " voter=" & Voter & " kind=" & Kind
                             & " subj=" & Subj & " choice=" & Choice & " w=" & W & Extra;
   begin
      V_N := V_N + 1;
      Votes_Out.Append (V);
      Votes_All.Append (V);
   end Vote;

   procedure From_Decision (Line : String) is
      K : constant String := Tok (Line, "kind");
      Tick : constant Int := Num (Tok (Line, "t"));
      Pet : constant String := Tok (Line, "pet");
      Tr : constant String := Tok (Line, "trust");
      St : constant String := Tok (Line, "stand");
   begin
      if not Is_Active or else K not in "grant" | "partial" | "defer" | "refuse" or else Pet'Length < 2 then return; end if;
      Vote (Tick, Tok (Line, "player"), "petition", Pet, K, Img (Num (Tr)), " st=" & Img (Num (St)) & " of=" & Tok (Line, "wesen"));
      if K /= "defer" then
         declare
            N : constant Positive := Positive (Int'Max (1, Num (Pet (Pet'First + 1 .. Pet'Last))));
            Topic : constant String := Tok (Line, "topic");
            T : constant Natural := Topic_Id (Topic);
            Lever : constant String := Tok (Line, "lever");
            P : constant String := Pet & " t=" & Img (Tick) & " s=" & Img (Sess_N) & " filed=" & Img (Petition_Tick (N))
                                   & " wesen=" & Tok (Line, "wesen") & " topic=" & Topic & " lever=" & Lever
                                   & " req=" & (if T > 0 then Dashed (Topic_Phrase (T)) else "-")
                                   & " player=" & Tok (Line, "player") & " out=" & K & " why=" & Tok (Line, "why");
         begin
            Pets_Out.Append (P);
            Pets_All.Append (P);
         end;
      end if;
   end From_Decision;

   procedure From_Trial (Line : String) is
      Win : constant String := Tok (Line, "win");
      A : constant String := Tok (Line, "a");
      B : constant String := Tok (Line, "b");
      Verdict : constant String := Tok (Line, "verdict");
      Key : constant String := Line (Line'First .. (if Fx.Index (Line, " ") = 0 then Line'Last else Fx.Index (Line, " ") - 1));
   begin
      if not Is_Active or else Verdict not in "adhered" | "refused" or else Win = "" or else Win = "-" then return; end if;
      Vote (Num (Tok (Line, "t")), (if Win = A then B else A), "trial", Key, Verdict, "1");
   end From_Trial;

   procedure From_Advice (Line : String) is
      Tick : constant Int := Num (Tok (Line, "t"));
      Key : constant String := Line (Line'First .. (if Fx.Index (Line, " ") = 0 then Line'Last else Fx.Index (Line, " ") - 1));
      We : constant String := Tok (Line, "wesen");
      Pl : constant String := Tok (Line, "players");
   begin
      if not Is_Active then return; end if;
      for E in Entity_Id loop
         if Part (We, Positive (E), '/') /= "" then Vote (Tick, Name (E), "advice", Key, Part (We, Positive (E), '/'), "1"); end if;
      end loop;
      for P in Sim_Dharma.Player_Id loop
         if Part (Pl, Positive (P), '/') /= "" then
            Vote (Tick, Sim_Dharma.Player_Name (P), "advice", Key, Part (Pl, Positive (P), '/'), "1");
         end if;
      end loop;
   end From_Advice;

   procedure Length_Votes (Tick : Int; Votes : Kalpa_Votes) is
   begin
      if not Is_Active then return; end if;
      for E in Entity_Id loop Vote (Tick, Name (E), "length", "S" & Img (Sess_N), Img (Votes (Positive (E))), "1"); end loop;
   end Length_Votes;

   --  ---- announcements -----------------------------------------------------------------------------------------------------
   procedure Put_Ann (Tick : Int; By, Kind, Topic : String; Heard, Mood, Cost : Integer; Counter : Boolean) is
      A : constant String := "A" & Img (A_N + 1) & " t=" & Img (Tick) & " s=" & Img (Sess_N) & " by=" & By & " kind=" & Kind & " topic=" & Topic
                             & " heard=" & Img (Heard) & " mood=" & Sgn (Int (Mood)) & " cost=" & Img (Cost) & " react=" & (if Counter then "counter" else "ok");
   begin
      A_N := A_N + 1;
      Anns_Out.Append (A);
      Anns_All.Append (A);
      Ses_Ann := Ses_Ann + 1;
   end Put_Ann;

   --  E tells everybody (Kind 1: its wish, Kind 3: its word).
   procedure Announce (E : Entity_Id; Tick : Int; Kind : Positive; Topic : String; Mood : Integer) is
      Mx : constant Integer := Integer'Max (0, L ("rec.ann_mood", 2));
      Nudge : constant Integer := Clamp (Mood / 40, -Mx, Mx);
      Heard, Mood_Sum : Integer := 0;
      Counter : constant Boolean := Roll (Seed_V, Positive (E), Tick, 14003, 100) <= L ("rec.ann_counter_pct", 25);
      Cost : constant Integer := Integer'Max (0, L ("rec.ann_cost", 1));
   begin
      for X in Entity_Id loop
         if X /= E and then Roll (Seed_V, Positive (X), Tick, 14002, 100) <= L ("rec.ann_hear_pct", 80) then
            Heard := Heard + 1;
            Mood_P (X) := Mood_P (X) + Nudge;
            Mood_Sum := Mood_Sum + Nudge;
         end if;
      end loop;
      Cost_P (E) := Cost_P (E) + Natural (Cost);
      Anns.Append (Ann_Rec'(Kind => Kind, Who => Natural (E), Topic => To_Unbounded_String (Topic), At_T => Tick, Counter => Counter));
      Put_Ann (Tick, Name (E), (if Kind = 3 then "word" else "wish"), Topic, Heard, Mood_Sum, Cost, Counter);
   end Announce;

   function Shift (E : Entity_Id; Topic : String; Tick : Int) return Integer is
      Win : constant Int := Int (L ("rec.ann_window", 150));
      R : Integer := 0;
      Sup, Own : Integer := 0;
   begin
      if not Is_Active or else Anns.Is_Empty then return 0; end if;
      for A of Anns loop
         if A.Kind /= 3 and then Tick >= A.At_T and then Tick - A.At_T <= Win and then To_String (A.Topic) = Topic then
            if A.Kind = 1 and then A.Who /= Natural (E) then Sup := Sup + L ("rec.ann_vote", 6);
            elsif A.Kind = 1 and then A.Counter then Own := Own - L ("rec.ann_counter", 15);
            elsif A.Kind = 2 and then Natural (Sim_Dharma.Watcher (E)) = A.Who then Sup := Sup + L ("rec.pann_commit", 8);
            end if;
         end if;
      end loop;
      R := Integer'Min (Sup, L ("rec.ann_vote_max", 12)) + Integer'Max (Own, -L ("rec.ann_counter", 15));
      return R;
   end Shift;

   function Take_Mood (E : Entity_Id) return Integer is
      M : constant Integer := Mood_P (E);
   begin
      Mood_P (E) := 0;
      return M;
   end Take_Mood;

   function Take_Cost (E : Entity_Id) return Natural is
      C : constant Natural := Cost_P (E);
   begin
      Cost_P (E) := 0;
      return C;
   end Take_Cost;

   --  ---- word proposals ----------------------------------------------------------------------------------------------------
   function Is_Known_Text (T : String) return Boolean is
   begin
      if Find (T) /= 0 then return True; end if;
      for P of Pending loop if To_String (P.Text) = T then return True; end if; end loop;
      for D of Dict_All loop if Tok (D, "word") = T then return True; end if; end loop;
      return False;
   end Is_Known_Text;

   --  records=2: a meaning that is agreed, pending, or was rejected less than rec.mean_cooldown sessions ago is not put to a vote
   function Mean_Blocked (Mean : String; With_Pending : Boolean := True) return Boolean is
      Cool : constant Natural := Natural (L ("rec.mean_cooldown", 3));
   begin
      if With_Pending then for P of Pending loop if To_String (P.Mean) = Mean then return True; end if; end loop; end if;
      for D of Dict_All loop
         if Tok (D, "mean") = Mean then
            if Tok (D, "st") = "A" or else Natural (Num (Tok (D, "s"))) + Cool > Sess_N then return True; end if;
         end if;
      end loop;
      return False;
   end Mean_Blocked;

   function Is_Base (Name : String) return Boolean is   --  a plain word of data/vocab.txt
      W : constant Natural := Find (Name);
   begin
      return W /= 0 and then W <= Base_Count and then Plain (W);
   end Is_Base;

   function Base_Pair (Mean : String) return Boolean is   --  "hand+phone": every part is a base word
      Plus : constant Natural := Fx.Index (Mean, "+");
   begin
      return (if Plus = 0 then Is_Base (Mean) else Is_Base (Mean (Mean'First .. Plus - 1)) and then Is_Base (Mean (Plus + 1 .. Mean'Last)));
   end Base_Pair;

   function Alt_Count (Mean : String) return Natural is   --  records=2: the forms waiting for the same meaning
      N : Natural := 0;
   begin
      for P of Pending loop if To_String (P.Mean) = Mean then N := N + 1; end if; end loop;
      return N;
   end Alt_Count;

   procedure Add_Prop (Text, Mean : String; Slot : Positive; By : Entity_Id; Tick : Int; Salt : Natural) is
   begin
      if Natural (Pending.Length) >= Natural (L ("rec.prop_cap", 12)) or else Is_Known_Text (Text) then return; end if;
      if Is_Quality and then (not Base_Pair (Mean) or else Mean_Blocked (Mean, False) or else Alt_Count (Mean) >= Natural (L ("rec.alt_max", 3))) then return; end if;
      declare
         Ann : constant Boolean := Roll (Seed_V, Positive (By), Tick, 14004 + Salt mod 30, 100) <= L ("rec.word_ann_pct", 20);
      begin
         Pending.Append (Prop_Rec'(Text => To_Unbounded_String (Text), Mean => To_Unbounded_String (Mean), Slot => Slot, By => By, At_T => Tick, Ann => Ann));
         if Ann and then not Is_Quality then Announce (By, Tick, 3, Text, 0); end if;   --  records=2: only the winning form is announced (secret ballot)
      end;
   end Add_Prop;

   procedure Scan_Coined (Tick : Int) is
   begin
      if not Is_Active then return; end if;
      while Last_Scan < Count loop
         Last_Scan := Last_Scan + 1;
         declare
            W : constant Positive := Last_Scan;
            C : constant String := Coined_By (W);
            Who : constant Natural := (if C = "" then 0 else Sim_Dharma.Find_Wesen (C));
         begin
            if Who > 0 and then Parents (W) /= "" then Add_Prop (Word (W), Parents (W), 1, Entity_Id (Who), Tick, W); end if;
         end;
      end loop;
   end Scan_Coined;

   function Pick_Known (E : Entity_Id; Tick : Int) return Natural is   --  a plain word E knows, picked by dice (0: none)
      N : constant Natural := Count;
   begin
      if N = 0 then return 0; end if;
      declare
         Start : constant Positive := Roll (Seed_V, Positive (E), Tick, 14040, N);
      begin
         for I in 0 .. N - 1 loop
            declare
               W : constant Positive := (Start - 1 + I) mod N + 1;
            begin
               if Knows (E, W) and then Plain (W) and then (not Is_Quality or else (W <= Base_Count and then not Mean_Blocked (Word (W), False))) then return W; end if;
            end;
         end loop;
      end;
      return 0;
   end Pick_Known;

   procedure Note_Petition (E : Entity_Id; Tick : Int; Topic : String; Mood : Integer) is
   begin
      if not Is_Active then return; end if;
      if Roll (Seed_V, Positive (E), Tick, 14001, 100) <= L ("rec.ann_pct", 20) then Announce (E, Tick, 1, Topic, Mood); end if;
      if Roll (Seed_V, Positive (E), Tick, 14010, 100) <= L ("rec.prop_pct", 30) then
         declare
            Syl : constant Positive := 1 + Roll (Seed_V, Positive (E), Tick, 14011, 2);   --  2 or 3 syllables
            Text : Unbounded_String;
            Mean : constant Natural := Pick_Known (E, Tick);
            Alt : Unbounded_String;   --  records=2: sometimes a wesen names a meaning that already waits for a name (an alternative)
         begin
            if Is_Quality and then Roll (Seed_V, Positive (E), Tick, 14060, 100) <= L ("rec.alt_pct", 35) then
               declare
                  Open : Natural := 0;
               begin
                  for P of Pending loop if Alt_Count (To_String (P.Mean)) < Natural (L ("rec.alt_max", 3)) then Open := Open + 1; end if; end loop;
                  if Open > 0 then
                     declare
                        Pick : Positive := Roll (Seed_V, Positive (E), Tick, 14061, Open);
                     begin
                        for P of Pending loop
                           if Alt_Count (To_String (P.Mean)) < Natural (L ("rec.alt_max", 3)) then
                              if Pick = 1 then Alt := P.Mean; exit; end if;
                              Pick := Pick - 1;
                           end if;
                        end loop;
                     end;
                  end if;
               end;
            end if;
            for I in 1 .. Syl loop
               Append (Text, Ada.Characters.Handling.To_Lower (Sim_Things.Blend_Syllable (E, Tick, 14200 + 50 * I)));
            end loop;
            if Length (Alt) > 0 and then Length (Text) in 3 .. L ("rec.prop_max_len", 12) and then (for all C of To_String (Text) => C in 'a' .. 'z') then
               Add_Prop (To_String (Text), To_String (Alt), 2, E, Tick, 7);
            elsif Mean > 0 and then Length (Text) in 3 .. L ("rec.prop_max_len", 12) and then (for all C of To_String (Text) => C in 'a' .. 'z') then
               Add_Prop (To_String (Text), Word (Mean), 2, E, Tick, 7);
            end if;
         end;
      end if;
   end Note_Petition;

   --  ---- the secret ballot (records=2): several forms for one meaning --------------------------------------------------------
   --  Every player picks one form (a dice score plus its trust in the proposer, less for long forms), the plurality wins, a tie is broken
   --  by a seeded die.  The line goes to diaries/ballots.txt ONLY (the Ground reads it with make ballots); nothing else shows it.
   procedure Ballot (Group : Prop_Vectors.Vector; Tick : Int; K : Positive; Trust : Trust_Array; Winner : out Positive) is
      Np : constant Positive := Positive (Sim_Dharma.Last_Player);
      Na : constant Positive := Positive (Group.Length);
      Tally : array (1 .. Na) of Natural := [others => 0];
      Picks, Alts, Tl : Unbounded_String;
      Top, Tied : Natural := 0;
   begin
      for Pl in 1 .. Np loop
         declare
            Pid : constant Sim_Dharma.Player_Id := Sim_Dharma.Player_Id (Pl);
            Best : Positive := 1;
            Best_S : Integer := Integer'First;
         begin
            for A in 1 .. Na loop
               declare
                  P : constant Prop_Rec := Group (A);
                  Tr : constant Integer := (if Sim_Dharma.Watcher (P.By) = Pid then Trust (P.By) else 50);
                  Sc : constant Integer :=
                    Roll (Seed_V, 200 + 10 * K + Pl, Tick, 14360 + A, 100) + (Tr - 50) * L ("rec.ballot_trust", 40) / 100
                    - Integer'Max (0, Length (P.Text) - 5) * L ("rec.ballot_len", 3);
               begin
                  if Sc > Best_S then Best := A; Best_S := Sc; end if;
               end;
            end loop;
            Tally (Best) := Tally (Best) + 1;
            Append (Picks, (if Pl > 1 then "," else "") & Sim_Dharma.Player_Name (Pid) & ":" & To_String (Group (Best).Text));
         end;
      end loop;
      for A in 1 .. Na loop
         Append (Alts, (if A > 1 then "," else "") & To_String (Group (A).Text));
         Append (Tl, (if A > 1 then "," else "") & To_String (Group (A).Text) & ":" & Img (Tally (A)));
         if Tally (A) > Top then Top := Tally (A); end if;
      end loop;
      for A in 1 .. Na loop if Tally (A) = Top then Tied := Tied + 1; end if; end loop;
      Winner := 1;
      if Tied = 1 then
         for A in 1 .. Na loop if Tally (A) = Top then Winner := A; end if; end loop;
      else
         declare
            Pick : Positive := Roll (Seed_V, 200 + 10 * K, Tick, 14370, Tied);
         begin
            for A in 1 .. Na loop
               if Tally (A) = Top then
                  if Pick = 1 then Winner := A; exit; end if;
                  Pick := Pick - 1;
               end if;
            end loop;
         end;
      end if;
      B_N := B_N + 1;
      declare
         Line : constant String := "B" & Img (B_N) & " t=" & Img (Tick) & " s=" & Img (Sess_N) & " mean=" & To_String (Group (1).Mean)
                                   & " alts=" & To_String (Alts) & " picks=" & To_String (Picks) & " tally=" & To_String (Tl)
                                   & " win=" & To_String (Group (Winner).Text) & " tie=" & (if Tied > 1 then "1" else "0");
      begin
         Bals_Out.Append (Line);
         Bals_All.Append (Line);
      end;
   end Ballot;

   --  The next proposal to be put to the vote: records=2 gathers all forms of its meaning and lets the players choose among them.
   procedure Take_Next (Tick : Int; K : Positive; Trust : Trust_Array; Chosen : out Prop_Rec) is
      First : constant Prop_Rec := Pending.First_Element;
      Group : Prop_Vectors.Vector;
      Rest : Prop_Vectors.Vector;
      W : Positive := 1;
   begin
      Pending.Delete_First;
      Chosen := First;
      if not Is_Quality then return; end if;
      Group.Append (First);
      for P of Pending loop
         if P.Mean = First.Mean then Group.Append (P); else Rest.Append (P); end if;
      end loop;
      Pending := Rest;
      if Natural (Group.Length) > 1 then
         Ballot (Group, Tick, K, Trust, W);
         Chosen := Group (W);
      end if;
   end Take_Next;

   --  ---- the end of a session -----------------------------------------------------------------------------------------------
   procedure Vote_Words (Tick : Int; Trust : Trust_Array) is
      Np : constant Positive := Positive (Sim_Dharma.Last_Player);
      K : Natural := 0;
   begin
      if Is_Quality then   --  records=2: proposals made before (old rules) or meanwhile blocked are dropped, not voted on
         declare
            Waiting : constant Prop_Vectors.Vector := Pending;
         begin
            Pending.Clear;
            for P of Waiting loop
               if Base_Pair (To_String (P.Mean)) and then not Mean_Blocked (To_String (P.Mean), False) then Pending.Append (P); end if;
            end loop;
         end;
      end if;
      while not Pending.Is_Empty and then K < Natural (L ("rec.words_per_session", 6)) loop
         declare
            Chosen : Prop_Rec;
         begin
            Take_Next (Tick, K + 1, Trust, Chosen);
            declare
            P : constant Prop_Rec := Chosen;
            Txt : constant String := To_String (P.Text);
            Yes : Natural := 0;
            Subj : constant String := "L" & Img (L_N + 1);
         begin
            if Is_Quality and then P.Ann then Announce (P.By, Tick, 3, Txt, 0); end if;   --  records=2: only the winning form is announced
            K := K + 1;
            for Pl in 1 .. Np loop
               declare
                  Pid : constant Sim_Dharma.Player_Id := Sim_Dharma.Player_Id (Pl);
                  Tr : constant Integer := (if Sim_Dharma.Watcher (P.By) = Pid then Trust (P.By) else 50);
                  Score : constant Integer :=
                    L ("rec.word_base", 45) + Sim_Dharma.Warm_Of (Pid) * L ("rec.word_warm", 40) / 100
                    - (Sim_Dharma.Brev_Of (Pid) - 50) * L ("rec.word_strict", 30) / 100 + (Tr - 50) * L ("rec.word_trust", 40) / 100
                    - Integer'Max (0, Txt'Length - 6) * L ("rec.word_len", 4) + (if P.Ann then L ("rec.word_ann_vote", 12) else 0)
                    + (if P.Slot = 1 then L ("rec.coin_bonus", 10) else 0);
                  Pct : constant Integer := Clamp (Score, 5, 95);
                  Y : constant Boolean := Roll (Seed_V, 10 + Pl, Tick, 14100 + K, 100) <= Pct;
               begin
                  if Y then Yes := Yes + 1; end if;
                  Vote (Tick, Sim_Dharma.Player_Name (Pid), "word", Subj, (if Y then "yes" else "no"), Img (Pct));
               end;
            end loop;
            declare
               Agree : constant Boolean := Yes * 2 > Np and then Agreed_N < Natural (L ("rec.agree_cap", 3));
               Why : constant String := (if Agree then "majority" elsif Yes * 2 > Np then "cap" elsif Yes * 2 = Np then "tie" else "split");
               Line : constant String := Subj & " t=" & Img (Tick) & " s=" & Img (Sess_N) & " st=" & (if Agree then "A" else "R") & " word=" & Txt
                                          & " slot=" & (if P.Slot = 1 then "coined" else "name") & " mean=" & To_String (P.Mean)
                                          & " by=" & Name (P.By) & " prop=" & Img (P.At_T) & " yes=" & Img (Yes) & " no=" & Img (Np - Yes)
                                          & " ann=" & (if P.Ann then "1" else "0") & " why=" & Why;
            begin
               L_N := L_N + 1;
               Voted_N := Voted_N + 1;
               if Agree then Agreed_N := Agreed_N + 1; Ses_Agreed := Ses_Agreed + 1; else Ses_Rejected := Ses_Rejected + 1; end if;
               Dict_Out.Append (Line);
               Dict_All.Append (Line);
            end;
            end;
         end;
      end loop;
   end Vote_Words;

   procedure Players_Announce (Tick : Int; Concern : Str_Vectors.Vector) is
      Np : constant Positive := Positive (Sim_Dharma.Last_Player);
   begin
      for Pl in 1 .. Np loop
         declare
            Pid : constant Sim_Dharma.Player_Id := Sim_Dharma.Player_Id (Pl);
            Topic : constant String := (if Pl <= Natural (Concern.Length) then Concern (Pl) else "");
            T : constant Natural := Topic_Id (Topic);
         begin
            if Topic /= "" and then T > 0 and then Roll (Seed_V, 10 + Pl, Tick, 14150, 100) <= L ("rec.pann_pct", 30) then
               declare
                  Counter : constant Boolean := Roll (Seed_V, 10 + Pl, Tick, 14151, 100) <= L ("rec.ann_counter_pct", 25);
                  Cost : constant Integer := Integer'Max (0, L ("rec.ann_cost", 1)) * (if Counter then 2 else 1);
                  Heard, Mood_Sum : Integer := 0;
               begin
                  for E in Entity_Id loop
                     if Sim_Dharma.Watcher (E) = Pid then
                        Cost_P (E) := Cost_P (E) + Natural (Cost);
                        if Asked (E, T) > 0 then Heard := Heard + 1; Mood_P (E) := Mood_P (E) + 1; Mood_Sum := Mood_Sum + 1; end if;
                     end if;
                  end loop;
                  Anns.Append (Ann_Rec'(Kind => 2, Who => Pl, Topic => To_Unbounded_String (Topic), At_T => Tick, Counter => Counter));
                  Put_Ann (Tick, Sim_Dharma.Player_Name (Pid), "player", Topic, Heard, Mood_Sum, Cost, Counter);
               end;
            end if;
         end;
      end loop;
   end Players_Announce;

   procedure Session_End (Tick : Int; Favourites : Str_Vectors.Vector; C_Line : String; Trust : Trust_Array; Concern : Str_Vectors.Vector) is
   begin
      if not Is_Active then return; end if;
      for E in Entity_Id loop
         if Positive (E) <= Natural (Favourites.Length) then
            declare
               W : constant String := Favourites (Positive (E));
            begin
               Vote (Tick, Name (E), "favourite", "W" & Img (Sess_N), (if W = "" then "-" else W), "1");
            end;
         end if;
      end loop;
      if C_Line'Length > 1 then
         declare
            Key : constant String := C_Line (C_Line'First .. (if Fx.Index (C_Line, " ") = 0 then C_Line'Last else Fx.Index (C_Line, " ") - 1));
            Vs : constant String := Tok (C_Line, "votes");
            I : Positive := 1;
         begin
            while Part (Vs, I, ',') /= "" loop
               declare
                  Pair : constant String := Part (Vs, I, ',');
               begin
                  Vote (Tick, Part (Pair, 1, ':'), "collective", Key, Part (Pair, 2, ':'), "1");
               end;
               I := I + 1;
            end loop;
         end;
      end if;
      Vote_Words (Tick, Trust);
      Players_Announce (Tick, Concern);
   end Session_End;

   procedure Drain (Votes, Pets, Dict, Notes, Ballots : in out Str_Vectors.Vector) is
   begin
      Votes.Append (Votes_Out); Votes_Out.Clear;
      Pets.Append (Pets_Out); Pets_Out.Clear;
      Dict.Append (Dict_Out); Dict_Out.Clear;
      Notes.Append (Anns_Out); Anns_Out.Clear;
      Ballots.Append (Bals_Out); Bals_Out.Clear;
   end Drain;

   --  ---- views ---------------------------------------------------------------------------------------------------------------
   function Box_Line (Players : Positive) return String is
   begin
      if not Is_Active or else Sess_N = 0 or else Ses_Agreed + Ses_Rejected + Ses_Ann = 0 then return ""; end if;
      return Msg ("rec.box", Sim_Dharma.Player_Name (Sim_Dharma.Player_Id (Roll (Seed_V, 4, Int (Sess_N), 14190, Players))),
                  Img (Ses_Agreed), Img (Ses_Rejected), Img (Ses_Ann));
   end Box_Line;

   function Count_Dict (St : String) return Natural is
      N : Natural := 0;
   begin
      for D of Dict_All loop if Tok (D, "st") = St then N := N + 1; end if; end loop;
      return N;
   end Count_Dict;

   function Waiting return Natural is   --  proposals waiting for a vote (records=2: one per meaning: the forms stay secret)
      Seen : Str_Vectors.Vector;
   begin
      if not Is_Quality then return Natural (Pending.Length); end if;
      for P of Pending loop
         if not Seen.Contains (To_String (P.Mean)) then Seen.Append (To_String (P.Mean)); end if;
      end loop;
      return Natural (Seen.Length);
   end Waiting;

   function Counts return String is
     (Img (Count_Dict ("A")) & " agreed, " & Img (Count_Dict ("R")) & " rejected, " & Img (Waiting) & " waiting, "
      & Img (Natural (Anns_All.Length)) & " announced");

   --  trend.txt: the petition votes of each player so far (the raw votes, not the reports) and the words agreed / rejected.  All zero
   --  without records.
   function Trend return String is
      type Four is array (1 .. 4) of Natural;
      Grant, Refuse : Four := [others => 0];
      function List (A : Four) return String is (Img (A (1)) & "," & Img (A (2)) & "," & Img (A (3)) & "," & Img (A (4)));
   begin
      for V of Votes_All loop
         if Tok (V, "kind") = "petition" then
            declare
               Pl : constant Natural := Sim_Dharma.Find_Player (Tok (V, "voter"));
            begin
               if Pl in 1 .. 4 then
                  if Tok (V, "choice") = "grant" then Grant (Pl) := Grant (Pl) + 1;
                  elsif Tok (V, "choice") not in "partial" | "defer" then Refuse (Pl) := Refuse (Pl) + 1;
                  end if;
               end if;
            end;
         end if;
      end loop;
      return " grant=" & List (Grant) & " refuse=" & List (Refuse) & " agreed=" & Img (Count_Dict ("A")) & " rejected=" & Img (Count_Dict ("R"));
   end Trend;

   function Session_Of (T : Int) return Natural is   --  the session that ends at or contains tick T
   begin
      for I in reverse 1 .. Natural (Sess_List.Length) loop
         if Sess_List (I).Start < T then return Sess_List (I).N; end if;
      end loop;
      return 0;
   end Session_Of;

   type Row_Rec is record
      S, Pl : Natural := 0;
      Claim, True_V, Reports : Integer := 0;
      Grant, Part, Defer, Refuse, Yes, No : Natural := 0;
   end record;
   package Row_Vectors is new Ada.Containers.Vectors (Positive, Row_Rec);

   function Divergence return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
      Rows : Row_Vectors.Vector;
      Lines : Str_Vectors.Vector;
      Found : Boolean;
      Last_Sess : Natural := 0;

      function Row_Of (S, Pl : Natural) return Positive is
      begin
         for I in 1 .. Natural (Rows.Length) loop
            if Rows (I).S = S and then Rows (I).Pl = Pl then return I; end if;
         end loop;
         Rows.Append (Row_Rec'(S => S, Pl => Pl, others => <>));
         return Natural (Rows.Length);
      end Row_Of;
   begin
      Read_Lines ("diaries/preports.txt", Lines, Found);
      for Ln of Lines loop
         if Ln'Length > 1 and then Ln (Ln'First) = 'P' and then Tok (Ln, "claimed") /= "" then
            declare
               S : constant Natural := Session_Of (Num (Tok (Ln, "t")));
               Pl : constant Natural := Sim_Dharma.Find_Player (Tok (Ln, "player"));
            begin
               if S > 0 and then Pl > 0 then
                  declare
                     I : constant Positive := Row_Of (S, Pl);
                  begin
                     Rows (I).Claim := Rows (I).Claim + Integer (Num (Tok (Ln, "claimed")));
                     Rows (I).True_V := Rows (I).True_V + Integer (Num (Tok (Ln, "true")));
                     Rows (I).Reports := Rows (I).Reports + 1;
                  end;
               end if;
            end;
         end if;
      end loop;
      for V of Votes_All loop
         declare
            K : constant String := Tok (V, "kind");
            S : constant Natural := Natural (Num (Tok (V, "s")));
            Pl : constant Natural := Sim_Dharma.Find_Player (Tok (V, "voter"));
            C : constant String := Tok (V, "choice");
         begin
            if Pl > 0 and then S > 0 and then K in "petition" | "word" then
               declare
                  I : constant Positive := Row_Of (S, Pl);
               begin
                  if K = "petition" then
                     if C = "grant" then Rows (I).Grant := Rows (I).Grant + 1;
                     elsif C = "partial" then Rows (I).Part := Rows (I).Part + 1;
                     elsif C = "defer" then Rows (I).Defer := Rows (I).Defer + 1;
                     else Rows (I).Refuse := Rows (I).Refuse + 1;
                     end if;
                  elsif C = "yes" then Rows (I).Yes := Rows (I).Yes + 1;
                  else Rows (I).No := Rows (I).No + 1;
                  end if;
               end;
            end if;
         end;
      end loop;
      if Sess_List.Is_Empty or else (Votes_All.Is_Empty and then Dict_All.Is_Empty) then
         R.Append (Msg ("rec.none"));
         return R;
      end if;
      R.Append (Msg ("rec.div.head"));
      R.Append (Msg ("rec.div.cols"));
      declare
         Rec_Sessions : Natural := 0;
         From : Natural := 0;
         Keep : constant Natural := Natural (L ("rec.div_sessions", 6));
      begin
         for I in reverse 1 .. Natural (Sess_List.Length) loop
            if Sess_List (I).On then
               Rec_Sessions := Rec_Sessions + 1;
               if Rec_Sessions <= Keep then From := Sess_List (I).N; end if;
            end if;
         end loop;
         for S of Sess_List loop
            if S.On and then S.N >= From then
               Last_Sess := S.N;
               for Pl in 1 .. Natural (Sim_Dharma.Last_Player) loop
                  declare
                     I : constant Positive := Row_Of (S.N, Pl);
                     X : constant Row_Rec := Rows (I);
                     Cl : constant String := (if X.Reports = 0 then "-" else Sgn (Int (X.Claim / X.Reports)));
                     Tr : constant String := (if X.Reports = 0 then "-" else Sgn (Int (X.True_V / X.Reports)));
                     Gap : constant String := (if X.Reports = 0 then "-" else Sgn (Int ((X.Claim - X.True_V) / X.Reports)));
                  begin
                     R.Append (Pad_Left (Img (S.N), 4) & " " & Pad_Right (Show (Sim_Dharma.Player_Name (Sim_Dharma.Player_Id (Pl))), 9)
                               & Pad_Left (Cl, 6) & Pad_Left (Tr, 6) & Pad_Left (Gap, 6) & " |" & Pad_Left (Img (X.Grant), 6)
                               & Pad_Left (Img (X.Part), 5) & Pad_Left (Img (X.Defer), 6) & Pad_Left (Img (X.Refuse), 7) & " |"
                               & Pad_Left (Img (X.Yes) & "/" & Img (X.No), 7));
                  end;
               end loop;
            end if;
         end loop;
      end;
      R.Append (Msg ("rec.dict.head", Img (Base_Count)));
      R.Append (Msg ("rec.dict.cols"));
      declare
         Total : Natural := 0;
      begin
         for S of Sess_List loop
            if S.On then
               declare
                  Ag, Rj : Natural := 0;
               begin
                  for D of Dict_All loop
                     if Natural (Num (Tok (D, "s"))) = S.N then
                        if Tok (D, "st") = "A" then Ag := Ag + 1; else Rj := Rj + 1; end if;
                     end if;
                  end loop;
                  Total := Total + Ag;
                  if S.N >= Last_Sess - Natural'Min (Last_Sess, Natural (L ("rec.div_sessions", 6))) + 1 then
                     R.Append (Pad_Left (Img (S.N), 4) & Pad_Left (Img (Ag + Rj), 10) & Pad_Left (Img (Ag), 8) & Pad_Left (Img (Rj), 10)
                               & Pad_Left (Img (Total), 8));
                  end if;
               end;
            end if;
         end loop;
      end;
      R.Append (Msg ("rec.div.sum", Counts));
      return R;
   end Divergence;

   --  make ballots: the Ground only
   function Ballots return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
      Keep : constant Natural := Natural (L ("rec.ballot_rows", 5));
      Ties : Natural := 0;
   begin
      for B of Bals_All loop if Tok (B, "tie") = "1" then Ties := Ties + 1; end if; end loop;
      R.Append (Msg ("rec.bal.head"));
      if Bals_All.Is_Empty then
         R.Append (Msg ("rec.bal.none"));
         return R;
      end if;
      R.Append (Msg ("rec.bal.sum", Img (Natural (Bals_All.Length)), Img (Ties)));
      for I in Natural'Max (1, Natural (Bals_All.Length) - Keep + 1) .. Natural (Bals_All.Length) loop
         declare
            B : constant String := Bals_All (I);
            Pk : constant String := Tok (B, "picks");
            Line : Unbounded_String;
            N : Positive := 1;
         begin
            R.Append (Pad_Right (B (B'First .. Fx.Index (B, " ") - 1), 5) & "s" & Tok (B, "s") & " = " & Tok (B, "mean") & ": " & Tok (B, "tally")
                      & " -> " & Tok (B, "win") & (if Tok (B, "tie") = "1" then " (die)" else ""));
            while Part (Pk, N, ',') /= "" loop
               declare
                  Pair : constant String := Part (Pk, N, ',');
               begin
                  declare
                     Item : constant String := Show (Part (Pair, 1, ':')) & " " & Part (Pair, 2, ':');
                  begin
                     if Length (Line) > 0 and then Length (Line) + Item'Length + 2 > 72 then
                        R.Append ("     " & To_String (Line) & ",");
                        Line := Null_Unbounded_String;
                     end if;
                     Append (Line, (if Length (Line) > 0 then ", " else "") & Item);
                  end;
               end;
               N := N + 1;
            end loop;
            R.Append ("     " & To_String (Line));
         end;
      end loop;
      return R;
   end Ballots;

   function Dictionary return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
      Keep : constant Natural := Natural (L ("rec.dict_rows", 14));
   begin
      R.Append (Msg ("rec.dict.head", Img (Base_Count)));
      R.Append (Msg ("rec.dict.sum", Counts));
      for I in Natural'Max (1, Natural (Dict_All.Length) - Keep + 1) .. Natural (Dict_All.Length) loop
         declare
            D : constant String := Dict_All (I);
         begin
            R.Append (Pad_Right (D (D'First .. Fx.Index (D, " ") - 1), 5) & Tok (D, "st") & " " & Pad_Right (Tok (D, "word"), 12)
                      & Pad_Right ("= " & Tok (D, "mean"), 18) & Pad_Right (Show (Tok (D, "by")), 9) & Tok (D, "yes") & "/" & Tok (D, "no")
                      & " s" & Tok (D, "s"));
         end;
      end loop;
      if Dict_All.Is_Empty then R.Append (Msg ("rec.dict.none")); end if;
      return R;
   end Dictionary;

   --  0.058: the checkpoint.
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Integer);
      procedure IO is new Sim_Ckpt.IO (Int);
      procedure IO is new Sim_Ckpt.IO (Boolean);
      procedure IO is new Sim_Ckpt.IO (Prop_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Ann_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Sess_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Str_Vectors.Vector);
   begin
      IO (S, Save, Seed_V);
      IO (S, Save, Is_Active); IO (S, Save, Is_Quality);
      IO (S, Save, Sess_N);
      IO (S, Save, Scan_Init);
      IO (S, Save, Last_Scan);
      IO (S, Save, V_N); IO (S, Save, A_N); IO (S, Save, L_N); IO (S, Save, B_N);
      IO (S, Save, Voted_N); IO (S, Save, Agreed_N);
      IO (S, Save, Ses_Agreed); IO (S, Save, Ses_Rejected); IO (S, Save, Ses_Ann);
      IO (S, Save, Pending);
      IO (S, Save, Anns);
      IO (S, Save, Sess_List);
      for E in Entity_Id loop IO (S, Save, Mood_P (E)); IO (S, Save, Cost_P (E)); end loop;
      IO (S, Save, Votes_Out); IO (S, Save, Pets_Out); IO (S, Save, Dict_Out); IO (S, Save, Anns_Out); IO (S, Save, Bals_Out);
      IO (S, Save, Votes_All); IO (S, Save, Pets_All); IO (S, Save, Dict_All); IO (S, Save, Anns_All); IO (S, Save, Bals_All);
   end State_IO;

end Sim_Records;
