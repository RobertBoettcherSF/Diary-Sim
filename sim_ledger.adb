--  Version: 0.004
--  See sim_ledger.ads.
pragma Ada_2022;

with Sim_Ckpt;

with Ada.Characters.Handling;
with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
use Ada.Strings.Unbounded;

package body Sim_Ledger is

   type Rec is record
      E : Entity_Id := 1;
      Tick : Int := 0;
      A : Action := Rest;
      V : List_Id := Rest;
      Loc : Natural := 0;
      Base, Rst, Psh, Chs, Gvn, Nom, Phase : Integer := 0;
      Cool : Boolean := False;
      Feel : Integer := -1;
   end record;
   package Rec_Vectors is new Ada.Containers.Vectors (Positive, Rec);
   Recs : Rec_Vectors.Vector;   --  0.058: only the ticks after the start of the newest session (Keep_From); the whole run is in Total
   Last_Tick : Int := 0;
   N_Seen : Natural := 0;       --  all ticks added (all wesen)

   subtype Place is Natural range 0 .. 3;
   type Verb_Sums is array (List_Id range Rest .. Greet) of Integer;
   type Verb_Cnts is array (List_Id range Rest .. Greet) of Natural;

   type Cell_Sums is array (Action, Place) of Integer;
   type Cell_Cnts is array (Action, Place) of Natural;
   type Act_Sums is array (Action) of Integer;
   type Act_Cnts is array (Action) of Natural;
   type Loc_Sums is array (Place) of Integer;
   type Loc_Cnts is array (Place) of Natural;
   type Push_Sums is array (0 .. 2) of Integer;
   type Push_Cnts is array (0 .. 2) of Natural;

   --  Everything one scope (a wesen, a tick range) sums up.
   type Agg is record
      N : Natural := 0;
      Net, Absorbed : Integer := 0;
      Cell : Cell_Sums := [others => [others => 0]];   --  base part by action and place
      Cell_N : Cell_Cnts := [others => [others => 0]];
      Act : Act_Sums := [others => 0];                 --  the whole tick change by action
      Act_N : Act_Cnts := [others => 0];
      Loc : Loc_Sums := [others => 0];                 --  ... by place
      Loc_N : Loc_Cnts := [others => 0];
      Verb : Verb_Sums := [others => 0];               --  ... by diary verb
      Verb_N : Verb_Cnts := [others => 0];
      Push : Push_Sums := [others => 0];
      Push_N : Push_Cnts := [others => 0];
      Quick, Calm, Cool_Sum : Integer := 0;
      Quick_N, Calm_N, Cool_N : Natural := 0;
      Chess : Integer := 0;                            --  mood of finished chess games
      Gov : Integer := 0;                              --  mood of governance decisions (govern=1)
      Gov_N : Natural := 0;
      Chess_N : Natural := 0;
   end record;

   procedure Add_To (G : in out Agg; R : Rec) is
   begin
      declare
         L : constant Place := Place'Min (3, R.Loc);
         D : constant Integer := R.Base + R.Rst + R.Psh + R.Chs + R.Gvn;
      begin
         G.N := G.N + 1;
         G.Net := G.Net + D;
         G.Absorbed := G.Absorbed + (R.Nom - D);
         G.Cell (R.A, L) := G.Cell (R.A, L) + R.Base;
         G.Cell_N (R.A, L) := G.Cell_N (R.A, L) + 1;
         G.Act (R.A) := G.Act (R.A) + D;
         G.Act_N (R.A) := G.Act_N (R.A) + 1;
         G.Loc (L) := G.Loc (L) + D;
         G.Loc_N (L) := G.Loc_N (L) + 1;
         G.Verb (R.V) := G.Verb (R.V) + D;
         G.Verb_N (R.V) := G.Verb_N (R.V) + 1;
         if R.Feel in 0 .. 2 then
            G.Push (R.Feel) := G.Push (R.Feel) + R.Psh;
            G.Push_N (R.Feel) := G.Push_N (R.Feel) + 1;
         end if;
         G.Chess := G.Chess + R.Chs;
         G.Gov := G.Gov + R.Gvn;
         if R.Gvn /= 0 then G.Gov_N := G.Gov_N + 1; end if;
         if R.Chs /= 0 then G.Chess_N := G.Chess_N + 1; end if;
         if R.Phase < 0 then
            G.Quick := G.Quick + R.Rst;
            G.Quick_N := G.Quick_N + 1;
         elsif R.Phase > 0 then
            G.Calm := G.Calm + R.Rst;
            G.Calm_N := G.Calm_N + 1;
         end if;
         if R.Cool then
            G.Cool_Sum := G.Cool_Sum + D;
            G.Cool_N := G.Cool_N + 1;
         end if;
      end;
   end Add_To;

   Total : array (Entity_Id) of Agg;   --  0.058: the sums of the whole run (Sum (E, 0)), kept as the ticks come

   procedure Reset is
   begin
      Recs.Clear;
      Last_Tick := 0;
      N_Seen := 0;
      Total := [others => <>];
   end Reset;

   procedure Add (E : Entity_Id; Tick : Int; A : Action; V : List_Id; Loc : Natural;
                  Base, Rest_Fx, Push_Fx, Nominal, Phase : Integer; Cool : Boolean; Feel : Integer; Chess_Fx : Integer := 0;
                  Gov_Fx : Integer := 0) is
      R : constant Rec := (E => E, Tick => Tick, A => A, V => V, Loc => Loc, Base => Base, Rst => Rest_Fx, Psh => Push_Fx, Chs => Chess_Fx, Gvn => Gov_Fx,
                           Nom => Nominal, Phase => Phase, Cool => Cool, Feel => Feel);
   begin
      Recs.Append (R);
      Add_To (Total (E), R);
      N_Seen := N_Seen + 1;
      if Tick > Last_Tick then Last_Tick := Tick; end if;
   end Add;

   procedure Keep_From (Tick : Int) is
      K : Natural := 0;
   begin
      for R of Recs loop
         exit when R.Tick > Tick;
         K := K + 1;
      end loop;
      if K > 0 then Recs.Delete_First (Ada.Containers.Count_Type (K)); end if;
   end Keep_From;


   function Ticks_Seen return Natural is (N_Seen);

   function Net (E : Entity_Id; From, To : Int) return Integer is
      T : Integer := 0;
   begin
      if From <= 0 and then To = 0 then return Total (E).Net; end if;
      for R of Recs loop
         if R.E = E and then R.Tick > From and then (To = 0 or else R.Tick <= To) then T := T + R.Base + R.Rst + R.Psh + R.Chs + R.Gvn; end if;
      end loop;
      return T;
   end Net;

   function Sum (E : Entity_Id; From : Int) return Agg is
      G : Agg;
   begin
      if From <= 0 then return Total (E); end if;
      for R of Recs loop
         if R.E = E and then R.Tick > From then Add_To (G, R); end if;
      end loop;
      return G;
   end Sum;

   --  ---- the candidates of the top lists: a partition of the whole mood change ----------------------
   type Kind_T is (Cell_K, Quick_K, Calm_K, Push_K, Chess_K, Gov_K);
   type Cand is record
      Kind : Kind_T := Cell_K;
      A : Action := Rest;
      L : Place := 0;
      Class : Natural := 0;
      Val : Integer := 0;
      N : Natural := 0;
   end record;
   type Cand_Array is array (Positive range <>) of Cand;

   function Lower (A : List_Id) return String is (Ada.Characters.Handling.To_Lower (List_Id'Image (A)));
   function Act_Label (A : List_Id) return String is (Msg ("ledger.v." & Lower (A)));
   function Place_Label (L : Natural) return String is (Msg ("loc." & Img (L)));

   function Label (C : Cand) return String is
     (case C.Kind is
         when Cell_K => Msg ("ledger.cell", Act_Label (C.A), Place_Label (C.L)),
         when Quick_K => Msg ("ledger.quick"),
         when Calm_K => Msg ("ledger.calm"),
         when Push_K => Msg ("ledger.push." & Img (C.Class)),
         when Chess_K => Msg ("ledger.chess"),
         when Gov_K => Msg ("ledger.govern"));

   function Candidates (G : Agg) return Cand_Array is
      Out_A : Cand_Array (1 .. 64);
      N : Natural := 0;
      procedure Put (C : Cand) is
      begin
         if C.N > 0 then N := N + 1; Out_A (N) := C; end if;
      end Put;
   begin
      for A in Action loop
         for L in Place loop
            Put (Cand'(Cell_K, A, L, 0, G.Cell (A, L), G.Cell_N (A, L)));
         end loop;
      end loop;
      Put (Cand'(Quick_K, Rest, 0, 0, G.Quick, G.Quick_N));
      Put (Cand'(Calm_K, Rest, 0, 0, G.Calm, G.Calm_N));
      for K in 0 .. 2 loop Put (Cand'(Push_K, Rest, 0, K, G.Push (K), G.Push_N (K))); end loop;
      Put (Cand'(Chess_K, Rest, 0, 0, G.Chess, G.Chess_N));
      Put (Cand'(Gov_K, Rest, 0, 0, G.Gov, G.Gov_N));
      return Out_A (1 .. N);
   end Candidates;

   --  The I-th best candidate: Drain true = most negative first, else most positive first (ties: list order).
   --  Zero values do not count.  Returns False when there are fewer than I.
   function Pick (C : Cand_Array; Drain : Boolean; I : Positive; R : out Cand) return Boolean is
      Taken : array (C'Range) of Boolean := [others => False];
      Best : Natural;
   begin
      R := (others => <>);
      for Round in 1 .. I loop
         Best := 0;
         for K in C'Range loop
            if not Taken (K) and then (if Drain then C (K).Val < 0 else C (K).Val > 0)
              and then (Best = 0 or else (if Drain then C (K).Val < C (Best).Val else C (K).Val > C (Best).Val))
            then
               Best := K;
            end if;
         end loop;
         if Best = 0 then return False; end if;
         Taken (Best) := True;
         if Round = I then R := C (Best); end if;
      end loop;
      return True;
   end Pick;

   function Blanks (N : Natural) return String is (Ada.Strings.Fixed."*" (N, ' '));
   function Pad_R (S : String; W : Positive) return String is (if S'Length >= W then S else S & Blanks (W - S'Length));

   function Item (Name : String; Val : Integer; N : Natural) return String is
     (Msg ("ledger.item", Name, Sgn (Int (Val)), Img (N)));

   --  A line of items: the prefix first, then the items in rows of at most Width columns; continuation rows are
   --  indented under the first item.
   function Wrap (Prefix : String; Items : Str_Vectors.Vector; Width : Positive := 79) return String is
      Out_S : Unbounded_String;
      Row : Unbounded_String := To_Unbounded_String (Prefix);
      Fresh : Boolean := True;
      Pad : constant String := Blanks (Prefix'Length);
   begin
      if Items.Is_Empty then return Prefix & Msg ("ledger.none") & ASCII.LF; end if;
      for It of Items loop
         if not Fresh and then Length (Row) + 2 + It'Length > Width then
            Append (Out_S, To_String (Row) & ASCII.LF);
            Row := To_Unbounded_String (Pad);
            Fresh := True;
         end if;
         Append (Row, (if Fresh then "" else "  ") & It);
         Fresh := False;
      end loop;
      return To_String (Out_S) & To_String (Row) & ASCII.LF;
   end Wrap;

   --  Plain words wrapped at Width, rows indented by Indent blanks.
   function Wrap_Text (Indent : Natural; Text : String; Width : Positive := 79) return String is
      Out_S : Unbounded_String;
      Row : Unbounded_String := To_Unbounded_String (Blanks (Indent));
      Fresh : Boolean := True;
      From : Positive := Text'First;
   begin
      for I in Text'First .. Text'Last + 1 loop
         if I > Text'Last or else Text (I) = ' ' then
            if I > From then
               declare
                  W : constant String := Text (From .. I - 1);
               begin
                  if not Fresh and then Length (Row) + 1 + W'Length > Width then
                     Append (Out_S, To_String (Row) & ASCII.LF);
                     Row := To_Unbounded_String (Blanks (Indent));
                     Fresh := True;
                  end if;
                  Append (Row, (if Fresh then "" else " ") & W);
                  Fresh := False;
               end;
            end if;
            From := I + 1;
         end if;
      end loop;
      return To_String (Out_S) & To_String (Row) & ASCII.LF;
   end Wrap_Text;

   function Top_Items (C : Cand_Array; Drain : Boolean) return Str_Vectors.Vector is
      R : Str_Vectors.Vector;
      X : Cand;
   begin
      for I in 1 .. 3 loop
         exit when not Pick (C, Drain, I, X);
         R.Append (Item (Label (X), X.Val, X.N));
      end loop;
      return R;
   end Top_Items;

   --  ---- text ------------------------------------------------------------------------------------------
   function Sentence (E : Entity_Id) return String is
      G : constant Agg := Sum (E, 0);
      C : constant Cand_Array := Candidates (G);
      X : Cand;
      Back : constant String := Sgn (Int (G.Act (Rest)));
   begin
      if not Pick (C, True, 1, X) then return Msg ("ledger.sentence.none", Display (E), Back); end if;
      case X.Kind is
         when Cell_K =>
            return Msg ("ledger.sentence", Display (E), Act_Label (X.A), Msg ("ledger.at." & Img (X.L)), Sgn (Int (X.Val)), Img (X.N), Back);
         when others =>
            return Msg ("ledger.sentence.event", Display (E), Label (X), Sgn (Int (X.Val)), Img (X.N), Back);
      end case;
   end Sentence;

   function Digest_Line (E : Entity_Id; Last_From : Int) return String is
      G : constant Agg := Sum (E, 0);
      L : constant Agg := Sum (E, Last_From);
      C : constant Cand_Array := Candidates (G);
      D, P : Cand;
      Has_D : constant Boolean := Pick (C, True, 1, D);
      Has_P : constant Boolean := Pick (C, False, 1, P);
   begin
      return Msg ("ledger.digest", Display (E), Sgn (Int (G.Net)), Sgn (Int (L.Net)),
                  (if Has_D then Item (Label (D), D.Val, D.N) else Msg ("ledger.none")),
                  (if Has_P then Item (Label (P), P.Val, P.N) else Msg ("ledger.none")));
   end Digest_Line;

   function Breakdown (G : Agg) return String is
      Out_S : Unbounded_String;
      Items : Str_Vectors.Vector;
      W : constant Positive := 13;
   begin
      for A in Action loop
         if G.Act_N (A) > 0 then Items.Append (Item (Act_Label (A), G.Act (A), G.Act_N (A))); end if;
      end loop;
      Append (Out_S, Wrap ("  " & Pad_R (Msg ("ledger.by.action"), W), Items));
      Items.Clear;
      for L in Place loop
         if G.Loc_N (L) > 0 then Items.Append (Item (Place_Label (L), G.Loc (L), G.Loc_N (L))); end if;
      end loop;
      Append (Out_S, Wrap ("  " & Pad_R (Msg ("ledger.by.place"), W), Items));
      Items.Clear;
      for V in G.Verb'Range loop
         if G.Verb_N (V) > 0 then Items.Append (Item (Act_Label (V), G.Verb (V), G.Verb_N (V))); end if;
      end loop;
      Append (Out_S, Wrap ("  " & Pad_R (Msg ("ledger.by.verb"), W), Items));
      Items.Clear;
      if G.Act_N (Propose) > 0 then Items.Append (Item (Msg ("ledger.petition"), G.Act (Propose), G.Act_N (Propose))); end if;
      for K in 0 .. 2 loop
         if G.Push_N (K) > 0 then Items.Append (Item (Msg ("ledger.push." & Img (K)), G.Push (K), G.Push_N (K))); end if;
      end loop;
      if G.Chess_N > 0 then Items.Append (Item (Msg ("ledger.chess"), G.Chess, G.Chess_N)); end if;
      if G.Gov_N > 0 then Items.Append (Item (Msg ("ledger.govern"), G.Gov, G.Gov_N)); end if;
      Append (Out_S, Wrap ("  " & Pad_R (Msg ("ledger.by.event"), W), Items));
      Items.Clear;
      if G.Quick_N > 0 then Items.Append (Item (Msg ("ledger.quick"), G.Quick, G.Quick_N)); end if;
      if G.Calm_N > 0 then Items.Append (Item (Msg ("ledger.calm"), G.Calm, G.Calm_N)); end if;
      if G.Cool_N > 0 then Items.Append (Item (Msg ("ledger.cool"), G.Cool_Sum, G.Cool_N)); end if;
      Append (Out_S, Wrap ("  " & Pad_R (Msg ("ledger.by.rest"), W), Items));
      return To_String (Out_S);
   end Breakdown;

   function Report (Seed, Last_From : Int; Full : Boolean) return String is
      Out_S : Unbounded_String;
      Wide : Positive := 1;
      Scope_Name : constant array (1 .. 2) of Unbounded_String :=
        [To_Unbounded_String (Msg ("ledger.run")), To_Unbounded_String (Msg ("ledger.last"))];
   begin
      for E in Entity_Id loop Wide := Positive'Max (Wide, Display (E)'Length); end loop;
      Append (Out_S, Msg ("ledger.head", Img (Seed), Img (Last_Tick), Img (Last_From + 1)) & ASCII.LF);
      if N_Seen = 0 then return To_String (Out_S) & Msg ("ledger.empty"); end if;
      for E in Entity_Id loop
         declare
            G : constant Agg := Sum (E, 0);
            L : constant Agg := Sum (E, Last_From);
            Scopes : constant array (1 .. 2) of Agg := [G, L];
         begin
            Append (Out_S, Msg ("ledger.wesen", Pad_R (Display (E), Wide), Sgn (Int (G.Net)), Img (G.N), Sgn (Int (L.Net)), Img (L.N),
                                Img (G.Absorbed)) & ASCII.LF);
            for S in 1 .. 2 loop
               declare
                  C : constant Cand_Array := Candidates (Scopes (S));
                  Tag : constant String := Pad_R (To_String (Scope_Name (S)), 5);
               begin
                  Append (Out_S, Wrap ("  " & Msg ("ledger.drain") & " " & Tag, Top_Items (C, True)));
                  Append (Out_S, Wrap ("  " & Msg ("ledger.gain") & " " & Tag, Top_Items (C, False)));
               end;
            end loop;
            Append (Out_S, Wrap_Text (2, Sentence (E)));
            if Full then Append (Out_S, Breakdown (G)); end if;
         end;
      end loop;
      return To_String (Out_S) (1 .. Length (Out_S) - 1);   --  without the last line feed (the caller's Put_Line adds it)
   end Report;

   --  0.058: the checkpoint.
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Integer);
      procedure IO is new Sim_Ckpt.IO (Int);
      procedure IO is new Sim_Ckpt.IO (Rec_Vectors.Vector);
      procedure IO is new Sim_Ckpt.IO (Agg);
   begin
      IO (S, Save, Recs);
      IO (S, Save, Last_Tick);
      IO (S, Save, N_Seen);
      for E in Entity_Id loop IO (S, Save, Total (E)); end loop;
   end State_IO;

end Sim_Ledger;
