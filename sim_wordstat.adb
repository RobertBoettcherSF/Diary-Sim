--  Version: 0.002
--  See sim_wordstat.ads.  Read-only counting over strings; no I/O here.
pragma Ada_2022;

with Ada.Containers.Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

package body Sim_Wordstat is

   use Ada.Strings.Unbounded;

   type Word_Rec is record
      Id        : Positive := 1;
      Text      : Unbounded_String;
      K         : Kind := Other;
      Origin    : Kind := Other;
      Tick      : Natural := 0;
      Described : Boolean := False;
      Used      : Boolean := False;
   end record;
   package Word_Vectors is new Ada.Containers.Vectors (Positive, Word_Rec);
   function Id_Hash (K : Positive) return Ada.Containers.Hash_Type is (Ada.Containers.Hash_Type (K));
   package Id_Maps is new Ada.Containers.Hashed_Maps (Positive, Positive, Id_Hash, "=");
   package Text_Maps is new Ada.Containers.Indefinite_Hashed_Maps (String, Positive, Ada.Strings.Hash, "=");
   package Text_Sets is new Ada.Containers.Indefinite_Hashed_Sets (String, Ada.Strings.Hash, "=");
   package Tick_Maps is new Ada.Containers.Indefinite_Hashed_Maps (String, Natural, Ada.Strings.Hash, "=");

   type Ent_Data is record
      Words   : Word_Vectors.Vector;
      By_Id   : Id_Maps.Map;
      By_Text : Text_Maps.Map;
   end record;

   Ents : array (1 .. Max_Ent) of Ent_Data;
   Agreed_Set : Tick_Maps.Map;   --  agreed text -> tick of the first agreement
   Min_Stem : Natural := 3;
   Class_Edges : Edge_Array := [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15];

   function Is_Chess (T : String) return Boolean is
     (T'Length in 4 .. 5
      and then T (T'First) in 'a' .. 'h' and then T (T'First + 1) in '1' .. '8'
      and then T (T'First + 2) in 'a' .. 'h' and then T (T'First + 3) in '1' .. '8'
      and then (T'Length = 4 or else T (T'First + 4) in 'q' | 'r' | 'b' | 'n'));

   function Is_Number (T : String) return Boolean is (T'Length >= 1 and then (for all C of T => C in '0' .. '9'));

   function Origin_Of (How : String) return Kind is
     (if How = "start" then Start
      elsif How = "world" then World
      elsif How = "taught" then Taught
      elsif How = "screen" then Screen
      elsif How = "coined" then Coined
      else Other);

   function Kind_Of (T, How : String) return Kind is
     (if Is_Chess (T) then Chess elsif Is_Number (T) then Number else Origin_Of (How));

   function Bucket_Of (Length : Natural) return Positive is
   begin
      for I in Class_Edges'Range loop
         if Length <= Class_Edges (I) then return I; end if;
      end loop;
      return Buckets;
   end Bucket_Of;

   procedure Reset (Stem_Min : Natural; Edges : Edge_Array) is
   begin
      for E of Ents loop
         E.Words.Clear;
         E.By_Id.Clear;
         E.By_Text.Clear;
      end loop;
      Agreed_Set.Clear;
      Min_Stem := Natural'Max (1, Stem_Min);
      Class_Edges := Edges;
   end Reset;

   procedure Add_Word (E : Positive; Id : Positive; Text, How : String; Tick : Natural; Extra : String) is
   begin
      if E > Max_Ent or else Text = "" or else Ents (E).By_Id.Contains (Id) then return; end if;
      declare
         Rec : constant Word_Rec :=
           (Id => Id, Text => To_Unbounded_String (Text), K => Kind_Of (Text, How), Origin => Origin_Of (How), Tick => Tick,
            Described => How = "world" and then Extra /= "", Used => False);
      begin
         Ents (E).Words.Append (Rec);
      end;
      Ents (E).By_Id.Insert (Id, Positive (Ents (E).Words.Length));
      if not Ents (E).By_Text.Contains (Text) then Ents (E).By_Text.Insert (Text, Positive (Ents (E).Words.Length)); end if;
   end Add_Word;

   procedure Mark (E : Positive; Index : Positive; Tick : Natural) is
   begin
      if Tick > Ents (E).Words (Index).Tick then Ents (E).Words (Index).Used := True; end if;
   end Mark;

   procedure Seen_Id (E : Positive; Id : Positive; Tick : Natural) is
   begin
      if E <= Max_Ent and then Ents (E).By_Id.Contains (Id) then Mark (E, Ents (E).By_Id (Id), Tick); end if;
   end Seen_Id;

   procedure Seen_Text (E : Positive; Text : String; Tick : Natural) is
   begin
      if E <= Max_Ent and then Ents (E).By_Text.Contains (Text) then Mark (E, Ents (E).By_Text (Text), Tick); end if;
   end Seen_Text;

   procedure Agree (Text : String; Tick : Natural) is
   begin
      if Text /= "" and then not Agreed_Set.Contains (Text) then Agreed_Set.Insert (Text, Tick); end if;
   end Agree;

   function Result (E : Natural) return Stat is
      R : Stat;
      All_Text, All_Chess, All_Number : Text_Sets.Set;

      procedure One (X : Positive) is
         Ent : Ent_Data renames Ents (X);
         Chess_Seen, Number_Seen : Text_Sets.Set;
      begin
         for W of Ent.Words loop
            declare
               T : constant String := To_String (W.Text);
               Pre, Suf : Boolean := False;
            begin
               R.Total := R.Total + 1;
               R.Known (W.K) := R.Known (W.K) + 1;
               if W.Used then R.Used := R.Used + 1; R.Used_Kind (W.K) := R.Used_Kind (W.K) + 1; end if;
               if Agreed_Set.Contains (T) then
                  R.Agreed := R.Agreed + 1;
                  if W.Tick >= Agreed_Set (T) then R.Agreed_After := R.Agreed_After + 1; end if;
               end if;
               if W.Described then R.Described := R.Described + 1; end if;
               R.Len (Bucket_Of (T'Length)) := R.Len (Bucket_Of (T'Length)) + 1;
               if W.K not in Chess | Number then R.Len_Plain (Bucket_Of (T'Length)) := R.Len_Plain (Bucket_Of (T'Length)) + 1; end if;
               if W.K in Chess | Number then R.Token_From (W.Origin) := R.Token_From (W.Origin) + 1; end if;
               if W.Tick > R.Last_Tick then R.Last_Tick := W.Tick; end if;
               if not All_Text.Contains (T) then All_Text.Insert (T); end if;
               if W.K = Chess then
                  if not Chess_Seen.Contains (T) then Chess_Seen.Insert (T); end if;
                  if not All_Chess.Contains (T) then All_Chess.Insert (T); end if;
               elsif W.K = Number then
                  if not Number_Seen.Contains (T) then Number_Seen.Insert (T); end if;
                  if not All_Number.Contains (T) then All_Number.Insert (T); end if;
               else
                  for L in Min_Stem .. T'Length - 1 loop   --  a proper stem of at least Min_Stem letters
                     declare
                        Head : constant String := T (T'First .. T'First + L - 1);
                        Tail : constant String := T (T'Last - L + 1 .. T'Last);
                     begin
                        if not Pre and then Ent.By_Text.Contains (Head) and then Ent.Words (Ent.By_Text (Head)).K not in Chess | Number then Pre := True; end if;
                        if not Suf and then Ent.By_Text.Contains (Tail) and then Ent.Words (Ent.By_Text (Tail)).K not in Chess | Number then Suf := True; end if;
                     end;
                  end loop;
                  if Pre then R.Prefix_Var := R.Prefix_Var + 1; end if;
                  if Suf then R.Suffix_Var := R.Suffix_Var + 1; end if;
                  if Pre or else Suf then R.Any_Var := R.Any_Var + 1; end if;
               end if;
            end;
         end loop;
         if E /= 0 then
            R.Distinct := Natural (Ent.By_Text.Length);
            R.Chess_Dist := Natural (Chess_Seen.Length);
            R.Number_Dist := Natural (Number_Seen.Length);
         end if;
      end One;
   begin
      if E in 1 .. Max_Ent then
         One (E);
      elsif E = 0 then
         for X in 1 .. Max_Ent loop One (X); end loop;
         R.Distinct := Natural (All_Text.Length);
         R.Chess_Dist := Natural (All_Chess.Length);
         R.Number_Dist := Natural (All_Number.Length);
      end if;
      return R;
   end Result;

end Sim_Wordstat;
