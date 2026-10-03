--  Version: 0.001
--  The visit (visit=1 sessions; inspired by Exile, 1988), STEP 1 = watch and talk.  Robert, the human player, is placed next to ONE wesen
--  for the ticks of a session: every tick shows what that wesen sees (the 5x5 treadmill view as the robot camera draws it, its screen,
--  mood, energy, what it does this tick, who and what is near), the simulation runs as normal and the wesen acts on its own.  Between
--  ticks the human may type (diary_sim reads the lines; this unit only parses, answers and draws):
--    say <text>    the wesen understands only the words it KNOWS at that tick; the others are shown as "unknown to it".  Its answer is
--                  built ONLY from its known vocabulary: data/visit.txt holds templates per mood band (and tired / petition / fond /
--                  cold sets), a template word that the wesen does not know is dropped, so early talks are short and odd and grow
--                  richer with the vocabulary.  "I do not know that word" has several variants (visit.unk.N).
--    teach <word>  feeds the word learning path (Sim_World.Learn_Word, filed in the words file by diary_sim), with a data chance and
--                  caps per tick and per visit (the same spirit as the screens: screen.read / screen.learn_pct).
--    show          shows it a screen of base words; each unknown one is learned with the chance visit.show_pct (same caps).
--    wait [n]      let n ticks pass (default 1; an empty line is a wait 1).      leave   end the frames (the session still runs on).
--  Every input is a V line, every answer an A line of diaries/visit.txt (Sim_Store, replay-verified: a changed, removed or invented line
--  is DRIFT; the V line carries a check number h= over its content).  Answers, learning and the bond are pure functions of
--  (seed, wesen, tick, command number, salts 9900 .. 9999) and of the replayed state, like the rest of the simulation.  The bond is the
--  trust of the wesen towards the human player: it moves by the small numbers visit.bond_* of data/limits.txt after talks.
--  STEP 2 (possess / steer the wesen) is NOT built: see README "Visit, step 2 hook".
--  Off (no visit=1 session) nothing here runs and nothing is stored.
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (command parsing, template filling, bounded integer arithmetic, hash dice)
pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Sim_Util;
with Sim_World;

package Sim_Visit is

   use Sim_Util;
   use Sim_World;

   type Cmd_Kind is (Bad, Say, Teach, Show_Cmd, Wait, Leave);
   type Command is record
      Kind : Cmd_Kind := Bad;
      Text : Ada.Strings.Unbounded.Unbounded_String;   --  say: the words, teach: the word, bad: the line
      N    : Natural := 0;                             --  wait: ticks
   end record;
   package Word_Vectors is new Ada.Containers.Vectors (Positive, Positive);

   procedure Init (Seed : Int);                                  --  reads data/limits.txt (visit.*) and data/visit.txt; bonds back to 0
   procedure Begin_Session (N : Positive; E : Entity_Id);   --  a visit=1 session starts (counters of the visit)
   function Enabled return Boolean;                              --  visit.enabled
   function Default_Ticks return Natural;                        --  visit.ticks of data/visit.txt
   function Every return Positive;                               --  visit.every: a prompt every k-th tick

   --  One typed line (or a script line); "" is a wait 1.
   function Parse (Line : String) return Command;
   --  The recorded input: V<n> t=<tick> cmd=<say|teach|show|wait|leave> [n=<k>] h=<check> [text=<words>]
   function Input_Line (N : Positive; Tick : Int; C : Command) return String;
   procedure Parse_Input (L : String; N : out Natural; Tick : out Int; C : out Command; OK : out Boolean);   --  OK False: bad line or check

   --  Carry out a command at the end of Tick for wesen E (state before: Mood, Energy, open petitions Pets).  Answer: the A line (empty for
   --  wait / leave).  Learned: the words that E learned now (the caller files them in the words file and on the screen).
   procedure Apply (C : Command; E : Entity_Id; Tick : Int; N : Positive; Mood, Energy, Pets : Integer;
                    Answer : out Ada.Strings.Unbounded.Unbounded_String; Learned : out Word_Vectors.Vector);

   function Bond_Of (E : Entity_Id) return Integer;              --  the trust of E towards the human, bond_min .. bond_max
   function Talks return Natural;                                --  say commands of the visit so far
   function Commands return Natural;                             --  all commands of the visit so far
   function Visit_Session return Natural;                        --  number of the latest visit session, 0 if none yet
   --  One optional short line for the box of the players (data/preport.txt rbox.visit.*), "" if none.
   function Comment (Session : Natural; Players : Positive) return String;

   type Scene is record
      E : Entity_Id := 1;
      Tick : Int := 0;
      Index, Total : Natural := 0;                     --  the tick within the visit and the length of the session
      Mood, Energy, Location, Pets : Integer := 0;
      Diary : Ada.Strings.Unbounded.Unbounded_String;   --  the diary line of this tick
      World, Screen : Boolean := False;
      Prompt : Boolean := True;                         --  ask for a command now (else only the frame)
      Note : Ada.Strings.Unbounded.Unbounded_String;    --  one more line (help), "" if none
   end record;
   --  The whole frame (at most 23 lines of at most 79 characters), ending with the prompt if Scene.Prompt.
   function Frame (S : Scene) return String;
   function Leave_Text (E : Entity_Id) return String;
   function Help_Text return String;

end Sim_Visit;
