--  Version: 0.001
--  A record file of lines that the replay computes (record-first, like diaries/world.txt): every line starts
--  with a unique key token ("K12", "H3"), and a "t=<tick>" token tells when it happened.  Emit compares a
--  computed line with the stored line of the same key: equal is fine, different is DRIFT (the caller raises
--  it), a missing line is appended when writing is allowed.  Orphan finds a stored line the replay did not
--  produce.  Used by the screens (diaries/screens.txt) and the chess games (diaries/chess.txt).
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (key lookup, token parsing)
pragma Ada_2022;

with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Sim_Util;

package Sim_Store is

   use Sim_Util;

   type Store is limited private;
   type Status is (Same, Appended, Differs, Skipped);

   --  Forget everything and read Path (if it exists).  Header is written first into a new file.
   procedure Open (S : in out Store; Path, Header : String);
   procedure Clear (S : in out Store);
   --  Compare / append one computed line.  Old: the stored line when Differs.
   procedure Emit (S : in out Store; Line : String; Write : Boolean; Result : out Status;
                   Old : out Ada.Strings.Unbounded.Unbounded_String);
   --  First stored line with t <= Upto that no Emit has matched ("" if none).
   function Orphan (S : Store; Upto : Int) return String;
   function Count (S : Store) return Natural;
   function Key_Of (Line : String) return String;   --  the first token

private

   package Str_Vectors_P is new Ada.Containers.Vectors (Positive, Ada.Strings.Unbounded.Unbounded_String, Ada.Strings.Unbounded."=");
   package Key_Maps is new Ada.Containers.Indefinite_Hashed_Maps (String, Positive, Ada.Strings.Hash, "=");
   package Bool_Vectors is new Ada.Containers.Vectors (Positive, Boolean);

   type Store is limited record
      Path   : Ada.Strings.Unbounded.Unbounded_String;
      Header : Ada.Strings.Unbounded.Unbounded_String;
      Lines  : Str_Vectors_P.Vector;
      Hit    : Bool_Vectors.Vector;
      Index  : Key_Maps.Map;
   end record;

end Sim_Store;
