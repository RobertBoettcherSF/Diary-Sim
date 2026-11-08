pragma Style_Checks (Off);
pragma Warnings (Off);
--  Spec-only iterator interface, copied in shape from the GNAT runtime so
--  "for C in Container.Iterate" compiles on the WASM profile.
generic
   type Cursor;
   with function Has_Element (Position : Cursor) return Boolean;
   pragma Unreferenced (Has_Element);

package Ada.Iterator_Interfaces is
   pragma Pure;

   type Forward_Iterator is limited interface;

   function First (Object : Forward_Iterator) return Cursor is abstract;
   function Next (Object : Forward_Iterator; Position : Cursor) return Cursor is abstract;

   type Reversible_Iterator is limited interface and Forward_Iterator;

   function Last (Object : Reversible_Iterator) return Cursor is abstract;
   function Previous (Object : Reversible_Iterator; Position : Cursor) return Cursor is abstract;
end Ada.Iterator_Interfaces;
