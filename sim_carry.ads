--  Version: 0.001
--  Word carrying of diary_sim (build 0.061, carry=1 sessions only; older sessions never call it, so they replay byte for byte).
--  The wesen plan it among themselves; no player (god) takes part and no grant is credited:
--    target   the wesen missing the most of the words every other wesen knows (Sim_World.Missing_By_One; any number of wesen)
--    pull     a wesen with spare energy and a low mood teaches the target one of those words (bounded per session)
--    relief   a wesen below the relief energy rests instead of talking (teaching)
--    reward   the learner owes the teacher a favour (per pair) and the teacher gains standing; being useful lifts its mood a little
--    favour   later, when the teacher works, a debtor helps: the work costs no mood and half the energy that tick, the debtor
--             pays a little energy, and the favour is spent
--  Tunables: data/limits.txt carry.* (read once).  State (checkpoint section "carry", format 3): Active, Lessons, Acts, Spent,
--  the favours and the standing.
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (counters, argmax with the lowest id on ties)
pragma Ada_2022;

with Ada.Streams;

with Sim_World;

package Sim_Carry is

   use Sim_World;

   procedure Reset;                              --  everything zero (a new save, or a checkpoint without the section)
   function Zero return Boolean;                 --  the state of Reset
   procedure Begin_Session (On : Boolean);       --  a session starts: carry=1 or not; the lesson count of the session is 0

   function Active return Boolean;
   function Lessons return Natural;              --  carried lessons in the current session
   function Acts return Natural;                 --  all carried lessons
   function Spent return Natural;                --  all favours returned
   function Favour (Learner, Teacher : Entity_Id) return Natural;   --  open favours Learner owes Teacher
   function Open_Favours return Natural;
   function Standing (E : Entity_Id) return Natural;

   --  the tunables
   function Relief_Energy return Integer;        --  below: rest instead of teaching (20)
   function Teacher_Energy return Integer;       --  a teacher has at least (60)
   function Teacher_Mood return Integer;         --  ... and a mood of at most (0)
   function Pull_Pct return Natural;             --  the die of the pull (30)
   function Session_Cap return Natural;          --  carried lessons per session, all teachers (24)
   function Mood_Gain return Natural;            --  the teacher's mood per carried lesson (2)
   function Spend_Pct return Natural;            --  the die of a debtor's help (50)
   function Help_Energy return Natural;          --  what the help costs the debtor (1)

   --  The wesen missing the most words known by all the others (lowest id on a tie), 0: nobody misses one.
   function Target return Natural;

   procedure Carried (Teacher, Learner : Entity_Id);   --  one lesson: a favour, standing, the counts
   function Debtor (Teacher : Entity_Id) return Natural;   --  who owes Teacher the most favours (lowest id on a tie), 0: nobody
   procedure Spend (Learner, Teacher : Entity_Id);

   --  the state for the checkpoint (state.ckpt section "carry"): Save writes it, else it is read back
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean);

end Sim_Carry;
