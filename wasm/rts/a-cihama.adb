pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Unchecked_Deallocation;

package body Ada.Containers.Indefinite_Hashed_Maps is

   procedure Free_Key is new Ada.Unchecked_Deallocation (Key_Type, Key_Access);
   procedure Free_Elem is new Ada.Unchecked_Deallocation (Element_Type, Elem_Access);
   procedure Free_Node is new Ada.Unchecked_Deallocation (Node, Node_Access);
   procedure Free_Buckets is new Ada.Unchecked_Deallocation (Bucket_Array, Bucket_Access);
   procedure Free_Order is new Ada.Unchecked_Deallocation (Order_Array, Order_Access);

   function Bucket_Of (Container : Map; Key : Key_Type) return Positive is
     (Positive (Hash (Key) mod Hash_Type (Container.Buckets'Length) + 1));

   function Find_Node (Container : Map; Key : Key_Type) return Node_Access is
   begin
      if Container.Buckets = null then
         return null;
      end if;
      declare
         N : Node_Access := Container.Buckets (Bucket_Of (Container, Key));
      begin
         while N /= null loop
            if Equivalent_Keys (N.Key.all, Key) then
               return N;
            end if;
            N := N.Next;
         end loop;
         return null;
      end;
   end Find_Node;

   procedure Ensure (Container : in out Map) is
   begin
      if Container.Buckets = null then
         Container.Buckets := new Bucket_Array'(1 .. 16 => null);
         Container.Order := new Order_Array (1 .. 16);
         Container.Len := 0;
      end if;
   end Ensure;

   procedure Rehash (Container : in out Map) is
      Old_Order : Order_Access := Container.Order;
      N : constant Natural := Container.Len;
      Cap : constant Positive := Container.Buckets'Length * 2;
   begin
      Free_Buckets (Container.Buckets);
      Container.Buckets := new Bucket_Array'(1 .. Cap => null);
      Container.Order := new Order_Array (1 .. Cap);
      Container.Len := 0;
      for I in 1 .. N loop
         declare
            Node : constant Node_Access := Old_Order (I);
            B : constant Positive := Bucket_Of (Container, Node.Key.all);
         begin
            Node.Next := Container.Buckets (B);
            Container.Buckets (B) := Node;
            Container.Len := Container.Len + 1;
            Node.Ord := Container.Len;
            Container.Order (Container.Len) := Node;
         end;
      end loop;
      Free_Order (Old_Order);
   end Rehash;

   procedure Place (Container : in out Map; Key : Key_Type; Item : Element_Type) is
      N : Node_Access;
      B : Positive;
   begin
      Ensure (Container);
      if Container.Len * 4 >= Container.Buckets'Length * 3 then
         Rehash (Container);
      end if;
      if Container.Len = Container.Order'Length then
         Rehash (Container);
      end if;
      N := new Node;
      N.Key := new Key_Type'(Key);
      N.Elem := new Element_Type'(Item);
      B := Bucket_Of (Container, Key);
      N.Next := Container.Buckets (B);
      Container.Buckets (B) := N;
      Container.Len := Container.Len + 1;
      N.Ord := Container.Len;
      Container.Order (Container.Len) := N;
   end Place;

   overriding procedure Finalize (Container : in out Map) is
   begin
      if Container.Order /= null then
         for I in 1 .. Container.Len loop
            Free_Key (Container.Order (I).Key);
            Free_Elem (Container.Order (I).Elem);
            Free_Node (Container.Order (I));
         end loop;
         Free_Order (Container.Order);
      end if;
      if Container.Buckets /= null then
         Free_Buckets (Container.Buckets);
      end if;
      Container.Len := 0;
   end Finalize;

   overriding procedure Adjust (Container : in out Map) is
      Src : constant Order_Access := Container.Order;
      N : constant Natural := Container.Len;
   begin
      Container.Buckets := null;
      Container.Order := null;
      Container.Len := 0;
      if Src = null or else N = 0 then
         return;
      end if;
      for I in 1 .. N loop
         Place (Container, Src (I).Key.all, Src (I).Elem.all);
      end loop;
   end Adjust;

   function Length (Container : Map) return Count_Type is (Count_Type (Container.Len));
   function Is_Empty (Container : Map) return Boolean is (Container.Len = 0);

   procedure Clear (Container : in out Map) is
   begin
      Finalize (Container);
   end Clear;

   function Contains (Container : Map; Key : Key_Type) return Boolean is
     (Find_Node (Container, Key) /= null);

   function Find (Container : Map; Key : Key_Type) return Cursor is
      N : constant Node_Access := Find_Node (Container, Key);
   begin
      if N = null then
         return No_Element;
      end if;
      return (Node => N);
   end Find;

   function Element (Container : Map; Key : Key_Type) return Element_Type is
      N : constant Node_Access := Find_Node (Container, Key);
   begin
      return N.Elem.all;
   end Element;

   function Element (Container : Map; Position : Cursor) return Element_Type is
     (Position.Node.Elem.all);

   function Element (Position : Cursor) return Element_Type is (Position.Node.Elem.all);

   function Key (Position : Cursor) return Key_Type is (Position.Node.Key.all);

   procedure Insert (Container : in out Map; Key : Key_Type; New_Item : Element_Type) is
   begin
      if Contains (Container, Key) then
         raise Constraint_Error;
      end if;
      Place (Container, Key, New_Item);
   end Insert;

   procedure Include (Container : in out Map; Key : Key_Type; New_Item : Element_Type) is
      N : constant Node_Access := Find_Node (Container, Key);
   begin
      if N = null then
         Place (Container, Key, New_Item);
      else
         Free_Elem (N.Elem);
         N.Elem := new Element_Type'(New_Item);
      end if;
   end Include;

   procedure Replace (Container : in out Map; Key : Key_Type; New_Item : Element_Type) is
      N : constant Node_Access := Find_Node (Container, Key);
   begin
      Free_Elem (N.Elem);
      N.Elem := new Element_Type'(New_Item);
   end Replace;

   procedure Unlink (Container : in out Map; N : Node_Access) is
      B : constant Positive := Bucket_Of (Container, N.Key.all);
      Prev : Node_Access := null;
      Cur : Node_Access := Container.Buckets (B);
   begin
      while Cur /= null and then Cur /= N loop
         Prev := Cur;
         Cur := Cur.Next;
      end loop;
      if Prev = null then
         Container.Buckets (B) := N.Next;
      else
         Prev.Next := N.Next;
      end if;
      for I in N.Ord .. Container.Len - 1 loop
         Container.Order (I) := Container.Order (I + 1);
         Container.Order (I).Ord := I;
      end loop;
      Container.Order (Container.Len) := null;
      Container.Len := Container.Len - 1;
      declare
         Gone : Node_Access := N;
         Key : Key_Access := Gone.Key;
         Elem : Elem_Access := Gone.Elem;
      begin
         Free_Key (Key);
         Free_Elem (Elem);
         Free_Node (Gone);
      end;
   end Unlink;

   procedure Delete (Container : in out Map; Key : Key_Type) is
   begin
      Unlink (Container, Find_Node (Container, Key));
   end Delete;

   procedure Exclude (Container : in out Map; Key : Key_Type) is
      N : constant Node_Access := Find_Node (Container, Key);
   begin
      if N /= null then
         Unlink (Container, N);
      end if;
   end Exclude;

   function Constant_Reference (Container : aliased Map; Key : Key_Type) return Constant_Reference_Type is
     (Element => Find_Node (Container, Key).Elem);
   function Reference (Container : aliased in out Map; Key : Key_Type) return Reference_Type is
     (Element => Find_Node (Container, Key).Elem);
   function Constant_Reference (Container : aliased Map; Position : Cursor) return Constant_Reference_Type is
     (Element => Position.Node.Elem);
   function Reference (Container : aliased in out Map; Position : Cursor) return Reference_Type is
     (Element => Position.Node.Elem);
   function Has_Element (Position : Cursor) return Boolean is (Position.Node /= null);

   type Iterator is new Map_Iterator_Interfaces.Reversible_Iterator with record
      Container : access constant Map;
   end record;
   overriding function First (Object : Iterator) return Cursor;
   overriding function Next (Object : Iterator; Position : Cursor) return Cursor;
   overriding function Last (Object : Iterator) return Cursor;
   overriding function Previous (Object : Iterator; Position : Cursor) return Cursor;

   overriding function First (Object : Iterator) return Cursor is
     (if Object.Container.Len = 0 then No_Element else (Node => Object.Container.Order (1)));
   overriding function Next (Object : Iterator; Position : Cursor) return Cursor is
     (if Position.Node.Ord >= Object.Container.Len then No_Element
      else (Node => Object.Container.Order (Position.Node.Ord + 1)));
   overriding function Last (Object : Iterator) return Cursor is
     (if Object.Container.Len = 0 then No_Element else (Node => Object.Container.Order (Object.Container.Len)));
   overriding function Previous (Object : Iterator; Position : Cursor) return Cursor is
     (if Position.Node.Ord <= 1 then No_Element
      else (Node => Object.Container.Order (Position.Node.Ord - 1)));

   function Iterate (Container : aliased Map) return Map_Iterator_Interfaces.Reversible_Iterator'Class is
   begin
      return It : Iterator do
         It.Container := Container'Unchecked_Access;
      end return;
   end Iterate;

end Ada.Containers.Indefinite_Hashed_Maps;
