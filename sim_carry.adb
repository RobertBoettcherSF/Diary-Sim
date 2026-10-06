--  Version: 0.001
--  Word carrying (carry=1 sessions): see sim_carry.ads.
pragma Ada_2022;

with Sim_Ckpt;
with Sim_Util;

package body Sim_Carry is

   use Sim_Util;

   type Favour_Table is array (Entity_Id, Entity_Id) of Natural;
   type Standing_Table is array (Entity_Id) of Natural;

   On : Boolean := False;
   N_Lessons, N_Acts, N_Spent : Natural := 0;
   Fav : Favour_Table := [others => [others => 0]];
   Stand : Standing_Table := [others => 0];

   Loaded : Boolean := False;
   T_Relief, T_Energy, T_Mood : Integer := 0;
   T_Pull, T_Cap, T_Gain, T_Spend, T_Help : Natural := 0;

   procedure Load is
      function Nat (Key : String; Default : Int) return Natural is (Natural (Int'Max (0, Int'Min (100_000, Limit (Key, Default)))));
      function Whole (Key : String; Default : Int) return Integer is (Integer (Int'Max (-1000, Int'Min (1000, Limit (Key, Default)))));
   begin
      if Loaded then return; end if;
      T_Relief := Whole ("carry.relief_energy", 20);
      T_Energy := Whole ("carry.teacher_energy", 60);
      T_Mood := Whole ("carry.teacher_mood", 0);
      T_Pull := Natural'Min (100, Nat ("carry.pull_pct", 30));
      T_Cap := Nat ("carry.session_cap", 24);
      T_Gain := Natural'Min (20, Nat ("carry.mood_gain", 2));
      T_Spend := Natural'Min (100, Nat ("carry.spend_pct", 50));
      T_Help := Natural'Min (20, Nat ("carry.help_energy", 1));
      Loaded := True;
   end Load;

   procedure Reset is
   begin
      On := False;
      N_Lessons := 0;
      N_Acts := 0;
      N_Spent := 0;
      Fav := [others => [others => 0]];
      Stand := [others => 0];
   end Reset;

   function Zero return Boolean is
     (not On and then N_Lessons = 0 and then N_Acts = 0 and then N_Spent = 0
      and then (for all L in Entity_Id => (for all T in Entity_Id => Fav (L, T) = 0))
      and then (for all E in Entity_Id => Stand (E) = 0));

   procedure Begin_Session (On : Boolean) is
   begin
      Sim_Carry.On := On;
      N_Lessons := 0;
   end Begin_Session;

   function Active return Boolean is (On);
   function Lessons return Natural is (N_Lessons);
   function Acts return Natural is (N_Acts);
   function Spent return Natural is (N_Spent);
   function Favour (Learner, Teacher : Entity_Id) return Natural is (Fav (Learner, Teacher));
   function Standing (E : Entity_Id) return Natural is (Stand (E));

   function Open_Favours return Natural is
      N : Natural := 0;
   begin
      for L in Entity_Id loop
         for T in Entity_Id loop N := N + Fav (L, T); end loop;
      end loop;
      return N;
   end Open_Favours;

   function Relief_Energy return Integer is begin Load; return T_Relief; end Relief_Energy;
   function Teacher_Energy return Integer is begin Load; return T_Energy; end Teacher_Energy;
   function Teacher_Mood return Integer is begin Load; return T_Mood; end Teacher_Mood;
   function Pull_Pct return Natural is begin Load; return T_Pull; end Pull_Pct;
   function Session_Cap return Natural is begin Load; return T_Cap; end Session_Cap;
   function Mood_Gain return Natural is begin Load; return T_Gain; end Mood_Gain;
   function Spend_Pct return Natural is begin Load; return T_Spend; end Spend_Pct;
   function Help_Energy return Natural is begin Load; return T_Help; end Help_Energy;

   function Target return Natural is
      Best : Natural := 0;
      Most : Natural := 0;
   begin
      for E in Entity_Id loop
         declare
            M : constant Natural := Missing_By_One (E);
         begin
            if M > Most then Most := M; Best := Natural (E); end if;
         end;
      end loop;
      return Best;
   end Target;

   procedure Carried (Teacher, Learner : Entity_Id) is
   begin
      Fav (Learner, Teacher) := Fav (Learner, Teacher) + 1;
      Stand (Teacher) := Stand (Teacher) + 1;
      N_Lessons := N_Lessons + 1;
      N_Acts := N_Acts + 1;
   end Carried;

   function Debtor (Teacher : Entity_Id) return Natural is
      Best : Natural := 0;
      Most : Natural := 0;
   begin
      for L in Entity_Id loop
         if L /= Teacher and then Fav (L, Teacher) > Most then Most := Fav (L, Teacher); Best := Natural (L); end if;
      end loop;
      return Best;
   end Debtor;

   procedure Spend (Learner, Teacher : Entity_Id) is
   begin
      if Fav (Learner, Teacher) > 0 then
         Fav (Learner, Teacher) := Fav (Learner, Teacher) - 1;
         N_Spent := N_Spent + 1;
      end if;
   end Spend;

   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean) is
      procedure IO is new Sim_Ckpt.IO (Natural);
      procedure IO is new Sim_Ckpt.IO (Boolean);
      procedure IO is new Sim_Ckpt.IO (Favour_Table);
      procedure IO is new Sim_Ckpt.IO (Standing_Table);
   begin
      IO (S, Save, On);
      IO (S, Save, N_Lessons);
      IO (S, Save, N_Acts);
      IO (S, Save, N_Spent);
      IO (S, Save, Fav);
      IO (S, Save, Stand);
   end State_IO;

end Sim_Carry;
