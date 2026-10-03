--  Version: 0.001
--  Chess for diary_sim (chess=1 sessions): a legal-move generator with the full rules (castling, en passant,
--  promotion, check, checkmate, stalemate, the 50-move rule), coordinate and ICCF notation, and a move chooser
--  whose strength runs from a random legal move to a 1-ply lookahead.  Plain integer arithmetic on a 64-cell board,
--  no state: every function is a pure function of its arguments (and, for the chooser, of hash (seed, entity, tick,
--  salt), so a replay chooses the same move).  Threefold repetition needs the history, so the caller keeps the
--  position keys (Key) and decides.  The move generator is tested with perft counts (data/chess.txt,
--  diary_sim --perft).
--  PROOF-LATER: Importance 5/10, Urgency 3/10, SPARK2 (the move generator: array bounds, no overflow, a perft proof)
pragma Ada_2022;

with Interfaces;
with Sim_Util;

package Sim_Chess is

   subtype Square is Integer range 0 .. 63;   --  a1 = 0, b1 = 1, ..., h1 = 7, a2 = 8, ..., h8 = 63
   type Piece_Kind is (None, Pawn, Knight, Bishop, Rook, Queen, King);
   type Colour is (White, Black);
   type Cell is record
      Kind : Piece_Kind := None;
      Side : Colour := White;
   end record;
   type Board_Array is array (Square) of Cell;
   type Rights is array (1 .. 4) of Boolean;   --  white king side, white queen side, black king side, black queen side

   type Position is record
      Board : Board_Array;
      To_Move : Colour := White;
      Castle : Rights := [others => False];
      Ep : Integer := -1;           --  the square a pawn passed over with a double step, else -1
      Half : Natural := 0;          --  plies since a pawn move or a capture
      Full : Positive := 1;         --  the move number
   end record;

   type Move is record
      From, To : Square := 0;
      Promo : Piece_Kind := None;   --  Knight .. Queen when a pawn promotes
   end record;
   type Move_Array is array (1 .. 256) of Move;
   type Move_List is record
      Items : Move_Array;
      Count : Natural := 0;
   end record;

   type Game_State is (Ongoing, Checkmate, Stalemate, Fifty_Moves);

   function Start return Position;
   function From_Fen (Fen : String; OK : out Boolean) return Position;
   function To_Fen (P : Position) return String;

   function Legal (P : Position) return Move_List;
   function Play (P : Position; M : Move) return Position;   --  M must be legal in P
   function In_Check (P : Position; Side : Colour) return Boolean;
   function State_Of (P : Position) return Game_State;       --  of the side to move

   function Coord (M : Move) return String;   --  e2e4, e7e8q
   function Iccf (M : Move) return String;    --  5254, 5758 + 1 / 2 / 3 / 4 for q / r / b / n: 57581
   function Same (A, B : Move) return Boolean;
   function Key (P : Position) return Interfaces.Unsigned_64;   --  one value per position (repetition test)
   function Material (P : Position; Side : Colour) return Integer;   --  balance for Side: pawns 1, knights and bishops 3, rooks 5, queens 9

   function Perft (P : Position; Depth : Natural) return Natural;   --  the number of leaf positions

   --  A move by hash dice.  Strength 0 .. 100 is the chance in percent that the move is the best of a 1-ply look-ahead
   --  (material after the move, mate wins, stalemate is level); otherwise a random legal move.  Salts 9500 .. 9510.
   function Choose (P : Position; Seed : Sim_Util.Int; Entity : Positive; Tick : Sim_Util.Int; Strength : Natural) return Move;

end Sim_Chess;
