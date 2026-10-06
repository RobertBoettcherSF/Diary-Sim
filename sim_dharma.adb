--  Version: 0.007
pragma Ada_2022;

with Sim_Ckpt;

with Ada.Characters.Handling, Ada.Containers.Vectors, Ada.Strings.Fixed, Ada.Strings.Unbounded, Interfaces;
use Ada.Strings.Unbounded;

package body Sim_Dharma is

   package Fx renames Ada.Strings.Fixed;
   use type Interfaces.Unsigned_32;

   type Category is (No_Cat, Cat_Company, Cat_Rest, Cat_Words);
   subtype Real_Cat is Category range Cat_Company .. Cat_Words;
   type Outcome is (Relayed, Softened, Withheld);
   type Fact_Kind is (F_Karma, F_Liberated, F_Unrest, F_Conflict, F_Aware, F_Anchor, F_Petition,
                      F_Relayed, F_Softened, F_Withheld);
   Kind_Name : constant array (Fact_Kind) of String (1 .. 9) :=
     ["karma    ", "liberated", "unrest   ", "conflict ", "aware    ", "anchor   ", "petition ", "relayed  ", "softened ",
      "withheld "];
   function KN (K : Fact_Kind) return String is (Fx.Trim (Kind_Name (K), Ada.Strings.Right));

   --  ---- parameters (data/karma.txt, read by Init) ----------------------------------------------
   function L (Key : String; D : Integer) return Integer is (Integer (Limit (Key, Int (D))));

   Sd : Int := 0;
   Deed_W : array (Action) of Integer := [others => 0];
   Deed_Teach, Deed_Coin, Deed_Tired, Tired_Below : Integer := 0;
   Realm_Limit : array (1 .. 5) of Integer := [others => 0];
   Ladder_Limit : array (1 .. 4) of Integer := [others => 0];
   Lib_Karma, Bias_Div, Bias_Cap : Integer := 1;
   Bias_Sign : array (1 .. 4) of Integer := [others => 0];
   Pull : array (1 .. 4) of Integer := [others => 0];
   Attach_Window, Attach_Dom, Attach_Rise, Attach_Fall : Integer := 1;
   Commit_Start, Commit_Rise, Commit_Fall, Commit_Mid, Value_High : Integer := 0;
   Aw_Say, Aw_All, Aw_Relay, Sudden_Gap, Sudden_Bonus, Aw_Decay, Aw_Base_Max, Sens_Min, Sens_Max, Watch_Pct,
     Aw_Note, Aw_Alert : Integer := 0;
   Unrest_Note, Unrest_Alert, Conflict_Alert : Integer := 0;
   Trust_Start, Trust_Rise, Trust_Fall, Relay_Pct, Soft_Pct : Integer := 0;
   Attn_Start, Attn_Base_Max, Attn_Alert, Attn_Note, Attn_Msg, Attn_Decay, Tone_Step, Omit_Info, Inbox_Max : Integer := 0;
   P_Steps : Integer := 8;
   Show_Per : Integer := 2;

   type Player_Ints is array (Player_Id) of Integer;
   type Wesen_Ints is array (Entity_Id) of Integer;
   --  ---- state --------------------------------------------------------------------------------
   Good, Bad, Life_No : array (Entity_Id) of Integer := [others => 0];
   Vals : array (Entity_Id, 1 .. 4) of Integer := [others => [others => 0]];
   Unrest_V : array (Entity_Id) of Integer := [others => 0];
   Win_Count : array (Entity_Id, Real_Cat) of Integer := [others => [others => 0]];
   Dom_Cat : array (Entity_Id) of Category := [others => No_Cat];
   Dom_Pct : array (Entity_Id) of Integer := [others => 0];
   Rank_V, Rung_V, Conflict_V, Realm_V : array (Entity_Id) of Integer := [others => 0];
   Commit_V : Wesen_Ints := [others => 0];
   Aware_M : array (Entity_Id) of Int := [others => 0];   --  thousandths of a point
   Last_Addr : array (Entity_Id) of Int := [others => -1];
   Lib, New_Lib : array (Entity_Id) of Boolean := [others => False];
   Reb : array (Entity_Id) of Integer := [others => -1];
   Prev_Net : array (Entity_Id) of Integer := [others => 0];
   Life_Start : Int := 0;
   Anchor_E, First_E : Natural := 0;
   Ended : Boolean := False;

   Base_Aware, Sens : array (Entity_Id) of Integer := [others => 0];   --  from the Rule 30 core bits
   type Watch_Array is array (Entity_Id) of Player_Id;
   Watch, Watch0 : Watch_Array := [others => 1];   --  Watch0: players.txt 'watches'; Watch: this session's
   Takes : array (Entity_Id) of Natural := [others => 0];            --  players.txt 'takes': the player that takes E over in a players4=1 session
   Last_P : Player_Id := 3;

   --  The players: persistent state.
   type Trusts is array (Entity_Id) of Integer;
   P_Name, P_Goal_Tag : array (Player_Id) of Unbounded_String;
   P_Values : array (Player_Id) of Str_Vectors.Vector;
   Attn, Tone, Tone0, Brev, Warm, Attn_Base, Msgs : Player_Ints := [others => 0];
   Trust : array (Player_Id) of Trusts := [others => [others => 0]];

   type Addr_Rec is record
      Tick : Int;
      Kind : Address_Kind;
      To   : Natural;
      Text : Unbounded_String;
   end record;
   package Addr_Vectors is new Ada.Containers.Vectors (Positive, Addr_Rec);
   Addrs : Addr_Vectors.Vector;

   type Decision is record
      Tick : Int;
      P    : Player_Id;
      E    : Entity_Id;
      Out_C : Outcome;
      Text : Unbounded_String;
   end record;
   package Dec_Vectors is new Ada.Containers.Vectors (Positive, Decision);
   Decisions : Dec_Vectors.Vector;

   type Four is array (1 .. 4) of Unbounded_String;
   type Fact is record
      Kind : Fact_Kind;
      E    : Natural;      --  0: all
      Sev  : Positive;
      Tick : Int;
      P    : Four;
   end record;
   package Fact_Vectors is new Ada.Containers.Vectors (Positive, Fact);

   Inbox : Str_Vectors.Vector;
   type Gov_Reports is array (Player_Id) of Str_Vectors.Vector;
   Gov_Lines : Gov_Reports;
   Last_Table, Last_Block, Last_Report : Str_Vectors.Vector;
   Last_C : Unbounded_String;
   Last_Win_N : Natural := 0;

   Start_Net, Start_Unrest, Start_Aware, Start_Commit : array (Entity_Id) of Integer := [others => 0];

   --  ---- helpers --------------------------------------------------------------------------------
   function Low (A : Action) return String is (Ada.Characters.Handling.To_Lower (A'Image));
   function Txt (Key, Default : String) return String is
      R : constant String := Msg (Key);
   begin
      return (if R = "[" & Key & "]" then Default else R);
   end Txt;

   function Split (S : String; Sep : Character) return Str_Vectors.Vector is
      Res : Str_Vectors.Vector;
      From : Positive := S'First;
   begin
      for I in S'Range loop
         if S (I) = Sep then
            if I > From then Res.Append (Fx.Trim (S (From .. I - 1), Ada.Strings.Both)); end if;
            From := I + 1;
         end if;
      end loop;
      if S'Last >= From then Res.Append (Fx.Trim (S (From .. S'Last), Ada.Strings.Both)); end if;
      return Res;
   end Split;

   function Cat_Name (C : Category) return String is
     (case C is when No_Cat => "-", when Cat_Company => Msg ("cat.company"), when Cat_Rest => Msg ("cat.rest"),
                when Cat_Words => Msg ("cat.words"));

   function Net (E : Entity_Id) return Integer is (Good (E) - Bad (E));
   function Aware_Pts (E : Entity_Id) return Integer is (Integer (Aware_M (E) / 1000));
   function Player_Name (P : Player_Id) return String is (To_String (P_Name (P)));
   function Watcher (E : Entity_Id) return Player_Id is (Watch (E));
   function Chess_Watcher (E : Entity_Id) return Player_Id is (Watch0 (E));
   function Last_Player return Player_Id is (Last_P);
   --  name (role): goal, straight from data/players.txt (needs no Init)
   function Player_Info (P : Player_Id) return String is
      K : constant String := "player." & Img (Integer (P)) & ".";
      G : constant String := Txt (K & "goal", "");
      Bar : constant Natural := Fx.Index (G, "|");
   begin
      return Txt (K & "name", "?") & " (" & Txt (K & "role", "") & "): "
        & (if Bar > 0 then Fx.Trim (G (Bar + 1 .. G'Last), Ada.Strings.Both) else G);
   end Player_Info;

   --  A player by id (iris), display name ('Player 1', any case, with or without the space) or number ('1').
   function Find_Player (Text : String) return Natural is
      function Squeeze (S : String) return String is
         R : String (1 .. S'Length);
         N : Natural := 0;
      begin
         for C of S loop
            if C /= ' ' then N := N + 1; R (N) := Ada.Characters.Handling.To_Lower (C); end if;
         end loop;
         return R (1 .. N);
      end Squeeze;
      T : constant String := Squeeze (Text);
   begin
      for P in Player_Id loop
         if Squeeze (Player_Name (P)) = T or else Squeeze (Sim_World.Show (Player_Name (P))) = T
           or else T = Img (Integer (P)) or else T = "player" & Img (Integer (P))
           or else Squeeze (Sim_World.Internal_Id (Text)) = Squeeze (Player_Name (P))
         then
            return Natural (P);
         end if;
      end loop;
      return 0;
   end Find_Player;

   function Find_Wesen (Text : String) return Natural is
      T : constant String := Ada.Characters.Handling.To_Lower (Fx.Trim (Text, Ada.Strings.Both));
   begin
      for E in Entity_Id loop
         if Name (E) = T then return Natural (E); end if;
      end loop;
      return 0;
   end Find_Wesen;

   --  Rule 30 on a 32-cell ring (new = left xor (centre or right)), bit counts of segments.
   function Pop (R : Interfaces.Unsigned_32; Lo, Hi : Natural) return Natural is
      N : Natural := 0;
   begin
      for I in Lo .. Hi loop
         if (Interfaces.Shift_Right (R, I) and 1) = 1 then N := N + 1; end if;
      end loop;
      return N;
   end Pop;

   --  ---- Init --------------------------------------------------------------------------------
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (parsing of the data/ keys, bit counts)
   procedure Init (Seed : Int) is
      Defaults : constant array (Player_Id) of String (1 .. 5) := ["iris ", "sol  ", "noor ", "vega "];
   begin
      Sd := Seed;
      for A in Action loop Deed_W (A) := L ("deed." & Low (A), 0); end loop;
      Deed_Teach := L ("deed.teach", 3);
      Deed_Coin := L ("deed.coin", 2);
      Deed_Tired := L ("deed.tired_work", -2);
      Tired_Below := L ("deed.tired_below", 20);
      for I in Realm_Limit'Range loop Realm_Limit (I) := L ("realm.limit." & Img (I), I * 100); end loop;
      for I in Ladder_Limit'Range loop Ladder_Limit (I) := L ("ladder.limit." & Img (I), I * 20); end loop;
      Lib_Karma := L ("liberation.karma", 800);
      Bias_Div := Integer'Max (1, L ("rebirth.bias_div", 10));
      Bias_Cap := L ("rebirth.bias_cap", 20);
      Attach_Window := Integer'Max (1, L ("attach.window", 50));
      Attach_Dom := L ("attach.dominant", 40);
      Attach_Rise := L ("attach.rise", 2);
      Attach_Fall := L ("attach.fall", 1);
      Commit_Start := L ("commit.start", 50);
      Commit_Rise := L ("commit.anchor_rise", 6);
      Commit_Fall := L ("commit.first_fall", 6);
      Commit_Mid := L ("commit.mid", 50);
      Value_High := L ("value.high", 60);
      Aw_Say := L ("aware.say", 20);
      Aw_All := L ("aware.all", 8);
      Aw_Relay := L ("aware.relay", 35);
      Sudden_Gap := L ("aware.sudden_gap", 300);
      Sudden_Bonus := L ("aware.sudden_bonus", 10);
      Aw_Decay := L ("aware.decay_milli", 50);
      Aw_Base_Max := L ("aware.base_max", 20);
      Sens_Min := L ("aware.sens_min", 70);
      Sens_Max := L ("aware.sens_max", 130);
      Watch_Pct := L ("aware.watch_pct", 20);
      Aw_Note := L ("aware.note", 40);
      Aw_Alert := L ("aware.alert", 70);
      Unrest_Note := L ("unrest.note", 30);
      Unrest_Alert := L ("unrest.alert", 60);
      Conflict_Alert := L ("conflict.alert", 2);
      Trust_Start := L ("trust.start", 50);
      Trust_Rise := L ("trust.rise", 4);
      Trust_Fall := L ("trust.fall", 6);
      Relay_Pct := L ("relay.pct", 80);
      Soft_Pct := L ("soft.pct", 30);
      Attn_Start := L ("attn.start", 30);
      Attn_Base_Max := L ("attn.base_max", 20);
      Attn_Alert := L ("attn.alert", 15);
      Attn_Note := L ("attn.note", 5);
      Attn_Msg := L ("attn.msg", 20);
      Attn_Decay := L ("attn.decay", 10);
      Tone_Step := L ("tone.step", 8);
      Omit_Info := L ("omit.info", 70);
      Inbox_Max := Integer'Max (1, L ("inbox.max_lines", 4));
      Show_Per := Integer'Max (1, L ("inbox.show", 2));
      P_Steps := Clamp (L ("player.rule30_steps", 8), 0, 64);
      for I in 1 .. 4 loop
         Bias_Sign (I) := L ("bias." & (case I is when 1 => "curiosity", when 2 => "rest", when 3 => "company", when others => "craft"), 0);
         Pull (I) := L ("pull." & (case I is when 1 => "curiosity", when 2 => "rest", when 3 => "company", when others => "craft"), 0);
      end loop;
      Good := [others => 0]; Bad := [others => 0]; Life_No := [others => 0];
      Vals := [others => [others => 0]];
      Unrest_V := [others => 0];
      Win_Count := [others => [others => 0]];
      Dom_Cat := [others => No_Cat]; Dom_Pct := [others => 0];
      Rank_V := [others => 0]; Rung_V := [others => 1]; Conflict_V := [others => 0]; Realm_V := [others => 5];
      Commit_V := [others => Commit_Start];
      Last_Addr := [others => -1];
      Lib := [others => False]; New_Lib := [others => False]; Reb := [others => -1]; Prev_Net := [others => 0];
      Life_Start := 0; Anchor_E := 0; First_E := 0; Ended := False;
      Addrs.Clear; Decisions.Clear; Inbox.Clear; Last_Table.Clear; Last_Block.Clear; Last_Report.Clear;
      Last_C := Null_Unbounded_String; Last_Win_N := 0;
      Msgs := [others => 0];
      Watch := [others => 1];
      Takes := [others => 0];
      Last_P := 3;
      for P in Player_Id loop
         declare
            K : constant String := "player." & Img (Integer (P)) & ".";
            G : constant String := Txt (K & "goal", "unrest | keep the wesen steady");
            Bar : constant Natural := Fx.Index (G, "|");
            R : Interfaces.Unsigned_32 := 0;
         begin
            P_Name (P) := To_Unbounded_String (Ada.Characters.Handling.To_Lower (Txt (K & "name", Fx.Trim (Defaults (P), Ada.Strings.Both))));
            P_Values (P) := Split (Txt (K & "values", "calm"), ',');
            P_Goal_Tag (P) := To_Unbounded_String (Fx.Trim ((if Bar > 0 then G (G'First .. Bar - 1) else G), Ada.Strings.Both));
            for W of Split (Txt (K & "watches", ""), ',') loop
               if Find_Wesen (W) > 0 then Watch (Entity_Id (Find_Wesen (W))) := P; end if;
            end loop;
            for W of Split (Txt (K & "takes", ""), ',') loop
               if Find_Wesen (W) > 0 then Takes (Entity_Id (Find_Wesen (W))) := Natural (P); end if;
            end loop;
            --  personality: hashed start row, then Rule 30 steps (own salts 5040 .. 5071)
            for I in 0 .. 31 loop
               if Roll (Seed, 10 + Positive (P), 0, 5040 + I, 2) = 2 then R := R or Interfaces.Shift_Left (1, I); end if;
            end loop;
            if R = 0 then R := 1; end if;
            for S in 1 .. P_Steps loop
               R := Interfaces.Rotate_Left (R, 1) xor (R or Interfaces.Rotate_Right (R, 1));
            end loop;
            Tone0 (P) := (Pop (R, 0, 9) * 2 - 10) * 10;
            Tone (P) := Tone0 (P);
            Brev (P) := Pop (R, 10, 19) * 10;
            Warm (P) := (Pop (R, 20, 29) * 2 - 10) * 5;
            Attn_Base (P) := Attn_Base_Max * Pop (R, 0, 31) / 32;
            Attn (P) := Integer'Max (Attn_Start, Attn_Base (P));
            Trust (P) := [others => Trust_Start];
         end;
      end loop;
      Watch0 := Watch;
      for E in Entity_Id loop
         Base_Aware (E) := Aw_Base_Max * Core_Percent (Seed, E) / 100;
         Sens (E) := Sens_Min + (Sens_Max - Sens_Min) * Core_Percent (Seed, E) / 100;
         Aware_M (E) := Int (Base_Aware (E)) * 1000 + Int (Attn (Watch (E))) * Int (Watch_Pct) * 10;
      end loop;
   end Init;

   --  ---- per tick ----------------------------------------------------------------------------
   procedure Deed (E : Entity_Id; A : Action; Pre_Energy : Integer; Taught, Coined : Boolean) is
      W : Integer := Deed_W (A) + (if Taught then Deed_Teach else 0) + (if Coined then Deed_Coin else 0);
      C : constant Category :=
        (if Taught or else Coined or else A = Learn then Cat_Words elsif A = Talk then Cat_Company
         elsif A = Rest then Cat_Rest else No_Cat);
   begin
      if A in Work | Bench and then Pre_Energy < Tired_Below then W := W + Deed_Tired; end if;
      if W > 0 then Good (E) := Good (E) + W; elsif W < 0 then Bad (E) := Bad (E) - W; end if;
      if C /= No_Cat then Win_Count (E, C) := Win_Count (E, C) + 1; end if;
   end Deed;

   procedure Add_Address (Tick : Int; Kind : Address_Kind; To : Natural; Text : String) is
   begin
      Addrs.Append (Addr_Rec'(Tick, Kind, To, To_Unbounded_String (Text)));
   end Add_Address;

   function Addresses_Before (Tick : Int) return Natural is
      N : Natural := 0;
   begin
      for A of Addrs loop
         if A.Tick < Tick then N := N + 1; end if;
      end loop;
      return N;
   end Addresses_Before;

   procedure Raise_Aware (E : Entity_Id; Base : Integer; At_Tick : Int) is
      Sudden : constant Boolean := Last_Addr (E) < 0 or else At_Tick - Last_Addr (E) >= Int (Sudden_Gap);
      Pts : constant Integer := Base + (if Sudden then Sudden_Bonus else 0);
   begin
      Aware_M (E) := Int'Min (100_000, Aware_M (E) + Int (Pts) * Int (Sens (E)) * 10);
      Last_Addr (E) := At_Tick;
   end Raise_Aware;

   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (percent thresholds of one hashed roll)
   procedure Relay_To (P : Player_Id; E : Entity_Id; A : Addr_Rec) is
      Pct : constant Integer := Clamp (Trust (P) (E) * Relay_Pct / 100 + Warm (P) / 5, 0, 100);
      R : constant Positive := Roll (Sd, Positive (E), A.Tick, 5030 + Integer (P), 100);
      Out_C : constant Outcome := (if R <= Pct then Relayed elsif R <= Pct + Soft_Pct then Softened else Withheld);
   begin
      Msgs (P) := Msgs (P) + 1;
      Decisions.Append (Decision'(A.Tick, P, E, Out_C, A.Text));
      case Out_C is
         when Relayed => Raise_Aware (E, Aw_Relay, A.Tick);
         when Softened => Raise_Aware (E, Aw_Relay / 2, A.Tick);
         when Withheld => null;
      end case;
   end Relay_To;

   procedure Tick_Begin (Tick : Int) is
   begin
      for A of Addrs loop
         if A.Tick = Tick - 1 then
            case A.Kind is
               when Say =>
                  if A.To in 1 .. 4 then Raise_Aware (Entity_Id (A.To), Aw_Say, A.Tick); end if;
               when Say_All =>
                  for E in Entity_Id loop Raise_Aware (E, Aw_All, A.Tick); end loop;
               when Relay =>
                  for E in Entity_Id loop
                     if A.To in 1 .. 4 and then Natural (Watch (E)) = A.To then Relay_To (Watch (E), E, A); end if;
                  end loop;
               when Answer =>
                  for E in Entity_Id loop Relay_To (Watch (E), E, A); end loop;
            end case;
         end if;
      end loop;
   end Tick_Begin;

   procedure Tick_End (Tick : Int) is
   begin
      for E in Entity_Id loop
         declare
            Floor : constant Int := Int (Base_Aware (E)) * 1000 + Int (Attn (Watch (E))) * Int (Watch_Pct) * 10;
         begin
            Aware_M (E) := Int'Max (Floor, Aware_M (E) - Int (Aw_Decay));
         end;
         if Tick mod Int (Attach_Window) = 0 then
            declare
               Best : Category := No_Cat;
               Best_N : Integer := 0;
               Pct : Integer;
            begin
               for C in Real_Cat loop
                  if Win_Count (E, C) > Best_N then Best := C; Best_N := Win_Count (E, C); end if;
               end loop;
               Pct := Best_N * 100 / Attach_Window;
               Dom_Cat (E) := Best;
               Dom_Pct (E) := Pct;
               if Pct >= Attach_Dom and then Best /= No_Cat then
                  Unrest_V (E) := Unrest_V (E) + Integer'Max (1, (Pct - Attach_Dom) * Attach_Rise / 10);
               else
                  Unrest_V (E) := Unrest_V (E) - Attach_Fall;
               end if;
               Unrest_V (E) := Clamp (Unrest_V (E), 0, 100);
               for C in Real_Cat loop Win_Count (E, C) := 0; end loop;
            end;
         end if;
      end loop;
   end Tick_End;

   --  ---- sessions ----------------------------------------------------------------------------
   procedure Begin_Life (Seed, Tick : Int; Session : Positive; Locations : Positive; Dharma : Boolean; Players4 : Boolean := False) is
   begin
      Life_Start := Tick;
      Last_P := (if Players4 then 4 else 3);   --  player 4 is there from the first players4=1 session on and takes its wesen over
      Watch := Watch0;
      if Players4 then
         for E in Entity_Id loop
            if Takes (E) in 1 .. 4 then Watch (E) := Player_Id (Takes (E)); end if;
         end loop;
      end if;
      for E in Entity_Id loop
         declare
            Shift : constant Integer := Clamp (Net (E) / Bias_Div, -Bias_Cap, Bias_Cap);
         begin
            Life_No (E) := Session;
            for I in 1 .. 4 loop
               Vals (E, I) := Clamp (Roll (Seed, Positive (E), Tick, 5000 + I, 100) + Shift * Bias_Sign (I), 0, 100);
            end loop;
            Reb (E) := (if Dharma and then Lib (E) then Roll (Seed, Positive (E), Tick, 5020, Locations) - 1 else -1);
         end;
      end loop;
   end Begin_Life;

   function Rebirth_Location (E : Entity_Id) return Integer is (Reb (E));

   procedure Mark_Start is
   begin
      for E in Entity_Id loop
         Start_Net (E) := Net (E);
         Start_Unrest (E) := Unrest_V (E);
         Start_Aware (E) := Aware_Pts (E);
         Start_Commit (E) := Commit_V (E);
      end loop;
   end Mark_Start;

   function Realm_Of (K : Integer) return Integer is
      R : Integer := 1;
   begin
      for I in Realm_Limit'Range loop if K >= Realm_Limit (I) then R := R + 1; end if; end loop;
      return R;
   end Realm_Of;

   function Tag_Hit (K : Fact_Kind; P : Player_Id) return Boolean is
      Tags : constant Str_Vectors.Vector := Split (Txt ("tags." & KN (K), ""), ',');
   begin
      for T of Tags loop
         for V of P_Values (P) loop
            if T = V then return True; end if;
         end loop;
      end loop;
      return False;
   end Tag_Hit;

   function Cut (S : String; N : Positive) return String is (if S'Length > N then S (S'First .. S'First + N - 4) & "..." else S);
   function Src_Name (E : Natural) return String is (if E = 0 then "all" else Name (Entity_Id (E)));

   function End_Life (Seed, Tick : Int; Session : Positive; Votes : Kalpa_Votes; Energy : Energies)
     return Str_Vectors.Vector
   is
      Res : Str_Vectors.Vector;
      Facts : Fact_Vectors.Vector;
      Ballot : array (Entity_Id) of Natural;
      Tally : array (1 .. 40) of Natural := [others => 0];
      Win : Natural := 0;
      Best : Natural := 0;
      Ties : Natural := 0;
      Sum_Delta : Integer := 0;
      Voters, Tally_Text : Unbounded_String;

      function Before (F, E : Entity_Id) return Boolean is
        (Votes (Integer (F)) < Votes (Integer (E))
         or else (Votes (Integer (F)) = Votes (Integer (E))
                  and then (Energy (F) < Energy (E) or else (Energy (F) = Energy (E) and then F < E))));

      procedure Add (K : Fact_Kind; E : Natural; Sev : Positive; Tk : Int; P1, P2, P3, P4 : String := "") is
      begin
         Facts.Append (Fact'(K, E, Sev, Tk, [To_Unbounded_String (P1), To_Unbounded_String (P2), To_Unbounded_String (P3),
                                         To_Unbounded_String (P4)]));
      end Add;
   begin
      Ended := True;
      Last_Report.Clear;
      --  karma, liberation, ladder, conflict
      for E in Entity_Id loop Sum_Delta := Sum_Delta + Net (E) - Prev_Net (E); end loop;
      for E in Entity_Id loop
         New_Lib (E) := not Lib (E) and then Net (E) >= Lib_Karma;
         Lib (E) := Lib (E) or else New_Lib (E);
         Realm_V (E) := Realm_Of (Net (E));
         Rank_V (E) := 1;
         for F in Entity_Id loop
            if F /= E and then Before (F, E) then Rank_V (E) := Rank_V (E) + 1; end if;
         end loop;
         if Rank_V (E) = 4 then Anchor_E := Natural (E); end if;
         if Rank_V (E) = 1 then First_E := Natural (E); end if;
         if Rank_V (E) = 4 then
            Commit_V (E) := Clamp (Commit_V (E) + Commit_Rise, 0, 100);
         elsif Rank_V (E) = 1 then
            Commit_V (E) := Clamp (Commit_V (E) - Commit_Fall, 0, 100);
         end if;
         Rung_V (E) := 1;
         for I in Ladder_Limit'Range loop if Commit_V (E) >= Ladder_Limit (I) then Rung_V (E) := Rung_V (E) + 1; end if; end loop;
         Conflict_V (E) := 0;
         for I in 1 .. 4 loop
            if Vals (E, I) >= Value_High
              and then ((Commit_V (E) >= Commit_Mid and then Pull (I) < 0) or else (Commit_V (E) < Commit_Mid and then Pull (I) > 0))
            then
               Conflict_V (E) := Conflict_V (E) + 1;
            end if;
         end loop;
      end loop;
      --  D lines
      for E in Entity_Id loop
         Res.Append ("D" & Img (Session) & " tick=" & Img (Tick) & " wesen=" & Name (E) & " karma=" & Sgn (Int (Net (E)))
                     & " good=" & Img (Good (E)) & " bad=" & Img (Bad (E)) & " life=" & Img (Life_No (E))
                     & " realm=" & Img (Realm_V (E))
                     & " vals=" & Img (Vals (E, 1)) & "/" & Img (Vals (E, 2)) & "/" & Img (Vals (E, 3)) & "/" & Img (Vals (E, 4))
                     & " unrest=" & Img (Unrest_V (E)) & " dom=" & Cat_Name (Dom_Cat (E)) & ":" & Img (Dom_Pct (E))
                     & " rank=" & Img (Rank_V (E)) & " commit=" & Img (Commit_V (E)) & " rung=" & Img (Rung_V (E))
                     & " conflict=" & Img (Conflict_V (E)) & " aware=" & Img (Aware_Pts (E))
                     & " lib=" & (if Lib (E) then "1" else "0")
                     & " rebirth=" & (if Reb (E) >= 0 then Img (Reb (E)) else "-"));
      end loop;
      --  C line: the wesen vote on the collective petition
      for E in Entity_Id loop
         Ballot (E) := Ballot_For (Seed, E, Tick, Life_Start);
         if Ballot (E) > 0 then Tally (Ballot (E)) := Tally (Ballot (E)) + 1; end if;
         Append (Voters, (if E = 1 then "" else ",") & Name (E) & ":" & (if Ballot (E) = 0 then "-" else Topic_Name (Ballot (E))));
      end loop;
      for T in 1 .. Topic_Count loop
         if Tally (T) > Best then Best := Tally (T); end if;
      end loop;
      if Best > 0 then
         for T in 1 .. Topic_Count loop if Tally (T) = Best then Ties := Ties + 1; end if; end loop;
         declare
            Pick : Positive := Roll (Seed, 1, Tick, 5011, Ties);
         begin
            for T in 1 .. Topic_Count loop
               if Tally (T) = Best then
                  if Pick = 1 then Win := T; exit; end if;
                  Pick := Pick - 1;
               end if;
            end loop;
         end;
      end if;
      declare
         Used : array (1 .. 40) of Boolean := [others => False];
      begin
         for K in 1 .. Topic_Count loop
            declare
               B : Natural := 0;
            begin
               for T in 1 .. Topic_Count loop
                  if not Used (T) and then Tally (T) > 0 and then (B = 0 or else Tally (T) > Tally (B)) then B := T; end if;
               end loop;
               exit when B = 0;
               Used (B) := True;
               Append (Tally_Text, (if Length (Tally_Text) = 0 then "" else ",") & Topic_Name (B) & ":" & Img (Tally (B)));
            end;
         end loop;
      end;
      Last_Win_N := (if Win > 0 then Tally (Win) else 0);
      Res.Append ("C" & Img (Session) & " tick=" & Img (Tick) & " win=" & (if Win = 0 then "-" else Topic_Name (Win))
                  & " tally=" & (if Length (Tally_Text) = 0 then "-" else To_String (Tally_Text)) & " votes=" & To_String (Voters));
      Last_C := To_Unbounded_String ("C" & Img (Session) & " " & (if Win = 0 then "-" else Topic_Name (Win)) & " " & Img (Last_Win_N) & "/4");
      --  facts: the one recorded base every player reads
      for E in Entity_Id loop
         Add (F_Karma, Natural (E), 1, Tick, Name (E), Sgn (Int (Net (E) - Prev_Net (E))), Sgn (Int (Net (E))), Msg ("realm.name." & Img (Realm_V (E))));
         if New_Lib (E) then Add (F_Liberated, Natural (E), 3, Tick, Name (E), Sgn (Int (Net (E))), Img (Lib_Karma)); end if;
         if Unrest_V (E) >= Unrest_Note then
            Add (F_Unrest, Natural (E), (if Unrest_V (E) >= Unrest_Alert then 3 else 2), Tick, Name (E), Img (Unrest_V (E)),
                 Cat_Name (Dom_Cat (E)), Img (Dom_Pct (E)));
         end if;
         if Conflict_V (E) >= 1 then
            Add (F_Conflict, Natural (E), (if Conflict_V (E) >= Conflict_Alert then 3 else 2), Tick, Name (E), Img (Conflict_V (E)),
                 Img (Commit_V (E)), Msg ("ladder.name." & Img (Rung_V (E))));
         end if;
         if Aware_Pts (E) >= Aw_Note then
            Add (F_Aware, Natural (E), (if Aware_Pts (E) >= Aw_Alert then 3 else 2), Tick, Name (E), Img (Aware_Pts (E)),
                 Player_Name (Watch (E)));
         end if;
      end loop;
      Add (F_Anchor, 0, 1, Tick, Name (Entity_Id (Anchor_E)), Name (Entity_Id (First_E)), Msg ("anchor.label"),
           Img (Commit_V (Entity_Id (Anchor_E))));
      if Win > 0 then Add (F_Petition, 0, 2, Tick, Topic_Name (Win), Topic_Phrase (Win), Img (Last_Win_N), "4"); end if;
      for D of Decisions loop
         Add ((case D.Out_C is when Relayed => F_Relayed, when Softened => F_Softened, when Withheld => F_Withheld),
              Natural (D.E), 2, D.Tick, Player_Name (D.P), Name (D.E),
              Cut (To_String (D.Text), 40));
      end loop;
      --  players: trust, attention, tone (the state is recorded in the Y lines)
      for P in Player_Id range 1 .. Last_P loop
         declare
            Alerts, Notes : Integer := 0;
         begin
            for F of Facts loop
               if F.Sev >= 2 and then (F.E = 0 or else Watch (Entity_Id (F.E)) = P) and then F.Kind in F_Unrest | F_Conflict | F_Aware | F_Liberated | F_Withheld then
                  if F.Sev = 3 then Alerts := Alerts + 1; else Notes := Notes + 1; end if;
               end if;
            end loop;
            for E in Entity_Id loop
               if (Net (E) - Prev_Net (E)) * 4 >= Sum_Delta then   --  at least the average gain: trust rises (twice for a watched wesen)
                  Trust (P) (E) := Clamp (Trust (P) (E) + Trust_Rise * (if Watch (E) = P then 2 else 1) * (100 + Warm (P)) / 100, 0, 100);
               else
                  Trust (P) (E) := Clamp (Trust (P) (E) - Trust_Fall / 2 * (100 - Warm (P)) / 100, 0, 100);
               end if;
               if Unrest_V (E) >= Unrest_Alert or else Conflict_V (E) >= Conflict_Alert then
                  Trust (P) (E) := Clamp (Trust (P) (E) - Trust_Fall * (100 - Warm (P)) / 100, 0, 100);
               end if;
            end loop;
            Attn (P) := Clamp (Attn (P) + Alerts * Attn_Alert + Notes * Attn_Note + Msgs (P) * Attn_Msg - Attn_Decay,
                               Attn_Base (P), 100);
            Msgs (P) := 0;
            if Alerts > 0 then
               Tone (P) := Clamp (Tone (P) + Tone_Step, -100, 100);
            elsif Tone (P) > Tone0 (P) then
               Tone (P) := Integer'Max (Tone0 (P), Tone (P) - Tone_Step / 2);
            elsif Tone (P) < Tone0 (P) then
               Tone (P) := Integer'Min (Tone0 (P), Tone (P) + Tone_Step / 2);
            end if;
         end;
      end loop;
      for P in Player_Id range 1 .. Last_P loop
         Res.Append ("Y" & Img (Session) & " tick=" & Img (Tick) & " player=" & Player_Name (P) & " attn=" & Img (Attn (P))
                     & " tone=" & Sgn (Int (Tone (P))) & " brev=" & Img (Brev (P)) & " warm=" & Sgn (Int (Warm (P)))
                     & " trust=" & Img (Trust (P) (1)) & "/" & Img (Trust (P) (2)) & "/" & Img (Trust (P) (3)) & "/" & Img (Trust (P) (4)));
      end loop;
      --  the reports of the players to Robert (the inbox): same facts, own emphasis, omission, wording
      for P in Player_Id range 1 .. Last_P loop
         declare
            type Cand is record
               Idx, Prio : Natural;
            end record;
            Cands : array (1 .. 64) of Cand;
            N : Natural := 0;
            Variant : constant String := (if Tone (P) <= -34 then "calm" elsif Tone (P) >= 34 then "alarm" else "plain");
         begin
            for I in 1 .. Natural (Facts.Length) loop
               declare
                  F : constant Fact := Facts (I);
                  Goal : constant Boolean := KN (F.Kind) = To_String (P_Goal_Tag (P));
                  Hit : constant Boolean := Tag_Hit (F.Kind, P);
                  Omit : constant Integer := (if F.Sev >= 3 or else Goal or else Hit then 0
                                              elsif F.Sev = 2 then Brev (P) * Omit_Info / 200 else Brev (P) * Omit_Info / 100);
                  R : constant Positive := Roll (Seed, Positive'Max (1, F.E), Tick, 5100 + 10 * Integer (P) + Fact_Kind'Pos (F.Kind), 100);
               begin
                  if R > Omit and then N < Cands'Last then
                     N := N + 1;
                     Cands (N) := (I, (if F.Kind in F_Relayed | F_Softened | F_Withheld then 4 elsif Goal then 3 elsif Hit then 2 else 1));
                  end if;
               end;
            end loop;
            --  order: priority, then severity, then fact order (insertion sort)
            for I in 2 .. N loop
               declare
                  X : constant Cand := Cands (I);
                  J : Integer := I - 1;
                  function Better (A, B : Cand) return Boolean is
                    (A.Prio > B.Prio or else (A.Prio = B.Prio and then Facts (A.Idx).Sev > Facts (B.Idx).Sev));
               begin
                  while J >= 1 and then Better (X, Cands (J)) loop
                     Cands (J + 1) := Cands (J);
                     J := J - 1;
                  end loop;
                  Cands (J + 1) := X;
               end;
            end loop;
            for K in 1 .. Integer'Min (N, Inbox_Max) loop
               declare
                  F : constant Fact := Facts (Cands (K).Idx);
                  Focus : constant String := (if Cands (K).Prio = 3 then Msg ("inbox.goal") & " " elsif Cands (K).Prio = 2 then Msg ("inbox.value") & " " else "");
               begin
                  Inbox.Append ("I" & Img (Integer (Inbox.Length) + 1) & " " & Msg ("sev." & Img (F.Sev)) & " from=" & Player_Name (P)
                                & " s" & Img (Session) & " t" & Img (Tick) & " | " & Focus
                                & Msg ("inbox." & KN (F.Kind) & "." & Variant, To_String (F.P (1)), To_String (F.P (2)),
                                       To_String (F.P (3)), To_String (F.P (4)))
                                & " | src=s" & Img (Session) & ":t" & Img (F.Tick) & ":" & Src_Name (F.E));
                  if K <= Show_Per then Last_Report.Append (Inbox.Last_Element); end if;
               end;
            end loop;
         end;
      end loop;
      for P in Player_Id range 1 .. Last_P loop   --  govern=1: the changes and decisions, from the D records, whatever the tone
         for K in 1 .. Natural (Gov_Lines (P).Length) loop
            Inbox.Append ("I" & Img (Integer (Inbox.Length) + 1) & " " & Msg ("sev.2") & " from=" & Player_Name (P)
                          & " s" & Img (Session) & " t" & Img (Tick) & " | " & Gov_Lines (P) (K) & " | src=s" & Img (Session) & ":govern");
            if K = 1 then Last_Report.Append (Inbox.Last_Element); end if;
         end loop;
         Gov_Lines (P).Clear;
      end loop;
      Decisions.Clear;
      Prev_Net := [for E in Entity_Id => Net (E)];
      Last_Block := Res;
      --  the table of the end-of-session report
      Last_Table.Clear;
      Last_Table.Append (Msg ("table.head", Img (Session), Img (Tick)));
      Last_Table.Append (Msg ("table.cols"));
      for E in Entity_Id loop
         Last_Table.Append
           (Fx.Head (Name (E), 8) & " " & Fx.Head (Msg ("realm.name." & Img (Realm_V (E))), 7)
            & Fx.Tail (Sgn (Int (Net (E))), 5) & Fx.Tail (Img (Good (E)) & "/" & Img (Bad (E)), 9) & " |"
            & Fx.Tail (Img (Vals (E, 1)), 4) & Fx.Tail (Img (Vals (E, 2)), 4) & Fx.Tail (Img (Vals (E, 3)), 4) & Fx.Tail (Img (Vals (E, 4)), 4) & " |"
            & Fx.Tail (Img (Unrest_V (E)), 4) & " " & Fx.Head (Cat_Name (Dom_Cat (E)) & ":" & Img (Dom_Pct (E)), 10) & "|"
            & Fx.Tail (Img (Rank_V (E)), 3) & Fx.Tail (Img (Commit_V (E)), 4) & Fx.Tail (Img (Rung_V (E)), 3) & Fx.Tail (Img (Conflict_V (E)), 3) & " |"
            & Fx.Tail (Img (Aware_Pts (E)), 4) & " " & Player_Name (Watch (E))
            & (if Natural (E) = Anchor_E then " " & Msg ("table.anchor") else "")
            & (if Lib (E) then " " & Msg ("table.lib") else ""));
      end loop;
      Last_Table.Append (Msg ("table.petition", To_String (Last_C), (if Win > 0 then Topic_Phrase (Win) else "-"), To_String (Tally_Text)));
      declare
         Pl : Unbounded_String;
      begin
         for P in Player_Id range 1 .. Last_P loop
            Append (Pl, (if P = 1 then "" else " | ") & Player_Name (P) & " attn " & Img (Attn (P)) & " tone " & Sgn (Int (Tone (P)))
                    & " trust " & Img (Trust (P) (1)) & "/" & Img (Trust (P) (2)) & "/" & Img (Trust (P) (3)) & "/" & Img (Trust (P) (4)));
         end loop;
         Last_Table.Append (Msg ("table.players", To_String (Pl)));
      end;
      Last_Table.Append (Msg ("table.anchorline", Src_Name (Anchor_E), Msg ("anchor.label"), Src_Name (First_E)));
      return Res;
   end End_Life;

   --  ---- views ---------------------------------------------------------------------------------
   function Table_Lines return Str_Vectors.Vector is (Last_Table);

   function Since_Lines return Str_Vectors.Vector is
      Res : Str_Vectors.Vector;
   begin
      if not Ended then return Res; end if;
      for E in Entity_Id loop
         Res.Append (Fx.Head (Name (E), 9)
                     & Msg ("since.dharma", Sgn (Int (Net (E) - Start_Net (E))), Sgn (Int (Net (E))), Img (Life_No (E)),
                            Sgn (Int (Unrest_V (E) - Start_Unrest (E))), Sgn (Int (Aware_Pts (E) - Start_Aware (E))),
                            Sgn (Int (Commit_V (E) - Start_Commit (E))), Img (Commit_V (E))));
      end loop;
      return Res;
   end Since_Lines;

   function Debug_Line return String is
      R : Unbounded_String;
   begin
      if not Ended then return ""; end if;
      for E in Entity_Id loop
         Append (R, (if E = 1 then "" else " ") & Fx.Head (Name (E), 3) & Sgn (Int (Net (E))));
      end loop;
      Append (R, " aw");
      for E in Entity_Id loop Append (R, " " & Img (Aware_Pts (E))); end loop;
      Append (R, " anchor " & Src_Name (Anchor_E) & " inbox " & Img (Integer (Inbox.Length)));
      return To_String (R);
   end Debug_Line;

   function Address_Counts (From_Tick : Int) return String is
      N : array (Address_Kind) of Natural := [others => 0];
   begin
      for A of Addrs loop
         if A.Tick >= From_Tick then N (A.Kind) := N (A.Kind) + 1; end if;
      end loop;
      return "say " & Img (N (Say)) & ", all " & Img (N (Say_All)) & ", to players " & Img (N (Relay)) & ", answers " & Img (N (Answer));
   end Address_Counts;

   function Latest_Report return Str_Vectors.Vector is (Last_Report);
   function Warm_Of (P : Player_Id) return Integer is (Warm (P));
   function Brev_Of (P : Player_Id) return Integer is (Brev (P));
   function Unrest_Of (E : Entity_Id) return Integer is (Unrest_V (E));
   function Attn_Of (P : Player_Id) return Integer is (Attn (P));
   function Variant_Of (P : Player_Id) return String is (if Tone (P) <= -34 then "calm" elsif Tone (P) >= 34 then "alarm" else "plain");
   procedure Set_Govern_Report (P : Player_Id; Lines : Str_Vectors.Vector) is
   begin
      Gov_Lines (P) := Lines;
   end Set_Govern_Report;
   function Inbox_Count return Natural is (Natural (Inbox.Length));
   function Inbox_Line (N : Positive) return String is (Inbox (N));
   function Inbox_Tail (Max : Positive) return Str_Vectors.Vector is
      Res : Str_Vectors.Vector;
   begin
      for I in Integer'Max (1, Natural (Inbox.Length) - Max + 1) .. Natural (Inbox.Length) loop Res.Append (Inbox (I)); end loop;
      return Res;
   end Inbox_Tail;

   function Last_Petition return String is (To_String (Last_C));

   --  0.058: the checkpoint.  Not in it: Addrs (Robert's words, read from diaries/says.txt at every start), the players' names, goals
   --  and values (data/players.txt), and Start_* (Mark_Start sets them after the replay of every run).
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Integer);
      procedure IO is new Sim_Ckpt.IO (Int);
      procedure IO is new Sim_Ckpt.IO (Boolean);
      procedure IO is new Sim_Ckpt.IO (Category);
      procedure IO is new Sim_Ckpt.IO (Player_Id);
      procedure IO is new Sim_Ckpt.IO (Player_Ints);
      procedure IO is new Sim_Ckpt.IO (Wesen_Ints);
      procedure IO is new Sim_Ckpt.IO (Watch_Array);
      procedure IO is new Sim_Ckpt.IO (Trusts);
      procedure IO is new Sim_Ckpt.IO (Dec_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Str_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Unbounded_String);
   begin
      IO (S, Save, Sd);
      for A in Action loop IO (S, Save, Deed_W (A)); end loop;
      IO (S, Save, Deed_Teach); IO (S, Save, Deed_Coin); IO (S, Save, Deed_Tired); IO (S, Save, Tired_Below);
      for I in 1 .. 5 loop IO (S, Save, Realm_Limit (I)); end loop;
      for I in 1 .. 4 loop
         IO (S, Save, Ladder_Limit (I));
         IO (S, Save, Bias_Sign (I));
         IO (S, Save, Pull (I));
      end loop;
      IO (S, Save, Lib_Karma); IO (S, Save, Bias_Div); IO (S, Save, Bias_Cap);
      IO (S, Save, Attach_Window); IO (S, Save, Attach_Dom); IO (S, Save, Attach_Rise); IO (S, Save, Attach_Fall);
      IO (S, Save, Commit_Start); IO (S, Save, Commit_Rise); IO (S, Save, Commit_Fall); IO (S, Save, Commit_Mid); IO (S, Save, Value_High);
      IO (S, Save, Aw_Say); IO (S, Save, Aw_All); IO (S, Save, Aw_Relay); IO (S, Save, Sudden_Gap); IO (S, Save, Sudden_Bonus);
      IO (S, Save, Aw_Decay); IO (S, Save, Aw_Base_Max); IO (S, Save, Sens_Min); IO (S, Save, Sens_Max); IO (S, Save, Watch_Pct);
      IO (S, Save, Aw_Note); IO (S, Save, Aw_Alert);
      IO (S, Save, Unrest_Note); IO (S, Save, Unrest_Alert); IO (S, Save, Conflict_Alert);
      IO (S, Save, Trust_Start); IO (S, Save, Trust_Rise); IO (S, Save, Trust_Fall); IO (S, Save, Relay_Pct); IO (S, Save, Soft_Pct);
      IO (S, Save, Attn_Start); IO (S, Save, Attn_Base_Max); IO (S, Save, Attn_Alert); IO (S, Save, Attn_Note); IO (S, Save, Attn_Msg);
      IO (S, Save, Attn_Decay); IO (S, Save, Tone_Step); IO (S, Save, Omit_Info); IO (S, Save, Inbox_Max);
      IO (S, Save, P_Steps); IO (S, Save, Show_Per);
      for E in Entity_Id loop
         IO (S, Save, Good (E)); IO (S, Save, Bad (E)); IO (S, Save, Life_No (E));
         for I in 1 .. 4 loop IO (S, Save, Vals (E, I)); end loop;
         IO (S, Save, Unrest_V (E));
         for C in Real_Cat loop IO (S, Save, Win_Count (E, C)); end loop;
         IO (S, Save, Dom_Cat (E)); IO (S, Save, Dom_Pct (E));
         IO (S, Save, Rank_V (E)); IO (S, Save, Rung_V (E)); IO (S, Save, Conflict_V (E)); IO (S, Save, Realm_V (E));
         IO (S, Save, Aware_M (E)); IO (S, Save, Last_Addr (E));
         IO (S, Save, Lib (E)); IO (S, Save, New_Lib (E)); IO (S, Save, Reb (E)); IO (S, Save, Prev_Net (E));
         IO (S, Save, Base_Aware (E)); IO (S, Save, Sens (E)); IO (S, Save, Takes (E));
      end loop;
      IO (S, Save, Commit_V);
      IO (S, Save, Life_Start);
      IO (S, Save, Anchor_E); IO (S, Save, First_E);
      IO (S, Save, Ended);
      IO (S, Save, Watch); IO (S, Save, Watch0);
      IO (S, Save, Last_P);
      IO (S, Save, Attn); IO (S, Save, Tone); IO (S, Save, Tone0); IO (S, Save, Brev); IO (S, Save, Warm); IO (S, Save, Attn_Base); IO (S, Save, Msgs);
      for P in Player_Id loop
         IO (S, Save, Trust (P));
         IO (S, Save, Gov_Lines (P));
      end loop;
      IO (S, Save, Decisions);
      IO (S, Save, Inbox);
      IO (S, Save, Last_Table); IO (S, Save, Last_Block); IO (S, Save, Last_Report);
      IO (S, Save, Last_C);
      IO (S, Save, Last_Win_N);
   end State_IO;

end Sim_Dharma;
