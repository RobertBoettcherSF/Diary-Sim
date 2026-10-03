--  Version: 0.002
--  The treadmill world of diary_sim (world=1 sessions only): an endless grid that is generated
--  around the wesen as they walk and is identical whenever they come back.
--
--  * A cell (x, y) has a biome and up to two things, both PURE functions of hash (seed, cell, slot)
--    with the base-60 lists of data/things.txt.  Nothing of an untouched cell is ever stored.
--  * Only EDITS are stored (a thing eaten, pushed away, worn out, a new thing from churn): an edit log,
--    kept per chunk (data/limits.txt world.chunk x world.chunk cells) and written to diaries/world.txt
--    by the caller, so a replay re-creates the identical world and a tampered edit is a DRIFT.
--  * A thing = quality + shape + material ("red round stone") and a made-up name from the syllable
--    table; the name, the quality, the feel, the taste are words the wesen learn by meeting the thing.
--  * Four landmark regions (office, lab, cafe, home) at fixed cells near the origin keep the old
--    location numbers 0 .. 3: Region (x, y) is the nearest landmark.
--  Plain hashing and small text tables, CPU only.  Salts 7000 .. 8999 are this package's own.
pragma Ada_2022;

with Ada.Containers.Vectors;
with Sim_Util;
with Sim_World;

package Sim_Things is

   use Sim_Util;
   use Sim_World;

   type Thing is record
      Ent : Positive := 1;   --  the cell it was born in (hash key) or the cell of a churn event
      Sub : Int := 0;        --  slot 1 / 2 of a generated thing, 1000 + tick of a churn thing
   end record;
   package Thing_Vectors is new Ada.Containers.Vectors (Positive, Thing);
   type Reach_Item is record
      T : Thing;
      X, Y : Integer := 0;
   end record;
   package Reach_Vectors is new Ada.Containers.Vectors (Positive, Reach_Item);

   procedure Load (Lines : Str_Vectors.Vector);   --  data/things.txt
   function Loaded return Boolean;                --  all lists present (else the world cannot start)
   procedure Init (Seed : Int);                   --  empty edit log, nobody placed; reads data/limits.txt

   --  ---- places and walking ------------------------------------------------------------------
   type Pos_Array is array (Entity_Id) of Integer;
   type Placed_Array is array (Entity_Id) of Boolean;
   function Placed (E : Entity_Id) return Boolean;
   function X (E : Entity_Id) return Integer;
   function Y (E : Entity_Id) return Integer;
   function Region (X, Y : Integer) return Natural;   --  nearest landmark 0 .. 3 (ties: the lower)
   function Region_Of (E : Entity_Id) return Natural;
   procedure Place (E : Entity_Id; Tick : Int; Landmark : Natural);   --  beside that landmark
   --  One cell by dice (personality, a pull home beyond world.leash); Seek: towards the nearest wesen.
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (direction weights, cumulative pick)
   procedure Walk (E : Entity_Id; Tick : Int; Seek : Boolean);
   function Adjacent (A, B : Entity_Id) return Boolean;   --  same or neighbouring cell
   function Facing (E : Entity_Id; Tick : Int) return Natural;   --  0 N, 1 E, 2 S, 3 W by dice

   --  ---- cells and things ------------------------------------------------------------------------
   function Biome (X, Y : Integer) return String;
   function Biome_Glyph (X, Y : Integer) return Character;
   function Things_At (X, Y : Integer) return Thing_Vectors.Vector;
   function Reach (E : Entity_Id) return Reach_Vectors.Vector;   --  things in E's cell and the 4 neighbours
   function Quality_Text (T : Thing) return String;
   function Feel_Text (T : Thing) return String;
   function Taste_Text (T : Thing) return String;
   function Description (T : Thing) return String;   --  "red round stone"
   function Name_Text (T : Thing) return String;     --  the made-up name
   function Thing_Key (X, Y : Integer; T : Thing) return String;   --  "x,y/ent.sub": where a screen note lies
   --  A syllable of the name table by the caller's own salt (Sim_Screen: the bridge of a coined blend).
   function Blend_Syllable (E : Entity_Id; Tick : Int; Salt : Natural) return String;
   function Feel_Class (T : Thing) return Natural;   --  0 pleasant, 1 neutral, 2 unpleasant (block of 20)
   function Taste_Class (T : Thing) return Natural;
   function Social_Text (E : Entity_Id; Tick : Int) return String;

   --  ---- words (the vocabulary is Sim_World's) ---------------------------------------------------
   function Name_Word (T : Thing) return Positive;   --  creates the word on the first meeting
   function Name_Known (E : Entity_Id; T : Thing) return Boolean;
   function Prop_Word (Text, Meaning : String) return Positive;   --  an existing word, or a new world word
   --  Passing a word on may change one letter (a dialect): W itself or a variant word.
   function Mutate (W : Positive; E : Entity_Id; Tick : Int) return Positive;

   --  ---- edits ---------------------------------------------------------------------------------------
   type Edit_Op is (Gone, Add);
   procedure Edit (Tick : Int; Op : Edit_Op; T : Thing; X, Y : Integer; By : String);
   function Edit_Count return Natural;
   function Edit_Line (N : Positive) return String;   --  X<n> t=<tick> gone|add <ent>.<sub> <x>,<y> by=<who>
   procedure Apply_Line (L : String; OK : out Boolean);   --  a stored edit line (the --map view; no log entry)
   procedure Churn (Tick : Int);   --  every world.churn ticks: things appear, wear out or change near the wesen

   --  ---- the treadmill view ---------------------------------------------------------------------------
   --  Position, nearest landmark, biome and a 5x5 window per wesen (glyphs: data/things.txt).
   function Treadmill (PX, PY : Pos_Array; Present : Placed_Array) return Str_Vectors.Vector;
   function Treadmill_Now return Str_Vectors.Vector;   --  of the live state

end Sim_Things;
