pragma Style_Checks (Off);
pragma Warnings (Off);
with Ada.Unchecked_Deallocation;

package body Ada.Containers.Vectors is

   procedure Free_Elem is new Ada.Unchecked_Deallocation (Element_Type, Element_Access);
   procedure Free_Arr is new Ada.Unchecked_Deallocation (Element_Array, Element_Array_Access);

   function Off (Index : Index_Type'Base) return Positive is
     (Positive (Index - Index_Type'First + 1));

   procedure Grow (Container : in out Vector; Need : Natural) is
      Cap : constant Natural := (if Container.Data = null then 0 else Container.Data'Length);
   begin
      if Need <= Cap then
         return;
      end if;
      declare
         Ncap : Natural := (if Cap = 0 then 8 else Cap);
      begin
         while Ncap < Need loop
            Ncap := Ncap * 2;
         end loop;
         declare
            Fresh : constant Element_Array_Access := new Element_Array (1 .. Ncap);
         begin
            if Container.Data /= null then
               Fresh (1 .. Container.Len) := Container.Data (1 .. Container.Len);
               Free_Arr (Container.Data);
            end if;
            Container.Data := Fresh;
         end;
      end;
   end Grow;

   overriding procedure Adjust (Container : in out Vector) is
      Src : constant Element_Array_Access := Container.Data;
   begin
      if Src = null or else Container.Len = 0 then
         Container.Data := null;
         Container.Len := 0;
         return;
      end if;
      Container.Data := new Element_Array (1 .. Src'Length);
      for I in 1 .. Container.Len loop
         Container.Data (I) := new Element_Type'(Src (I).all);
      end loop;
   end Adjust;

   overriding procedure Finalize (Container : in out Vector) is
   begin
      if Container.Data /= null then
         for I in 1 .. Container.Len loop
            Free_Elem (Container.Data (I));
         end loop;
         Free_Arr (Container.Data);
      end if;
      Container.Len := 0;
   end Finalize;

   function Length (Container : Vector) return Count_Type is (Count_Type (Container.Len));
   function Is_Empty (Container : Vector) return Boolean is (Container.Len = 0);

   function Contains (Container : Vector; Item : Element_Type) return Boolean is
   begin
      for I in 1 .. Container.Len loop
         if Container.Data (I).all = Item then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   procedure Clear (Container : in out Vector) is
   begin
      Finalize (Container);
   end Clear;

   function First_Index (Container : Vector) return Extended_Index is
     (if Container.Len = 0 then No_Index else Extended_Index (Index_Type'First));

   function Last_Index (Container : Vector) return Extended_Index is
     (if Container.Len = 0 then No_Index
      else Extended_Index (Index_Type'Pos (Index_Type'First) + Container.Len - 1));

   function Slot (Container : Vector; Index : Index_Type) return Element_Access is
     (Container.Data (Off (Index)));

   function First_Element (Container : Vector) return Element_Type is
     (Container.Data (1).all);

   function Last_Element (Container : Vector) return Element_Type is
     (Container.Data (Container.Len).all);

   function Element (Container : Vector; Index : Index_Type) return Element_Type is
     (Slot (Container, Index).all);

   function Element (Container : Vector; Position : Cursor) return Element_Type is
     (Element (Container, Index_Type (Position.Index)));

   procedure Replace_Element (Container : in out Vector; Index : Index_Type; New_Item : Element_Type) is
      P : constant Positive := Off (Index);
   begin
      Free_Elem (Container.Data (P));
      Container.Data (P) := new Element_Type'(New_Item);
   end Replace_Element;

   procedure Append_One (Container : in out Vector; New_Item : Element_Type) is
   begin
      Grow (Container, Container.Len + 1);
      Container.Len := Container.Len + 1;
      Container.Data (Container.Len) := new Element_Type'(New_Item);
   end Append_One;

   procedure Append (Container : in out Vector; New_Item : Vector) is
   begin
      for I in 1 .. New_Item.Len loop
         Append_One (Container, New_Item.Data (I).all);
      end loop;
   end Append;

   procedure Insert (Container : in out Vector; Before : Extended_Index; New_Item : Element_Type) is
      Slot : Positive;
   begin
      if Container.Len = 0 then
         Append_One (Container, New_Item);
         return;
      end if;
      Slot := Off (Before);
      if Slot > Container.Len then
         Append_One (Container, New_Item);
         return;
      end if;
      Grow (Container, Container.Len + 1);
      for I in reverse Slot .. Container.Len loop
         Container.Data (I + 1) := Container.Data (I);
      end loop;
      Container.Data (Slot) := new Element_Type'(New_Item);
      Container.Len := Container.Len + 1;
   end Insert;

   procedure Delete_Last (Container : in out Vector; Count : Count_Type := 1) is
      N : constant Natural := Natural'Min (Container.Len, Natural (Count));
   begin
      for I in Container.Len - N + 1 .. Container.Len loop
         Free_Elem (Container.Data (I));
         Container.Data (I) := null;
      end loop;
      Container.Len := Container.Len - N;
   end Delete_Last;

   procedure Prepend (Container : in out Vector; New_Item : Element_Type) is
   begin
      Grow (Container, Container.Len + 1);
      for I in reverse 1 .. Container.Len loop
         Container.Data (I + 1) := Container.Data (I);
      end loop;
      Container.Len := Container.Len + 1;
      Container.Data (1) := new Element_Type'(New_Item);
   end Prepend;

   procedure Delete (Container : in out Vector; Index : Extended_Index; Count : Count_Type := 1) is
      From : constant Natural := Off (Index);
      N    : constant Natural := Natural (Count);
      Last : constant Natural := From + N - 1;
   begin
      for I in From .. Last loop
         Free_Elem (Container.Data (I));
      end loop;
      for I in Last + 1 .. Container.Len loop
         Container.Data (I - N) := Container.Data (I);
         Container.Data (I) := null;
      end loop;
      Container.Len := Container.Len - N;
   end Delete;

   procedure Delete_First (Container : in out Vector; Count : Count_Type := 1) is
   begin
      if Count > 0 then
         Delete (Container, Extended_Index (Index_Type'First), Count);
      end if;
   end Delete_First;

   procedure Move (Target : in out Vector; Source : in out Vector) is
   begin
      if Target.Data /= Source.Data then
         Finalize (Target);
         Target.Data := Source.Data;
         Target.Len := Source.Len;
         Source.Data := null;
         Source.Len := 0;
      end if;
   end Move;

   function To_Vector (New_Item : Element_Type; Length : Count_Type) return Vector is
      R : Vector;
   begin
      for I in 1 .. Natural (Length) loop
         Append (R, New_Item);
      end loop;
      return R;
   end To_Vector;

   function "=" (Left, Right : Vector) return Boolean is
   begin
      if Left.Len /= Right.Len then
         return False;
      end if;
      for I in 1 .. Left.Len loop
         if Left.Data (I).all /= Right.Data (I).all then
            return False;
         end if;
      end loop;
      return True;
   end "=";

   function Constant_Reference (Container : aliased Vector; Index : Index_Type) return Constant_Reference_Type is
     (Element => Slot (Container, Index));

   function Reference (Container : aliased in out Vector; Index : Index_Type) return Reference_Type is
     (Element => Slot (Container, Index));

   function Constant_Reference (Container : aliased Vector; Position : Cursor) return Constant_Reference_Type is
     (Constant_Reference (Container, Index_Type (Position.Index)));

   function Reference (Container : aliased in out Vector; Position : Cursor) return Reference_Type is
     (Reference (Container, Index_Type (Position.Index)));

   function Has_Element (Position : Cursor) return Boolean is (Position.Valid);

   function First_Cursor (Container : Vector) return Cursor is
     (if Container.Len = 0 then No_Element else (Valid => True, Index => Index_Type'First));

   function Next_Cursor (Container : Vector; Position : Cursor) return Cursor is
      N : constant Index_Type'Base := Position.Index + 1;
   begin
      if not Position.Valid or else N > Index_Type'Base (Last_Index (Container)) then
         return No_Element;
      end if;
      return (Valid => True, Index => N);
   end Next_Cursor;

   function Cursor_Element (Container : Vector; Position : Cursor) return Element_Type is
     (Element (Container, Position));

   type Iterator is new Vector_Iterator_Interfaces.Reversible_Iterator with record
      Container : access constant Vector;
   end record;
   overriding function First (Object : Iterator) return Cursor;
   overriding function Next (Object : Iterator; Position : Cursor) return Cursor;
   overriding function Last (Object : Iterator) return Cursor;
   overriding function Previous (Object : Iterator; Position : Cursor) return Cursor;

   overriding function First (Object : Iterator) return Cursor is (First_Cursor (Object.Container.all));
   overriding function Next (Object : Iterator; Position : Cursor) return Cursor is
     (Next_Cursor (Object.Container.all, Position));
   overriding function Last (Object : Iterator) return Cursor is
     (if Object.Container.Len = 0 then No_Element
      else (Valid => True, Index => Index_Type'Base (Last_Index (Object.Container.all))));
   overriding function Previous (Object : Iterator; Position : Cursor) return Cursor is
     (if not Position.Valid or else Position.Index <= Index_Type'First then No_Element
      else (Valid => True, Index => Position.Index - 1));

   function Iterate (Container : aliased Vector) return Vector_Iterator_Interfaces.Reversible_Iterator'Class is
   begin
      return It : Iterator do
         It.Container := Container'Unchecked_Access;
      end return;
   end Iterate;

   package body Generic_Sorting is
      procedure Sort (Container : in out Vector) is
      begin
         for I in 2 .. Container.Len loop
            declare
               Item : constant Element_Access := Container.Data (I);
               J    : Natural := I;
            begin
               while J > 1 and then Item.all < Container.Data (J - 1).all loop
                  Container.Data (J) := Container.Data (J - 1);
                  J := J - 1;
               end loop;
               Container.Data (J) := Item;
            end;
         end loop;
      end Sort;
   end Generic_Sorting;

end Ada.Containers.Vectors;
