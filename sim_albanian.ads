--  Version: 0.002
--  Albanian of diary_sim (build 0.064, alb=1 sessions only; older sessions never call it, so they replay byte for byte).
--  The wesen find a book (data/sq_book.txt, Tatoeba sentences) in their first alb=1 session; nobody hands it over.  At the start
--  of every alb=1 session each wesen hears a few sentences of it in book order (albanian.hear_per_session, a die of its own per
--  step, salts 24001 ..), learns gender cues of the nouns it can identify through data/sq_noun_forms.txt (a definite singular in
--  -i / -u is masculine, in -a feminine; an article i / e after a singular noun: m / f) into a small table per wesen (noun
--  ending class x gender) and a bounded memory of nouns heard with a cue; then it says albanian.say_per_session short sentences
--  of its own (noun + article + adjective of data/sq_adj.txt), the article from memory, else from its ending counts (ties: i),
--  and one first-person sentence "jam i/e <adj>" when its gender (stamped into the session line) is m or f.
--  A held-back set of book nouns (albanian.held_pct percent, by a hash of the lemma) is never heard: a sentence with any form
--  of one is skipped; the first sentence a wesen says each session uses one, so they get tested.
--  Nothing here is scored: the report (scripts/alb_report.sh) checks the said sentences against data/sq_nouns.txt.  Nothing
--  touches the dice of the rest of the simulation, nor the diaries; the shared word counts never see Albanian.
--  State (checkpoint section "albanian", format 4): the found session, the book position, the ending table and the memory.
--  PROOF-LATER: Importance 3/10, Urgency 2/10, SPARK2 (bounded tables, counters, indices inside the book)
pragma Ada_2022;

with Ada.Streams;

with Sim_Util;

package Sim_Albanian is

   use Sim_Util;

   --  The data folder of the run (the one Load_Data read, before the start moves into the save folder): the book, the nouns,
   --  the adjectives and the genders come from there.  Unset: Data_Path.
   procedure Set_Data_Dir (Dir : String);

   procedure Reset;                              --  everything zero (a new save, or a checkpoint without the section)
   function Zero return Boolean;                 --  the state of Reset
   function Found return Natural;                --  the session that found the book (0: not yet)

   --  data/wesen_gender.txt as four characters in Entity_Id order: m, f, n (none) or u (unset, '-' in the file); "uuuu" without
   --  the file (letters only: the session line stays [a-z0-9= ])
   function Genders_Now return String;

   --  One alb=1 session N starting after tick Start: hearing, learning, saying.  Genders: the stamp of the session line.
   --  Lines gets the record lines of diaries/albanian.txt (B on the find, H, U, J); the caller writes them once.
   procedure Session (Seed : Int; N : Positive; Start : Int; Genders : String; Lines : in out Str_Vectors.Vector);

   --  the state for the checkpoint (state.ckpt section "albanian"): Save writes it, else it is read back
   procedure State_IO (S : not null access Ada.Streams.Root_Stream_Type'Class; Save : Boolean);

end Sim_Albanian;
