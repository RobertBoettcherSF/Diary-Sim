--  Version: 0.003
--  The vocabulary report (make wordstat, --wordstat): READ-ONLY.  The caller feeds the lines of entities/<id>/words.txt and of the diaries
--  (screens, votes, petitions, dictionary) in; this package sorts every known word of every wesen into one kind (start, world, taught,
--  screen, coined, chess coordinate, number, other), decides whether it was used again after it was learned, whether the dictionary agreed
--  a meaning for it, how long it is and whether it is a prefix or suffix variant of another word the same wesen knows.  Nothing is written,
--  nothing is simulated, no dice: the numbers are counts over the files, so the same files always give the same report.
--  PROOF-LATER: Importance 2/10, Urgency 1/10, SPARK2 (bounded counting, string slices within bounds)
pragma Ada_2022;

package Sim_Wordstat is

   Max_Ent : constant := 4;
   Buckets : constant := 12;   --  length classes of the histogram

   --  A word counts once, under the first of: chess coordinate (e2e4), number (5755), else the way it was learned.
   type Kind is (Start, World, Taught, Screen, Coined, Chess, Number, Other);
   type Kind_Counts is array (Kind) of Natural;
   type Len_Counts is array (1 .. Buckets) of Natural;
   type Edge_Array is array (1 .. Buckets - 1) of Natural;   --  upper length of each class but the last

   type Stat is record
      Total       : Natural := 0;   --  words known (the sum over the wesen for E = 0)
      Distinct    : Natural := 0;   --  different word texts (E = 0: over all wesen)
      Known       : Kind_Counts := [others => 0];
      Used_Kind   : Kind_Counts := [others => 0];   --  seen again after being learned
      Token_From  : Kind_Counts := [others => 0];   --  chess and number tokens, by the way they were learned (Start .. Other)
      Used        : Natural := 0;
      Agreed      : Natural := 0;   --  words whose TEXT is also an agreed dictionary word (the dictionary is a separate list: see Agree)
      Agreed_After : Natural := 0;  --  of those, learned after the agreement (the text was minted later by chance)
      Described   : Natural := 0;   --  learned from the world with a meaning attached
      Len         : Len_Counts := [others => 0];
      Len_Plain   : Len_Counts := [others => 0];   --  the same without the chess and number tokens
      Chess_Dist  : Natural := 0;   --  different chess coordinate tokens
      Number_Dist : Natural := 0;   --  different numeric tokens
      Prefix_Var  : Natural := 0;   --  words that start with another known word (at least Stem_Min letters)
      Suffix_Var  : Natural := 0;   --  words that end with another known word
      Any_Var     : Natural := 0;   --  either (counted once), tokens and stems of tokens left out
      Last_Tick   : Natural := 0;   --  the latest learning tick seen
      Since       : Natural := 0;   --  words learned at or after the tick of Set_Symbols (all kinds)
      Since_Token : Natural := 0;   --  of those, chess and number strings
   end record;

   function Is_Chess (T : String) return Boolean;    --  e2e4, g7g8q
   function Is_Number (T : String) return Boolean;   --  digits only
   function Kind_Of (T, How : String) return Kind;
   function Origin_Of (How : String) return Kind;   --  Start .. Coined or Other, the way alone

   procedure Reset (Stem_Min : Natural; Edges : Edge_Array);
   --  One line of entities/<id>/words.txt: "<id> <word> <how> <tick> [extra]".
   procedure Add_Word (E : Positive; Id : Positive; Text, How : String; Tick : Natural; Extra : String);
   --  The wesen used the word again (a screen action, a vote, a petition, the dictionary, a notebook): counts only after the learning tick.
   procedure Seen_Id (E : Positive; Id : Positive; Tick : Natural);
   procedure Seen_Text (E : Positive; Text : String; Tick : Natural);
   --  The dictionary agreed a meaning for the word text at Tick.  Agreed names are NOT added to the wesen's word lists by the program; a word list
   --  only holds such a text if the world minted the same letters later.
   procedure Agree (Text : String; Tick : Natural);
   --  The first symbols=1 session starts at Tick (chess strings are no longer minted as words from then on); -1: no such session.
   procedure Set_Symbols (Tick : Integer);
   function Result (E : Natural) return Stat;   --  E = 0: all wesen together
   function Bucket_Of (Length : Natural) return Positive;

end Sim_Wordstat;
