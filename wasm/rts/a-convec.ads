pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Containers;
with Ada.Finalization;
with Ada.Iterator_Interfaces;

generic
   type Index_Type is range <>;
   type Element_Type is private;
   with function "=" (Left, Right : Element_Type) return Boolean is <>;
package Ada.Containers.Vectors is
   pragma Preelaborate;

   subtype Extended_Index is Index_Type'Base range
     Index_Type'Base (Index_Type'Pos (Index_Type'First) - 1) .. Index_Type'Base'Last;
   No_Index : constant Extended_Index := Extended_Index'First;

   type Vector is tagged private
     with Constant_Indexing => Constant_Reference,
          Variable_Indexing => Reference,
          Default_Iterator  => Iterate,
          Iterator_Element  => Element_Type,
          Aggregate         => (Empty => Empty_Vector, Add_Unnamed => Append_One);
   pragma Preelaborable_Initialization (Vector);

   type Cursor is private;
   pragma Preelaborable_Initialization (Cursor);
   No_Element : constant Cursor;

   Empty_Vector : constant Vector;

   function Length (Container : Vector) return Count_Type;
   function Is_Empty (Container : Vector) return Boolean;
   function Contains (Container : Vector; Item : Element_Type) return Boolean;
   procedure Clear (Container : in out Vector);

   function First_Index (Container : Vector) return Extended_Index;
   function Last_Index (Container : Vector) return Extended_Index;
   function First_Element (Container : Vector) return Element_Type;
   function Last_Element (Container : Vector) return Element_Type;
   function Element (Container : Vector; Index : Index_Type) return Element_Type;
   function Element (Container : Vector; Position : Cursor) return Element_Type;

   procedure Replace_Element (Container : in out Vector; Index : Index_Type; New_Item : Element_Type);
   procedure Append_One (Container : in out Vector; New_Item : Element_Type);
   procedure Append (Container : in out Vector; New_Item : Element_Type) renames Append_One;
   procedure Append (Container : in out Vector; New_Item : Vector);
   procedure Append_Vector (Container : in out Vector; New_Item : Vector) renames Append;
   procedure Prepend (Container : in out Vector; New_Item : Element_Type);
   procedure Insert (Container : in out Vector; Before : Extended_Index; New_Item : Element_Type);
   procedure Delete_Last (Container : in out Vector; Count : Count_Type := 1);
   procedure Delete (Container : in out Vector; Index : Extended_Index; Count : Count_Type := 1);
   procedure Delete_First (Container : in out Vector; Count : Count_Type := 1);
   procedure Move (Target : in out Vector; Source : in out Vector);
   function To_Vector (New_Item : Element_Type; Length : Count_Type) return Vector;
   function "=" (Left, Right : Vector) return Boolean;

   type Constant_Reference_Type (Element : not null access constant Element_Type) is limited null record
     with Implicit_Dereference => Element;
   type Reference_Type (Element : not null access Element_Type) is limited null record
     with Implicit_Dereference => Element;

   function Constant_Reference (Container : aliased Vector; Index : Index_Type) return Constant_Reference_Type;
   function Reference (Container : aliased in out Vector; Index : Index_Type) return Reference_Type;
   function Constant_Reference (Container : aliased Vector; Position : Cursor) return Constant_Reference_Type;
   function Reference (Container : aliased in out Vector; Position : Cursor) return Reference_Type;

   function Has_Element (Position : Cursor) return Boolean;
   package Vector_Iterator_Interfaces is new Ada.Iterator_Interfaces (Cursor, Has_Element);
   function Iterate (Container : aliased Vector) return Vector_Iterator_Interfaces.Reversible_Iterator'Class;

   generic
      with function "<" (Left, Right : Element_Type) return Boolean is <>;
   package Generic_Sorting is
      procedure Sort (Container : in out Vector);
   end Generic_Sorting;

private
   type Element_Access is access all Element_Type;
   type Element_Array is array (Positive range <>) of Element_Access;
   type Element_Array_Access is access all Element_Array;

   type Vector is new Ada.Finalization.Controlled with record
      Data : Element_Array_Access;
      Len  : Natural := 0;
   end record;

   overriding procedure Adjust (Container : in out Vector);
   overriding procedure Finalize (Container : in out Vector);

   type Cursor is record
      Valid : Boolean := False;
      Index : Index_Type'Base := Index_Type'First;
   end record;

   No_Element : constant Cursor := (Valid => False, Index => Index_Type'First);
   Empty_Vector : constant Vector := (Ada.Finalization.Controlled with Data => null, Len => 0);
end Ada.Containers.Vectors;
