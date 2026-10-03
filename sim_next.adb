--  Version: 0.001
--  See sim_next.ads.
pragma Ada_2022;

with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Sim_Dharma;

package body Sim_Next is

   use Ada.Strings.Unbounded;
   use Sim_Dharma;
   package Fx renames Ada.Strings.Fixed;

   type Players is array (Player_Id) of Integer;
   type Flags is array (Player_Id) of Boolean;
   type Factor is (F_Open, F_Defer, F_Unrest, F_Tired, F_Curious, F_Calm);
   type Parts is array (Factor range F_Open .. F_Curious) of Integer;
   type Part_List is array (Entity_Id) of Parts;

   type Result is record
      Tick : Int := -1;
      Wesen : Ints := [others => 0];
      Part : Part_List := [others => [others => 0]];
      Mean : Players := [others => 0];     --  mean of the proposals of the wesen the player watches
      Pref : Players := [others => 0];     --  its own preference
      Choice : Players := [others => 0];   --  what it settled on
      Biased : Flags := [others => False];
      Next : Integer := 0;
      Why : Factor := F_Calm;
      Voice : Player_Id := 1;
   end record;

   Seed_V : Int := 0;
   Latest : Result;
   Count : Natural := 0;

   --  a number of data/ticks.txt
   function K (Key : String; D : Integer) return Integer is
      V : constant String := Fx.Trim (Msg (Key), Ada.Strings.Both);
   begin
      return (if V'Length = 0 or else V (V'First) = '[' then D else Integer'Value (V));
   exception
      when Constraint_Error => return D;
   end K;

   function Min_T return Integer is (Integer'Max (1, K ("ticks.min", 100)));
   function Max_T return Integer is (Integer'Max (Min_T, K ("ticks.max", 1000)));
   function Step_T return Integer is (Integer'Max (1, K ("ticks.step", 100)));

   --  the allowed set: Min, Min + Step, ..., never above Max.  Down / Up / nearest (ties go up).
   function Snap_Down (X : Integer) return Integer is
     (Min_T + (Clamp (X, Min_T, Max_T) - Min_T) / Step_T * Step_T);
   function Snap_Up (X : Integer) return Integer is
     (Integer'Min (Max_T, Min_T + (Clamp (X, Min_T, Max_T) - Min_T + Step_T - 1) / Step_T * Step_T));
   function Snap (X : Integer) return Integer is
      D : constant Integer := Snap_Down (X);
      U : constant Integer := Snap_Up (X);
   begin
      return (if Clamp (X, Min_T, Max_T) - D < U - Clamp (X, Min_T, Max_T) then D else U);
   end Snap;

   procedure Init (Seed : Int) is
   begin
      Seed_V := Seed;
      Latest := (others => <>);
      Count := 0;
   end Init;

   --  ---- the proposal of a wesen ------------------------------------------------------------------------------------------
   procedure Propose (E : Entity_Id; Tick : Int; D : Inputs; Into : out Parts; Total : out Integer) is
      Base : constant Integer := K ("ticks.base", 300);
      Raw : Integer := Base;
   begin
      Into := [others => 0];
      Into (F_Open) := Integer'Min (K ("ticks.open_cap", 200), K ("ticks.open_w", 40) * Integer'Max (0, D.Open (E) - D.Defer (E)));
      Into (F_Defer) := Integer'Min (K ("ticks.open_cap", 200), K ("ticks.defer_w", 60) * D.Defer (E));
      Into (F_Unrest) := (if D.Unrest (E) > K ("ticks.unrest_at", 30)
                          then Integer'Min (K ("ticks.unrest_cap", 200), (D.Unrest (E) - K ("ticks.unrest_at", 30)) * K ("ticks.unrest_w", 30) / 10) else 0);
      Into (F_Tired) := (if D.Energy (E) < K ("ticks.tired_at", 30)
                         then -Integer'Min (K ("ticks.tired_cap", 200), (K ("ticks.tired_at", 30) - D.Energy (E)) * K ("ticks.tired_w", 40) / 10) else 0);
      Into (F_Curious) := (Roll (Seed_V, Positive (E), Tick, 9820, K ("ticks.curious_n", 3)) - 1) * K ("ticks.curious_step", 50);
      for F in Parts'Range loop Raw := Raw + Into (F); end loop;
      Total := Snap (Raw);
   end Propose;

   --  ---- the decision of a player -----------------------------------------------------------------------------------------
   function Honesty (P : Player_Id) return Integer is
     (Clamp (K ("ticks.hon_base", 55) + (Brev_Of (P) - 50) * K ("ticks.hon_brev", 40) / 100 - Warm_Of (P) * K ("ticks.hon_warm", 70) / 100, 0, 100));

   function Median (V : Players; N : Natural) return Integer is
      A : array (1 .. 4) of Integer := [others => 0];
      T : Integer;
   begin
      for I in 1 .. N loop A (I) := V (Player_Id (I)); end loop;
      for I in 1 .. N loop   --  sort (N <= 4)
         for J in I + 1 .. N loop
            if A (J) < A (I) then T := A (I); A (I) := A (J); A (J) := T; end if;
         end loop;
      end loop;
      return (if N = 0 then K ("ticks.base", 300) elsif N mod 2 = 1 then A ((N + 1) / 2) else Snap_Up ((A (N / 2) + A (N / 2 + 1) + 1) / 2));
   end Median;

   function Compute (Tick : Int; D : Inputs) return Result is
      R : Result;
      Base : constant Integer := K ("ticks.base", 300);
      Sum : array (Factor range F_Open .. F_Curious) of Integer := [others => 0];
      Best : Integer := 0;
      Dist : Integer := Integer'Last;
   begin
      R.Tick := Tick;
      for E in Entity_Id loop
         declare
            Pt : Parts;
         begin
            Propose (E, Tick, D, Pt, R.Wesen (E));
            R.Part (E) := Pt;
            for F in Pt'Range loop Sum (F) := Sum (F) + Pt (F); end loop;
         end;
      end loop;
      for P in Player_Id range 1 .. Last_Player loop
         declare
            Tot, N : Integer := 0;
            Raw, Lean : Integer;
            Bias_Pct : Integer;
         begin
            for E in Entity_Id loop
               if Watcher (E) = P then Tot := Tot + R.Wesen (E); N := N + 1; end if;
            end loop;
            R.Mean (P) := (if N = 0 then Base else Tot / N);
            R.Pref (P) := Clamp (Base + Warm_Of (P) * K ("ticks.pref_warm", 200) / 100 - (Brev_Of (P) - 50) * K ("ticks.pref_brev", 100) / 100, Min_T, Max_T);
            Raw := (R.Mean (P) * (100 - K ("ticks.self_w", 30)) + R.Pref (P) * K ("ticks.self_w", 30)) / 100;
            Bias_Pct := Clamp ((100 - Honesty (P)) * K ("ticks.bias_scale", 60) / 100, 0, K ("ticks.bias_cap", 90));
            Lean := (if Raw = Snap_Down (Raw) then Raw
                     elsif Roll (Seed_V, 100 + Integer (P), Tick, 9821, 100) <= Bias_Pct then (if R.Pref (P) >= Raw then Snap_Up (Raw) else Snap_Down (Raw))
                     else Snap (Raw));
            R.Biased (P) := Lean /= Snap (Raw);
            R.Choice (P) := Lean;
         end;
      end loop;
      R.Next := Median (R.Choice, Natural (Last_Player));
      for F in Sum'Range loop
         if abs Sum (F) > Best then Best := abs Sum (F); R.Why := F; end if;
      end loop;
      if Best < K ("ticks.calm_below", 50) * 4 then R.Why := F_Calm; end if;
      declare
         Ties : Natural := 0;
         Skip : Natural;
      begin
         for P in Player_Id range 1 .. Last_Player loop
            Dist := Integer'Min (Dist, abs (R.Choice (P) - R.Next));
         end loop;
         for P in Player_Id range 1 .. Last_Player loop
            if abs (R.Choice (P) - R.Next) = Dist then Ties := Ties + 1; end if;
         end loop;
         Skip := Roll (Seed_V, 100, Tick, 9824, Ties) - 1;   --  the voice: one of the players closest to the result, by the hash
         for P in Player_Id range 1 .. Last_Player loop
            if abs (R.Choice (P) - R.Next) = Dist then
               if Skip = 0 then R.Voice := P; exit; end if;
               Skip := Skip - 1;
            end if;
         end loop;
      end;
      return R;
   end Compute;

   function Why_Key (F : Factor) return String is
     (case F is when F_Open => "open", when F_Defer => "defer", when F_Unrest => "unrest", when F_Tired => "tired",
                when F_Curious => "curious", when F_Calm => "calm");

   function Slashed (V : Ints) return String is
      R : Unbounded_String;
   begin
      for E in Entity_Id loop Append (R, (if E = Entity_Id'First then "" else "/") & Img (V (E))); end loop;
      return To_String (R);
   end Slashed;

   function Slashed (V : Players) return String is
      R : Unbounded_String;
   begin
      for P in Player_Id range 1 .. Last_Player loop Append (R, (if P = 1 then "" else "/") & Img (V (P))); end loop;
      return To_String (R);
   end Slashed;

   function Line_Of (N : Natural; R : Result) return String is
     ("N" & Img (N) & " t=" & Img (R.Tick) & " wesen=" & Slashed (R.Wesen) & " players=" & Slashed (R.Choice) & " next=" & Img (R.Next)
      & " why=" & Why_Key (R.Why) & " voice=" & Player_Name (R.Voice));

   procedure Round (Tick : Int; Data : Inputs; Lines : in out Str_Vectors.Vector) is
      R : constant Result := Compute (Tick, Data);
   begin
      Count := Count + 1;
      Latest := R;
      Lines.Append (Line_Of (Count, R));
   end Round;

   function Rounds return Natural is (Count);
   function Last_Tick return Int is (Latest.Tick);
   function Recommended return Natural is (if Count = 0 then 0 else Natural (Latest.Next));

   function Made (Tick : Int; Data : Inputs) return Result is
     (if Count > 0 and then Latest.Tick = Tick then Latest else Compute (Tick, Data));

   function Box_Lines (Tick : Int; Data : Inputs) return Str_Vectors.Vector is
      R : constant Result := Made (Tick, Data);
      V : Str_Vectors.Vector;
      Pick : constant Positive := Roll (Seed_V, 100, Tick, 9823, 3);
   begin
      V.Append (Msg ("next.box." & Img (Pick), Img (R.Next), Slashed (R.Wesen), Slashed (R.Choice)));
      V.Append (Msg ("next.why." & Why_Key (R.Why) & "." & Variant_Of (R.Voice), Player_Name (R.Voice), Img (R.Next)));
      return V;
   end Box_Lines;

   function View (Tick : Int; Data : Inputs) return Str_Vectors.Vector is
      V : Str_Vectors.Vector;
      R : constant Result := Made (Tick, Data);
   begin
      if Count = 0 and then Tick < 0 then return V; end if;
      V.Append (Msg ("next.head", Img (R.Tick), Img (R.Next), Img (Min_T), Img (Max_T), Img (Step_T)));
      for E in Entity_Id loop
         V.Append (Msg ("next.wesen", Name (E), Img (R.Wesen (E)), Img (Data.Open (E)), Img (Data.Defer (E)), Img (Data.Unrest (E)), Img (Data.Energy (E)),
                        "open " & Sgn (Int (R.Part (E) (F_Open))) & " deferred " & Sgn (Int (R.Part (E) (F_Defer))) & " unrest " & Sgn (Int (R.Part (E) (F_Unrest)))
                        & " tired " & Sgn (Int (R.Part (E) (F_Tired))) & " curious " & Sgn (Int (R.Part (E) (F_Curious)))));
      end loop;
      for P in Player_Id range 1 .. Last_Player loop
         V.Append (Msg ("next.player", Player_Name (P), Img (R.Mean (P)), Img (R.Pref (P)), Img (R.Choice (P)), (if R.Biased (P) then Msg ("next.biased") else ""),
                        Img (Honesty (P))));
      end loop;
      V.Append (Msg ("next.median", Img (R.Next), Slashed (R.Choice)));
      V.Append (Msg ("next.why." & Why_Key (R.Why) & "." & Variant_Of (R.Voice), Player_Name (R.Voice), Img (R.Next)));
      V.Append (Msg ((if Limit ("nextticks.use", 0) /= 0 then "next.use.on" else "next.use.off"), Img (R.Next)));
      return V;
   end View;

   function Digest_Line return String is
     (Msg ("next.digest", Img (Count), Img (Latest.Next), Slashed (Latest.Wesen)));

end Sim_Next;
