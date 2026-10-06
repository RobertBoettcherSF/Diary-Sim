--  Version: 0.002
--  See sim_trial.ads.
pragma Ada_2022;

with Sim_Ckpt;

with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces;
with Sim_Dharma;
with Sim_Govern;

package body Sim_Trial is

   use Ada.Strings.Unbounded;
   use type Interfaces.Unsigned_32;

   type Step_Rec is record
      Loc : Integer := -1;
      Worked, Tired : Boolean := False;
      Coin_At, Pet_At, Pet_No : Int := -1;
      Pet_Topic : Unbounded_String;
   end record;
   type Step_Array is array (Entity_Id) of Step_Rec;
   type Last_Array is array (Sim_Games.Comp_Id) of Int;

   Seed_V : Int := 0;
   Info : Step_Array;
   Busy_Until : Last_Array := [others => -1_000_000];
   Last_T : Int := -1;
   Total, Session_N, Refused_N, Coin_N : Natural := 0;
   Seen_Refusal : array (Entity_Id) of Int := [others => -1];
   Claim_Window, Window, Pause, Rest, Cap, First, Ext_First, Ext_Step, Max_Games, Petition_Pct, Escalate_Pct, Appeal_Pct, Claim_Pct, Restwork_Pct,
     Adhere_Pct, Adhere_Min, Adhere_Max, Unrest_W, Stand_W, Win_Stand, Win_Trust, Win_Mood, Loss_Mood, Refuse_Stand : Integer := 0;
   Last_Src, Last_Win, Last_Lose, Last_Score, Last_How : Unbounded_String;
   All_Lines : Str_Vectors.Vector;

   function L (Key : String; D, Lo, Hi : Integer) return Integer is
     (Integer'Max (Lo, Integer'Min (Hi, Integer (Limit (Key, Int (D))))));

   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
      Info := [others => <>];
      Busy_Until := [others => -1_000_000];
      Last_T := -1;
      Total := 0; Session_N := 0; Refused_N := 0; Coin_N := 0;
      Seen_Refusal := [others => -1];
      All_Lines.Clear;
      Window := L ("trial.window", 30, 1, 10_000);
      Claim_Window := L ("trial.claim_window", 6, 1, 10_000);
      Pause := L ("trial.pause", 20, 0, 100_000);
      Rest := L ("trial.rest", 60, 0, 100_000);
      Cap := L ("trial.session_cap", 5, 0, 1000);
      First := L ("trial.first", 3, 1, 15);
      Ext_First := L ("trial.ext_first", 3, 1, 15);
      Ext_Step := L ("trial.ext_step", 2, 2, 10);
      Max_Games := L ("trial.max_games", 15, 1, 101);
      Petition_Pct := L ("trial.petition_pct", 50, 0, 100);
      Escalate_Pct := L ("trial.escalate_pct", 30, 0, 100);
      Appeal_Pct := L ("trial.appeal_pct", 25, 0, 100);
      Claim_Pct := L ("trial.claim_pct", 40, 0, 100);
      Restwork_Pct := L ("trial.restwork_pct", 6, 0, 100);
      Adhere_Pct := L ("trial.adhere_pct", 85, 0, 100);
      Adhere_Min := L ("trial.adhere_min", 5, 0, 100);
      Adhere_Max := L ("trial.adhere_max", 99, 0, 100);
      Unrest_W := L ("trial.unrest_w", 30, 0, 100);
      Stand_W := L ("trial.stand_w", 20, 0, 100);
      Win_Stand := L ("trial.win_stand", 1, 0, 10);
      Win_Trust := L ("trial.win_trust", 1, 0, 10);
      Win_Mood := L ("trial.win_mood", 1, -20, 20);
      Loss_Mood := L ("trial.loss_mood", -1, -20, 20);
      Refuse_Stand := L ("trial.refuse_stand", 2, 0, 20);
      --  an odd series needs odd matches: the first and the extension are made odd, the step even (>= 2)
      if First mod 2 = 0 then First := First + 1; end if;
      if Ext_First mod 2 = 0 then Ext_First := Ext_First + 1; end if;
      if Ext_Step mod 2 = 1 then Ext_Step := Ext_Step + 1; end if;
   end Init;

   procedure Begin_Session is
   begin
      Session_N := 0;
   end Begin_Session;

   procedure Note_Step (E : Entity_Id; Tick : Int; Loc : Integer; Worked, Coined, Tired : Boolean) is
   begin
      Info (E).Loc := Loc;
      Info (E).Worked := Worked;
      Info (E).Tired := Tired;
      if Coined then Info (E).Coin_At := Tick; end if;
   end Note_Step;

   procedure Note_Petition (E : Entity_Id; Tick : Int; Pet : Positive; Topic : String) is
   begin
      Info (E).Pet_At := Tick;
      Info (E).Pet_No := Int (Pet);
      Info (E).Pet_Topic := To_Unbounded_String (Topic);
   end Note_Petition;

   --  The Rule 30 coin: a 32-bit ring from a hashed start, 20 steps of new = left xor (centre or right), the middle bit.
   --  PROOF-LATER: Importance 2/10, Urgency 1/10, SPARK2 (bit arithmetic on a modular type)
   function Coin (Tick : Int; N : Natural) return Boolean is
      Row : Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Roll (Seed_V, 1, Tick, 9970 + N mod 5, 60_000)) * 65_536 + Interfaces.Unsigned_32 (Roll (Seed_V, 2, Tick, 9975, 60_000));
   begin
      if Row = 0 then Row := 1; end if;
      for I in 1 .. 20 loop
         Row := Interfaces.Rotate_Left (Row, 1) xor (Row or Interfaces.Rotate_Right (Row, 1));
      end loop;
      return (Row and 16#1_0000#) /= 0;
   end Coin;

   function Clashes (A, B : String) return Boolean is
   begin
      for N in 1 .. 99 loop
         declare
            T : constant String := Msg ("trial.clash." & Img (N));
            Sp : constant Natural := Ada.Strings.Fixed.Index (T, " ");
         begin
            exit when T'Length = 0 or else T (T'First) = '[' or else Sp = 0;
            declare
               X : constant String := T (T'First .. Sp - 1);
               Y : constant String := T (Sp + 1 .. T'Last);
            begin
               if (X = A and then Y = B) or else (X = B and then Y = A) then return True; end if;
            end;
         end;
      end loop;
      return False;
   end Clashes;

   function Sign (V : Integer) return String is (if V > 0 then "+" & Img (V) else Img (V));

   --  The series between A and B (competitors): returns the winner; writes the line.
   procedure Series (Tick : Int; Src, Subj : String; A, B : Sim_Games.Comp_Id; Moods : Sim_Games.Mood_Array; Lines, Chess_Lines : in out Str_Vectors.Vector) is
      WA, WB, Played, Match_N, Stages : Natural := 0;
      Games_List, Res_List : Unbounded_String;
      By_Coin : Boolean := False;
      Winner : Sim_Games.Comp_Id := A;
      Loser : Sim_Games.Comp_Id := B;
      Decided : Boolean := False;
      Mid : Natural := First;
      Adhere : Boolean := True;
      Chance : Integer := 100;
      Fx : Unbounded_String;
      Stand_Now, Unrest_Now : Integer := 0;
   begin
      loop
         Stages := Stages + 1;
         declare
            SA, SB, K : Natural := 0;
         begin
            while K < Mid and then SA * 2 <= Mid and then SB * 2 <= Mid loop
               declare
                  White : constant Sim_Games.Comp_Id := (if Played mod 2 = 0 then A else B);
                  Win, Gno : Natural;
               begin
                  Sim_Games.Play_Out (A, B, White, Tick, Moods, Chess_Lines, Win, Gno);
                  Games_List := Games_List & (if Played > 0 then "," else "") & Img (Gno);
                  Res_List := Res_List & (if Win = 0 then "d" elsif Win = A then "A" else "B");
                  if Win = A then SA := SA + 1; WA := WA + 1; elsif Win = B then SB := SB + 1; WB := WB + 1; end if;
                  Played := Played + 1; K := K + 1;
               end;
            end loop;
            if SA /= SB then
               Winner := (if SA > SB then A else B);
               Decided := True;
            end if;
            Match_N := Mid;
         end;
         exit when Decided;
         Mid := (if Stages = 1 then Ext_First else Mid + Ext_Step);
         if Played + Mid > Max_Games then   --  the data cap: the Rule 30 coin
            By_Coin := True;
            Winner := (if Coin (Tick, Total) then A else B);
            exit;
         end if;
      end loop;
      Loser := (if Winner = A then B else A);
      if Loser <= 4 then   --  a wesen as the loser: adherence (standing helps, unrest hurts)
         Stand_Now := Sim_Govern.Standing_Of (Entity_Id (Loser));
         Unrest_Now := Sim_Dharma.Unrest_Of (Entity_Id (Loser));
         Chance := Integer'Max (Adhere_Min, Integer'Min (Adhere_Max, Adhere_Pct + (Stand_Now - 50) * Stand_W / 100 - Unrest_Now * Unrest_W / 100));
         Adhere := Integer (Roll (Seed_V, Positive (Loser), Tick, 9965, 100)) <= Chance;
      end if;
      --  effects: a few points on a wesen's standing / trust / mood
      if Winner <= 4 then
         Sim_Govern.Adjust (Entity_Id (Winner), Win_Trust, Win_Stand);
         Sim_Games.Add_Mood (Winner, Win_Mood);
         Fx := To_Unbounded_String (" fxw=" & Sign (Win_Stand) & "/" & Sign (Win_Trust) & "/" & Sign (Win_Mood));
      end if;
      if Loser <= 4 then
         Sim_Games.Add_Mood (Loser, Loss_Mood);
         if not Adhere then Sim_Govern.Adjust (Entity_Id (Loser), 0, -Refuse_Stand); end if;
         Fx := Fx & " fxl=" & Sign (if Adhere then 0 else -Refuse_Stand) & "/" & Sign (0) & "/" & Sign (Loss_Mood);
      end if;
      if Length (Fx) = 0 then Fx := To_Unbounded_String (" fx=none"); end if;
      Total := Total + 1;
      Session_N := Session_N + 1;
      if not Adhere then Refused_N := Refused_N + 1; end if;
      if By_Coin then Coin_N := Coin_N + 1; end if;
      Busy_Until (A) := Tick + Int (Rest); Busy_Until (B) := Tick + Int (Rest);
      Last_T := Tick;
      declare
         Line : constant String :=
           "T" & Img (Total) & " t=" & Img (Tick) & " src=" & Src & " a=" & Sim_Games.Comp_Name (A) & " b=" & Sim_Games.Comp_Name (B)
           & (if Subj /= "" then " subj=" & Subj else "") & " games=" & To_String (Games_List) & " res=" & To_String (Res_List)
           & " score=" & Img (WA) & "-" & Img (WB) & " match=" & Img (Match_N) & " win=" & Sim_Games.Comp_Name (Winner)
           & " by=" & (if By_Coin then "coin" else "score") & " verdict=" & (if Adhere then "adhered" else "refused") & To_String (Fx);
      begin
         Lines.Append (Line);
         All_Lines.Append (Line);
         Last_Src := To_Unbounded_String (Src);
         Last_Win := To_Unbounded_String (Sim_Games.Comp_Name (Winner));
         Last_Lose := To_Unbounded_String (Sim_Games.Comp_Name (Loser));
         Last_Score := To_Unbounded_String (Img (WA) & "-" & Img (WB));
         Last_How := To_Unbounded_String ((if By_Coin then "coin" elsif not Adhere then "refused" else "score"));
      end;
   end Series;

   function Free (C : Sim_Games.Comp_Id; Tick : Int) return Boolean is (Busy_Until (C) <= Tick);

   procedure Step (Tick : Int; Moods : Sim_Games.Mood_Array; Lines, Chess_Lines : in out Str_Vectors.Vector) is
      Done : Boolean := False;
      function P_Of (E : Entity_Id) return Natural is
        (if Natural (Sim_Dharma.Watcher (E)) <= 3 then Natural (Sim_Dharma.Watcher (E)) + 4 else 0);
   begin
      --  the appeal tick is consumed whether or not a trial follows
      if Session_N >= Cap or else Tick - Last_T < Int (Pause) then
         for E in Entity_Id loop Seen_Refusal (E) := Sim_Govern.Refusal_Tick (E); end loop;
         return;
      end if;
      --  1. clashing petitions, filed now
      for E in Entity_Id loop
         exit when Done;
         if Info (E).Pet_At = Tick then
            for F in Entity_Id loop
               exit when Done;
               if F /= E and then Info (F).Pet_At >= 0 and then Tick - Info (F).Pet_At <= Int (Window)
                 and then (Info (F).Pet_At < Tick or else F < E)
                 and then Clashes (To_String (Info (E).Pet_Topic), To_String (Info (F).Pet_Topic))
                 and then Free (Sim_Games.As_Comp (E), Tick) and then Free (Sim_Games.As_Comp (F), Tick)
               then
                  if Integer (Roll (Seed_V, Positive (E) * 10 + Positive (F), Tick, 9960, 100)) <= Petition_Pct then
                     declare
                        Subj : constant String := "P" & Img (Info (F).Pet_No) & "/P" & Img (Info (E).Pet_No);
                        Pe : constant Natural := P_Of (E);
                        Pf : constant Natural := P_Of (F);
                     begin
                        if Pe /= 0 and then Pf /= 0 and then Pe /= Pf and then Free (Pe, Tick) and then Free (Pf, Tick)
                          and then Integer (Roll (Seed_V, Positive (E) * 10 + Positive (F), Tick, 9961, 100)) <= Escalate_Pct
                        then   --  the watching players take the case over
                           Series (Tick, "petition", Subj, Pe, Pf, Moods, Lines, Chess_Lines);
                        else
                           Series (Tick, "petition", Subj, Sim_Games.As_Comp (F), Sim_Games.As_Comp (E), Moods, Lines, Chess_Lines);
                        end if;
                        Done := True;
                     end;
                  end if;
               end if;
            end loop;
         end if;
      end loop;
      --  2. a refused petition appealed against the refusing player
      for E in Entity_Id loop
         declare
            R : constant Int := Sim_Govern.Refusal_Tick (E);
            Pl : constant Natural := P_Of (E);
         begin
            if R = Tick and then Seen_Refusal (E) /= R then
               Seen_Refusal (E) := R;
               if not Done and then Pl /= 0 and then Free (Sim_Games.As_Comp (E), Tick) and then Free (Pl, Tick)
                 and then Integer (Roll (Seed_V, Positive (E), Tick, 9962, 100)) <= Appeal_Pct
               then
                  Series (Tick, "appeal", "", Sim_Games.As_Comp (E), Pl, Moods, Lines, Chess_Lines);
                  Done := True;
               end if;
            end if;
         end;
      end loop;
      --  3. rival claims to a coined word
      for E in Entity_Id loop
         exit when Done;
         if Info (E).Coin_At = Tick then
            for F in Entity_Id loop
               exit when Done;
               if F /= E and then Info (F).Coin_At >= 0 and then Tick - Info (F).Coin_At <= Int (Claim_Window) and then (Info (F).Coin_At < Tick or else F < E)
                 and then Free (Sim_Games.As_Comp (E), Tick) and then Free (Sim_Games.As_Comp (F), Tick)
                 and then Integer (Roll (Seed_V, Positive (E) * 10 + Positive (F), Tick, 9963, 100)) <= Claim_Pct
               then
                  Series (Tick, "claim", "", Sim_Games.As_Comp (F), Sim_Games.As_Comp (E), Moods, Lines, Chess_Lines);
                  Done := True;
               end if;
            end loop;
         end if;
      end loop;
      --  4. rest against work: one is cooling down, a neighbour in the same place works
      for E in Entity_Id loop
         exit when Done;
         if Info (E).Tired and then Info (E).Loc >= 0 then
            for F in Entity_Id loop
               exit when Done;
               if F /= E and then Info (F).Worked and then Info (F).Loc = Info (E).Loc
                 and then Free (Sim_Games.As_Comp (E), Tick) and then Free (Sim_Games.As_Comp (F), Tick)
                 and then Integer (Roll (Seed_V, Positive (E) * 10 + Positive (F), Tick, 9964, 100)) <= Restwork_Pct
               then
                  Series (Tick, "restwork", "", Sim_Games.As_Comp (E), Sim_Games.As_Comp (F), Moods, Lines, Chess_Lines);
                  Done := True;
               end if;
            end loop;
         end if;
      end loop;
      for E in Entity_Id loop Seen_Refusal (E) := Int'Max (Seen_Refusal (E), Sim_Govern.Refusal_Tick (E)); end loop;
   end Step;

   function Count return Natural is (Total);
   function Last_Tick return Int is (Last_T);

   function Box_Line (Players : Positive) return String is
   begin
      if Session_N = 0 then return ""; end if;
      return Msg ("trial.box." & To_String (Last_How),
                  Sim_Dharma.Player_Name (Sim_Dharma.Player_Id (Roll (Seed_V, 4, Int (Total), 9966, Players))), Img (Total),
                  To_String (Last_Win), To_String (Last_Lose), To_String (Last_Score), Msg ("trial.src." & To_String (Last_Src)));
   end Box_Line;

   function View return Str_Vectors.Vector is
      V : Str_Vectors.Vector;
   begin
      if Total = 0 then V.Append (Msg ("trial.none")); return V; end if;
      V.Append (Msg ("trial.head", Img (Total), Img (Refused_N), Img (Coin_N)));
      for T of All_Lines loop V.Append (T); end loop;
      return V;
   end View;

   function Digest_Line return String is
     (Img (Total) & " trials (" & Img (Refused_N) & " refused, " & Img (Coin_N) & " coin)");

   --  0.058: the checkpoint.
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Integer);
      procedure IO is new Sim_Ckpt.IO (Int);
      procedure IO is new Sim_Ckpt.IO (Step_Array);
      procedure IO is new Sim_Ckpt.IO (Last_Array);
      procedure IO is new Sim_Ckpt.IO (Unbounded_String);
      procedure IO is new Sim_Ckpt.IO (Str_Vectors.Vector);
   begin
      IO (S, Save, Seed_V);
      IO (S, Save, Info);
      IO (S, Save, Busy_Until);
      IO (S, Save, Last_T);
      IO (S, Save, Total); IO (S, Save, Session_N); IO (S, Save, Refused_N); IO (S, Save, Coin_N);
      for E in Entity_Id loop IO (S, Save, Seen_Refusal (E)); end loop;
      IO (S, Save, Claim_Window); IO (S, Save, Window); IO (S, Save, Pause); IO (S, Save, Rest); IO (S, Save, Cap); IO (S, Save, First);
      IO (S, Save, Ext_First); IO (S, Save, Ext_Step); IO (S, Save, Max_Games); IO (S, Save, Petition_Pct); IO (S, Save, Escalate_Pct);
      IO (S, Save, Appeal_Pct); IO (S, Save, Claim_Pct); IO (S, Save, Restwork_Pct); IO (S, Save, Adhere_Pct); IO (S, Save, Adhere_Min);
      IO (S, Save, Adhere_Max); IO (S, Save, Unrest_W); IO (S, Save, Stand_W); IO (S, Save, Win_Stand); IO (S, Save, Win_Trust);
      IO (S, Save, Win_Mood); IO (S, Save, Loss_Mood); IO (S, Save, Refuse_Stand);
      IO (S, Save, Last_Src); IO (S, Save, Last_Win); IO (S, Save, Last_Lose); IO (S, Save, Last_Score); IO (S, Save, Last_How);
      IO (S, Save, All_Lines);
   end State_IO;

end Sim_Trial;
