--  Version: 0.002
--  The screens of diary_sim (screen=1 sessions).  Every wesen owns a small text screen (screen.cols x screen.rows
--  characters, data/limits.txt) with the words it knows, the names of things it examined, and words it saw on other
--  screens.  A wesen can pin and drop words, show its screen to a wesen in the same or a neighbouring cell, or leave
--  it on a thing for others to read.  A viewer who meets a word it does not know learns it with a data-set chance
--  ("taught from a screen"); two words side by side may be coined into a blend ("coined from a screen"; the
--  blend of two words with an optional syllable of the existing name table).
--  Everything is a pure function of (seed, wesen, tick, salt 9100 .. 9199) and of the state, like the rest of the
--  simulation: each state change comes out as a record line (Step, Lines) for diaries/screens.txt, which the
--  replay checks (Sim_Store).  Off (no screen=1 session) nothing here runs and nothing is stored.
--  HOOK for a later condensed-vocabulary step (NOT built): Words_Of and Count give the words on a screen in
--  order; a later step may fold the most seen words into one short form there.  Reserved: screen.condense = 0.
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (layout width arithmetic, bounded vectors)
pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Sim_Util;
with Sim_World;

package Sim_Screen is

   use Sim_Util;
   use Sim_World;

   type Learn_Rec is record
      Who : Entity_Id := 1;
      W : Positive := 1;
      From : Natural := 0;       --  the wesen whose screen taught it (0: coined)
      Coined : Boolean := False;
   end record;
   package Learn_Vectors is new Ada.Containers.Vectors (Positive, Learn_Rec);

   type Read_Rec is record
      Viewer, Owner : Entity_Id := 1;
   end record;
   package Read_Vectors is new Ada.Containers.Vectors (Positive, Read_Rec);

   procedure Init (Seed, Coin_Cap : Int);   --  empty screens, no notes; reads data/limits.txt

   --  A word E learned or a thing name E examined (called from the step; the line comes out with the next Step).
   procedure Note (E : Entity_Id; W : Positive; Src : String);

   --  One tick of E's screen life.  Lines: the record lines of every change (text without key and tick);
   --  Learned: words that were learned or coined (the caller files them in the words files);
   --  Detail: the sentence for E's diary line (appended; empty if nothing happened).
   procedure Step (E : Entity_Id; Tick : Int; Lines : in out Str_Vectors.Vector;
                   Learned : in out Learn_Vectors.Vector; Detail : in out Ada.Strings.Unbounded.Unbounded_String);

   --  ---- the robot's hooks (robot=1; Sim_Robot) ----------------------------------------------------------------------------
   --  Pin up to two command words (a command like "go north"): the earlier command pins are released, a word not yet on the
   --  screen is put there first.  A command word of 0 is left out.  Not counted against screen.pins.
   procedure Pin_Command (E : Entity_Id; W1, W2 : Natural);
   --  The 5x5 camera view (and the error line, "" if none) the robot wrote to the screen of E; Box shows it below the frame.
   procedure Set_Frame (E : Entity_Id; Rows : Str_Vectors.Vector; Err : String);
   function Has_Frame (E : Entity_Id) return Boolean;
   function Frame_Of (E : Entity_Id) return Str_Vectors.Vector;
   function Word_At (E : Entity_Id; I : Positive) return Positive;   --  the I-th word on the screen
   --  Who read whose screen (show or note) since the last call; the log is emptied.
   function Take_Reads return Read_Vectors.Vector;

   function Count (E : Entity_Id) return Natural;                 --  words on the screen
   function Words_Of (E : Entity_Id) return String;               --  ids in order, "*" before a pinned one
   function Box (E : Entity_Id) return Str_Vectors.Vector;        --  the framed screen, one string per row
   function Taught_From (E : Entity_Id) return Natural;           --  words E learned from a screen
   function Coined_From (E : Entity_Id) return Natural;           --  words E coined from a screen
   function Shown (E : Entity_Id) return Natural;                 --  times E showed its screen
   function Left_Notes (E : Entity_Id) return Natural;            --  times E left its screen on a thing
   function Read_Notes (E : Entity_Id) return Natural;            --  notes E read
   function Notes_Now return Natural;                             --  notes lying on things
   function Summary (E : Entity_Id) return String;                --  one report line

end Sim_Screen;
