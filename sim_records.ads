--  Version: 0.001
--  The raw records of diary_sim (records=1 sessions; needs govern=1): WHAT WAS VOTED, WHAT WAS ASKED, which words were agreed, what was
--  announced.  Four record files in diaries/, all derived from the replay and compared with it by diary_sim through Sim_Store (a changed,
--  invented or removed line is DRIFT; own hash salts 14000 .. 14399):
--    votes.txt          V<n>  one line per vote: petition decisions of the players (the D records, weight = trust, st = standing), the
--                             adherence of a losing party in a trial, the session-length votes, the favourite words, the votes on the
--                             collective petition, the advice for the next run, and the votes of the players on new words.
--    petitions.txt      P<n>  one line per petition that reached an answer (n = the petition number): who, what, which lever, who decided.
--    dictionary.txt     L<n>  the words the wesen proposed and the players voted on: status A (agreed) or R (rejected), with the tally.
--    announcements.txt  A<n>  what a wesen or a player told everybody it expects.
--  New words: a wesen that coins a word proposes it; a wesen that files a petition may add the proposal of a made-up name for a word it
--  knows (the world's own vocabulary is not changed: the dictionary is the OFFICIAL list).  At the end of a session the players vote
--  (majority of the players, ties are rejected; at most rec.words_per_session votes and rec.agree_cap agreed words per session).
--  An announcement raises awareness: the other wesen hear it (their mood moves a few points toward the speaker's), the deciding players
--  weigh a petition of the announced topic a little more; it costs the announcer standing and may draw a counter-reaction (a lower
--  chance for its own petitions of that topic).  Every chance and number is in data/limits.txt (rec.*), the wording in data/records.txt.
--  Records sessions also keep the word vote clean (Sim_World.Set_Clean: no chess moves as favourite words, no coined word that
--  contains its own part).  Pure functions of (seed, wesen/player, tick, salts) and of the replayed state; nothing runs without records=1.
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (bounded integer arithmetic, hash dice, record parsing)
pragma Ada_2022;

with Sim_Util;
with Sim_World;

package Sim_Records is

   use Sim_Util;
   use Sim_World;

   type Trust_Array is array (Entity_Id) of Integer;

   procedure Init (Seed : Int);                            --  forgets everything (a new replay); reads nothing yet
   --  A session begins (every session, with or without the marker): sets the per-session counters and the clean word vote.
   procedure Begin_Session (N : Positive; Start : Int; On : Boolean);
   function Active return Boolean;

   --  Lines of other records, verified by the caller: they become vote and petition lines.
   procedure From_Decision (Line : String);   --  a D line of govern.txt
   procedure From_Trial (Line : String);      --  a T line of trials.txt
   procedure From_Advice (Line : String);     --  an N line of nextticks.txt
   procedure Length_Votes (Tick : Int; Votes : Kalpa_Votes);   --  the wesen's votes for the length of the session that starts at Tick

   --  Once per tick after the steps: new coined words become proposals.
   procedure Scan_Coined (Tick : Int);
   --  E filed a petition of Topic at Tick in the given mood: it may announce its wish and may propose a new word.
   procedure Note_Petition (E : Entity_Id; Tick : Int; Topic : String; Mood : Integer);
   --  The end of a session at Tick: favourite words (4 texts, "-" for none), the C line, then the vote on the proposed words and the
   --  announcements of the players (Concern: the topic each player was asked about most, by player number, "" if none).
   procedure Session_End (Tick : Int; Favourites : Str_Vectors.Vector; C_Line : String; Trust : Trust_Array; Concern : Str_Vectors.Vector);

   function Shift (E : Entity_Id; Topic : String; Tick : Int) return Integer;   --  points added to the decision score of a petition of E
   function Take_Mood (E : Entity_Id) return Integer;    --  mood of what E heard since its last step, handed over once
   function Take_Cost (E : Entity_Id) return Natural;    --  standing E's watching player lost by announcing, handed over once

   --  The new lines since the last call (the caller compares / appends them).
   procedure Drain (Votes, Pets, Dict, Notes : in out Str_Vectors.Vector);   --  Notes: the announcements

   function Box_Line (Players : Positive) return String;      --  one line of a player about this session, "" if nothing happened
   function Divergence return Str_Vectors.Vector;             --  make divergence: official reports against the raw records
   function Dictionary return Str_Vectors.Vector;             --  make dictionary: the official word list
   function Counts return String;                              --  "3 agreed, 2 rejected, 1 waiting, 4 announced" (all sessions)

end Sim_Records;
