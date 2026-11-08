pragma Style_Checks (Off);
pragma Warnings (Off);
package body System.Atomic_Counters is
   function Add (Value : Atomic_Unsigned; Delta_V : Atomic_Unsigned) return Atomic_Unsigned is
      type U is mod 2**32;
   begin
      return Atomic_Unsigned (U (Value) + U (Delta_V));
   end Add;

   function Sub (Value : Atomic_Unsigned; Delta_V : Atomic_Unsigned) return Atomic_Unsigned is
      type U is mod 2**32;
   begin
      return Atomic_Unsigned (U (Value) - U (Delta_V));
   end Sub;

   procedure Increment (Item : in out Atomic_Counter) is
   begin
      Item.Value := Add (Item.Value, 1);
   end Increment;

   function Decrement (Item : in out Atomic_Counter) return Boolean is
   begin
      Item.Value := Sub (Item.Value, 1);
      return Item.Value = 0;
   end Decrement;

   function Is_One (Item : Atomic_Counter) return Boolean is (Item.Value = 1);

   procedure Initialize (Item : out Atomic_Counter) is
   begin
      Item.Value := 1;
   end Initialize;

   procedure Increment (Item : aliased in out Atomic_Unsigned) is
   begin
      Item := Add (Item, 1);
   end Increment;

   function Decrement (Item : aliased in out Atomic_Unsigned) return Boolean is
   begin
      Item := Sub (Item, 1);
      return Item = 0;
   end Decrement;

   procedure Decrement (Item : aliased in out Atomic_Unsigned) is
   begin
      Item := Sub (Item, 1);
   end Decrement;
end System.Atomic_Counters;
