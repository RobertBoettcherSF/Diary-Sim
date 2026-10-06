--  Version: 0.003
--  The state checkpoint of a save (state.ckpt, build 0.058): helpers only, the content is written by diary_sim and the
--  modules (their State_IO).  A memory stream (the whole payload is built in memory and written in one block), a fast
--  64-bit hash (FNV-1a), and the fingerprint of a record file: its size and two hashes over its first Size bytes, the
--  last 64 KB and 32 sample blocks of 4 KB spread over the file.  The record files only grow (append-only), so a later
--  file is still "the same" as long as its first Size bytes are; the next start then replays only the ticks after
--  the checkpoint.  Reading 64 KB + 128 KB per file is cheap on a 1 GB save (a full hash would read every byte).
--  0.003 (build 0.059): the tagged sections of format 2 (a section head: tag, byte length and hash of the body, docs/CHECKPOINT.md),
--  and the data prints: one hash per rule file of data/ (the text-only files are left out, they never touch the state).
pragma Ada_2022;

with Ada.Streams;
with Interfaces;
with Sim_Util;

package Sim_Ckpt is

   use Ada.Streams;

   type Buffer_Access is access Stream_Element_Array;

   --  Write appends, Read takes from the read position (End_Error at the end).
   type Mem_Stream is new Root_Stream_Type with record
      Buf  : Buffer_Access;
      Last : Stream_Element_Offset := 0;   --  bytes held
      Pos  : Stream_Element_Offset := 0;   --  bytes read
   end record;
   overriding procedure Read (S : in out Mem_Stream; Item : out Stream_Element_Array; Last : out Stream_Element_Offset);
   overriding procedure Write (S : in out Mem_Stream; Item : Stream_Element_Array);
   procedure Clear (S : in out Mem_Stream);       --  frees the buffer
   procedure Rewind (S : in out Mem_Stream);      --  read from the start again
   function Length (S : Mem_Stream) return Stream_Element_Offset is (S.Last);

   subtype Hash_T is Interfaces.Unsigned_64;
   Hash_Start : constant Hash_T := 16#CBF2_9CE4_8422_2325#;
   function Hash (A : Stream_Element_Array; H : Hash_T := Hash_Start) return Hash_T;
   function Hash_Of (S : Mem_Stream; From, To : Stream_Element_Offset) return Hash_T;   --  bytes From .. To (1-based)
   function Hex (H : Hash_T) return String;   --  16 hex digits

   --  "<tail>-<samples>" over the first Size bytes of the file ("" when it is shorter or cannot be read); a file of up to 1 MB
   --  (the human inputs) is hashed whole.
   function File_Print (Path : String; Size : Long_Long_Integer) return String;
   function File_Size (Path : String) return Long_Long_Integer;   --  -1: missing

   --  The record files of the save folder (the current folder): every file in diaries/ and entities/*/, sorted (not diaries/inbox.txt,
   --  a view the program rewrites, and no *.tmp).
   procedure Record_Files (Into : in out Sim_Util.Str_Vectors.Vector);

   --  The data files of the checkpoint (build 0.059): "name hash" per *.txt file of Dir that may feed the state (sorted); the display
   --  text files (Is_Text_Only) are left out, and so are comment and blank lines (a changed comment is no changed rule).
   function Is_Text_Only (Name : String) return Boolean;
   procedure Data_Prints (Dir : String; Into : in out Sim_Util.Str_Vectors.Vector);
   function Lines_Hash (L : Sim_Util.Str_Vectors.Vector) return String;   --  one hash over lines

   --  Format 2: every section of the payload is a head of Sect_Head_Len bytes (the tag, 8 characters padded with blanks, then the
   --  byte length and the FNV-1a hash of the body, each 8 bytes little-endian) and the body.  Section_Begin writes the head with
   --  room for the length and hash, Section_End fills them in from the body written since.  Section_Head reads a head at byte At + 1.
   Tag_Len : constant := 8;
   Sect_Head_Len : constant := 24;
   procedure Section_Begin (S : in out Mem_Stream; Tag : String; At_B : out Stream_Element_Offset);
   procedure Section_End (S : in out Mem_Stream; At_B : Stream_Element_Offset);
   procedure Section_Head (S : Mem_Stream; At_B : Stream_Element_Offset; Tag : out String; Len : out Long_Long_Integer; H : out Hash_T;
                           OK : out Boolean);   --  OK = False: the head runs past the end
   function Pad_Tag (Tag : String) return String;   --  8 characters

   --  One variable of a State_IO: written (Save) or read back.
   generic
      type T is private;
   procedure IO (S : not null access Root_Stream_Type'Class; Save : Boolean; X : in out T);

   --  Writes Head (text) and then the payload bytes of S to Path (through Path.tmp and a rename).
   procedure Write_File (Path, Head : String; S : Mem_Stream);
   --  Reads the whole file: the text up to and with the line "end", and the rest as the payload in S.
   procedure Read_File (Path : String; Head : out Sim_Util.Str_Vectors.Vector; S : in out Mem_Stream; OK : out Boolean);

end Sim_Ckpt;
