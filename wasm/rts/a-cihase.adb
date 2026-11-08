pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Unchecked_Deallocation;

package body Ada.Containers.Indefinite_Hashed_Sets is

   procedure Free_Elem is new Ada.Unchecked_Deallocation (Element_Type, Element_Access);
   procedure Free_Node is new Ada.Unchecked_Deallocation (Node, Node_Access);
   procedure Free_Buckets is new Ada.Unchecked_Deallocation (Bucket_Array, Bucket_Access);

   procedure Ensure (Container : in out Set) is
   begin
      if Container.Buckets = null then
         Container.Buckets := new Bucket_Array'(1 .. 16 => null);
      end if;
   end Ensure;

   function Bucket_Of (Container : Set; Item : Element_Type) return Positive is
     (Positive (Hash (Item) mod Hash_Type (Container.Buckets'Length) + 1));

   function Find_Node (Container : Set; Item : Element_Type) return Node_Access is
   begin
      if Container.Buckets = null then
         return null;
      end if;
      declare
         N : Node_Access := Container.Buckets (Bucket_Of (Container, Item));
      begin
         while N /= null loop
            if Equivalent_Elements (N.Item.all, Item) then
               return N;
            end if;
            N := N.Next;
         end loop;
         return null;
      end;
   end Find_Node;

   procedure Place (Container : in out Set; Item : Element_Type) is
      N : Node_Access;
      B : Positive;
   begin
      Ensure (Container);
      N := new Node;
      N.Item := new Element_Type'(Item);
      B := Bucket_Of (Container, Item);
      N.Next := Container.Buckets (B);
      Container.Buckets (B) := N;
      Container.Len := Container.Len + 1;
   end Place;

   overriding procedure Finalize (Container : in out Set) is
   begin
      if Container.Buckets /= null then
         for B in Container.Buckets'Range loop
            declare
               N : Node_Access := Container.Buckets (B);
            begin
               while N /= null loop
                  declare
                     Nx : constant Node_Access := N.Next;
                  begin
                     Free_Elem (N.Item);
                     Free_Node (N);
                     N := Nx;
                  end;
               end loop;
            end;
         end loop;
         Free_Buckets (Container.Buckets);
      end if;
      Container.Len := 0;
   end Finalize;

   overriding procedure Adjust (Container : in out Set) is
      Src : constant Bucket_Access := Container.Buckets;
   begin
      Container.Buckets := null;
      Container.Len := 0;
      if Src = null then
         return;
      end if;
      for B in Src'Range loop
         declare
            N : Node_Access := Src (B);
         begin
            while N /= null loop
               Place (Container, N.Item.all);
               N := N.Next;
            end loop;
         end;
      end loop;
   end Adjust;

   function Length (Container : Set) return Count_Type is (Count_Type (Container.Len));
   function Is_Empty (Container : Set) return Boolean is (Container.Len = 0);
   procedure Clear (Container : in out Set) is
   begin
      Finalize (Container);
   end Clear;

   function Contains (Container : Set; Item : Element_Type) return Boolean is
     (Find_Node (Container, Item) /= null);

   procedure Insert (Container : in out Set; New_Item : Element_Type) is
   begin
      if Contains (Container, New_Item) then
         raise Constraint_Error;
      end if;
      Place (Container, New_Item);
   end Insert;

   procedure Include (Container : in out Set; New_Item : Element_Type) is
   begin
      if not Contains (Container, New_Item) then
         Place (Container, New_Item);
      end if;
   end Include;

   procedure Unlink (Container : in out Set; Item : Element_Type) is
      B : constant Positive := Bucket_Of (Container, Item);
      Prev : Node_Access := null;
      Cur : Node_Access := Container.Buckets (B);
   begin
      while Cur /= null and then not Equivalent_Elements (Cur.Item.all, Item) loop
         Prev := Cur;
         Cur := Cur.Next;
      end loop;
      if Cur = null then
         raise Constraint_Error;
      end if;
      if Prev = null then
         Container.Buckets (B) := Cur.Next;
      else
         Prev.Next := Cur.Next;
      end if;
      Free_Elem (Cur.Item);
      Free_Node (Cur);
      Container.Len := Container.Len - 1;
   end Unlink;

   procedure Delete (Container : in out Set; Item : Element_Type) is
   begin
      Unlink (Container, Item);
   end Delete;

   procedure Exclude (Container : in out Set; Item : Element_Type) is
   begin
      if Contains (Container, Item) then
         Unlink (Container, Item);
      end if;
   end Exclude;

end Ada.Containers.Indefinite_Hashed_Sets;
