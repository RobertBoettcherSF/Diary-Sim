pragma Style_Checks (Off);
pragma Warnings (Off);
package Interfaces.C is
   type int is range -2**31 .. 2**31 - 1;
   type long is range -2**63 .. 2**63 - 1;
   type size_t is mod 2**32;
   type unsigned is mod 2**32;
   type char is new Character;
end Interfaces.C;
