pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Containers;
with Ada.Finalization;
with Ada.Iterator_Interfaces;

generic
   type Key_Type is private;
   type Element_Type is private;
   with function Hash (Key : Key_Type) return Hash_Type;
   with function Equivalent_Keys (Left, Right : Key_Type) return Boolean;
   with function "=" (Left, Right : Element_Type) return Boolean is <>;
package Ada.Containers.Hashed_Maps is
   pragma Preelaborate;

   type Map is tagged private
     with Constant_Indexing => Constant_Reference,
          Variable_Indexing => Reference;
   pragma Preelaborable_Initialization (Map);

   type Cursor is private;
   pragma Preelaborable_Initialization (Cursor);
   No_Element : constant Cursor;

   function Length (Container : Map) return Count_Type;
   function Is_Empty (Container : Map) return Boolean;
   procedure Clear (Container : in out Map);
   function Contains (Container : Map; Key : Key_Type) return Boolean;
   function Find (Container : Map; Key : Key_Type) return Cursor;
   function Element (Container : Map; Key : Key_Type) return Element_Type;
   function Element (Container : Map; Position : Cursor) return Element_Type;
   function Element (Position : Cursor) return Element_Type;
   function Key (Position : Cursor) return Key_Type;
   procedure Insert (Container : in out Map; Key : Key_Type; New_Item : Element_Type);
   procedure Include (Container : in out Map; Key : Key_Type; New_Item : Element_Type);
   procedure Replace (Container : in out Map; Key : Key_Type; New_Item : Element_Type);
   procedure Delete (Container : in out Map; Key : Key_Type);
   procedure Exclude (Container : in out Map; Key : Key_Type);

   type Constant_Reference_Type (Element : not null access constant Element_Type) is limited null record
     with Implicit_Dereference => Element;
   type Reference_Type (Element : not null access Element_Type) is limited null record
     with Implicit_Dereference => Element;

   function Constant_Reference (Container : aliased Map; Key : Key_Type) return Constant_Reference_Type;
   function Reference (Container : aliased in out Map; Key : Key_Type) return Reference_Type;
   function Constant_Reference (Container : aliased Map; Position : Cursor) return Constant_Reference_Type;
   function Reference (Container : aliased in out Map; Position : Cursor) return Reference_Type;
   function Has_Element (Position : Cursor) return Boolean;

   package Map_Iterator_Interfaces is new Ada.Iterator_Interfaces (Cursor, Has_Element);
   function Iterate (Container : aliased Map) return Map_Iterator_Interfaces.Reversible_Iterator'Class;

private
   type Key_Access is access Key_Type;
   type Elem_Access is access all Element_Type;
   type Node;
   type Node_Access is access all Node;
   type Node is record
      Key  : Key_Access;
      Elem : Elem_Access;
      Next : Node_Access;
      Ord  : Natural := 0;
   end record;
   type Bucket_Array is array (Positive range <>) of Node_Access;
   type Bucket_Access is access Bucket_Array;
   type Order_Array is array (Positive range <>) of Node_Access;
   type Order_Access is access Order_Array;

   type Map is new Ada.Finalization.Controlled with record
      Buckets : Bucket_Access;
      Order   : Order_Access;
      Len     : Natural := 0;
   end record;

   overriding procedure Adjust (Container : in out Map);
   overriding procedure Finalize (Container : in out Map);

   type Cursor is record
      Node : Node_Access := null;
   end record;
   No_Element : constant Cursor := (Node => null);
end Ada.Containers.Hashed_Maps;
