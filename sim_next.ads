--  Version: 0.001
--  The advice for the next run (nextticks=1 sessions; needs govern=1): at the last tick of every such session each wesen PROPOSES a tick
--  count from its own state (open and deferred petitions, unrest, low energy, a small Rule 30 'would like to see what happens' bump),
--  each player then DECIDES with a bounded rule (the mean of the proposals of the wesen it watches, pulled toward its own preference by a
--  fixed share; the rounding to the allowed set may lean toward what suits the player when its honesty is low) and the choices of the
--  players are combined by their median.  All numbers and the wording are data (data/ticks.txt, nextticks.* in data/limits.txt).
--  The result is a record line N<n> (diaries/nextticks.txt, replay-checked by diary_sim through Sim_Store, own hash salts 9820 .. 9824):
--  a changed, invented or removed line is DRIFT.  It is ADVICE only: it changes nothing in the simulation; make run uses it when TICKS
--  is omitted and nextticks.use = 1.  Pure functions of (seed, wesen/player, tick, salts) and of the replayed state.
--  PROOF-LATER: Importance 2/10, Urgency 2/10, SPARK2 (bounded integer arithmetic, hash dice, record parsing)
pragma Ada_2022;

with Sim_Util;
with Sim_World;

package Sim_Next is

   use Sim_Util;
   use Sim_World;

   type Ints is array (Entity_Id) of Integer;
   type Inputs is record
      Mood, Energy, Unrest, Open, Defer : Ints := [others => 0];
   end record;

   procedure Init (Seed : Int);   --  reads data/limits.txt (nextticks.*) and data/ticks.txt; nothing is started
   --  The advice at Tick (computed, nothing remembered); Round also remembers it and returns the record line.
   procedure Round (Tick : Int; Data : Inputs; Lines : in out Str_Vectors.Vector);
   function Rounds return Natural;
   function Last_Tick return Int;                 --  tick of the latest round, -1 before the first
   function Recommended return Natural;           --  the tick count of the latest round, 0 before the first
   --  The lines for the end box (display names, no frame): "Next run: ..." and the reason in a player's voice, of the advice at Tick
   --  (the latest round if it is at Tick, else computed now without recording anything); empty without nextticks.
   function Box_Lines (Tick : Int; Data : Inputs) return Str_Vectors.Vector;
   function View (Tick : Int; Data : Inputs) return Str_Vectors.Vector;   --  --next / make next (ids; the output layer maps names)
   function Digest_Line return String;            --  "3 rounds, last 400 (wesen 300/400/300/200)"

end Sim_Next;
