pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Containers;
with Ada.Finalization;

generic
   type Element_Type (<>) is private;
   with function Hash (Element : Element_Type) return Hash_Type;
   with function Equivalent_Elements (Left, Right : Element_Type) return Boolean;
   with function "=" (Left, Right : Element_Type) return Boolean is <>;
package Ada.Containers.Indefinite_Hashed_Sets is
   pragma Preelaborate;

   type Set is tagged private;
   pragma Preelaborable_Initialization (Set);

   function Length (Container : Set) return Count_Type;
   function Is_Empty (Container : Set) return Boolean;
   procedure Clear (Container : in out Set);
   function Contains (Container : Set; Item : Element_Type) return Boolean;
   procedure Insert (Container : in out Set; New_Item : Element_Type);
   procedure Include (Container : in out Set; New_Item : Element_Type);
   procedure Delete (Container : in out Set; Item : Element_Type);
   procedure Exclude (Container : in out Set; Item : Element_Type);

private
   type Element_Access is access Element_Type;
   type Node;
   type Node_Access is access Node;
   type Node is record
      Item : Element_Access;
      Next : Node_Access;
   end record;
   type Bucket_Array is array (Positive range <>) of Node_Access;
   type Bucket_Access is access Bucket_Array;

   type Set is new Ada.Finalization.Controlled with record
      Buckets : Bucket_Access;
      Len     : Natural := 0;
   end record;

   overriding procedure Adjust (Container : in out Set);
   overriding procedure Finalize (Container : in out Set);
end Ada.Containers.Indefinite_Hashed_Sets;
