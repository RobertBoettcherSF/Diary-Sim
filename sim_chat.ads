--  Version: 0.001
--  The chat (B2): Robert types a line that starts with @ or /.  `@name text` speaks to one character, wesen, player or the observer
--  role; the character answers from the templates of data/chat.txt (chat.<id>.<intent>.<k>) using the real state (mood, energy, words,
--  what it asked for, its last petition, the decisions of the players).  `/word` is an order that only SHOWS something or controls the
--  run (/help /who /status /mood /energy /words /trend /clear /voices /pause /resume /quit); nothing here changes the simulation.
--  This unit is pure: Handle turns (a snapshot of the replayed state, the line number, the typed text) into the answer lines, with a hash
--  die (seed, line number, tick; salts 18100 .. 18299), so a replay reproduces every answer.  Every line (Robert's and the answers) is a
--  C line of diaries/chat.txt: C<n> t=<tick> who=<id> to=<id> h=<check> text=<text>; h= is a check number over the line (salt 18400).
--  diary_sim stores the lines record-first (Sim_Store) and verifies them on every replay: a changed, removed or invented line is DRIFT.
--  Later, NOT built: /story and portals.
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (name matching, template filling, bounded string building, hash dice)
pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Sim_Util;
with Sim_Voice;

package Sim_Chat is

   use Sim_Util;
   use Ada.Strings.Unbounded;

   type Kind_T is (Wesen, Player, Observer);
   type Quad is array (1 .. 4) of Integer;

   --  One character that can be addressed (the facts are those of the replayed state at the tick of the line).
   type Person is record
      Kind       : Kind_T := Wesen;
      Id, Name   : Unbounded_String;
      Present    : Boolean := True;               --  a fourth player is only there in a players4=1 session
      Facts      : Sim_Voice.Facts;               --  wesen: mood, energy, words, activity, place, newest word, topic, last decision, open petitions
      Word_List  : Unbounded_String;              --  wesen: the newest words, separated by commas ("" none)
      Watches    : Unbounded_String;              --  player: the name of the wesen it watches
      Watch_Mood, Watch_Energy, Stance : Integer := 0;
      Seen, Granted, Refused, Open : Natural := 0;   --  player: petitions seen, granted, refused, still open (of its wesen)
   end record;
   package Person_Vectors is new Ada.Containers.Vectors (Positive, Person);

   --  The mood and energy of the four wesen every chat.trend_step ticks (for /trend).
   type Sample is record
      Tick : Int := 0;
      Mood, Energy : Quad := [others => 0];
   end record;
   package Sample_Vectors is new Ada.Containers.Vectors (Positive, Sample);

   type World is record
      Tick : Int := 0;
      Session, Sessions : Natural := 0;
      People : Person_Vectors.Vector;             --  the 4 wesen, then the 4 players, then the observer
      Samples : Sample_Vectors.Vector;
   end record;

   type Effect_T is (None, Pause, Resume, Quit, Clear, Voices_On, Voices_Off);   --  what the run does for an order (live only; never in a replay)
   type Reply is record
      Who, To_Id, Text : Unbounded_String;
   end record;
   package Reply_Vectors is new Ada.Containers.Vectors (Positive, Reply);
   type Result is record
      To      : Unbounded_String;                 --  the id the typed line was meant for (a character, or the system id for orders and errors)
      Replies : Reply_Vectors.Vector;
      Effect  : Effect_T := None;
   end record;

   procedure Init (Seed : Int);
   function Enabled return Boolean;                 --  chat.enabled: new sessions carry chat=1
   function Me return String;                       --  the id of Robert in chat.txt lines
   function Handle (W : World; N : Positive; Text : String) return Result;

   --  A stored line: C<n> t=<tick> who=<id> to=<id> h=<check> text=<text>
   function Line_Of (N : Positive; Tick : Int; Who, To_Id, Text : String) return String;
   type Parsed is record
      N : Natural := 0;
      Tick : Int := 0;
      Who, To_Id, Text : Unbounded_String;
   end record;
   procedure Parse_Line (L : String; P : out Parsed; OK : out Boolean);   --  OK False: not a C line, or the check number does not fit

end Sim_Chat;
