--  Version: 0.001
--  The robot of diary_sim (robot=1 sessions; needs screen=1): one world thing with a position, a heading, a battery and a short
--  command list (data/robot.txt: go <north|east|south|west>, turn <left|right>, look, pick, push).  A wesen steers it by PINNING the
--  command words on its screen (Sim_Screen.Pin_Command): only words the wesen already knows can be pinned, so the robot ties to word
--  growth (a wesen learns the command words by standing within reach of the robot, or from other screens).  The robot acts when its
--  delay is over (robot.delay + dice; one command per robot.gap ticks), pays battery for it, and writes its 5x5 camera view back to
--  the controller's screen.  A wesen that reads the controller's screen gets the view and may steer too, so several can steer one
--  robot.  A command it cannot parse (an unknown word, a missing direction) or cannot do (battery, hands full, nothing there) puts an
--  error line on the screen.  The battery is recharged at a landmark (and trickles slowly elsewhere).
--  Every step is a Q line (without key and tick) that diary_sim stores in diaries/robot.txt (Sim_Store) and the replay verifies.
--  Pure functions of (seed, wesen, tick, salts 9600 .. 9699) and the replayed state.
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (command parsing, bounded battery arithmetic)
pragma Ada_2022;

with Ada.Strings.Unbounded;
with Sim_Util;
with Sim_World;

package Sim_Robot is

   use Sim_Util;
   use Sim_World;

   procedure Init (Seed : Int);   --  not started; reads data/limits.txt (robot.*)
   --  The first robot=1 session: place the robot, create the command words, fill the battery.
   procedure Begin_Life (Tick : Int);
   function Started return Boolean;

   --  Once per tick before the wesen: charge, and carry out the pending command when it is due.  Lines: record lines.
   procedure Tick_Begin (Tick : Int; Lines : in out Str_Vectors.Vector);
   --  The step of wesen E: contact with the robot (may teach a command word: Learned), may pin and send a command.
   procedure Control (E : Entity_Id; Tick : Int; Lines : in out Str_Vectors.Vector; Learned : in out Str_Vectors.Vector;
                      Detail : in out Ada.Strings.Unbounded.Unbounded_String);
   --  Viewer read the screen of Owner: if Owner steers, Viewer gets the camera view and may steer too.
   procedure Share (Viewer, Owner : Entity_Id; Tick : Int; Lines : in out Str_Vectors.Vector);
   --  What the robot answered E since its last step (once), "" if nothing.
   function Take_Reply (E : Entity_Id) return String;
   function Steers (E : Entity_Id; Tick : Int) return Boolean;

   --  Views.
   function View (Tick : Int) return Str_Vectors.Vector;     --  state, camera, controllers (--robot / make robot)
   function Report return Str_Vectors.Vector;                --  the end report block
   function Count_Commands return Natural;
   function Count_Errors return Natural;

end Sim_Robot;
