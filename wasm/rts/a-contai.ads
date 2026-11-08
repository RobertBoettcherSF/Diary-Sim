pragma Style_Checks (Off);
pragma Warnings (Off);
--  WASM runtime subset of Ada.Containers.  Hash_Type and Count_Type match the
--  GNAT declarations the simulation already instantiates.  The container
--  bodies in this directory implement the operations Diary Sim calls; the
--  native build keeps using the full GNAT library.
package Ada.Containers is
   pragma Pure;

   type Hash_Type is mod 2**32;
   type Count_Type is range 0 .. 2**31 - 1;

   Capacity_Error : exception;
end Ada.Containers;
