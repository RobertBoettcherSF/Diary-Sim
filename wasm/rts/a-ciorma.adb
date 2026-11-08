pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Unchecked_Deallocation;

package body Ada.Containers.Indefinite_Ordered_Maps is

   procedure Free_Key is new Ada.Unchecked_Deallocation (Key_Type, Key_Access);
   procedure Free_Elem is new Ada.Unchecked_Deallocation (Element_Type, Elem_Access);
   procedure Free_Node is new Ada.Unchecked_Deallocation (Node, Node_Access);
   procedure Free_Order is new Ada.Unchecked_Deallocation (Order_Array, Order_Access);

   function Equal_Keys (Left, Right : Key_Type) return Boolean is
     (not (Left < Right) and then not (Right < Left));

   --  0 when absent. Found is the index when present; otherwise the insertion point.
   procedure Locate (Container : Map; Key : Key_Type; Index : out Natural; Found : out Boolean) is
      Lo : Natural := 1;
      Hi : Natural := Container.Len;
   begin
      Found := False;
      Index := 1;
      while Lo <= Hi loop
         declare
            Mid : constant Natural := (Lo + Hi) / 2;
            K   : Key_Type renames Container.Order (Mid).Key.all;
         begin
            if K < Key then
               Lo := Mid + 1;
            elsif Key < K then
               Hi := Mid - 1;
            else
               Index := Mid;
               Found := True;
               return;
            end if;
         end;
      end loop;
      Index := Lo;
   end Locate;

   procedure Grow (Container : in out Map) is
   begin
      if Container.Order /= null and then Container.Len < Container.Order'Length then
         return;
      end if;
      declare
         Cap : constant Positive := (if Container.Order = null then 8 else Container.Order'Length * 2);
         Fresh : constant Order_Access := new Order_Array (1 .. Cap);
      begin
         if Container.Order /= null then
            Fresh (1 .. Container.Len) := Container.Order (1 .. Container.Len);
            Free_Order (Container.Order);
         end if;
         Container.Order := Fresh;
      end;
   end Grow;

   procedure Place_At (Container : in out Map; Index : Positive; Key : Key_Type; Item : Element_Type) is
      N : Node_Access;
   begin
      Grow (Container);
      for I in reverse Index .. Container.Len loop
         Container.Order (I + 1) := Container.Order (I);
         Container.Order (I + 1).Ord := I + 1;
      end loop;
      N := new Node;
      N.Key := new Key_Type'(Key);
      N.Elem := new Element_Type'(Item);
      N.Ord := Index;
      Container.Order (Index) := N;
      Container.Len := Container.Len + 1;
   end Place_At;

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
      Container.Len := 0;
   end Finalize;

   overriding procedure Adjust (Container : in out Map) is
      Src : constant Order_Access := Container.Order;
      N : constant Natural := Container.Len;
   begin
      Container.Order := null;
      Container.Len := 0;
      if Src = null or else N = 0 then
         return;
      end if;
      for I in 1 .. N loop
         Place_At (Container, I, Src (I).Key.all, Src (I).Elem.all);
      end loop;
   end Adjust;

   function Length (Container : Map) return Count_Type is (Count_Type (Container.Len));
   function Is_Empty (Container : Map) return Boolean is (Container.Len = 0);
   procedure Clear (Container : in out Map) is
   begin
      Finalize (Container);
   end Clear;

   function Find (Container : Map; Key : Key_Type) return Cursor is
      Index : Natural;
      Found : Boolean;
   begin
      if Container.Len = 0 then
         return No_Element;
      end if;
      Locate (Container, Key, Index, Found);
      if not Found then
         return No_Element;
      end if;
      return (Node => Container.Order (Index));
   end Find;

   function Contains (Container : Map; Key : Key_Type) return Boolean is
     (Find (Container, Key).Node /= null);

   function Element (Container : Map; Key : Key_Type) return Element_Type is
     (Find (Container, Key).Node.Elem.all);
   function Element (Container : Map; Position : Cursor) return Element_Type is
     (Position.Node.Elem.all);
   function Element (Position : Cursor) return Element_Type is (Position.Node.Elem.all);
   function Key (Position : Cursor) return Key_Type is (Position.Node.Key.all);

   procedure Insert (Container : in out Map; Key : Key_Type; New_Item : Element_Type) is
      Index : Natural;
      Found : Boolean;
   begin
      Locate (Container, Key, Index, Found);
      if Found then
         raise Constraint_Error;
      end if;
      Place_At (Container, Index, Key, New_Item);
   end Insert;

   procedure Include (Container : in out Map; Key : Key_Type; New_Item : Element_Type) is
      Index : Natural;
      Found : Boolean;
   begin
      Locate (Container, Key, Index, Found);
      if Found then
         Free_Elem (Container.Order (Index).Elem);
         Container.Order (Index).Elem := new Element_Type'(New_Item);
      else
         Place_At (Container, Index, Key, New_Item);
      end if;
   end Include;

   procedure Replace (Container : in out Map; Key : Key_Type; New_Item : Element_Type) is
      N : constant Node_Access := Find (Container, Key).Node;
   begin
      Free_Elem (N.Elem);
      N.Elem := new Element_Type'(New_Item);
   end Replace;

   function Constant_Reference (Container : aliased Map; Key : Key_Type) return Constant_Reference_Type is
     (Element => Find (Container, Key).Node.Elem);
   function Reference (Container : aliased in out Map; Key : Key_Type) return Reference_Type is
     (Element => Find (Container, Key).Node.Elem);
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

   pragma Unreferenced (Equal_Keys);
end Ada.Containers.Indefinite_Ordered_Maps;
