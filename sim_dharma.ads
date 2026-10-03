--  Version: 0.003
--  The Buddhism layer of diary_sim, RECORD-FIRST: karma, reincarnation values, attachment
--  (unrest), the commitment ladder with an anchor, awareness ("feels watched"), and the three
--  in-sim PLAYERS that sit between the wesen and Robert (the real player) and write him summary
--  reports (the inbox).  None of it feeds back into the action table or the existing dice, so
--  stored diaries stay valid: the numbers only appear in diaries/sessions.txt (D, C, Y lines),
--  diaries/inbox.txt, the reports, debug.txt and the menu.  Every roll here has its own hash
--  salt (5000 and up).  The state is rebuilt by replay from tick 1, like the world.
--  Tradition labels (realms, ladder rungs, anchor) are flavour text in data/dharma.txt only.
--  Numbers: data/karma.txt; players: data/players.txt; wording: data/dharma.txt.
--  Standard library only.
pragma Ada_2022;

with Sim_Util, Sim_World;

package Sim_Dharma is

   use Sim_Util, Sim_World;

   --  Players 1 .. 3 exist from the start; player 4 joins with the first players4=1 session (Begin_Life) and takes over the
   --  wesen named in data/players.txt (player.4.takes).  Last_Player says how many are in the current session (3 or 4).
   type Player_Id is range 1 .. 4;
   --  say: from Robert to one wesen; say_all: to all four; relay: to a player, who may pass it
   --  on to the wesen it watches; answer: to all players (an answer to the latest collective petition).
   type Address_Kind is (Say, Say_All, Relay, Answer);
   type Energies is array (Entity_Id) of Integer;

   --  Rebuilds the state for a new replay (call after Sim_World.Init and after the data/ keys are loaded).
   procedure Init (Seed : Int);

   function Player_Name (P : Player_Id) return String;
   function Player_Info (P : Player_Id) return String;   --  name (role): goal
   function Find_Player (Text : String) return Natural;   --  0: no such player
   function Find_Wesen (Text : String) return Natural;    --  0: no such wesen
   function Watcher (E : Entity_Id) return Player_Id;     --  the player that watches E (in this session)
   function Chess_Watcher (E : Entity_Id) return Player_Id;   --  the player of players.txt 'watches' (players 1 .. 3): the chess opponents
   function Last_Player return Player_Id;                 --  3, or 4 in a players4=1 session

   --  ---- per tick (record only) -------------------------------------------------------------
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (counters, clamps, integer arithmetic)
   procedure Deed (E : Entity_Id; A : Action; Pre_Energy : Integer; Taught, Coined : Boolean);
   --  An address from Robert (diaries/says.txt): To = wesen id (Say) or player id (Relay), else 0.
   --  It takes effect from tick Tick + 1.  Text is kept (cut) for the inbox.
   procedure Add_Address (Tick : Int; Kind : Address_Kind; To : Natural; Text : String);
   procedure Tick_Begin (Tick : Int);   --  applies the addresses of Tick - 1
   procedure Tick_End (Tick : Int);     --  attachment windows, awareness decay

   --  ---- sessions ---------------------------------------------------------------------------
   --  A life begins with a session: the four values are rolled (salts 5001 .. 5004), biased by
   --  the karma.  Dharma = False (a session of an older diary): no rebirth move.
   --  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (clamped sums of hashed rolls)
   procedure Begin_Life (Seed, Tick : Int; Session : Positive; Locations : Positive; Dharma : Boolean; Players4 : Boolean := False);
   function Rebirth_Location (E : Entity_Id) return Integer;   --  -1: none (liberated wesen only)
   procedure Mark_Start;   --  remembers the numbers for the "since the last session" block

   --  The end of a session at Tick: karma, liberation, ladder, collective petition, player
   --  state, inbox.  Returns the lines for sessions.txt: D (per wesen), C, Y (per player).
   --  A replay calls it at the same tick and compares the lines (a difference is DRIFT).
   --  PROOF-LATER: Importance 4/10, Urgency 3/10, SPARK2 (ranking, tallies, text assembly)
   function End_Life (Seed, Tick : Int; Session : Positive; Votes : Kalpa_Votes; Energy : Energies)
     return Str_Vectors.Vector;

   --  ---- views ------------------------------------------------------------------------------
   function Table_Lines return Str_Vectors.Vector;   --  the dharma table of the last End_Life
   function Since_Lines return Str_Vectors.Vector;   --  changes since Mark_Start
   function Debug_Line return String;                --  one short line for debug.txt
   function Address_Counts (From_Tick : Int) return String;
   --  The first inbox.show lines of each player from the latest End_Life (the console sample).
   function Latest_Report return Str_Vectors.Vector;
   function Inbox_Count return Natural;
   function Inbox_Line (N : Positive) return String;
   function Inbox_Tail (Max : Positive) return Str_Vectors.Vector;   --  the newest Max lines
   --  govern=1: the personality the governance dice read (Rule 30 core), the workload, the tone variant of a report
   function Warm_Of (P : Player_Id) return Integer;    --  -50 .. +50: generous (+) or strict (-)
   function Brev_Of (P : Player_Id) return Integer;    --  0 .. 100: how curt (strict) the player is
   function Attn_Of (P : Player_Id) return Integer;    --  0 .. 100: workload / awareness of its wesen
   function Variant_Of (P : Player_Id) return String;  --  "calm" | "plain" | "alarm": the wording of its reports
   --  The governance lines a player must put into its report at the next End_Life (never omitted, wording may differ):
   --  the first line of a player is its counter line (shown in the end report), all lines go to the inbox.
   procedure Set_Govern_Report (P : Player_Id; Lines : Str_Vectors.Vector);
   function Last_Petition return String;   --  "C3 more_rest 3/4", "" before the first

end Sim_Dharma;
