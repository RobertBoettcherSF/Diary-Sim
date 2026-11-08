pragma Style_Checks (Off);
pragma Warnings (Off);
--  Single-thread counters for the WASM runtime.  The browser demo has one
--  instance and no tasks, so a plain modular update is the atomic one.
package System.Atomic_Counters is
   pragma Pure;

   type Atomic_Counter is limited private;

   procedure Increment (Item : in out Atomic_Counter);
   function Decrement (Item : in out Atomic_Counter) return Boolean;
   function Is_One (Item : Atomic_Counter) return Boolean;
   procedure Initialize (Item : out Atomic_Counter);

   type Atomic_Unsigned is mod 2**32 with Default_Value => 0;

   procedure Increment (Item : aliased in out Atomic_Unsigned);
   function Decrement (Item : aliased in out Atomic_Unsigned) return Boolean;
   procedure Decrement (Item : aliased in out Atomic_Unsigned);

   function "+" (Left, Right : Atomic_Unsigned) return Atomic_Unsigned is abstract;
   function "-" (Left, Right : Atomic_Unsigned) return Atomic_Unsigned is abstract;

private
   type Atomic_Counter is record
      Value : aliased Atomic_Unsigned := 1;
   end record;
end System.Atomic_Counters;
